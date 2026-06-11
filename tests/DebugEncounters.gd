# Diagnostic temporaire : distribution des rencontres + état des pools,
# puis simulation d'une vraie expédition accélérée (time_scale).
extends Node

func _ready() -> void:
	# Ne JAMAIS écrire la sauvegarde pendant un test.
	for sig: Signal in [EventBus.xp_gained, EventBus.bestiary_updated,
			EventBus.resources_changed, EventBus.entity_evolved,
			EventBus.passive_unlocked, EventBus.equipment_changed,
			EventBus.equipement_evolue]:
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)

	for bid: String in ["biome_foret", "biome_marecage", "biome_montagne"]:
		var biome := GameData.get_entity(bid)
		print("%s → pieges:%d benedictions:%d" % [
			bid,
			(biome.get("pieges", []) as Array).size(),
			(biome.get("benedictions", []) as Array).size(),
		])

	AdventureSystem.current_biome_id = "biome_foret"
	var counts := {"creature": 0, "benediction": 0, "trap": 0}
	for i in 10000:
		counts[AdventureSystem._roll_encounter_type()] += 1
	print("rolls x10000 : ", counts)

	# ── Vraie expédition accélérée ──────────────────────────
	Engine.time_scale = 25.0
	var events: Dictionary = {"creature": 0, "benediction": 0, "trap": 0}
	EventBus.adventure_event_resolved.connect(func(d: Dictionary) -> void:
		events[d.get("type", "?")] = int(events.get(d.get("type", "?"), 0)) + 1
	)
	AdventureSystem.start_adventure("biome_foret")
	await get_tree().create_timer(20.0 * 25.0).timeout
	Engine.time_scale = 1.0
	print("expédition réelle (~500 s simulées) : ", events)
	print("stats: events_total=%d combats_won=%d traps_triggered=%d positifs=%d" % [
		AdventureSystem._stats.events_total, AdventureSystem._stats.combats_won,
		AdventureSystem._stats.traps_triggered, AdventureSystem._stats.positive_events])
	SaveManager._save_dirty = false
	get_tree().quit(0)
