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
	"active_passives": []
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
