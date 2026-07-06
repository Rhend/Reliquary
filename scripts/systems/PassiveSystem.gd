# ============================================================
# PassiveSystem.gd — Gestion des effets de passifs actifs.
#
# Deux catégories d'effets :
#   1. Bonus plats (atk_bonus, def_bonus, hp_bonus, hp_regen_pct…)
#      → lus depuis tier_effects[tier].effects (ancien format compatible)
#      → cumulés dans _active_effects, consultés via get_combat_bonuses()
#
#   2. Effets conditionnels (poison on-hit)
#      → lus depuis tier_effects[tier].conditional_effects (nouveau champ)
#      → exposés via get_passive_combat_effects() — consommateur : l'intégration
#        CTB à venir (l'ancien resolver temps réel a été supprimé)
#      → cooldowns génériques gérés par passive_cooldowns (persistants entre combats)
#
# Rétrocompatibilité : les passifs sans conditional_effects sont ignorés
# par la partie conditionnelle, sans impact sur les bonus plats.
# ============================================================
extends Node

# Cache des effets plats cumulés : effect_id → valeur totale (float).
var _active_effects: Dictionary = {}

# Cooldowns génériques par passif : passive_id → cycles restants avant réutilisation.
# Décrémenté par decrement_cooldowns() (persistant entre combats via SaveManager).
var passive_cooldowns: Dictionary = {}

func _ready() -> void:
	EventBus.passive_unlocked.connect(_on_refresh_trigger)
	EventBus.entity_evolved.connect(_on_refresh_trigger)
	EventBus.load_completed.connect(_on_refresh_trigger)

# ═══════════════════════════════════════════════════════════
#  Recalcul du cache des effets plats
# ═══════════════════════════════════════════════════════════

# Vide et reconstruit entièrement le cache des effets plats.
func refresh_active_passives() -> void:
	_active_effects.clear()
	for entity_id in GameData.entities:
		var et = GameData.entities[entity_id].get("entity_type", "")
		if et == Enums.EntityType.CREATURE or et == Enums.EntityType.BIOME:
			_apply_entity_passives(entity_id)
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
	var tier: int      = passive.get("maitrise_actuelle", 0) as int
	var te_list: Array = passive.get("tier_effects", [])
	var effects: Array = []
	if tier < te_list.size():
		effects = te_list[tier].get("effects", [])
	if effects.is_empty() and not te_list.is_empty():
		effects = te_list[0].get("effects", [])
	for effect in effects:
		var eid   = effect.get("id",    "")
		var value = float(effect.get("value", 0.0))
		if eid != "":
			_active_effects[eid] = _active_effects.get(eid, 0.0) + value

# ═══════════════════════════════════════════════════════════
#  Accesseurs — Bonus plats
# ═══════════════════════════════════════════════════════════

# Retourne les bonus de combat issus des passifs actifs.
func get_combat_bonuses() -> Dictionary:
	return {
		"atk_bonus": _active_effects.get("atk_bonus", 0.0),
		"def_bonus": _active_effects.get("def_bonus", 0.0),
		"hp_bonus":  _active_effects.get("hp_bonus",  0.0)
	}

# Retourne la valeur cumulée d'un effet arbitraire.
func get_effect(effect_id: String) -> float:
	return _active_effects.get(effect_id, 0.0)

# ═══════════════════════════════════════════════════════════
#  Effets conditionnels — fournis au combat (intégration CTB à venir)
# ═══════════════════════════════════════════════════════════

# Retourne les effets conditionnels actifs pour la prochaine résolution de combat.
# h_atk : ATK effective du héros, nécessaire pour calculer les dégâts de poison passif.
#
# Résultat :
#   "passive_poison" → {} si pas de Contact Venimeux, sinon config complète
func get_passive_combat_effects(h_atk: float) -> Dictionary:
	var result := { "passive_poison": {} }

	for pid in _get_all_active_passive_ids():
		var passive := GameData.get_entity(pid)
		if passive.is_empty():
			continue
		var tier: int      = passive.get("maitrise_actuelle", 0) as int
		var te_list: Array = passive.get("tier_effects", [])
		if tier >= te_list.size():
			continue
		var cond_effects: Array = te_list[tier].get("conditional_effects", [])
		for ce in cond_effects:
			match ce.get("trigger", ""):
				"on_hit":
					if ce.get("effect", "") == "poison" and result["passive_poison"].is_empty():
						result["passive_poison"] = {
							"chance":          float(ce.get("chance", 0.0)),
							"damage_per_turn": h_atk * float(ce.get("damage_percent", 0.0)),
							"duration_turns":  int(ce.get("duration_turns", 2))
						}
	return result

# ═══════════════════════════════════════════════════════════
#  Gestion des cooldowns
# ═══════════════════════════════════════════════════════════

# Enregistre un cooldown générique sur un passif (cycles avant réutilisation).
func set_passive_cooldown(passive_id: String, cycles: int) -> void:
	if not passive_id.is_empty():
		passive_cooldowns[passive_id] = cycles

# Décrémente tous les cooldowns actifs d'un cycle. Appelé en fin de cycle.
func decrement_cooldowns() -> void:
	for pid in passive_cooldowns:
		passive_cooldowns[pid] = maxi(int(passive_cooldowns[pid]) - 1, 0)

# ═══════════════════════════════════════════════════════════
#  Utilitaires internes
# ═══════════════════════════════════════════════════════════

# Collecte tous les IDs de passifs actuellement actifs (sans doublons).
func _get_all_active_passive_ids() -> Array:
	var ids: Array = []
	for eid in GameData.entities:
		var et = GameData.entities[eid].get("entity_type", "")
		if et == Enums.EntityType.CREATURE or et == Enums.EntityType.BIOME:
			for pid in GameData.entities[eid].get("unlocked_passives", []):
				if pid not in ids:
					ids.append(pid)
	for pid in GameData.player.get("active_passives", []):
		if pid not in ids:
			ids.append(pid)
	return ids

func _on_refresh_trigger(_a = null, _b = null) -> void:
	refresh_active_passives()
