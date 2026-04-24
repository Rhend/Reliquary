class_name Equipment
extends Entity

func get_slot() -> String:
	return base_stats.get("slot", "")

func get_bonuses() -> Dictionary:
	return base_stats.get("bonuses", {})
