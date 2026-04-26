# ============================================================
# AdventureSystem.gd — Boucle principale d'aventure.
#
# Fonctionnement général :
#   1. start_adventure() initialise l'état et tire un modificateur.
#   2. _schedule_next_event() démarre un timer de 2 s.
#   3. À l'expiration, _process_event() tire le type d'événement
#      (combat / positif / piège) selon la table du biome.
#   4. Les événements de combat délèguent à CombatSystem et
#      attendent le signal combat_ended avant de continuer.
#   5. Après chaque événement, le héro régénère REGEN_PCT de
#      ses PV max (modifiable par le modificateur de cycle).
#
# Modificateurs de cycle :
#   Tirés aléatoirement au lancement, ils durent tout le cycle.
#   Exemples : XP ×1.5, régénération 30 %, pièges ignorés.
#
# Combo :
#   Incrémenté si le héro perd ≤ COMBO_HP_THRESHOLD % de ses PV.
#   Le combo donne un bonus d'ATK multiplicatif au combat suivant
#   (+5 % par niveau de combo au-dessus de 1).
#
# Luck de cycle :
#   Accumulée temporairement via les événements positifs de type "luck".
#   Elle s'ajoute à la luck permanente du joueur pour les rolls du cycle
#   et est réinitialisée à chaque nouvelle aventure.
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

const BETWEEN_EVENTS_DELAY: float = 2.0
const DEFAULT_REGEN_PCT:    float = 0.15
const COMBO_HP_THRESHOLD:   float = 0.25
const COMBO_ATK_BONUS_PCT:  float = 0.05   # +5 % ATK par niveau de combo au-dessus de 1

# ─── Modificateurs de cycle disponibles ─────────────────────
const CYCLE_MODIFIERS: Array = [
	{
		"id": "none", "name": "—", "desc": "", "xp_mult": 1.0
	},
	{
		"id": "bonus_xp", "name": "Cycle Chanceux",
		"desc": "XP ×1.5 ce cycle", "xp_mult": 1.5
	},
	{
		"id": "resilient", "name": "Endurance",
		"desc": "Régénère 30 % entre combats", "xp_mult": 0.8, "regen_pct": 0.30
	},
	{
		"id": "ghost", "name": "Fantôme",
		"desc": "Pièges ignorés, XP ×0.7", "xp_mult": 0.7, "ignore_traps": true
	},
	{
		"id": "berserker_mod", "name": "Frénésie",
		"desc": "ATK ×1.3, DEF ×0.6", "xp_mult": 1.1, "atk_mult": 1.3, "def_mult": 0.6
	},
]

# ─── État runtime ────────────────────────────────────────────

var is_running:        bool       = false
var current_biome_id:  String     = ""
var current_hp:        float      = 0.0
var current_modifier:  Dictionary = {}

var _event_timer:      Timer
var _combo_count:      int   = 0
var _combat_start_hp:  float = 0.0

# ─── Statistiques du cycle en cours ─────────────────────────

var _cycle_luck:        int   = 0    # Luck temporaire accumulée par les events positifs
var _cycle_xp:          float = 0.0  # XP totale gagnée par le héro ce cycle
var _cycle_loot:        int   = 0    # Nombre total d'objets droppés
var _cycle_combo_max:   int   = 0    # Meilleur combo atteint
var _cycle_combats_won: int   = 0    # Combats remportés
var _cycle_events:      int   = 0    # Événements totaux (hors combats)

func _ready() -> void:
	_event_timer          = Timer.new()
	_event_timer.one_shot = true
	_event_timer.timeout.connect(_on_event_timer)
	add_child(_event_timer)
	EventBus.combat_ended.connect(_on_combat_ended)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

func start_adventure(biome_id: String) -> void:
	var biome       = GameData.get_entity(biome_id)
	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	if biome.is_empty() or creature.is_empty():
		push_error("AdventureSystem: biome ou créature manquant pour démarrer")
		return

	current_biome_id = biome_id   # Nécessaire avant _get_max_hp()
	is_running       = true
	current_hp       = _get_max_hp()

	_combo_count     = 0

	# Réinitialise les statistiques du cycle
	_cycle_luck        = 0
	_cycle_xp          = 0.0
	_cycle_loot        = 0
	_cycle_combo_max   = 0
	_cycle_combats_won = 0
	_cycle_events      = 0

	_pick_modifier()

	GameData.player["active_biome_id"] = biome_id
	EventBus.adventure_started.emit(biome_id)
	_schedule_next_event()

func stop_adventure() -> void:
	if not is_running:
		return
	is_running = false
	_event_timer.stop()
	if CombatSystem.is_fighting:
		CombatSystem.stop_combat()
	EventBus.adventure_stopped.emit()

# Bonus ATK/DEF du modificateur de cycle + bonus de combo.
# Le combo donne +COMBO_ATK_BONUS_PCT par niveau au-dessus de 1.
func get_modifier_bonuses() -> Dictionary:
	var combo_mult = 1.0 + maxf(0.0, float(_combo_count - 1)) * COMBO_ATK_BONUS_PCT
	return {
		"atk_mult": float(current_modifier.get("atk_mult", 1.0)) * combo_mult,
		"def_mult": float(current_modifier.get("def_mult", 1.0))
	}

# Luck effective = luck permanente du joueur + luck temporaire du cycle.
func _get_effective_luck() -> int:
	return int(GameData.player.get("luck", 0)) + _cycle_luck

# ═══════════════════════════════════════════════════════════
#  Boucle d'événements
# ═══════════════════════════════════════════════════════════

func _on_event_timer() -> void:
	if is_running:
		_process_event()

func _process_event() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var event_type  = _roll_event_type()
	var event_data  = {
		"type":        event_type,
		"biome_id":    current_biome_id,
		"creature_id": creature_id
	}

	match event_type:
		"combat":   _handle_combat_event(creature_id, event_data)
		"positive": _handle_positive_event(creature_id, event_data)
		"trap":     _handle_trap_event(creature_id, event_data)

# ─── Combat ──────────────────────────────────────────────────

func _handle_combat_event(creature_id: String, event_data: Dictionary) -> void:
	var biome   = GameData.get_entity(current_biome_id)
	var enemies = biome.get("base_stats", {}).get("enemies", [])

	if enemies.is_empty():
		_schedule_next_event()
		return

	var enemy           = enemies[randi() % enemies.size()].duplicate()
	event_data["enemy"] = enemy
	_combat_start_hp    = current_hp

	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, 0.0
	)
	EventBus.adventure_event_resolved.emit(event_data)
	CombatSystem.start_combat(creature_id, enemy, current_hp)

# ─── Événement positif ───────────────────────────────────────

func _handle_positive_event(creature_id: String, event_data: Dictionary) -> void:
	var biome  = GameData.get_entity(current_biome_id)
	var events = biome.get("base_stats", {}).get("positive_events", [])

	if not events.is_empty():
		var evt              = events[randi() % events.size()]
		event_data["effect"] = evt
		GameData.record_encounter(
			evt.get("id", ""), evt.get("name", "?"), "Événement", current_biome_id, 5.0
		)
		_apply_positive_effect(evt)
		_cycle_events += 1

	EventBus.adventure_event_resolved.emit(event_data)
	_apply_regen(creature_id)
	_schedule_next_event()

func _apply_positive_effect(evt: Dictionary) -> void:
	var effect_type  = evt.get("effect", "")
	var effect_value = float(evt.get("value", 0.0))

	match effect_type:
		"heal":
			var max_hp      = _get_max_hp()
			var healed      = minf(effect_value, max_hp - current_hp)
			current_hp      = minf(current_hp + effect_value, max_hp)
			EventBus.heal_applied.emit(healed, current_hp)

		"luck":
			_cycle_luck += int(effect_value)
			EventBus.luck_boosted.emit(_cycle_luck)

# ─── Piège ────────────────────────────────────────────────────

func _handle_trap_event(creature_id: String, event_data: Dictionary) -> void:
	var biome = GameData.get_entity(current_biome_id)
	var traps = biome.get("base_stats", {}).get("traps", [])

	if traps.is_empty():
		EventBus.adventure_event_resolved.emit(event_data)
		_schedule_next_event()
		return

	var trap           = traps[randi() % traps.size()]
	event_data["trap"] = trap

	if current_modifier.get("ignore_traps", false):
		event_data["ignored"] = true
		GameData.record_encounter(
			trap.get("id", ""), trap.get("name", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(event_data)
		_apply_regen(creature_id)
		_schedule_next_event()
	else:
		_cycle_events += 1
		current_hp -= float(trap.get("damage", 10))
		GameData.record_encounter(
			trap.get("id", ""), trap.get("name", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(event_data)
		if current_hp <= 0.0:
			_end_adventure(false)
		else:
			_apply_regen(creature_id)
			_schedule_next_event()

# ═══════════════════════════════════════════════════════════
#  Résultat de combat
# ═══════════════════════════════════════════════════════════

func _on_combat_ended(result: Dictionary) -> void:
	if not is_running:
		return

	current_hp = result.get("remaining_creature_hp", 0.0)

	if result.get("victory", false):
		_resolve_victory(result.get("enemy", {}))
	else:
		_end_adventure(false)

func _resolve_victory(enemy: Dictionary) -> void:
	var xp_base    = float(enemy.get("xp_reward", 10))
	var gen_tier   = int(enemy.get("tier", 0))
	var xp_mult    = float(current_modifier.get("xp_mult", 1.0))
	var xp_earned  = xp_base * xp_mult

	# XP aux passifs actifs
	MasterySystem.add_xp_to_all_active(xp_earned, gen_tier)

	# XP au biome (40 % de l'XP du cycle)
	MasterySystem.add_xp_to_entity(current_biome_id, xp_earned * 0.40, gen_tier)

	# XP à la créature active (60 % de l'XP de base)
	var creature_id = GameData.player.get("active_creature_id", "")
	MasterySystem.add_xp_to_entity(creature_id, xp_base * 0.60, gen_tier)

	# Hall des Évolutions
	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, xp_base
	)

	# Loot
	_drop_loot(enemy)

	# Combo
	var max_hp      = _get_max_hp()
	var hp_lost_pct = (_combat_start_hp - current_hp) / max_hp if max_hp > 0.0 else 1.0
	if hp_lost_pct <= COMBO_HP_THRESHOLD:
		_combo_count += 1
	else:
		_combo_count = 0
	EventBus.combo_changed.emit(_combo_count)

	# Statistiques du cycle
	_cycle_xp          += xp_earned
	_cycle_combats_won += 1
	_cycle_combo_max    = maxi(_cycle_combo_max, _combo_count)

	_apply_regen(creature_id)
	_schedule_next_event()

# ═══════════════════════════════════════════════════════════
#  Utilitaires internes
# ═══════════════════════════════════════════════════════════

func _apply_regen(_creature_id: String) -> void:
	var regen_pct = float(current_modifier.get("regen_pct", DEFAULT_REGEN_PCT))
	var max_hp    = _get_max_hp()
	current_hp    = minf(current_hp + max_hp * regen_pct, max_hp)

func _get_max_hp() -> float:
	var creature_id = GameData.player.get("active_creature_id", "")
	var equip_hp    = GameData.get_equipment_bonuses().get("hp", 0.0)
	var hp_bonus    = PassiveSystem.get_combat_bonuses().get("hp_bonus", 0.0)
	return float(GameData.get_effective_stats(creature_id).get("hp", 100)) + equip_hp + hp_bonus

func _schedule_next_event() -> void:
	if not is_running:
		return
	_event_timer.wait_time = BETWEEN_EVENTS_DELAY
	_event_timer.start()

func _roll_event_type() -> String:
	var biome       = GameData.get_entity(current_biome_id)
	var event_table = biome.get("base_stats", {}).get("event_table", {
		"combat": 0.70, "positive": 0.15, "trap": 0.15
	})

	var luck        = float(_get_effective_luck())
	var trap_base   = float(event_table.get("trap", 0.15))
	var luck_shift  = minf(luck * 0.01, trap_base)

	var combat_chance   = float(event_table.get("combat",   0.70))
	var positive_chance = float(event_table.get("positive", 0.15)) + luck_shift

	var roll = randf()
	if roll < combat_chance:
		return "combat"
	elif roll < combat_chance + positive_chance:
		return "positive"
	else:
		return "trap"

func _pick_modifier() -> void:
	var roll = randf()
	if roll < 0.04:
		current_modifier = CYCLE_MODIFIERS[4]   # Frénésie       — 4 %
	elif roll < 0.09:
		current_modifier = CYCLE_MODIFIERS[3]   # Fantôme        — 5 %
	elif roll < 0.19:
		current_modifier = CYCLE_MODIFIERS[2]   # Endurance      — 10 %
	elif roll < 0.34:
		current_modifier = CYCLE_MODIFIERS[1]   # Cycle Chanceux — 15 %
	else:
		current_modifier = CYCLE_MODIFIERS[0]   # Normal         — 66 %
	EventBus.modifier_activated.emit(current_modifier)

func _drop_loot(enemy: Dictionary) -> void:
	var loot_table = enemy.get("loot_table", [])
	if loot_table.is_empty():
		return

	var drops:      Array = []
	var luck_bonus: float = float(_get_effective_luck()) * 0.01

	for entry in loot_table:
		var roll_threshold = float(entry.get("chance", 0.0)) + luck_bonus
		if randf() < roll_threshold:
			var item_id = entry.get("item_id", "")
			if item_id == "":
				continue
			GameData.add_resource(item_id, 1)
			var res = GameData.get_entity(item_id)
			drops.append({
				"item_id": item_id,
				"name":    res.get("name", item_id),
				"qty":     1
			})

	if not drops.is_empty():
		_cycle_loot += drops.size()
		EventBus.loot_dropped.emit(drops, enemy.get("name", "?"))

func _end_adventure(victory: bool) -> void:
	is_running = false
	_event_timer.stop()
	_cycle_combo_max = maxi(_cycle_combo_max, _combo_count)

	EventBus.adventure_cycle_ended.emit({
		"victory":      victory,
		"biome_id":     current_biome_id,
		"creature_id":  GameData.player.get("active_creature_id", ""),
		"modifier":     current_modifier,
		"xp_total":     _cycle_xp,
		"loot_total":   _cycle_loot,
		"combo_max":    _cycle_combo_max,
		"combats_won":  _cycle_combats_won,
		"events":       _cycle_events,
		"cycle_luck":   _cycle_luck,
	})
