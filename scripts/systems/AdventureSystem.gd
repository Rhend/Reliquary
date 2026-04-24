extends Node

# Délai entre la fin d'un événement et le déclenchement du suivant.
const BETWEEN_EVENTS_DELAY: float = 2.0

var is_running:       bool   = false
var current_biome_id: String = ""
var current_hp:       float  = 0.0

var _event_timer: Timer

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
			GameData.record_encounter(enemy.get("id",""), enemy.get("name","?"), "Créature", current_biome_id, 0.0)
			EventBus.adventure_event_resolved.emit(event_data)
			# Lance le combat visuel — le prochain événement attendra combat_ended
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
				var trap           = traps[randi() % traps.size()]
				current_hp        -= float(trap.get("damage", 10))
				event_data["trap"] = trap
				GameData.record_encounter(trap.get("id",""), trap.get("name","?"), "Piège", current_biome_id, 5.0)
			EventBus.adventure_event_resolved.emit(event_data)
			if current_hp <= 0.0:
				_end_adventure(false)
			else:
				_apply_regen(creature_id)
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
		MasterySystem.add_xp_to_all_active(xp_base, gen_tier)
		MasterySystem.add_xp_to_entity(current_biome_id, xp_base * 0.4, gen_tier)
		GameData.record_encounter(enemy.get("id",""), enemy.get("name","?"), "Créature", current_biome_id, xp_base)
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
	var equip_hp        = GameData.get_equipment_bonuses().get("hp", 0.0)
	var effective_stats = GameData.get_effective_stats(creature_id)
	var max_hp          = float(effective_stats.get("hp", 100)) + equip_hp
	current_hp          = minf(current_hp + max_hp * 0.15, max_hp)

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

func _end_adventure(victory: bool) -> void:
	is_running = false
	_event_timer.stop()
	EventBus.adventure_cycle_ended.emit({
		"victory":     victory,
		"biome_id":    current_biome_id,
		"creature_id": GameData.player.get("active_creature_id", "")
	})
