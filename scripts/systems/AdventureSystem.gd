extends Node

const BETWEEN_EVENTS_DELAY: float = 2.0

const CYCLE_MODIFIERS: Array = [
	{ "id": "none",      "name": "—",              "desc": "",                              "xp_mult": 1.0 },
	{ "id": "bonus_xp",  "name": "Cycle Chanceux",  "desc": "XP ×1.5 ce cycle",            "xp_mult": 1.5 },
	{ "id": "resilient", "name": "Endurance",       "desc": "Régénère 30% entre combats",   "xp_mult": 0.8, "regen_pct": 0.30 },
	{ "id": "ghost",     "name": "Fantôme",         "desc": "Pièges ignorés, XP ×0.7",     "xp_mult": 0.7, "ignore_traps": true },
]

var is_running:        bool       = false
var current_biome_id:  String     = ""
var current_hp:        float      = 0.0
var current_modifier:  Dictionary = {}

var _event_timer:      Timer
var _combo_count:      int   = 0
var _combat_start_hp:  float = 0.0

func _ready() -> void:
	_event_timer          = Timer.new()
	_event_timer.one_shot = true
	_event_timer.timeout.connect(_on_event_timer)
	add_child(_event_timer)
	EventBus.combat_ended.connect(_on_combat_ended)

func start_adventure(biome_id: String) -> void:
	var biome       = GameData.get_entity(biome_id)
	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	if biome.is_empty() or creature.is_empty():
		push_error("Biome ou créature manquant pour démarrer l'aventure")
		return

	current_biome_id = biome_id
	var equip_bonuses   = GameData.get_equipment_bonuses()
	var effective_stats = GameData.get_effective_stats(creature_id)
	current_hp = float(effective_stats.get("hp", 100)) + equip_bonuses.get("hp", 0.0)
	is_running = true
	_combo_count = 0
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

# Permet d'ajuster la vitesse depuis l'extérieur (outil de debug).
func set_interval(seconds: float) -> void:
	_event_timer.wait_time = maxf(seconds, 0.1)

# ─────────────────────────────────────────
#  Boucle d'événements
# ─────────────────────────────────────────

func _on_event_timer() -> void:
	if not is_running:
		return
	_process_event()

func _process_event() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var event_type  = _roll_event_type()
	var event_data  = { "type": event_type, "biome_id": current_biome_id, "creature_id": creature_id }

	match event_type:
		"combat":
			var biome   = GameData.get_entity(current_biome_id)
			var enemies = biome.get("base_stats", {}).get("enemies", [])
			if enemies.is_empty():
				_schedule_next_event()
				return
			var enemy          = enemies[randi() % enemies.size()].duplicate()
			event_data["enemy"] = enemy
			_combat_start_hp = current_hp
			GameData.record_encounter(enemy.get("id",""), enemy.get("name","?"), "Créature", current_biome_id, 0.0)
			EventBus.adventure_event_resolved.emit(event_data)
			CombatSystem.start_combat(creature_id, enemy, current_hp)

		"positive":
			var biome  = GameData.get_entity(current_biome_id)
			var events = biome.get("base_stats", {}).get("positive_events", [])
			if not events.is_empty():
				var evt            = events[randi() % events.size()]
				event_data["effect"] = evt
				GameData.record_encounter(evt.get("id",""), evt.get("name","?"), "Événement", current_biome_id, 5.0)
			EventBus.adventure_event_resolved.emit(event_data)
			_apply_regen(creature_id)
			_schedule_next_event()

		"trap":
			var biome = GameData.get_entity(current_biome_id)
			var traps = biome.get("base_stats", {}).get("traps", [])
			if not traps.is_empty():
				var trap = traps[randi() % traps.size()]
				event_data["trap"] = trap
				if current_modifier.get("ignore_traps", false):
					event_data["ignored"] = true
					GameData.record_encounter(trap.get("id",""), trap.get("name","?"), "Piège", current_biome_id, 5.0)
					EventBus.adventure_event_resolved.emit(event_data)
					_apply_regen(creature_id)
					_schedule_next_event()
				else:
					current_hp -= float(trap.get("damage", 10))
					GameData.record_encounter(trap.get("id",""), trap.get("name","?"), "Piège", current_biome_id, 5.0)
					EventBus.adventure_event_resolved.emit(event_data)
					if current_hp <= 0.0:
						_end_adventure(false)
					else:
						_apply_regen(creature_id)
						_schedule_next_event()
			else:
				EventBus.adventure_event_resolved.emit(event_data)
				_schedule_next_event()

# ─────────────────────────────────────────
#  Résultat de combat
# ─────────────────────────────────────────

func _on_combat_ended(result: Dictionary) -> void:
	if not is_running:
		return

	current_hp = result.get("remaining_creature_hp", 0.0)

	if result.get("victory", false):
		var enemy    = result.get("enemy", {})
		var xp_base  = float(enemy.get("xp_reward", 10))
		var gen_tier = int(enemy.get("tier", 0))
		var xp_mult  = float(current_modifier.get("xp_mult", 1.0))
		MasterySystem.add_xp_to_all_active(xp_base * xp_mult, gen_tier)
		MasterySystem.add_xp_to_entity(current_biome_id, xp_base * xp_mult * 0.4, gen_tier)
		GameData.record_encounter(enemy.get("id",""), enemy.get("name","?"), "Créature", current_biome_id, xp_base)
		_drop_loot(enemy)
		var max_hp       = _get_max_hp()
		var hp_lost_pct  = (_combat_start_hp - current_hp) / max_hp if max_hp > 0.0 else 1.0
		if hp_lost_pct <= 0.25:
			_combo_count += 1
		else:
			_combo_count = 0
		EventBus.combo_changed.emit(_combo_count)
		_apply_regen(GameData.player.get("active_creature_id", ""))
		_schedule_next_event()
	else:
		_end_adventure(false)

# ─────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────

func _apply_regen(creature_id: String) -> void:
	var creature = GameData.get_entity(creature_id)
	if creature.is_empty():
		return
	var regen_pct = float(current_modifier.get("regen_pct", 0.15))
	var max_hp    = _get_max_hp()
	current_hp    = minf(current_hp + max_hp * regen_pct, max_hp)

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

	var luck       = float(GameData.player.get("luck", 0))
	var trap_base  = float(event_table.get("trap", 0.15))
	var trap_shift = minf(luck * 0.01, trap_base)

	var combat_chance   = float(event_table.get("combat",   0.70))
	var positive_chance = float(event_table.get("positive", 0.15)) + trap_shift

	var roll = randf()
	if roll < combat_chance:
		return "combat"
	elif roll < combat_chance + positive_chance:
		return "positive"
	else:
		return "trap"

func _pick_modifier() -> void:
	var roll = randf()
	if roll < 0.05:
		current_modifier = CYCLE_MODIFIERS[3]
	elif roll < 0.15:
		current_modifier = CYCLE_MODIFIERS[2]
	elif roll < 0.30:
		current_modifier = CYCLE_MODIFIERS[1]
	else:
		current_modifier = CYCLE_MODIFIERS[0]
	EventBus.modifier_activated.emit(current_modifier)

func _drop_loot(enemy: Dictionary) -> void:
	var loot_table = enemy.get("loot_table", [])
	if loot_table.is_empty():
		return
	var drops: Array = []
	var luck_bonus = float(GameData.player.get("luck", 0)) * 0.01
	for entry in loot_table:
		if randf() < float(entry.get("chance", 0.0)) + luck_bonus:
			var item_id = entry.get("item_id", "")
			if item_id != "":
				GameData.add_resource(item_id, 1)
				var res = GameData.get_entity(item_id)
				drops.append({ "item_id": item_id, "name": res.get("name", item_id), "qty": 1 })
	if not drops.is_empty():
		EventBus.loot_dropped.emit(drops, enemy.get("name", "?"))

func get_modifier_bonuses() -> Dictionary:
	return {
		"atk_mult": float(current_modifier.get("atk_mult", 1.0)),
		"def_mult": float(current_modifier.get("def_mult", 1.0))
	}

func _get_max_hp() -> float:
	var creature_id = GameData.player.get("active_creature_id", "")
	var equip_hp    = GameData.get_equipment_bonuses().get("hp", 0.0)
	return float(GameData.get_effective_stats(creature_id).get("hp", 100)) + equip_hp

func _end_adventure(victory: bool) -> void:
	is_running = false
	_event_timer.stop()
	EventBus.adventure_cycle_ended.emit({
		"victory":     victory,
		"biome_id":    current_biome_id,
		"creature_id": GameData.player.get("active_creature_id", "")
	})
