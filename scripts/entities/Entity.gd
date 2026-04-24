class_name Entity
extends RefCounted

var id:          String = ""
var entity_name: String = ""
var entity_type: String = ""
var current_tier: int   = 0
var current_xp:  float  = 0.0
var base_stats:  Dictionary = {}
var passive_slots:       Array = []
var unlocked_passives:   Array = []

func load_from_data(data: Dictionary) -> void:
	id               = data.get("id",                "")
	entity_name      = data.get("name",              "")
	entity_type      = data.get("entity_type",       "")
	current_tier     = data.get("current_tier",      0)
	current_xp       = data.get("current_xp",        0.0)
	base_stats       = data.get("base_stats",        {})
	passive_slots    = data.get("passive_slots",     [])
	unlocked_passives = data.get("unlocked_passives", [])

func get_tier_name() -> String:
	return GameData.get_tier_name(current_tier)

func can_evolve() -> bool:
	if current_tier >= GameData.MAX_TIER:
		return false
	var next_idx = current_tier + 1
	if next_idx >= GameData.xp_thresholds.size():
		return false
	return current_xp >= float(GameData.xp_thresholds[next_idx])

func get_stat(stat_name: String, default_value: float = 0.0) -> float:
	return float(base_stats.get(stat_name, default_value))

func to_dict() -> Dictionary:
	return {
		"id":                id,
		"entity_type":       entity_type,
		"current_tier":      current_tier,
		"current_xp":        current_xp,
		"unlocked_passives": unlocked_passives
	}
