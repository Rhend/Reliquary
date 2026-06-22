# ============================================================
# CombatPlayer — Lecteur cosmétique d'une séquence de combat ATB temps réel.
#
# 1. AdventureSystem appelle start_combat() avec l'ennemi et les HP courants.
# 2. CombatPlayer délègue à CombatResolver (résolution ATB horodatée en secondes).
# 3. Chaque step est joué À SON HORODATAGE réel (step.time_sec) : la durée du
#    combat est ÉMERGENTE, sans borne. GameSettings.combat_speed est un
#    multiplicateur global de vitesse de lecture (uniforme sur tous les délais).
# 4. Chaque step émet step_started / step_ended pour piloter l'UI.
# 5. En fin de séquence, combat_finished est émis ET relayé via EventBus.
# ============================================================
extends Node

signal step_started(step: CombatStep)
signal step_ended(step: CombatStep)
signal combat_finished(winner: String)

const MIN_STEP_DURATION: float = 0.05  # plancher de délai entre deux steps (sécurité timer)

var _steps:            Array      = []
var _index:            int        = 0
var _prev_time_sec:    float      = 0.0   # horodatage du step précédent (calcul des délais)
var _timer:            Timer
var _current_hero_hp:  float      = 0.0
var _current_enemy_hp: float      = 0.0
var _enemy_dict:       Dictionary = {}

# Intervalle d'affichage entre deux attaques de chaque combattant, en secondes
# de LECTURE (déjà divisé par combat_speed). Permet à l'UI (CombatScene) de
# remplir honnêtement chaque jauge ATB à la vitesse réelle du combattant :
# un combattant rapide remplit visiblement plus vite.
var _hero_atb_interval:  float = 1.0
var _enemy_atb_interval: float = 1.0

# Fenêtre de hâte (modificateur de vitesse temporaire accélérant) de chaque
# combattant, en secondes de LECTURE : Vector2(début, fin). ZERO = aucune.
# Permet à la scène d'afficher le feedback « Hâte » (pill + jauge teintée).
var _hero_haste:  Vector2 = Vector2.ZERO
var _enemy_haste: Vector2 = Vector2.ZERO

var is_playing: bool:
	get: return _timer != null and not _timer.is_stopped()

var hero_atb_interval: float:
	get: return _hero_atb_interval
var enemy_atb_interval: float:
	get: return _enemy_atb_interval
var hero_haste_window: Vector2:
	get: return _hero_haste
var enemy_haste_window: Vector2:
	get: return _enemy_haste

func _ready() -> void:
	_timer          = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)

# Lance un nouveau combat contre l'ennemi donné depuis les HP courants du héros.
# modifier_bonuses : multiplicateurs fournis par AdventureSystem (atk_mult, def_mult).
# combat_options   : options de mécaniques de biome { "ambush": bool, "poison": bool }.
func start_combat(enemy: Dictionary, current_hp: float,
		modifier_bonuses: Dictionary, combat_options: Dictionary = {}) -> void:
	var passives := PassiveSystem.get_combat_bonuses()
	var equip    := GameData.get_equipment_bonuses()
	var stats    := GameData.get_effective_stats("hero")

	# Stat NUE + bonus PLATS hérités (équipement / passifs / familiarité bestiaire).
	# Tous les bonus EN POURCENTAGE transitent par StatStacker : empilement additif,
	# appliqué une seule fois, point unique clampable. v1 : seul le modificateur de
	# cycle (atk_mult/def_mult) et attack_speed_pct fournissent des % ; les futures
	# sources % (village, Forge, Maîtrise) viendront grossir ces listes — jamais de
	# produit multiplicatif réintroduit ailleurs.
	# Bonus % de village (Chantier 4) + nœuds de Forge (Chantier 5) — empilés
	# ADDITIVEMENT avec les autres % (jamais de produit séquentiel).
	var v_atk_pct  := VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT)  + ForgeSystem.get_stat_bonus("atk_pct")
	var v_def_pct  := VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT)  + ForgeSystem.get_stat_bonus("def_pct")
	var v_hp_pct   := VillageBuildings.get_bonus(VillageBuildings.CH_HP_MAX_PCT) + ForgeSystem.get_stat_bonus("hp_max_pct")
	var v_crit_pct := VillageBuildings.get_bonus(VillageBuildings.CH_CRIT_PCT) + ForgeSystem.get_stat_bonus("crit_pct")
	var f_atb_pct  := ForgeSystem.get_stat_bonus("atb_pct")
	var frules     := ForgeSystem.combat_rules()

	var atk_base: float = float(stats.get("atk", 0)) \
			+ float(passives.get("atk_bonus", 0.0)) \
			+ float(equip.get("atk", 0.0)) \
			+ GameData.get_mastery_combat_bonus(enemy.get("id", ""))
	var h_atk := StatStacker.final_stat(atk_base,
			[float(modifier_bonuses.get("atk_mult", 1.0)) - 1.0, v_atk_pct], "atk")

	var def_base: float = float(stats.get("def", 0)) \
			+ float(passives.get("def_bonus", 0.0)) \
			+ float(equip.get("def", 0.0))
	var h_def := StatStacker.final_stat(def_base,
			[float(modifier_bonuses.get("def_mult", 1.0)) - 1.0, v_def_pct], "def")

	# attack_speed_pct (équipement, ex. Anneau) + nœuds ATB de Forge → jauge VIT.
	var h_vit := StatStacker.final_stat(float(stats.get("vit", 20)),
			[float(equip.get("attack_speed_pct", 0.0)) / 100.0, f_atb_pct], "vit")

	# HP maximum du héros (référence pour les conditions de PV, ex. Élan)
	var h_hp_max := StatStacker.final_stat(
		float(stats.get("hp", 100))
			+ float(passives.get("hp_bonus", 0.0))
			+ float(equip.get("hp", 0.0)),
		[v_hp_pct], "hp")

	var e_hp := float(enemy.get("hp", 50))

	# Effets conditionnels des passifs (poison passif on-hit)
	var passive_effects := PassiveSystem.get_passive_combat_effects(h_atk)
	var extended_options := combat_options.duplicate()
	if not (passive_effects["passive_poison"] as Dictionary).is_empty():
		extended_options["passive_poison"] = passive_effects["passive_poison"]

	# Jauge ATB de départ : Village (Tour de Guet) + Forge (Embuscade complice), %
	# additifs. Le filet anti-mort (Palissade T5) et l'atténuation de venin sont
	# portés par combat_options (gérés à l'échelle de l'expédition par AdventureSystem).
	extended_options["hero_gauge_start"] = clampf(
			VillageBuildings.hero_gauge_start(bool(combat_options.get("ambush", false)))
			+ float(frules.get("gauge_start", 0.0)), 0.0, 1.0)

	# Effets de règle des nœuds de Forge passés au resolver.
	extended_options["hero_def_ignore_pct"]        = float(frules.get("def_ignore_pct", 0.0))
	extended_options["endurcissement_counter_pct"] = float(frules.get("endurcissement_counter_pct", 0.0))
	extended_options["cond_atk_hp_above"]          = frules.get("cond_atk_hp_above", [])
	# Dégâts résiduels (Saignée) via le rail du poison passif, si libre.
	var residual := frules.get("residual", {}) as Dictionary
	if not residual.is_empty() and (extended_options.get("passive_poison", {}) as Dictionary).is_empty():
		extended_options["passive_poison"] = {
			"chance":          float(residual.get("chance", 1.0)),
			"damage_per_turn": h_atk * float(residual.get("damage_pct", 0.0)),
			"duration_turns":  int(residual.get("duration", 2)),
		}

	var hero_stats := {
		"hp":              current_hp,
		"hp_max":          h_hp_max,
		"atk":             h_atk,
		"def":             h_def,
		"vit":             h_vit,
		"crit_chance":     float(stats.get("crit_chance",     Balance.CRIT_CHANCE)) + v_crit_pct,
		"crit_multiplier": float(stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER)) + float(frules.get("crit_mult", 0.0)),
	}
	var enemy_stats := {
		"hp":              e_hp,
		"atk":             float(enemy.get("atk", 8)),
		"def":             float(enemy.get("def", 2)),
		"vit":             float(enemy.get("vit", 20)),
		"crit_chance":     float(enemy.get("crit_chance",     Balance.CRIT_CHANCE)),
		"crit_multiplier": float(enemy.get("crit_multiplier", Balance.CRIT_MULTIPLIER)),
	}

	_enemy_dict       = enemy
	_current_hero_hp  = current_hp
	_current_enemy_hp = e_hp
	_steps            = CombatResolver.resolve(hero_stats, enemy_stats, extended_options)
	_index            = 0
	_prev_time_sec    = 0.0

	# Intervalle initial de chaque jauge ATB = temps de LECTURE jusqu'au PREMIER
	# coup du combattant (honnête : embuscade → jauge ennemie déjà pleine donc
	# coup à t≈0 ; hâte → premier coup plus tôt). Les coups suivants utilisent
	# gap_to_next_attack(). combat_speed > 1 → lecture plus rapide.
	var speed := maxf(GameSettings.combat_speed, 0.01)
	_hero_atb_interval  = _first_attack_playback(Enums.Actor.HERO,  speed)
	_enemy_atb_interval = _first_attack_playback(Enums.Actor.ENEMY, speed)

	# Fenêtres de hâte (feedback visuel) en secondes de lecture.
	_hero_haste  = _haste_window(extended_options.get("hero_speed_mods",  []), speed)
	_enemy_haste = _haste_window(extended_options.get("enemy_speed_mods", []), speed)

	EventBus.combat_started.emit("hero", enemy, current_hp, e_hp)
	_play_next()

# Temps de lecture (s) jusqu'au premier coup d'attaque du combattant `actor`
# (ignore les ticks de poison). Plancher MIN_STEP_DURATION ; combattant qui ne
# frappe jamais → plancher.
func _first_attack_playback(actor: String, speed: float) -> float:
	for s in _steps:
		var st := s as CombatStep
		if st.is_poison or st.is_passive_poison:
			continue
		if st.attacker == actor:
			return maxf(st.time_sec / speed, MIN_STEP_DURATION)
	return MIN_STEP_DURATION

# Temps de lecture (s) jusqu'à la PROCHAINE attaque du combattant donné, à partir
# du step courant (_index). Sert à remplir honnêtement la jauge ATB : pendant la
# hâte, les coups se rapprochent → la jauge monte plus vite.
func gap_to_next_attack(is_hero: bool) -> float:
	var speed := maxf(GameSettings.combat_speed, 0.01)
	var actor := Enums.Actor.HERO if is_hero else Enums.Actor.ENEMY
	if _index >= _steps.size():
		return _hero_atb_interval if is_hero else _enemy_atb_interval
	var from_t := (_steps[_index] as CombatStep).time_sec
	for j in range(_index + 1, _steps.size()):
		var s := _steps[j] as CombatStep
		if s.is_poison or s.is_passive_poison:
			continue
		if s.attacker == actor:
			return maxf((s.time_sec - from_t) / speed, MIN_STEP_DURATION)
	return _hero_atb_interval if is_hero else _enemy_atb_interval

# Première fenêtre de modificateur de vitesse TEMPORAIRE et accélérant
# (factor > 1 ou additive > 0), convertie en secondes de lecture. ZERO si aucune.
func _haste_window(mods: Array, speed: float) -> Vector2:
	for m: Dictionary in mods:
		var dur: float = float(m.get("duration", -1.0))
		var accel := float(m.get("factor", 1.0)) > 1.0 or float(m.get("additive", 0.0)) > 0.0
		if dur >= 0.0 and accel:
			var start: float = float(m.get("start", 0.0))
			return Vector2(start / speed, (start + dur) / speed)
	return Vector2.ZERO

func stop() -> void:
	if _timer:
		_timer.stop()

func _play_next() -> void:
	if _index >= _steps.size():
		_finish(_determine_winner())
		return

	var step: CombatStep = _steps[_index]

	if step.is_passive_poison:
		_current_enemy_hp = float(step.target_hp_after)   # Contact Venimeux : ronge l'ennemi
	elif step.is_poison:
		_current_hero_hp = float(step.target_hp_after)    # poison de biome : ronge le héros
	elif step.attacker == Enums.Actor.HERO:
		_current_enemy_hp = float(step.target_hp_after)
	else:
		_current_hero_hp = float(step.target_hp_after)

	step_started.emit(step)

	# Délai jusqu'à l'atterrissage de ce step = écart d'horodatage avec le step
	# précédent, ramené en secondes de lecture (÷ combat_speed). Les sous-steps
	# instantanés (poison partageant l'instant d'un coup) tombent au plancher.
	var speed := maxf(GameSettings.combat_speed, 0.01)
	var delay := (step.time_sec - _prev_time_sec) / speed
	_prev_time_sec = step.time_sec
	_timer.wait_time = maxf(delay, MIN_STEP_DURATION)
	_timer.start()

func _on_timer() -> void:
	step_ended.emit(_steps[_index])
	_index += 1
	_play_next()

func _finish(winner: String) -> void:
	combat_finished.emit(winner)
	EventBus.combat_ended.emit({
		"victory":           winner == Enums.Actor.HERO,
		"remaining_hero_hp": _current_hero_hp,
		"enemy":             _enemy_dict,
		"lethal_used":       _lethal_was_used(),
	})

# Vrai si le filet anti-mort (Palissade T5) a été consommé pendant ce combat :
# AdventureSystem s'en sert pour décrémenter la disponibilité du cycle.
func _lethal_was_used() -> bool:
	for s in _steps:
		if (s as CombatStep).is_lethal_ignored:
			return true
	return false

func _determine_winner() -> String:
	if _steps.is_empty():
		return Enums.Actor.HERO
	var last: CombatStep = _steps.back()
	if last.is_killing_blow:
		# Coup fatal porté par le héros OU poison passif (qui ronge l'ennemi) → victoire.
		# Le poison de biome porte attacker = ENEMY (il tue le héros) → défaite.
		return Enums.Actor.HERO if (last.attacker == Enums.Actor.HERO or last.is_passive_poison) else Enums.Actor.ENEMY
	return Enums.Actor.HERO if _current_enemy_hp <= _current_hero_hp else Enums.Actor.ENEMY
