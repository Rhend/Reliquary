extends Node

const SAVE_PATH = "user://save.json"

func save() -> void:
	var save_data: Dictionary = {
		"version": 1,
		"player":  GameData.player.duplicate(true),
		"entities": {}
	}

	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		save_data["entities"][entity_id] = {
			"current_tier":      e.get("current_tier",      0),
			"current_xp":        e.get("current_xp",        0.0),
			"unlocked_passives": e.get("unlocked_passives", [])
		}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Impossible d'ouvrir le fichier de sauvegarde")
		return
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	EventBus.save_completed.emit()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	var err  = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Erreur parsing sauvegarde")
		return

	var save_data: Dictionary = json.get_data()

	if save_data.has("player"):
		GameData.player.merge(save_data["player"], true)

	if save_data.has("entities"):
		for entity_id in save_data["entities"]:
			if GameData.entities.has(entity_id):
				var saved = save_data["entities"][entity_id]
				GameData.entities[entity_id]["current_tier"]      = saved.get("current_tier",      0)
				GameData.entities[entity_id]["current_xp"]        = saved.get("current_xp",        0.0)
				GameData.entities[entity_id]["unlocked_passives"] = saved.get("unlocked_passives", [])

	EventBus.load_completed.emit()
