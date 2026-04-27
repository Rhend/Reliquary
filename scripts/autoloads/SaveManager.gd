# ============================================================
# SaveManager.gd — Sauvegarde automatique sur progression.
#
# Stratégie de déclenchement :
#   Les signaux de progression marquent un flag "dirty" et
#   démarrent un timer de SAVE_DEBOUNCE secondes.  La sauvegarde
#   n'est écrite sur disque qu'à l'expiration du timer, pas à
#   chaque signal.  Cela évite les dizaines de writes par combat
#   (xp_gained × creature + biome + N passifs + bestiary_updated).
#
# Format : JSON indenté, un seul fichier.
# Chemin  : user://IdleEvolutionSave.json
#   Windows : %APPDATA%\Godot\app_userdata\IdleEvolution\
#   Linux   : ~/.local/share/godot/app_userdata/IdleEvolution/
# ============================================================
extends Node

const SAVE_PATH     = "user://IdleEvolutionSave.json"
const SAVE_VER      = 3      # Incrémenter lors d'un changement de format incompatible
const SAVE_DEBOUNCE = 2.0    # Secondes d'inactivité avant l'écriture sur disque

var _save_dirty: bool  = false
var _save_timer: Timer

func _ready() -> void:
	_save_timer           = Timer.new()
	_save_timer.one_shot  = true
	_save_timer.wait_time = SAVE_DEBOUNCE
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)

	EventBus.xp_gained.connect(_on_progress)
	EventBus.bestiary_updated.connect(_on_progress)
	EventBus.resources_changed.connect(_on_progress)
	EventBus.entity_evolved.connect(_on_progress)
	EventBus.passive_unlocked.connect(_on_progress)
	EventBus.player_state_changed.connect(_on_progress)

# Marque la sauvegarde comme nécessaire et remet le timer à zéro.
# start() sur un Timer en cours le relance depuis le début.
func _on_progress(_a = null, _b = null) -> void:
	_save_dirty = true
	_save_timer.start()

# Appelé quand le timer expire : écrit sur disque une seule fois.
func _flush_save() -> void:
	if _save_dirty:
		_save_dirty = false
		save()

# ═══════════════════════════════════════════════════════════
#  Sauvegarde
# ═══════════════════════════════════════════════════════════

func save() -> void:
	var save_data: Dictionary = {
		"version": SAVE_VER,
		"player":  GameData.player.duplicate(true),
		"entities": {}
	}

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

	# Abandonne si la version ne correspond pas (format incompatible)
	var saved_ver = int(save_data.get("version", 0))
	if saved_ver != SAVE_VER:
		push_warning("SaveManager: version %d en mémoire, %d attendu — sauvegarde ignorée" \
			% [saved_ver, SAVE_VER])
		return

	# Fusionne l'état joueur sauvegardé (true = les clés du save écrasent les défauts)
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
