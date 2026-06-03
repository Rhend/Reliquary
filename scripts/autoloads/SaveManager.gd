# ============================================================
# SaveManager.gd — Sauvegarde automatique sur progression.
#
# Format JSON à quatre sections :
#   "player"   — dict complet GameData.player (resources, equipped, bestiary…)
#   "entities" — état par entity_type → { id → champs } (tier, xp, flags d'état)
#   "systems"  — état runtime des autoloads (cooldowns, etc.)
#   "village"  — dict complet GameData.village (tier, fragments, xp, eclos…)
#
# Étendre la sauvegarde :
#   • Nouvelle donnée joueur  → l'ajouter dans GameData.player (sauvegardé automatiquement).
#   • Nouvelle entité         → rien à faire (détectée via maitrise_actuelle).
#   • Nouvel état de système  → ajouter une clé dans _save_systems() et _load_systems().
#
# Déclenchement :
#   Les signaux de progression marquent un flag "dirty" et démarrent un timer
#   de SAVE_DEBOUNCE secondes. La sauvegarde n'est écrite qu'à l'expiration,
#   évitant des dizaines de writes par combat.
#
# Versioning :
#   Incrémenter SAVE_VER dès qu'un champ est renommé ou supprimé.
#   Un simple ajout de clé NE nécessite PAS de bump (merge tolère les clés inconnues).
# ============================================================
extends Node

const SAVE_PATH     := "user://IdleEvolutionSave.json"
const SAVE_VER      := 12
const SAVE_DEBOUNCE := 2.0

var _save_dirty:  bool  = false
var _save_loaded: bool  = false
var _save_timer:  Timer

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
	EventBus.equipment_changed.connect(_on_progress)
	EventBus.equipement_evolue.connect(_on_progress)
	EventBus.village_tier_change.connect(_on_progress)

func _on_progress(_a = null, _b = null) -> void:
	_save_dirty = true
	_save_timer.start()

func _flush_save() -> void:
	if _save_dirty:
		_save_dirty = false
		save()

# ═══════════════════════════════════════════════════════════
#  Sauvegarde
# ═══════════════════════════════════════════════════════════

func save() -> void:
	var data := {
		"version":  SAVE_VER,
		"player":   _save_player(),
		"entities": _save_entities(),
		"systems":  _save_systems(),
		"village":  GameData.village.duplicate(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: impossible d'ouvrir le fichier de sauvegarde")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	EventBus.save_completed.emit()

func _save_player() -> Dictionary:
	return GameData.player.duplicate(true)

func _save_entities() -> Dictionary:
	var result: Dictionary = {}
	for entity_id in GameData.entities:
		var e: Dictionary = GameData.entities[entity_id]
		var entry: Dictionary = {}

		if e.has("maitrise_actuelle"):
			entry["maitrise_actuelle"]    = e.get("maitrise_actuelle",    0)
			entry["xp_maitrise_actuelle"] = e.get("xp_maitrise_actuelle", 0.0)
			entry["unlocked_passives"]    = e.get("unlocked_passives",    [])

		for field: String in ["est_decouvert", "mecanique_forte_activee", "creature_unique_vaincue",
				"est_collecte", "est_debloque"]:
			if e.has(field):
				entry[field] = e[field]

		if not entry.is_empty():
			var etype: String = e.get("entity_type", "misc")
			if not result.has(etype):
				result[etype] = {}
			result[etype][entity_id] = entry
	return result

func _save_systems() -> Dictionary:
	# ── Ajouter ici les états runtime à persister ──────────────
	return {
		"passive_cooldowns": PassiveSystem.passive_cooldowns.duplicate(),
	}

# ═══════════════════════════════════════════════════════════
#  Chargement
# ═══════════════════════════════════════════════════════════

func load_save() -> void:
	if _save_loaded:
		return
	_save_loaded = true

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SaveManager: fichier de sauvegarde corrompu — ignoré")
		return

	var data: Dictionary = json.get_data()
	var saved_ver: int   = int(data.get("version", 0))
	if saved_ver != SAVE_VER:
		push_warning("SaveManager: version %d trouvée, %d attendue — sauvegarde ignorée (supprimer le fichier pour repartir proprement)" \
			% [saved_ver, SAVE_VER])
		return

	_load_player(data)
	_load_entities(data)
	_load_systems(data)
	if data.has("village"):
		GameData.village.merge(data["village"], true)
	EventBus.load_completed.emit()

func _load_player(data: Dictionary) -> void:
	if not data.has("player"):
		return
	GameData.player.merge(data["player"], true)

func _load_entities(data: Dictionary) -> void:
	if not data.has("entities"):
		return
	# Format v12+ : hiérarchique { entity_type → { entity_id → entry } }
	for _etype in data["entities"]:
		var type_block: Dictionary = data["entities"][_etype]
		for entity_id in type_block:
			if not GameData.entities.has(entity_id):
				continue
			var saved: Dictionary = type_block[entity_id]
			var e: Dictionary     = GameData.entities[entity_id]

			if e.has("maitrise_actuelle"):
				e["maitrise_actuelle"]    = saved.get("maitrise_actuelle",    0)
				e["xp_maitrise_actuelle"] = saved.get("xp_maitrise_actuelle", 0.0)
				e["unlocked_passives"]    = saved.get("unlocked_passives",    [])
				e["xp_maitrise_palier_suivant"] = GameData.palier_suivant_cost(e.get("entity_type", ""), int(e["maitrise_actuelle"]))

			for field: String in ["est_decouvert", "mecanique_forte_activee", "creature_unique_vaincue",
					"est_collecte", "est_debloque"]:
				if e.has(field) and saved.has(field):
					e[field] = saved[field]

func _load_systems(data: Dictionary) -> void:
	if not data.has("systems"):
		return
	var sys: Dictionary = data["systems"]
	# ── Ajouter ici la restauration des états runtime ──────────
	if sys.has("passive_cooldowns"):
		PassiveSystem.passive_cooldowns = (sys["passive_cooldowns"] as Dictionary).duplicate()
