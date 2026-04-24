class_name Biome
extends Entity

func get_event_table() -> Dictionary:
	return base_stats.get("event_table", {
		"combat":   0.70,
		"positive": 0.15,
		"trap":     0.15
	})

func get_enemies() -> Array:
	return base_stats.get("enemies", [])

func get_positive_events() -> Array:
	return base_stats.get("positive_events", [])

func get_traps() -> Array:
	return base_stats.get("traps", [])
