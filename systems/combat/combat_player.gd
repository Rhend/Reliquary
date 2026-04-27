# ============================================================
# CombatPlayer — Lecteur cosmétique d'une séquence de combat.
#
# 1. AdventureSystem appelle start_combat() avec l'ennemi et les HP courants.
# 2. CombatPlayer délègue à CombatResolver pour le calcul instantané.
# 3. Les steps sont joués un par un à cadence GameSettings.combat_speed.
# 4. Chaque step émet step_started / step_ended pour piloter l'UI.
# 5. En fin de séquence, combat_finished est émis ET relayé via EventBus
#    pour la compatibilité avec AdventureSystem.
# ============================================================
extends Node

const BASE_STEP_DURATION: float = 0.8

signal step_started(step: CombatStep)
signal step_ended(step: CombatStep)
signal combat_finished(winner: String)

# ─── État runtime ────────────────────────────────────────────

var _steps:            Array[CombatStep] = []
var _index:            int               = 0
var _timer:            Timer
var _current_hero_hp:  float             = 0.0
var _current_enemy_hp: float             = 0.0
var _enemy_dict:       Dictionary        = {}

var is_playing: bool:
	get: return _timer != null and not _timer.is_stopped()

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_timer          = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Lance un combat. modifier_bonuses vient d'AdventureSystem.get_modifier_bonuses().
func start_combat(enemy: Dictionary, current_hp: float,
		modifier_bonuses: Dictionary) -> void:
	var passives  := PassiveSystem.get_combat_bonuses()
	var equip     := GameData.get_equipment_bonuses()
	var hero      := GameData.hero_data

	var h_atk := hero.get_effective_atk(
		passives.get("atk_bonus", 0.0),
		equip.get("atk", 0.0),
		modifier_bonuses.get("atk_mult", 1.0)
	)
	var h_atk_mastery := GameData.get_mastery_combat_bonus(enemy.get("id", ""))
	h_atk += h_atk_mastery

	var h_def := hero.get_effective_def(
		passives.get("def_bonus", 0.0),
		equip.get("def", 0.0),
		modifier_bonuses.get("def_mult", 1.0)
	)

	var e_atk := float(enemy.get("atk", 8))
	var e_def := float(enemy.get("def", 2))
	var e_hp  := float(enemy.get("hp",  50))

	_enemy_dict        = enemy
	_current_hero_hp   = current_hp
	_current_enemy_hp  = e_hp
	_steps             = CombatResolver.resolve(h_atk, h_def, current_hp, e_atk, e_def, e_hp)
	_index             = 0

	EventBus.combat_started.emit("hero", enemy, current_hp, e_hp)
	_play_next()

func stop() -> void:
	if _timer:
		_timer.stop()

# ═══════════════════════════════════════════════════════════
#  Boucle de playback
# ═══════════════════════════════════════════════════════════

func _play_next() -> void:
	if _index >= _steps.size():
		var winner := _determine_winner()
		_finish(winner)
		return

	var step := _steps[_index]

	# Met à jour les HP courants AVANT d'émettre (pour que l'UI soit cohérente)
	if step.attacker == "hero":
		_current_enemy_hp = float(step.target_hp_after)
	else:
		_current_hero_hp = float(step.target_hp_after)

	step_started.emit(step)
	# Compatibilité EventBus pour les handlers existants de Biome.gd
	EventBus.combat_turn.emit(
		step.attacker, float(step.damage), _current_hero_hp, _current_enemy_hp
	)

	var duration := BASE_STEP_DURATION * GameSettings.combat_speed
	_timer.wait_time = maxf(duration, 0.05)
	_timer.start()

func _on_timer() -> void:
	step_ended.emit(_steps[_index])
	_index += 1
	_play_next()

func _finish(winner: String) -> void:
	combat_finished.emit(winner)
	EventBus.combat_ended.emit({
		"victory":               winner == "hero",
		"remaining_creature_hp": _current_hero_hp,
		"enemy":                 _enemy_dict
	})

func _determine_winner() -> String:
	if _steps.is_empty():
		return "hero"
	var last: CombatStep = _steps.back()
	if last.is_killing_blow:
		return "hero" if last.attacker == "hero" else "enemy"
	# Si max_steps atteint sans mort : celui qui a le moins de HP perd
	return "hero" if _current_enemy_hp <= _current_hero_hp else "enemy"
