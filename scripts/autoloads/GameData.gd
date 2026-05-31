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

# Fragments requis pour passer du Tier n au Tier n+1 (index = tier source).
const VILLAGE_TIER_REQUIREMENTS: Array[int] = [
	0,  # T0→T1 : automatique
	1,  # T1→T2 : 1 Fragment requis
]

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

var village: Dictionary = {
	"tier_actuel":         1,
	"fragments_collectes": [],
}

var player: Dictionary = {
	"luck":               0,
	"resources":          {},          # item_id → quantité possédée
	"active_creature_id": "hero",
	"active_biome_id":    "",
	"active_passives":    [],
	"equipped": {
		"arme":     "equipment_arme",
		"anneau":   "",
		"armure":   "",
		"ceinture": "",
		"bouclier": "equipment_bouclier",
		"talisman": ""
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
	EventBus.entity_evolved.connect(_on_entity_evolved)

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
	# Pièges et bénédictions : entités de maîtrise (XP + évolution manuelle)
	_load_tres_entities_from_folder("res://data/pieges/",          "trap")
	_load_tres_entities_from_folder("res://data/benedictions/",    "benediction")
	# Données statiques VS
	_load_tres_data_from_folder("res://data/ingredients/", "ingredient")
	_load_tres_data_from_folder("res://data/fragments/",   "fragment")
	# Héro : chargé depuis .tres (source de vérité)
	_load_tres_entities_from_folder("res://data/hero/", "hero")
	_load_entities_from_folder("res://data/passives/",  "passive")
	_load_tres_entities_from_folder("res://data/equipements/", "equipment")
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

# ═══════════════════════════════════════════════════════════
#  Village
# ═══════════════════════════════════════════════════════════

# Hook entity_evolved : libère le Fragment (Rare) et révèle le biome secondaire (Légendaire).
func _on_entity_evolved(entity_id: String, new_tier: int) -> void:
	var entity := get_entity(entity_id)
	if entity.get("entity_type", "") != "biome":
		return

	# Rare (tier 2) → libération du Fragment
	if new_tier == 2:
		for fid in entities:
			var frag: Dictionary = entities[fid]
			if frag.get("entity_type", "") != "fragment":
				continue
			if frag.get("biome_source_id", "") != entity_id:
				continue
			if frag.get("est_collecte", false):
				break
			frag["est_collecte"] = true
			village["fragments_collectes"].append(fid)
			EventBus.fragment_libere.emit(fid, entity_id)
			break

	# Légendaire (tier 4) → révélation du biome secondaire
	if new_tier == 4:
		var secondary_id := entity.get("biome_secondaire_id", "") as String
		if secondary_id == "":
			return
		var secondary := get_entity(secondary_id)
		if secondary.is_empty() or secondary.get("est_decouvert", false):
			return
		secondary["est_decouvert"] = true
		EventBus.biome_revele.emit(secondary_id)

# Retourne true si le Village peut passer au Tier suivant.
func can_upgrade_village() -> bool:
	var current := int(village.get("tier_actuel", 1))
	if current >= VILLAGE_TIER_REQUIREMENTS.size():
		return false
	var req := VILLAGE_TIER_REQUIREMENTS[current]
	return village.get("fragments_collectes", []).size() >= req

# Passe le Village au Tier suivant. Retourne false si impossible.
func upgrade_village() -> bool:
	if not can_upgrade_village():
		return false
	village["tier_actuel"] = int(village.get("tier_actuel", 1)) + 1
	EventBus.village_tier_change.emit(village["tier_actuel"])
	return true

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
	var tier := int(entity.get("current_tier", 0))
	return {
		"atk": int(entity.get("atk", 0)) + tier * int(entity.get("atk_par_tier", 0)),
		"def": int(entity.get("def", 0)) + tier * int(entity.get("def_par_tier", 0)),
		"hp":  int(entity.get("hp",  0)) + tier * int(entity.get("hp_par_tier",  0)),
		"vit": int(entity.get("vit", 0)) + tier * int(entity.get("vit_par_tier", 0)),
	}

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
		var tier     := int(item.get("maitrise_actuelle", 0))
		var spm      := item.get("stats_par_palier", {}) as Dictionary
		var item_stats: Dictionary = spm.get(tier, spm.get(0, {}))
		for key in item_stats:
			bonuses[key] = bonuses.get(key, 0.0) + float(item_stats[key])
	return bonuses

# Retourne la recette (Array de {ingredient_id, quantite}) pour le palier cible,
# ou [] si aucune recette n'est définie.
func get_forge_recipe(equipment_id: String, target_tier: int) -> Array:
	var equip := get_entity(equipment_id)
	if equip.is_empty():
		return []
	return (equip.get("recettes_evolution", {}) as Dictionary).get(target_tier, []) as Array

# Retourne true si l'équipement peut être forgé au palier suivant.
func can_forge(equipment_id: String) -> bool:
	var equip := get_entity(equipment_id)
	if equip.is_empty():
		return false
	var current := int(equip.get("maitrise_actuelle", 0))
	if current >= MAX_TIER:
		return false
	var recipe := get_forge_recipe(equipment_id, current + 1)
	if recipe.is_empty():
		return false
	for req in recipe:
		var ingr := get_entity(req.get("ingredient_id", ""))
		if ingr.is_empty() or int(ingr.get("quantite_en_stock", 0)) < int(req.get("quantite", 1)):
			return false
	return true

# Forge l'équipement au palier suivant : consomme les ingrédients, monte le palier.
# Retourne false si impossible.
func forge(equipment_id: String) -> bool:
	if not can_forge(equipment_id):
		return false
	var equip   := get_entity(equipment_id)
	var current := int(equip.get("maitrise_actuelle", 0))
	var recipe  := get_forge_recipe(equipment_id, current + 1)
	for req in recipe:
		var ingr := get_entity(req.get("ingredient_id", ""))
		ingr["quantite_en_stock"] = int(ingr.get("quantite_en_stock", 0)) - int(req.get("quantite", 1))
	equip["maitrise_actuelle"] = current + 1
	EventBus.equipement_evolue.emit(equipment_id, current + 1)
	return true

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
	var slot_idx: int = int(item.get("slot", -1))
	if slot_idx < 0 or slot_idx >= Enums.SlotEquipement.size():
		return
	var slot: String = Enums.SlotEquipement.keys()[slot_idx].to_lower()
	if not player["equipped"].has(slot):
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
