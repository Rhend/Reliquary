class_name Passive
extends Entity

func get_effects() -> Array:
	return base_stats.get("effects", [])

func get_effect_value(effect_id: String) -> float:
	for effect in get_effects():
		if effect.get("id") == effect_id:
			return float(effect.get("value", 0.0))
	return 0.0
