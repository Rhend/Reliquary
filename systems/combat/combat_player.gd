# ============================================================
# CombatPlayer — Lecteur cosmétique d'une séquence de combat.
#
# 1. AdventureSystem appelle start_combat() avec l'ennemi et les HP courants.
# 2. CombatPlayer délègue à CombatResolver (résolution VIT-based instantanée).
# 3. Les steps sont joués un par un à cadence GameSettings.combat_speed.
# 4. Chaque step émet step_started / step_ended pour piloter l'UI.
# 5. En fin de séquence, combat_finished est émis ET relayé via EventBus.
# ============================================================
extends Node

# Durée par tour calculée dynamiquement dans start_combat() depuis Balance.

signal step_started(step: CombatStep)
signal step_ended(step: CombatStep)
signal combat_finished(winner: String)

const MIN_STEP_DURATION: float = 0.05  # plancher de durée d'un step (sécurité timer)

var _steps:            Array      = []
var _index:            int        = 0
var _step_duration:    float      = 0.0   # durée par tour calculée à start_combat
var _timer:            Timer
var _current_hero_hp:  float      = 0.0
var _current_enemy_hp: float      = 0.0
var _enemy_dict:       Dictionary = {}

var is_playing: bool:
	get: return _timer != null and not _timer.is_stopped()

# Durée d'affichage d'un step du combat courant (lecture seule).
# Utilisée par l'UI (CombatScene) pour caler ses animations de charge
# sur le rythme réel du playback.
var step_duration: float:
	get: return _step_duration

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

	var h_atk: float = (
		float(stats.get("atk", 0))
		+ float(passives.get("atk_bonus", 0.0))
		+ float(equip.get("atk", 0.0))
	) * float(modifier_bonuses.get("atk_mult", 1.0))
	h_atk += GameData.get_mastery_combat_bonus(enemy.get("id", ""))

	var h_def: float = (
		float(stats.get("def", 0))
		+ float(passives.get("def_bonus", 0.0))
		+ float(equip.get("def", 0.0))
	) * float(modifier_bonuses.get("def_mult", 1.0))
	# attack_speed_pct (équipement, ex. Anneau) accélère la jauge VIT.
	var h_vit: float = float(stats.get("vit", 20)) \
			* (1.0 + float(equip.get("attack_speed_pct", 0.0)) / 100.0)

	# HP maximum du héros (pour le calcul du seuil de bouclier)
	var h_hp_max: float = (
		float(stats.get("hp", 100))
		+ float(passives.get("hp_bonus", 0.0))
		+ float(equip.get("hp", 0.0))
	)

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

	# Durée d'affichage bornée : clamp(nb_tours × IDEAL, MIN, MAX), répartie équitablement.
	var nb := maxi(_steps.size(), 1)
	var duree := clampf(float(nb) * Balance.TEMPS_TOUR_IDEAL, Balance.COMBAT_MIN, Balance.COMBAT_MAX)
	_step_duration = maxf(duree / float(nb) * GameSettings.combat_speed, MIN_STEP_DURATION)

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

	_timer.wait_time = _step_duration
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
