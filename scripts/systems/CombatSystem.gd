extends Node

const TURN_INTERVAL: float = 1.0

var is_fighting: bool = false

var _timer: Timer
var _creature_id: String = ""
var _enemy: Dictionary = {}
var _creature_hp: float = 0.0
var _enemy_hp: float = 0.0
var _creature_turn: bool = true  # true = créature attaque, false = ennemi riposte

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TURN_INTERVAL
	_timer.one_shot = false
	_timer.timeout.connect(_on_turn_tick)
	add_child(_timer)

func start_combat(creature_id: String, enemy: Dictionary, current_hp: float) -> void:
	if is_fighting:
		return
	_creature_id  = creature_id
	_enemy        = enemy.duplicate()
	_creature_hp  = current_hp
	_enemy_hp     = float(enemy.get("hp", 50))
	_creature_turn = true
	is_fighting   = true
	EventBus.combat_started.emit(creature_id, _enemy, _creature_hp, _enemy_hp)
	_timer.start()

func stop_combat() -> void:
	if not is_fighting:
		return
	is_fighting = false
	_timer.stop()

func _on_turn_tick() -> void:
	if not is_fighting:
		return

	var creature = GameData.get_entity(_creature_id)
	if creature.is_empty():
		stop_combat()
		return

	var c_stats  = creature.get("base_stats", {})
	var c_atk    = float(c_stats.get("atk", 10))
	var c_def    = float(c_stats.get("def",  5))
	var bonuses  = PassiveSystem.get_combat_bonuses()
	c_atk += bonuses.get("atk_bonus", 0.0)
	c_def += bonuses.get("def_bonus", 0.0)

	var e_atk = float(_enemy.get("atk", 8))
	var e_def = float(_enemy.get("def", 3))

	if _creature_turn:
		var dmg   = maxf(c_atk - e_def, 1.0)
		_enemy_hp = maxf(_enemy_hp - dmg, 0.0)
		EventBus.combat_turn.emit("creature", dmg, _creature_hp, _enemy_hp)
		if _enemy_hp <= 0.0:
			_finish_combat(true)
			return
	else:
		var dmg      = maxf(e_atk - c_def, 0.0)
		_creature_hp = maxf(_creature_hp - dmg, 0.0)
		EventBus.combat_turn.emit("enemy", dmg, _creature_hp, _enemy_hp)
		if _creature_hp <= 0.0:
			_finish_combat(false)
			return

	_creature_turn = not _creature_turn

func _finish_combat(victory: bool) -> void:
	is_fighting = false
	_timer.stop()
	EventBus.combat_ended.emit({
		"victory":               victory,
		"remaining_creature_hp": _creature_hp,
		"enemy":                 _enemy
	})
