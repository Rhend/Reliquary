# ============================================================
# CombatSystem.gd — Moteur de combat au tour par tour.
#
# Séquence d'un round :
#   Tick 1 : CREATURE_TURN → le héro attaque ; si ennemi mort → victoire
#   Tick 2 : ENEMY_TURN   → l'ennemi riposte ; si héro mort   → défaite
#   (retour à CREATURE_TURN, et ainsi de suite)
#
# Modificateurs appliqués à chaque calcul d'ATK / DEF :
#   • Passifs actifs        (PassiveSystem.get_combat_bonuses)
#   • Équipements portés    (GameData.get_equipment_bonuses)
#   • Maîtrise de l'ennemi  (GameData.get_mastery_combat_bonus)
#   • Modificateur de cycle (AdventureSystem.get_modifier_bonuses)
#
# La vitesse d'attaque (attack_speed_pct depuis l'équipement) réduit
# l'intervalle BASE_TURN_INTERVAL, avec un plancher à ATTACK_SPEED_FLOOR.
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

# Délai de base entre deux tours (secondes).
const BASE_TURN_INTERVAL: float = 1.0

# Variance multiplicative aléatoire appliquée à chaque frappe (±10 %).
# Évite un combat trop prévisible sans déséquilibrer les stats.
const DAMAGE_VARIANCE: float = 0.10

# Plancher de dégâts pour les attaques du héro (toujours au moins 1).
const HERO_MIN_DAMAGE: float = 1.0

# Plancher de dégâts pour les attaques ennemies (toujours au moins 1).
# Les ennemis percent toujours, même face à une DEF très élevée.
const ENEMY_MIN_DAMAGE: float = 1.0

# Plancher du multiplicateur d'intervalle : même avec une vitesse max,
# le délai ne descend jamais en dessous de 10 % du délai de base.
const ATTACK_SPEED_FLOOR: float = 0.10

# ─── Machine d'état ─────────────────────────────────────────

enum CombatState {
	IDLE,          # Aucun combat — attente du prochain événement
	CREATURE_TURN, # Tick suivant : le héro attaque
	ENEMY_TURN,    # Tick suivant : l'ennemi riposte
	ENDED          # Combat terminé, signal émis, attente du nettoyage
}

var _state: CombatState = CombatState.IDLE

# Propriété calculée : vrai pendant CREATURE_TURN ou ENEMY_TURN.
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

# Démarre un nouveau combat. Ignoré si un combat est déjà en cours.
func start_combat(creature_id: String, enemy: Dictionary, current_hp: float) -> void:
	if is_fighting:
		return

	_creature_id = creature_id
	_enemy       = enemy.duplicate()
	_creature_hp = current_hp
	_enemy_hp    = float(enemy.get("hp", 50))
	_state       = CombatState.CREATURE_TURN

	# attack_speed_pct réduit l'intervalle entre tours (plancher à ATTACK_SPEED_FLOOR)
	var speed_pct: float = GameData.get_equipment_bonuses().get("attack_speed_pct", 0.0)
	_timer.wait_time = BASE_TURN_INTERVAL * maxf(1.0 - speed_pct / 100.0, ATTACK_SPEED_FLOOR)
	_timer.start()

	EventBus.combat_started.emit(creature_id, _enemy, _creature_hp, _enemy_hp)

# Interrompt le combat en cours (arrêt manuel de l'aventure).
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
		_: pass   # IDLE ou ENDED : le timer ne devrait pas tourner ici

# Tour du héro : il attaque l'ennemi.
func _do_creature_attack() -> void:
	var dmg   = _calc_damage(_compute_creature_atk(), float(_enemy.get("def", 3)), HERO_MIN_DAMAGE)
	_enemy_hp = maxf(_enemy_hp - dmg, 0.0)
	EventBus.combat_turn.emit("creature", dmg, _creature_hp, _enemy_hp)

	if _enemy_hp <= 0.0:
		_finish_combat(true)
	else:
		_state = CombatState.ENEMY_TURN

# Tour de l'ennemi : il riposte.
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
#  Calcul des statistiques effectives
# ═══════════════════════════════════════════════════════════

# ATK totale du héro = (base + passifs + équipement + maîtrise) × mod de cycle × combo.
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

# DEF totale du héro = (base + passifs + équipement) × mod de cycle.
# Le mod Frénésie peut passer def_mult à 0.6, ce qui est volontaire.
func _compute_creature_def() -> float:
	var c_stats  = GameData.get_effective_stats(_creature_id)
	var passives = PassiveSystem.get_combat_bonuses()
	var equip    = GameData.get_equipment_bonuses()
	var mod      = AdventureSystem.get_modifier_bonuses()

	var def = float(c_stats.get("def", 5))
	def += passives.get("def_bonus", 0.0)
	def += equip.get("def", 0.0)   # boucliers et armures contribuent à la DEF
	def *= mod.get("def_mult", 1.0)
	return def

# Formule de dégâts : atk × rand(0.9–1.1) − def, plancher à min_dmg.
func _calc_damage(atk: float, def: float, min_dmg: float) -> float:
	var raw = atk * randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE) - def
	return maxf(raw, min_dmg)
