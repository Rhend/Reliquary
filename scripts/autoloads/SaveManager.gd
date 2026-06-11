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
#   évitant des dizaines de writes par combat. À la fermeture de la fenêtre,
#   le flag dirty est flushé immédiatement (aucune progression perdue).
#
# Écriture atomique :
#   Le JSON est écrit dans un fichier .tmp puis renommé par-dessus la
#   sauvegarde. Un crash en pleine écriture ne peut donc pas corrompre
#   la sauvegarde existante.
#
# Versioning :
#   Incrémenter SAVE_VER dès qu'un champ est renommé ou supprimé.
#   Un simple ajout de clé NE nécessite PAS de bump (merge tolère les clés inconnues).
# ============================================================
extends Node

const SAVE_PATH     := "user://IdleEvolutionSave.json"
const BACKUP_PATH   := SAVE_PATH + ".bak"      # avant-dernière sauvegarde valide
const CORRUPT_PATH  := SAVE_PATH + ".corrupt"  # copie d'un fichier illisible (preuve)
const SAVE_VER      := 13
const SAVE_DEBOUNCE := 2.0

# Flags d'état booléens persistés par entité (en plus de la progression de Maîtrise).
# Ajouter un flag ici suffit pour qu'il soit sauvegardé ET rechargé.
const PERSISTED_FLAGS: Array[String] = [
	"est_decouvert", "mecanique_forte_activee", "creature_unique_vaincue",
	"est_collecte", "est_debloque",
]

var _save_dirty:  bool  = false
var _save_loaded: bool  = false
# load_save() a tourné (même si aucun fichier n'existait). Tant que ce
# n'est pas le cas, save() REFUSE d'écraser une sauvegarde existante :
# un outil dev / test qui émet des signaux de progression sans passer
# par le Village ne peut plus détruire la progression du joueur.
var _load_attempted: bool = false
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

# Fermeture de la fenêtre : flush immédiat de toute progression en attente
# de debounce, sinon les 2 dernières secondes de jeu seraient perdues.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_save()

# ═══════════════════════════════════════════════════════════
#  Sauvegarde
# ═══════════════════════════════════════════════════════════

func save() -> void:
	# Garde-fou : ne JAMAIS écraser une sauvegarde qu'on n'a pas chargée.
	if not _load_attempted and FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveManager: écriture refusée — sauvegarde existante jamais chargée (outil/test ?)")
		return
	var data := {
		"version":  SAVE_VER,
		"player":   _save_player(),
		"entities": _save_entities(),
		"systems":  _save_systems(),
		"village":  GameData.village.duplicate(),
	}
	if _write_text_atomic(SAVE_PATH, JSON.stringify(data, "\t")):
		EventBus.save_completed.emit()

# Écrit `content` dans `path` de façon atomique : écriture dans un .tmp,
# rotation de l'ancienne sauvegarde vers .bak (filet de sécurité chargé
# automatiquement si la principale devient illisible), puis renommage.
func _write_text_atomic(path: String, content: String) -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: impossible d'ouvrir %s en écriture" % tmp_path)
		return false
	file.store_string(content)
	file.flush()
	file.close()
	# Rotation : l'ancienne sauvegarde devient le backup.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(BACKUP_PATH)
		DirAccess.rename_absolute(path, BACKUP_PATH)
	if DirAccess.rename_absolute(tmp_path, path) == OK:
		return true
	push_error("SaveManager: impossible de remplacer %s (l'ancienne version est dans %s)"
			% [path, BACKUP_PATH])
	return false

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

		for field: String in PERSISTED_FLAGS:
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
	_save_loaded    = true
	_load_attempted = true

	# Sauvegarde principale, sinon repli sur le backup (.bak).
	var data := _read_save_file(SAVE_PATH)
	if data.is_empty() and FileAccess.file_exists(BACKUP_PATH):
		data = _read_save_file(BACKUP_PATH)
		if not data.is_empty():
			push_warning("SaveManager: sauvegarde principale illisible — backup .bak restauré")
	if data.is_empty():
		# Fichier présent mais inutilisable : copie de quarantaine pour ne pas
		# l'écraser silencieusement à la prochaine sauvegarde.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.copy_absolute(
					ProjectSettings.globalize_path(SAVE_PATH),
					ProjectSettings.globalize_path(CORRUPT_PATH))
			push_error("SaveManager: sauvegarde illisible — copie conservée dans %s" % CORRUPT_PATH)
		return

	var saved_ver: int = int(data.get("version", 0))

	# Migrations en chaîne (modifient data in-place)
	if saved_ver < 13:
		_migrate_v12_to_v13(data)

	_load_player(data)
	if saved_ver < 12:
		_load_entities_v11(data)
	else:
		_load_entities(data)
	_load_systems(data)
	if data.has("village"):
		GameData.village.merge(data["village"], true)
	# Rattrapage de la règle « biome Peu Commun → équipement » sur les
	# sauvegardes antérieures à son introduction.
	GameData.reconcile_equipment_unlocks()
	EventBus.load_completed.emit()

# Lit et valide un fichier de sauvegarde. Retourne {} si le fichier est
# absent, illisible, mal formé ou de version non supportée.
func _read_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SaveManager: %s corrompu (JSON invalide)" % path)
		return {}
	if not (json.get_data() is Dictionary):
		push_error("SaveManager: %s corrompu (racine non-dictionnaire)" % path)
		return {}
	var data: Dictionary = json.get_data()
	var saved_ver: int   = int(data.get("version", 0))
	if not _is_version_supported(saved_ver):
		push_warning("SaveManager: %s en version %d non supportée (attendu 11–%d)" \
				% [path, saved_ver, SAVE_VER])
		return {}
	return data

func _load_player(data: Dictionary) -> void:
	if not data.has("player"):
		return
	GameData.player.merge(data["player"], true)

# Applique une entrée sauvegardée sur l'entité runtime correspondante :
# progression de Maîtrise + flags d'état persistés (PERSISTED_FLAGS).
# Logique commune aux deux formats de sauvegarde (v11 plat / v12+ hiérarchique).
func _apply_entity_save(e: Dictionary, saved: Dictionary) -> void:
	if e.has("maitrise_actuelle"):
		e["maitrise_actuelle"]    = saved.get("maitrise_actuelle",    0)
		e["xp_maitrise_actuelle"] = saved.get("xp_maitrise_actuelle", 0.0)
		e["unlocked_passives"]    = saved.get("unlocked_passives",    [])
		e["xp_maitrise_palier_suivant"] = GameData.palier_suivant_cost(e.get("entity_type", ""), int(e["maitrise_actuelle"]))
	for field: String in PERSISTED_FLAGS:
		if e.has(field) and saved.has(field):
			# Garde-fou placeholder : une vieille sauvegarde ne peut pas
			# ré-activer une entité sans contenu (nom vide) — cas des
			# équipements des biomes cachés redevenus placeholders.
			if field == "est_debloque" and bool(saved[field]) \
					and str(e.get("nom_affichage_fr", "")) == "" \
					and str(e.get("name", "")) == "":
				continue
			e[field] = saved[field]

# Charge le format v11 : entities est un dict plat { entity_id → entry }.
func _load_entities_v11(data: Dictionary) -> void:
	if not data.has("entities"):
		return
	for entity_id in data["entities"]:
		if GameData.entities.has(entity_id):
			_apply_entity_save(GameData.entities[entity_id], data["entities"][entity_id])

# Charge le format v12+ : hiérarchique { entity_type → { entity_id → entry } }.
func _load_entities(data: Dictionary) -> void:
	if not data.has("entities"):
		return
	for _etype in data["entities"]:
		var type_block: Dictionary = data["entities"][_etype]
		for entity_id in type_block:
			if GameData.entities.has(entity_id):
				_apply_entity_save(GameData.entities[entity_id], type_block[entity_id])

# Renomme tier_actuel → maitrise_actuelle dans le village, supprime xp_maitrise et active_creature_id.
func _migrate_v12_to_v13(data: Dictionary) -> void:
	if data.has("village"):
		var v: Dictionary = data["village"]
		if v.has("tier_actuel"):
			v["maitrise_actuelle"] = v["tier_actuel"]
			v.erase("tier_actuel")
		v.erase("xp_maitrise")
	if data.has("player"):
		data["player"].erase("active_creature_id")

func _load_systems(data: Dictionary) -> void:
	if not data.has("systems"):
		return
	var sys: Dictionary = data["systems"]
	# ── Ajouter ici la restauration des états runtime ──────────
	if sys.has("passive_cooldowns"):
		PassiveSystem.passive_cooldowns = (sys["passive_cooldowns"] as Dictionary).duplicate()

# Versions supportées : 11 (format entities plat), 12+ (hiérarchique).
func _is_version_supported(ver: int) -> bool:
	return ver >= 11 and ver <= SAVE_VER

# ═══════════════════════════════════════════════════════════
#  Export / Import (panneau Paramètres)
# ═══════════════════════════════════════════════════════════

# Copie la sauvegarde courante vers dest_path. Retourne true si OK.
func export_to(dest_path: String) -> bool:
	var src := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if src == null:
		push_warning("SaveManager: aucune sauvegarde à exporter")
		return false
	var content := src.get_as_text()
	src.close()
	var dst := FileAccess.open(dest_path, FileAccess.WRITE)
	if dst == null:
		push_error("SaveManager: impossible d'écrire " + dest_path)
		return false
	dst.store_string(content)
	dst.close()
	return true

# Valide puis installe une sauvegarde externe à la place de la courante.
# La sauvegarde actuelle n'est JAMAIS écrasée par un fichier invalide
# (JSON illisible, structure inattendue ou version non supportée).
# Retourne true si l'import a réussi — l'appelant recharge alors la scène.
func import_from(src_path: String) -> bool:
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return false
	var content := src.get_as_text()
	src.close()

	var json := JSON.new()
	if json.parse(content) != OK or not (json.get_data() is Dictionary):
		push_warning("SaveManager: import refusé — fichier illisible ou mal formé")
		return false
	var data: Dictionary = json.get_data()
	var ver := int(data.get("version", 0))
	if not _is_version_supported(ver):
		push_warning("SaveManager: import refusé — version %d non supportée (attendu 11–%d)" \
				% [ver, SAVE_VER])
		return false

	return _write_text_atomic(SAVE_PATH, content)
