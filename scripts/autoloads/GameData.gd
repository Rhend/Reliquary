extends Node

const MASTERY_TIERS: Array[String] = ["Commun", "Peu Commun", "Rare", "Épique", "Légendaire", "Unique"]
const MAX_TIER: int = 5

# Chargés depuis mastery_config.json
var xp_thresholds: Array = []
var xp_modifiers: Dictionary = {}

# Toutes les entités du jeu (id -> Dictionary fusionnant définition + état runtime)
var entities: Dictionary = {}

# État courant du joueur
var player: Dictionary = {
	"luck": 0,
	"resources": {},
	"active_creature_id": "",
	"active_biome_id": "",
	"active_passives": [],
	"equipped": {
		"weapon": "equip_epee_bois",
		"shield": "equip_bouclier",
		"boots":  "equip_bottes"
	},
	"bestiary": {}
}

func _ready() -> void:
	_load_mastery_config()
	_load_all_entities()

func _load_mastery_config() -> void:
	var config = _read_json("res://data/mastery_config.json")
	if config.is_empty():
		push_error("mastery_config.json introuvable ou invalide")
		return
	xp_thresholds = config.get("xp_thresholds", [])
	xp_modifiers  = config.get("xp_modifiers", {})

func _load_all_entities() -> void:
	_load_entities_from_folder("res://data/creatures/", "creature")
	_load_entities_from_folder("res://data/biomes/",    "biome")
	_load_entities_from_folder("res://data/passives/",  "passive")
	_load_entities_from_folder("res://data/equipment/", "equipment")

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
		push_error("Erreur parsing JSON : " + path)
		return {}
	return json.get_data()

func get_entity(entity_id: String) -> Dictionary:
	return entities.get(entity_id, {})

func get_tier_name(tier: int) -> String:
	if tier < 0 or tier >= MASTERY_TIERS.size():
		return "Inconnu"
	return MASTERY_TIERS[tier]

# Retourne les stats de base d'une entité scalées par son tier actuel.
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

# Retourne les bonus cumulés de tous les équipements portés.
func get_equipment_bonuses() -> Dictionary:
	var bonuses: Dictionary = {"atk": 0.0, "hp": 0.0, "attack_speed_pct": 0.0}
	for item_id in player.get("equipped", {}).values():
		var item = get_entity(item_id)
		if item.is_empty():
			continue
		var item_bonuses: Dictionary = item.get("base_stats", {}).get("bonuses", {})
		for key in item_bonuses:
			bonuses[key] = bonuses.get(key, 0.0) + float(item_bonuses[key])
	return bonuses

# Enregistre ou met à jour une entrée dans le Hall des Évolutions.
# xp_reward = 0 : première rencontre sans XP (ex: début de combat).
func record_encounter(enc_id: String, enc_name: String, enc_type: String,
		biome_id: String, xp_reward: float) -> void:
	if enc_id == "":
		return
	var hall: Dictionary = player.get("bestiary", {})
	if not hall.has(enc_id):
		var biome = get_entity(biome_id)
		hall[enc_id] = {
			"name":       enc_name,
			"type":       enc_type,
			"biome_id":   biome_id,
			"biome_name": biome.get("name", biome_id),
			"count":      0,
			"xp":         0.0,
			"tier":       0
		}
	var entry: Dictionary = hall[enc_id]
	entry["count"] += 1
	if xp_reward > 0.0:
		entry["xp"] += xp_reward
		var tier: int = entry.get("tier", 0)
		while tier < MAX_TIER:
			var next_idx: int = tier + 1
			if next_idx >= xp_thresholds.size():
				break
			if entry["xp"] < float(xp_thresholds[next_idx]):
				break
			entry["xp"]   -= float(xp_thresholds[next_idx])
			entry["tier"] += 1
			tier           = entry["tier"]
	player["bestiary"] = hall
	EventBus.bestiary_updated.emit(enc_id)
