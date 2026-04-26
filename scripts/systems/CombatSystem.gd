# ============================================================
# CombatSystem.gd — Moteur de combat au tour par tour.
#
# Séquence d'un round :
#   Tick 1 : CREATURE_TURN → le héro attaque ; si ennemi mort → victoire
#   Tick 2 : ENEMY_TURN   → l'ennemi riposte ; si héro mort   → défaite
#   (retour à CREATURE_TURN, et ainsi de suite)
#
# Optimisation tick :
#   _turn_cache est calculé UNE fois au début de chaque tick et partagé
#   par _compute_creature_atk() et _compute_creature_def().
#   Cela réduit de 4 à 1 les appels vers les autoloads externes par tick.
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

const BASE_TURN_INTERVAL: float = 1.0
const DAMAGE_VARIANCE:    float = 0.10
const HERO_MIN_DAMAGE:    float = 1.0    # le héro fait toujours au moins 1
const ENEMY_MIN_DAMAGE:   float = 1.0    # l'ennemi perce toujours, même face à une DEF haute
const ATTACK_SPEED_FLOOR: float = 0.10   # plancher du multiplicateur de vitesse

# ─── Machine d'état ─────────────────────────────────────────

enum CombatState {
	IDLE,          # Aucun combat en cours
	CREATURE_TURN, # Prochain tick : le héro attaque
	ENEMY_TURN,    # Prochain tick : l'ennemi riposte
	ENDED          # Combat terminé, signal émis
}

var _state: CombatState = CombatState.IDLE

var is_fighting: bool:
	get: return _state == CombatState.CREATURE_TURN or _state == CombatState.ENEMY_TURN

# ─── État du combat en cours ─────────────────────────────────

var _timer:       Timer
var _creature_id: String     = ""
var _enemy:       Dictionary = {}
var _creature_hp: float      = 0.0
var _enemy_hp:    float      = 0.0

# Cache des stats calculé une fois par tick, partagé entre ATK et DEF.
var _turn_cache: Dictionary = {}

func _ready() -> void:
	_timer          = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_on_turn_tick)
	add_child(_timer)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

func start_combat(creature_id: String, enemy: Dictionary, current_hp: float) -> void:
	if is_fighting:
		return

	_creature_id = creature_id
	_enemy       = enemy.duplicate()
	_creature_hp = current_hp
	_enemy_hp    = float(enemy.get("hp", 50))
	_state       = CombatState.CREATURE_TURN

	var speed_pct: float = GameData.get_equipment_bonuses().get("attack_speed_pct", 0.0)
	_timer.wait_time = BASE_TURN_INTERVAL * maxf(1.0 - speed_pct / 100.0, ATTACK_SPEED_FLOOR)
	_timer.start()

	EventBus.combat_started.emit(creature_id, _enemy, _creature_hp, _enemy_hp)

func stop_combat() -> void:
	if not is_fighting:
		return
	_state = CombatState.ENDED
	_timer.stop()

# ═══════════════════════════════════════════════════════════
#  Boucle de combat
# ═══════════════════════════════════════════════════════════

func _on_turn_tick() -> void:
	# Calcule toutes les stats une seule fois par tick pour les deux branches
	_turn_cache = {
		"c_stats":  GameData.get_effective_stats(_creature_id),
		"passives": PassiveSystem.get_combat_bonuses(),
		"equip":    GameData.get_equipment_bonuses(),
		"mod":      AdventureSystem.get_modifier_bonuses(),
	}
	match _state:
		CombatState.CREATURE_TURN: _do_creature_attack()
		CombatState.ENEMY_TURN:    _do_enemy_attack()
		_: pass

func _do_creature_attack() -> void:
	var dmg   = _calc_damage(_compute_creature_atk(), float(_enemy.get("def", 3)), HERO_MIN_DAMAGE)
	_enemy_hp = maxf(_enemy_hp - dmg, 0.0)
	EventBus.combat_turn.emit("creature", dmg, _creature_hp, _enemy_hp)

	if _enemy_hp <= 0.0:
		_finish_combat(true)
	else:
		_state = CombatState.ENEMY_TURN

func _do_enemy_attack() -> void:
	var dmg      = _calc_damage(float(_enemy.get("atk", 8)), _compute_creature_def(), ENEMY_MIN_DAMAGE)
	_creature_hp = maxf(_creature_hp - dmg, 0.0)
	EventBus.combat_turn.emit("enemy", dmg, _creature_hp, _enemy_hp)

	if _creature_hp <= 0.0:
		_finish_combat(false)
	else:
		_state = CombatState.CREATURE_TURN

func _finish_combat(victory: bool) -> void:
	_state = CombatState.ENDED
	_timer.stop()
	EventBus.combat_ended.emit({
		"victory":               victory,
		"remaining_creature_hp": _creature_hp,
		"enemy":                 _enemy
	})

# ═══════════════════════════════════════════════════════════
#  Calcul des statistiques — lit _turn_cache, jamais les autoloads directement
# ═══════════════════════════════════════════════════════════

func _compute_creature_atk() -> float:
	var atk = float(_turn_cache["c_stats"].get("atk", 10))
	atk += _turn_cache["passives"].get("atk_bonus", 0.0)
	atk += _turn_cache["equip"].get("atk", 0.0)
	atk += GameData.get_mastery_combat_bonus(_enemy.get("id", ""))
	atk *= _turn_cache["mod"].get("atk_mult", 1.0)
	return atk

func _compute_creature_def() -> float:
	var def = float(_turn_cache["c_stats"].get("def", 5))
	def += _turn_cache["passives"].get("def_bonus", 0.0)
	def += _turn_cache["equip"].get("def", 0.0)
	def *= _turn_cache["mod"].get("def_mult", 1.0)
	return def

# atk × rand(0.9–1.1) − def, plancher à min_dmg.
func _calc_damage(atk: float, def: float, min_dmg: float) -> float:
	var raw = atk * randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE) - def
	return maxf(raw, min_dmg)
