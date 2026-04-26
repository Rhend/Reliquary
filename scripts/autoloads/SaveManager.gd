# ============================================================
# SaveManager.gd — Sauvegarde automatique sur progression.
#
# La sauvegarde est déclenchée par tout signal indiquant une
# progression (XP gagné, bestiaire mis à jour, ressources
# modifiées, évolution) afin que rien ne soit jamais perdu.
#
# Format : JSON indenté, un seul fichier.
# Chemin  : user://IdleEvolutionSave.json
#   Windows : %APPDATA%\Godot\app_userdata\IdleEvolution\
#   Linux   : ~/.local/share/godot/app_userdata/IdleEvolution/
# ============================================================
extends Node

const SAVE_PATH = "user://IdleEvolutionSave.json"
const SAVE_VER  = 2   # À incrémenter lors d'un changement de format incompatible

func _ready() -> void:
	# Connexion à tous les signaux de progression — chacun déclenche une sauvegarde
	EventBus.xp_gained.connect(_on_progress)
	EventBus.bestiary_updated.connect(_on_progress)
	EventBus.resources_changed.connect(_on_progress)
	EventBus.entity_evolved.connect(_on_progress)

# Callback mutualisé : les paramètres éventuels des signaux sont ignorés.
func _on_progress(_a = null, _b = null) -> void:
	save()

# ═══════════════════════════════════════════════════════════
#  Sauvegarde
# ═══════════════════════════════════════════════════════════

func save() -> void:
	var save_data: Dictionary = {
		"version": SAVE_VER,
		"player":  GameData.player.duplicate(true),   # copie profonde
		"entities": {}
	}

	# On ne persiste que les entités qui ont un système de progression
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if not e.has("current_tier"):
			continue   # resource / recipe — pas de progression à sauvegarder
		save_data["entities"][entity_id] = {
			"current_tier":      e.get("current_tier",      0),
			"current_xp":        e.get("current_xp",        0.0),
			"unlocked_passives": e.get("unlocked_passives", [])
		}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: impossible d'ouvrir le fichier de sauvegarde")
		return
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	EventBus.save_completed.emit()

# ═══════════════════════════════════════════════════════════
#  Chargement
# ═══════════════════════════════════════════════════════════

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return   # Première session — pas de fichier à charger

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	var err  = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SaveManager: fichier de sauvegarde corrompu — ignoré")
		return

	var save_data: Dictionary = json.get_data()

	# Fusionne l'état joueur sauvegardé dans l'état courant (true = écrase)
	if save_data.has("player"):
		GameData.player.merge(save_data["player"], true)

	# Restaure le tier / XP de chaque entité connue
	if save_data.has("entities"):
		for entity_id in save_data["entities"]:
			if not GameData.entities.has(entity_id):
				continue   # Entité supprimée depuis la dernière session — ignorée
			var saved = save_data["entities"][entity_id]
			GameData.entities[entity_id]["current_tier"]      = saved.get("current_tier",      0)
			GameData.entities[entity_id]["current_xp"]        = saved.get("current_xp",        0.0)
			GameData.entities[entity_id]["unlocked_passives"] = saved.get("unlocked_passives", [])

	EventBus.load_completed.emit()
