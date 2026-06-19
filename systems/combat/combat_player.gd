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
	var atk_base: float = float(stats.get("atk", 0)) \
			+ float(passives.get("atk_bonus", 0.0)) \
			+ float(equip.get("atk", 0.0)) \
			+ GameData.get_mastery_combat_bonus(enemy.get("id", ""))
	var h_atk := StatStacker.final_stat(atk_base,
			[float(modifier_bonuses.get("atk_mult", 1.0)) - 1.0], "atk")

	var def_base: float = float(stats.get("def", 0)) \
			+ float(passives.get("def_bonus", 0.0)) \
			+ float(equip.get("def", 0.0))
	var h_def := StatStacker.final_stat(def_base,
			[float(modifier_bonuses.get("def_mult", 1.0)) - 1.0], "def")

	# attack_speed_pct (équipement, ex. Anneau) accélère la jauge VIT (bonus %).
	var h_vit := StatStacker.final_stat(float(stats.get("vit", 20)),
			[float(equip.get("attack_speed_pct", 0.0)) / 100.0], "vit")

	# HP maximum du héros (pour le calcul du seuil de bouclier)
	var h_hp_max := StatStacker.final_stat(
		float(stats.get("hp", 100))
			+ float(passives.get("hp_bonus", 0.0))
			+ float(equip.get("hp", 0.0)),
		[], "hp")

	var e_hp := float(enemy.get("hp", 50))

	# Effets conditionnels des passifs (bouclier + poison passif)
	var passive_effects := PassiveSystem.get_passive_combat_effects(h_atk)
	var extended_options := combat_options.duplicate()
	if not (passive_effects["shield"] as Dictionary).is_empty():
		extended_options["passive_shield"] = passive_effects["shield"]
	if not (passive_effects["passive_poison"] as Dictionary).is_empty():
		extended_options["passive_poison"] = passive_effects["passive_poison"]

	var hero_stats := {
		"hp":              current_hp,
		"hp_max":          h_hp_max,
		"atk":             h_atk,
		"def":             h_def,
		"vit":             h_vit,
		"crit_chance":     float(stats.get("crit_chance",     Balance.CRIT_CHANCE)),
		"crit_multiplier": float(stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER)),
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

	# Enregistrer le cooldown du bouclier si il a procé pendant la résolution
	var shield_cfg := extended_options.get("passive_shield", {}) as Dictionary
	var shield_pid: String = shield_cfg.get("passive_id", "")
	if not shield_pid.is_empty():
		for s in _steps:
			if (s as CombatStep).is_shield_proc:
				PassiveSystem.set_shield_cooldown(shield_pid, int(shield_cfg.get("cooldown_cycles", 1)))
				break

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
		"enemy":             _enemy_dict
	})

func _determine_winner() -> String:
	if _steps.is_empty():
		return Enums.Actor.HERO
	var last: CombatStep = _steps.back()
	if last.is_killing_blow:
		# Coup fatal porté par le héros OU poison passif (qui ronge l'ennemi) → victoire.
		# Le poison de biome porte attacker = ENEMY (il tue le héros) → défaite.
		return Enums.Actor.HERO if (last.attacker == Enums.Actor.HERO or last.is_passive_poison) else Enums.Actor.ENEMY
	return Enums.Actor.HERO if _current_enemy_hp <= _current_hero_hp else Enums.Actor.ENEMY
