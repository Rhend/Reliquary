# ============================================================
# PassiveSystem.gd — Gestion des effets de passifs actifs.
#
# Un "passif" est une entité de type "passive" débloquée sur
# une créature ou un biome à un certain tier.  Ses effets
# sont cumulés dans _active_effects et consultés par
# CombatSystem à chaque tour.
#
# Le cache est recalculé entièrement (clear + rebuild) à chaque
# changement de passifs actifs, ce qui garantit la cohérence
# même si des passifs sont retirés.
# ============================================================
extends Node

# Cache des effets cumulés : effect_id (string) → valeur totale (float).
# Exemples d'effect_id : "atk_bonus", "def_bonus", "hp_bonus"
var _active_effects: Dictionary = {}

func _ready() -> void:
	# Recalcule le cache à chaque événement susceptible de changer les passifs actifs
	EventBus.passive_unlocked.connect(_on_refresh_trigger)
	EventBus.entity_evolved.connect(_on_refresh_trigger)
	EventBus.load_completed.connect(_on_refresh_trigger)

# ─── Recalcul du cache ──────────────────────────────────────

# Vide et reconstruit entièrement le cache des effets actifs.
# Appelé chaque fois que la liste des passifs actifs peut avoir changé.
func refresh_active_passives() -> void:
	_active_effects.clear()

	# Applique les passifs débloqués de la créature active
	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id != "":
		_apply_entity_passives(creature_id)

	# Applique les passifs actifs additionnels (placés manuellement par le joueur)
	for passive_id in GameData.player.get("active_passives", []):
		_apply_passive_effects(passive_id)

	EventBus.passives_refreshed.emit()

# Parcourt les passifs débloqués d'une entité et accumule leurs effets.
func _apply_entity_passives(entity_id: String) -> void:
	var entity = GameData.get_entity(entity_id)
	for passive_id in entity.get("unlocked_passives", []):
		_apply_passive_effects(passive_id)

# Accumule les effets d'un passif dans le cache.
func _apply_passive_effects(passive_id: String) -> void:
	var passive = GameData.get_entity(passive_id)
	if passive.is_empty():
		return
	for effect in passive.get("base_stats", {}).get("effects", []):
		var eid   = effect.get("id",    "")
		var value = float(effect.get("value", 0.0))
		if eid != "":
			_active_effects[eid] = _active_effects.get(eid, 0.0) + value

# ─── Accesseurs ─────────────────────────────────────────────

# Retourne les bonus de combat issus des passifs actifs.
# Retourne { atk_bonus:0, def_bonus:0, hp_bonus:0 } si aucun passif actif.
func get_combat_bonuses() -> Dictionary:
	return {
		"atk_bonus": _active_effects.get("atk_bonus", 0.0),
		"def_bonus": _active_effects.get("def_bonus", 0.0),
		"hp_bonus":  _active_effects.get("hp_bonus",  0.0)
	}

# Retourne la valeur cumulée d'un effet arbitraire.
func get_effect(effect_id: String) -> float:
	return _active_effects.get(effect_id, 0.0)

# ─── Réactions aux signaux ──────────────────────────────────

# Callback unique partagé par plusieurs signaux de rafraîchissement.
# Les paramètres des signaux sont ignorés ; seul le déclenchement compte.
func _on_refresh_trigger(_a = null, _b = null) -> void:
	refresh_active_passives()
