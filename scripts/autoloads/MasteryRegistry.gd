# ============================================================
# MasteryRegistry — Registre de découverte et de maîtrise.
#
# Une entité est "découverte" dès qu'elle apparaît dans le
# bestiaire du joueur (player["bestiary"]).
# Ce registre expose une vue filtrée de GameData pour l'UI
# du Hall des Évolutions et de la sélection de biome.
# ============================================================
extends Node

# Types d'entités soumises à la Maîtrise (le Héros est exclu).
const MASTERY_TYPES := [
	Enums.EntityType.CREATURE, Enums.EntityType.BIOME, Enums.EntityType.PASSIVE,
	Enums.EntityType.EQUIPMENT, Enums.EntityType.TRAP, Enums.EntityType.BENEDICTION,
]

# ═══════════════════════════════════════════════════════════
#  Requêtes publiques
# ═══════════════════════════════════════════════════════════

# Retourne true si l'entité a déjà été rencontrée / obtenue.
# Créatures/pièges/événements → bestiary.
# Équipements → inventaire ou slot équipé.
func is_discovered(entity_id: String) -> bool:
	if GameData.player.get("bestiary", {}).has(entity_id):
		return true
	var e = GameData.get_entity(entity_id)
	if e.get("entity_type") == Enums.EntityType.EQUIPMENT:
		if entity_id in GameData.player.get("equipment_inventory", []):
			return true
		if entity_id in GameData.player.get("equipped", {}).values():
			return true
	return false

# Retourne toutes les entités soumises à la Maîtrise.
# Résultat : Array de Dictionaries issus de GameData.entities.
func get_all_mastery_entities() -> Array:
	var result: Array = []
	for eid in GameData.entities:
		var e = GameData.entities[eid]
		if e.get("entity_type", "") in MASTERY_TYPES:
			result.append(e)
	return result

# Retourne les entités d'un type donné, triées par tier décroissant.
func get_entities_by_type(entity_type: String) -> Array:
	var result: Array = []
	for eid in GameData.entities:
		var e = GameData.entities[eid]
		if e.get("entity_type", "") == entity_type:
			result.append(e)
	result.sort_custom(func(a, b): return a.get("maitrise_actuelle", 0) > b.get("maitrise_actuelle", 0))
	return result

# Retourne les entités associées à un biome spécifique.
# Inclut ennemis, pièges, événements positifs issus de la définition JSON du biome.
func get_biome_entity_pools(biome_id: String) -> Dictionary:
	var biome = GameData.get_entity(biome_id)
	var creatures: Array = []
	for slot in ["creature_surface", "creature_profondeur", "creature_unique"]:
		var c := biome.get(slot, {}) as Dictionary
		if not c.is_empty():
			creatures.append(c)
	return {
		"creatures":    creatures,
		"traps":        biome.get("pieges",           []),
		"benedictions": biome.get("benedictions",     []),
		"ingredients":  biome.get("ingredients_drop", []),
	}

# Nombre d'entités découvertes parmi une liste de Dictionaries (issues du pool biome).
func count_discovered(pool: Array) -> int:
	var n := 0
	for entry in pool:
		if is_discovered(entry.get("id", "")):
			n += 1
	return n

# Données de maîtrise d'une entité pour l'affichage dans le Hall.
# Retourne {} si l'entité est inconnue.
func get_mastery_display(entity_id: String) -> Dictionary:
	var e = GameData.get_entity(entity_id)
	if e.is_empty():
		return {}
	var tier: int      = e.get("maitrise_actuelle", 0)
	var xp: float      = e.get("xp_maitrise_actuelle",   0.0)
	var next_idx: int  = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max: float  = float(GameData.xp_thresholds[next_idx])
	return {
		"name":       Translations.entity_name(e, entity_id),
		"tier":       tier,
		"tier_name":  GameData.get_tier_name(tier),
		"xp":         xp,
		"xp_max":     xp_max,
		"can_evolve": MasterySystem.can_evolve(entity_id),
		"at_max":     tier >= GameData.get_max_tier_for_type(e.get("entity_type", "")),
	}
