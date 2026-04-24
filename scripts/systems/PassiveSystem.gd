extends Node

# Cache des effets actifs : effect_id -> valeur cumulée de tous les passifs actifs
var _active_effects: Dictionary = {}

func _ready() -> void:
	EventBus.passive_unlocked.connect(_on_passive_unlocked)
	EventBus.entity_evolved.connect(_on_entity_evolved)
	EventBus.load_completed.connect(_on_load_completed)

# Recalcule tous les effets depuis les passifs débloqués et actifs.
func refresh_active_passives() -> void:
	_active_effects.clear()

	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id != "":
		_apply_entity_passives(creature_id)

	for passive_id in GameData.player.get("active_passives", []):
		_apply_passive_effects(passive_id)

	EventBus.passives_refreshed.emit()

func _apply_entity_passives(entity_id: String) -> void:
	var entity = GameData.get_entity(entity_id)
	for passive_id in entity.get("unlocked_passives", []):
		_apply_passive_effects(passive_id)

func _apply_passive_effects(passive_id: String) -> void:
	var passive = GameData.get_entity(passive_id)
	if passive.is_empty():
		return
	for effect in passive.get("base_stats", {}).get("effects", []):
		var eid   = effect.get("id",    "")
		var value = float(effect.get("value", 0.0))
		if eid != "":
			_active_effects[eid] = _active_effects.get(eid, 0.0) + value

# Retourne les bonus de combat issus des passifs actifs.
func get_combat_bonuses() -> Dictionary:
	return {
		"atk_bonus": _active_effects.get("atk_bonus", 0.0),
		"def_bonus": _active_effects.get("def_bonus", 0.0),
		"hp_bonus":  _active_effects.get("hp_bonus",  0.0)
	}

func get_effect(effect_id: String) -> float:
	return _active_effects.get(effect_id, 0.0)

func _on_passive_unlocked(_entity_id: String, _passive_id: String) -> void:
	refresh_active_passives()

func _on_entity_evolved(_entity_id: String, _new_tier: int) -> void:
	refresh_active_passives()

func _on_load_completed() -> void:
	refresh_active_passives()
