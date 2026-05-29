# ============================================================
# GameData.gd — Source de vérité unique pour les données du jeu.
#
# Responsabilités :
#   1. Charger les entités depuis les fichiers JSON au démarrage.
#   2. Maintenir l'état runtime du joueur (stats, inventaire, etc.).
#   3. Exposer des méthodes typées pour lire / modifier ces données.
#
# Structure des entités :
#   • Entités à maîtrise (creature / biome / passive / equipment) :
#     dict JSON + entity_type + current_tier + current_xp + unlocked_passives
#   • Données statiques (resource / recipe) :
#     dict JSON + entity_type  (pas de progression)
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

# Labels des paliers dans l'ordre croissant (index = tier).
const MASTERY_TIERS: Array[String] = [
	"Commun", "Peu Commun", "Rare", "Épique", "Légendaire", "Unique"
]
const MAX_TIER: int = 5

# ─── Données chargées depuis mastery_config.json ────────────

# XP cumulatif requis pour atteindre chaque tier [0, 100, 500, …]
var xp_thresholds: Array = []
# Dictionnaire écart_de_tier (string) → multiplicateur d'XP reçu (float)
var xp_modifiers: Dictionary = {}

# ─── Catalogue d'entités ────────────────────────────────────

# Toutes les entités du jeu, indexées par leur id.
# Fusionnent définition JSON et état runtime.
var entities: Dictionary = {}

# ─── État courant du joueur ─────────────────────────────────

var pending_evolution: Dictionary = {}

var player: Dictionary = {
	"luck":               0,
	"resources":          {},          # item_id → quantité possédée
	"active_creature_id": "hero",
	"active_biome_id":    "",
	"active_passives":    [],
	"equipped": {
		"weapon":    "equip_epee_bois",
		"armor":     "",
		"accessory": "equip_bouclier"
	},
	"equipment_inventory": [],
	"bestiary": {}   # enc_id → { name, type, biome_id, biome_name, count, xp, tier }
}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_load_mastery_config()
	_load_all_entities()
	_seed_test_bestiary()

# Données de test — couvre les 6 tiers de rareté pour le Hall des Évolutions.
func _seed_test_bestiary() -> void:
	var hall: Dictionary = player.get("bestiary", {})
	var test_entries: Array = [
		{"id":"creature_foret_surface",    "name":"Rat des Égouts",     "tier":0, "xp":50.0,   "count":6,  "type":"Créature", "biome_id":"biome_foret",    "biome_name":"Forêt Sombre"},
		{"id":"creature_foret_profondeur", "name":"Ours Légendaire",    "tier":1, "xp":180.0,  "count":22, "type":"Créature", "biome_id":"biome_foret",    "biome_name":"Forêt Sombre"},
		{"id":"creature_oscar",            "name":"Oscar",              "tier":2, "xp":750.0,  "count":55, "type":"Créature", "biome_id":"biome_foret",    "biome_name":"Forêt Sombre"},
		{"id":"creature_marecage_surface",    "name":"Grenouille Géante",  "tier":0, "xp":50.0,  "count":10, "type":"Créature", "biome_id":"biome_marecage", "biome_name":"Marécage Putride"},
		{"id":"creature_marecage_profondeur", "name":"Serpent des Marais", "tier":1, "xp":200.0, "count":30, "type":"Créature", "biome_id":"biome_marecage", "biome_name":"Marécage Putride"},
		{"id":"creature_cavalier_sans_tete",  "name":"Cavalier Sans Tête", "tier":2, "xp":0.0,   "count":5,  "type":"Créature", "biome_id":"biome_marecage", "biome_name":"Marécage Putride"},
	]
	for e in test_entries:
		if not hall.has(e["id"]):
			hall[e["id"]] = e.duplicate()

func _load_mastery_config() -> void:
	var config = _read_json("res://data/mastery_config.json")
	if config.is_empty():
		push_error("GameData: mastery_config.json introuvable ou invalide")
		return
	xp_thresholds = config.get("xp_thresholds", [])
	xp_modifiers  = config.get("xp_modifiers",  {})

# Charge toutes les entités depuis leurs dossiers respectifs.
func _load_all_entities() -> void:
	# Biomes : chargés depuis .tres (source de vérité)
	_load_tres_entities_from_folder("res://data/biomes/", "biome")
	# Contenu VS : créatures, passifs uniques
	_load_tres_entities_from_folder("res://data/creatures/",       "creature")
	_load_tres_entities_from_folder("res://data/passifs_uniques/", "passif_unique")
	# Données statiques VS
	_load_tres_data_from_folder("res://data/ingredients/", "ingredient")
	_load_tres_data_from_folder("res://data/fragments/",   "fragment")
	# Entités avec progression (tier / XP / passifs débloqués) — JSON
	_load_entities_from_folder("res://data/hero/",      "hero")
	_load_entities_from_folder("res://data/passives/",  "passive")
	_load_entities_from_folder("res://data/equipment/", "equipment")
	# Données statiques JSON
	_load_data_from_folder("res://data/resources/", "resource")
	_load_data_from_folder("res://data/forge/",     "recipe")

# Charge les .tres d'un dossier et initialise les champs de maîtrise.
func _load_tres_entities_from_folder(path: String, entity_type: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res := load(path + file_name)
			var id_val = res.get("id") if res != null else null
			if id_val != null and id_val != "":
				var data := _resource_to_dict(res)
				data["entity_type"]       = entity_type
				data["current_tier"]      = 0
				data["current_xp"]        = 0.0
				data["unlocked_passives"] = []
				entities[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Charge les .tres d'un dossier comme données statiques (sans progression).
func _load_tres_data_from_folder(path: String, entity_type: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res := load(path + file_name)
			var id_val = res.get("id") if res != null else null
			if id_val != null and id_val != "":
				var data := _resource_to_dict(res)
				data["entity_type"] = entity_type
				entities[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Convertit un Resource en Dictionary en extrayant toutes ses propriétés de script.
# Les sous-Resources et tableaux de Resources sont convertis récursivement.
func _resource_to_dict(res: Resource) -> Dictionary:
	var data: Dictionary = {}
	var skip := ["script", "resource_path", "resource_name", "resource_local_to_scene"]
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE and not skip.has(prop.name):
			var val = res.get(prop.name)
			if val is Resource:
				data[prop.name] = _resource_to_dict(val)
			elif val is Array:
				var arr: Array = []
				for item in val:
					if item is Resource:
						arr.append(_resource_to_dict(item))
					else:
						arr.append(item)
				data[prop.name] = arr
			else:
				data[prop.name] = val
	return data

# Charge un dossier JSON et initialise les champs de maîtrise.
func _load_entities_from_folder(path: String, entity_type: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data = _read_json(path + file_name)
			if not data.is_empty() and data.has("id"):
				data["entity_type"]       = entity_type
				data["current_tier"]      = 0
				data["current_xp"]        = 0.0
				data["unlocked_passives"] = []
				entities[data["id"]]      = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Charge un dossier de données statiques (sans champs de progression).
func _load_data_from_folder(path: String, entity_type: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data = _read_json(path + file_name)
			if not data.is_empty() and data.has("id"):
				data["entity_type"] = entity_type
				entities[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Lit et parse un fichier JSON. Retourne {} en cas d'erreur.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err  = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("GameData: erreur parsing JSON — " + path)
		return {}
	return json.get_data()

# ═══════════════════════════════════════════════════════════
#  Accesseurs — Entités
# ═══════════════════════════════════════════════════════════

# Retourne le dict d'une entité par son id, ou {} si introuvable.
func get_entity(entity_id: String) -> Dictionary:
	return entities.get(entity_id, {})

# Retourne le nom du palier correspondant à un tier (0–5).
func get_tier_name(tier: int) -> String:
	if tier < 0 or tier >= MASTERY_TIERS.size():
		return "Inconnu"
	return MASTERY_TIERS[tier]

# Stats de base d'une entité après application de sa progression de tier.
# Exemple : héro tier 2 avec tier_scaling.atk=3 → atk_base + 2×3 = +6 ATK.
func get_effective_stats(entity_id: String) -> Dictionary:
	var entity = get_entity(entity_id)
	if entity.is_empty():
		return {}
	var stats   = entity.get("base_stats", {}).duplicate()
	var tier    = entity.get("current_tier", 0)
	var scaling = entity.get("tier_scaling", {})
	for key in scaling:
		stats[key] = stats.get(key, 0) + tier * int(scaling[key])
	return stats

# Bonus cumulés de tous les équipements portés.
# Retourne au minimum { atk:0, hp:0, attack_speed_pct:0 }.
func get_equipment_bonuses() -> Dictionary:
	var bonuses: Dictionary = {"atk": 0.0, "hp": 0.0, "attack_speed_pct": 0.0}
	for item_id in player.get("equipped", {}).values():
		if item_id == "":
			continue
		var item = get_entity(item_id)
		if item.is_empty():
			continue
		var item_bonuses: Dictionary = item.get("base_stats", {}).get("bonuses", {})
		for key in item_bonuses:
			bonuses[key] = bonuses.get(key, 0.0) + float(item_bonuses[key])
	return bonuses

# ═══════════════════════════════════════════════════════════
#  Hall des Évolutions (Bestiaire)
# ═══════════════════════════════════════════════════════════

# Crée ou met à jour une entrée dans le Hall des Évolutions.
#
# xp_reward == 0 : début de rencontre (compteur incrémenté, pas d'XP).
# xp_reward  > 0 : rencontre terminée — XP distribué, tier vérifié.
#
# Le tier du Hall est indépendant du tier de l'entité dans le jeu :
# il mesure la familiarité du joueur avec cette rencontre spécifique.
func record_encounter(enc_id: String, enc_name: String, enc_type: String,
		biome_id: String, xp_reward: float) -> void:
	if enc_id == "":
		return

	var hall: Dictionary = player.get("bestiary", {})

	# Première rencontre : création de l'entrée
	if not hall.has(enc_id):
		var biome = get_entity(biome_id)
		hall[enc_id] = {
			"name":       enc_name,
			"type":       enc_type,
			"biome_id":   biome_id,
			"biome_name": biome.get("nom_affichage_fr", biome_id),
			"count":      0,
			"xp":         0.0,
			"tier":       0
		}

	var entry: Dictionary = hall[enc_id]

	# count n'est incrémenté qu'à la complétion (xp_reward > 0) pour éviter
	# le double-comptage : l'entrée est créée au début du combat (xp=0)
	# mais le kill n'est confirmé qu'à la victoire (xp>0).
	if xp_reward > 0.0:
		entry["count"] += 1
		entry["xp"]    += xp_reward
		var tier: int = entry.get("tier", 0)
		while tier < MAX_TIER:
			var next_idx: int = tier + 1
			if next_idx >= xp_thresholds.size():
				break
			if entry["xp"] < float(xp_thresholds[next_idx]):
				break
			entry["xp"]   -= float(xp_thresholds[next_idx])
			entry["tier"] += 1
			tier            = entry["tier"]

	# Pas de player["bestiary"] = hall : hall est déjà la même référence
	EventBus.bestiary_updated.emit(enc_id)

# ═══════════════════════════════════════════════════════════
#  Forge
# ═══════════════════════════════════════════════════════════

# Liste toutes les recettes de forge disponibles dans le catalogue.
func get_forge_recipes() -> Array:
	var result: Array = []
	for id in entities:
		if entities[id].get("entity_type") == "recipe":
			result.append(entities[id])
	return result

# Vérifie si le joueur possède tous les ingrédients d'une recette.
func can_craft(recipe: Dictionary) -> bool:
	for ing in recipe.get("ingredients", []):
		var needed = int(ing.get("qty", 0))
		var have   = int(player.get("resources", {}).get(ing.get("item_id", ""), 0))
		if have < needed:
			return false
	return true

# Consomme les ingrédients et équipe le résultat dans le slot approprié.
# Retourne false si les ressources sont insuffisantes.
func craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		return false
	for ing in recipe.get("ingredients", []):
		var item_id = ing.get("item_id", "")
		var qty     = int(ing.get("qty", 0))
		player["resources"][item_id] = int(player["resources"].get(item_id, 0)) - qty
	var result_id = recipe.get("result_id", "")
	if result_id != "":
		player["equipment_inventory"].append(result_id)
	EventBus.resources_changed.emit()
	return true

func equip_item(item_id: String) -> void:
	var item = get_entity(item_id)
	var slot = item.get("base_stats", {}).get("slot", "")
	if slot == "" or not player["equipped"].has(slot):
		return
	var old_id = player["equipped"].get(slot, "")
	if old_id != "":
		player["equipment_inventory"].append(old_id)
	player["equipment_inventory"].erase(item_id)
	player["equipped"][slot] = item_id
	EventBus.equipment_changed.emit()

func unequip_item(slot: String) -> void:
	var item_id = player["equipped"].get(slot, "")
	if item_id == "":
		return
	player["equipment_inventory"].append(item_id)
	player["equipped"][slot] = ""
	EventBus.equipment_changed.emit()

# ═══════════════════════════════════════════════════════════
#  Ressources
# ═══════════════════════════════════════════════════════════

# Ajoute qty unités d'une ressource à l'inventaire du joueur.
func add_resource(item_id: String, qty: int) -> void:
	player["resources"][item_id] = int(player["resources"].get(item_id, 0)) + qty
	EventBus.resources_changed.emit()

# ═══════════════════════════════════════════════════════════
#  Combat — Bonus de maîtrise spécifique à un ennemi
# ═══════════════════════════════════════════════════════════

# Retourne un bonus d'ATK basé sur la maîtrise accumulée face à cet ennemi précis.
# Formule : tier_hall × 2 ATK.
# Récompense les joueurs qui s'acharnent sur le même type d'ennemi.
func get_mastery_combat_bonus(enemy_id: String) -> float:
	var entry = player.get("bestiary", {}).get(enemy_id, {})
	return float(entry.get("tier", 0)) * 2.0
