# ============================================================
# CombatSystem.gd — Moteur de combat au tour par tour.
#
# Séquence d'un round :
#   Tick 1 : CREATURE_TURN → le héro attaque, si ennemi mort → victoire
#   Tick 2 : ENEMY_TURN   → l'ennemi riposte, si héro mort   → défaite
#   (puis retour à CREATURE_TURN, etc.)
#
# Modificateurs appliqués à chaque calcul d'ATK / DEF :
#   • Passifs actifs        (PassiveSystem.get_combat_bonuses)
#   • Équipements portés    (GameData.get_equipment_bonuses)
#   • Maîtrise de l'ennemi  (GameData.get_mastery_combat_bonus)
#   • Modificateur de cycle (AdventureSystem.get_modifier_bonuses)
#
# La vitesse d'attaque (attack_speed_pct depuis l'équipement) réduit
# le délai BASE_TURN_INTERVAL entre deux ticks de combat.
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

# Délai de base entre deux tours (secondes).
const BASE_TURN_INTERVAL: float = 1.0

# Variance multiplicative appliquée à chaque frappe (±10 %).
# Évite un combat trop prévisible sans déséquilibrer les stats.
const DAMAGE_VARIANCE: float = 0.10

# ─── Machine d'état ─────────────────────────────────────────

enum CombatState {
	IDLE,          # Aucun combat — attente du prochain événement
	CREATURE_TURN, # Tick suivant : le héro attaque
	ENEMY_TURN,    # Tick suivant : l'ennemi riposte
	ENDED          # Combat terminé, signal émis, attente du nettoyage
}

var _state: CombatState = CombatState.IDLE

# Propriété calculée pour la compatibilité avec AdventureSystem.
var is_fighting: bool:
	get: return _state == CombatState.CREATURE_TURN or _state == CombatState.ENEMY_TURN

# ─── État du combat en cours ─────────────────────────────────

var _timer:       Timer
var _creature_id: String     = ""
var _enemy:       Dictionary = {}
var _creature_hp: float      = 0.0
var _enemy_hp:    float      = 0.0

func _ready() -> void:
	_timer           = Timer.new()
	_timer.one_shot  = false
	_timer.timeout.connect(_on_turn_tick)
	add_child(_timer)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Démarre un nouveau combat.  Ignoré si un combat est déjà en cours.
func start_combat(creature_id: String, enemy: Dictionary, current_hp: float) -> void:
	if is_fighting:
		return

	_creature_id = creature_id
	_enemy       = enemy.duplicate()
	_creature_hp = current_hp
	_enemy_hp    = float(enemy.get("hp", 50))
	_state       = CombatState.CREATURE_TURN

	# La vitesse d'attaque raccourcit l'intervalle (plancher à 10 % du temps de base)
	var speed_pct: float  = GameData.get_equipment_bonuses().get("attack_speed_pct", 0.0)
	_timer.wait_time = BASE_TURN_INTERVAL * maxf(1.0 - speed_pct / 100.0, 0.10)
	_timer.start()

	EventBus.combat_started.emit(creature_id, _enemy, _creature_hp, _enemy_hp)

# Interrompt le combat (utilisé lors d'un arrêt d'aventure manuel).
func stop_combat() -> void:
	if not is_fighting:
		return
	_state = CombatState.ENDED
	_timer.stop()

# ═══════════════════════════════════════════════════════════
#  Boucle de combat
# ═══════════════════════════════════════════════════════════

func _on_turn_tick() -> void:
	match _state:
		CombatState.CREATURE_TURN: _do_creature_attack()
		CombatState.ENEMY_TURN:    _do_enemy_attack()
		_: pass   # IDLE ou ENDED : le timer ne devrait pas tourner

# Tour du héro : il attaque l'ennemi et l'on vérifie s'il est mort.
func _do_creature_attack() -> void:
	var dmg   = _calc_damage(_compute_creature_atk(), float(_enemy.get("def", 3)), 1.0)
	_enemy_hp = maxf(_enemy_hp - dmg, 0.0)
	EventBus.combat_turn.emit("creature", dmg, _creature_hp, _enemy_hp)

	if _enemy_hp <= 0.0:
		_finish_combat(true)
	else:
		_state = CombatState.ENEMY_TURN   # L'ennemi riposte au prochain tick

# Tour de l'ennemi : il riposte et l'on vérifie si le héro est mort.
func _do_enemy_attack() -> void:
	var dmg      = _calc_damage(float(_enemy.get("atk", 8)), _compute_creature_def(), 0.0)
	_creature_hp = maxf(_creature_hp - dmg, 0.0)
	EventBus.combat_turn.emit("enemy", dmg, _creature_hp, _enemy_hp)

	if _creature_hp <= 0.0:
		_finish_combat(false)
	else:
		_state = CombatState.CREATURE_TURN   # Le héro reattaque au prochain tick

func _finish_combat(victory: bool) -> void:
	_state = CombatState.ENDED
	_timer.stop()
	EventBus.combat_ended.emit({
		"victory":               victory,
		"remaining_creature_hp": _creature_hp,
		"enemy":                 _enemy
	})

# ═══════════════════════════════════════════════════════════
#  Calcul des statistiques effectives
# ═══════════════════════════════════════════════════════════

# ATK totale du héro :
#   base_stats.atk  (scalée par tier)
#   + bonus passifs
#   + bonus équipements
#   + bonus de maîtrise face à cet ennemi spécifique
#   × multiplicateur du modificateur de cycle
func _compute_creature_atk() -> float:
	var c_stats  = GameData.get_effective_stats(_creature_id)
	var passives = PassiveSystem.get_combat_bonuses()
	var equip    = GameData.get_equipment_bonuses()
	var mod      = AdventureSystem.get_modifier_bonuses()

	var atk = float(c_stats.get("atk", 10))
	atk += passives.get("atk_bonus", 0.0)
	atk += equip.get("atk", 0.0)
	atk += GameData.get_mastery_combat_bonus(_enemy.get("id", ""))
	atk *= mod.get("atk_mult", 1.0)
	return atk

# DEF totale du héro :
#   base_stats.def (scalée par tier)
#   + bonus passifs
#   × modificateur de cycle (peut être 0 si mode Berserk est actif)
func _compute_creature_def() -> float:
	var c_stats  = GameData.get_effective_stats(_creature_id)
	var passives = PassiveSystem.get_combat_bonuses()
	var mod      = AdventureSystem.get_modifier_bonuses()

	var def = float(c_stats.get("def", 5))
	def += passives.get("def_bonus", 0.0)
	def *= mod.get("def_mult", 1.0)
	return def

# Formule de dégâts avec variance aléatoire et plancher.
# raw = atk × rand(0.9–1.1) − def, ≥ min_dmg
func _calc_damage(atk: float, def: float, min_dmg: float) -> float:
	var raw = atk * randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE) - def
	return maxf(raw, min_dmg)
