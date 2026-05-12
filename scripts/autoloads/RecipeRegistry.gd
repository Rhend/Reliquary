# ============================================================
# RecipeRegistry — Catalogue des recettes de forge.
#
# Regroupe les recettes par catégorie d'équipement pour
# alimenter l'UI du Forgeron (SPEC 6).
# ============================================================
extends Node

# ═══════════════════════════════════════════════════════════
#  Requêtes publiques
# ═══════════════════════════════════════════════════════════

# Toutes les recettes disponibles.
func get_all() -> Array:
	return GameData.get_forge_recipes()

# Recettes filtrées par slot d'équipement ("weapon" | "armor" | "accessory").
# Correspond au champ result_slot dans le JSON de la recette.
func get_by_slot(slot: String) -> Array:
	var result: Array = []
	for recipe in get_all():
		if recipe.get("result_slot", "") == slot:
			result.append(recipe)
	return result

# Retourne true si le joueur peut crafter cette recette.
func can_craft(recipe: Dictionary) -> bool:
	return GameData.can_craft(recipe)

# Exécute le craft et retourne true si réussi.
func craft(recipe: Dictionary) -> bool:
	return GameData.craft(recipe)

# Nom de l'équipement résultant d'une recette.
func get_result_name(recipe: Dictionary) -> String:
	var item = GameData.get_entity(recipe.get("result_id", ""))
	return item.get("name", "?")

# Résumé des ingrédients pour l'affichage (Array de { name, needed, have, ok }).
func get_ingredient_summary(recipe: Dictionary) -> Array:
	var result: Array = []
	for ing in recipe.get("ingredients", []):
		var item_id = ing.get("item_id", "")
		var needed  = int(ing.get("qty", 0))
		var have    = int(GameData.player.get("resources", {}).get(item_id, 0))
		var item    = GameData.get_entity(item_id)
		result.append({
			"name":   item.get("name", item_id),
			"needed": needed,
			"have":   have,
			"ok":     have >= needed
		})
	return result
