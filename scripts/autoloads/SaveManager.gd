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
# Écritures SUSPENDUES pendant une run d'expédition (chantier 9) : la
# sauvegarde de référence est celle du LANCEMENT — aucune écriture en cours
# de run (ni debounce, ni flush de fermeture), sinon mourir renverrait à un
# état de mi-run et la sanction serait vide. Le dirty est CONSERVÉ pour la
# reprise (sortie normale → flush ; Game Over → rechargement, rien à écrire).
var _suspendue := false
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

	for sig: Signal in signaux_progression():
		sig.connect(_on_progress)

	# Nom du héros = compteur méta R-XXX dès le boot (GameData est chargé
	# avant nous dans l'ordre des autoloads).
	_appliquer_nom_hero()

# SOURCE UNIQUE des déclencheurs de sauvegarde. Les tests et le
# ScreenshotTool itèrent cette liste pour se déconnecter (ne jamais écrire
# la sauvegarde depuis un outil) — une liste en dur chez eux deviendrait
# fausse au premier signal ajouté ici.
func signaux_progression() -> Array[Signal]:
	return [
		EventBus.xp_gained,
		EventBus.bestiary_updated,
		EventBus.resources_changed,
		EventBus.entity_evolved,
		EventBus.passive_unlocked,
		EventBus.equipment_changed,
		EventBus.equipement_evolue,
		EventBus.village_tier_change,
		# Économie de récompense (chantier 6) :
		EventBus.heros_xp_gagnee,
		EventBus.heros_niveau_change,
		EventBus.euren_change,
		# Alarme & assauts (chantier 11) — un slot rempli doit survivre :
		EventBus.lieutenant_vaincu,
		# Économie du QG (chantier 12) — Modules (crédit/débit) et voies :
		EventBus.modules_change,
		EventBus.voie_ouverte,
	]

# Lecture publique : load_save() a-t-il déjà tourné ? (Un outil dev — ex.
# SandboxExpe pour le héros réel — charge la sauvegarde s'il est lancé seul,
# mais jamais deux fois par-dessus une partie en cours.)
func est_chargee() -> bool:
	return _load_attempted

func _on_progress(_a = null, _b = null) -> void:
	_save_dirty = true
	_save_timer.start()

func _flush_save() -> void:
	if _suspendue:
		return   # run en cours : le dirty attend la reprise (jamais perdu)
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
	if _suspendue:
		return   # run d'expédition en cours : la référence reste le lancement
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
# rotation de l'ancien fichier vers `path`.bak (filet de sécurité — pour la
# sauvegarde de partie, il est rechargé automatiquement si la principale
# devient illisible), puis renommage. Backup dérivé du chemin (le fichier
# méta a le sien, jamais mélangé à celui de la sauvegarde).
func _write_text_atomic(path: String, content: String) -> bool:
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: impossible d'ouvrir %s en écriture" % tmp_path)
		return false
	file.store_string(content)
	file.flush()
	file.close()
	# Rotation : l'ancien fichier devient le backup.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		DirAccess.rename_absolute(path, bak_path)
	if DirAccess.rename_absolute(tmp_path, path) == OK:
		return true
	push_error("SaveManager: impossible de remplacer %s (l'ancienne version est dans %s)"
			% [path, bak_path])
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
#  Sanction de mort (chantier 9) : flush de lancement, rechargement,
#  compteur de reconstruction R-XXX MÉTA-PERSISTANT
# ═══════════════════════════════════════════════════════════

# Fichier MÉTA, SÉPARÉ de la sauvegarde de partie (règle actée 06/07/2026) :
# le Game Over recharge la sauvegarde, le compteur ne doit JAMAIS reculer
# avec elle. JSON minimal { version, reconstructions } ; absent → R-001.
const META_PATH := "user://IdleEvolutionMeta.json"
const META_VER := 1
# Plafond D'AFFICHAGE : le nom reste R-999 au-delà (l'interne continue de
# compter — au plus simple, la donnée n'est pas perdue si un usage vient).
const RECONSTRUCTION_MAX_AFFICHE := 999

var _reconstructions := 1
var _meta_chargee := false

# Sauvegarde IMMÉDIATE (hors debounce) — point de sauvegarde de référence au
# lancement d'une expédition : mourir renvoie à l'état exact du départ.
func sauvegarder_maintenant() -> void:
	if _suspendue:
		return   # run en cours : la référence reste celle du lancement
	_save_timer.stop()
	_save_dirty = false
	save()

# Suspend toute écriture de la sauvegarde de partie (appelé par le Village au
# lancement d'une expédition, APRÈS le flush de référence). Le fichier méta
# n'est PAS concerné (écrit en direct, jamais par save()).
func suspendre_ecritures() -> void:
	_suspendue = true

# Reprise des écritures à la fin de la run. `flush` : true = sortie normale
# (la progression accumulée pendant la run — dirty conservé — est écrite
# immédiatement) ; false = Game Over (l'état va être rechargé, rien à écrire).
func reprendre_ecritures(flush := true) -> void:
	_suspendue = false
	if flush:
		_flush_save()

# Recharge la DERNIÈRE sauvegarde PAR-DESSUS l'état runtime (Game Over).
# Ré-application du fichier : suffisant aujourd'hui — depuis la sauvegarde de
# lancement, une run ne mutate que heros_xp / euren (crédités par signaux),
# depuis le chantier 11 expe_completions / lieutenants_vaincus, et depuis le
# chantier 12 modules / objets_lieutenants (accordés au premier kill) : ces
# clés sont TOUJOURS présentes dans la sauvegarde de lancement (player
# dupliqué intégralement, défauts initialisés dans GameData.player), donc
# _load_player (merge overwrite) les écrase — un Lieutenant tué ou un
# Module gagné PENDANT la run perdue est bien annulé (règle actée, testé ;
# dette « point ouvert 22 » réévaluée au chantier 12 : couvert).
# À re-évaluer quand une run mutera d'autres états (drops, découvertes) :
# il faudra alors réinitialiser GameData avant ré-application.
func recharger() -> void:
	_save_timer.stop()
	_save_dirty = false
	_save_loaded = false
	load_save()

# ─── Compteur de reconstruction R-XXX ────────────────────────

# Nom courant du héros : « R-%03d », plafonné à R-999 à l'affichage.
# SOURCE UNIQUE du formatage — ne jamais reformater ailleurs.
func nom_reconstruction() -> String:
	_charger_meta()
	return "R-%03d" % mini(_reconstructions, RECONSTRUCTION_MAX_AFFICHE)

func compteur_reconstruction() -> int:
	_charger_meta()
	return _reconstructions

# Incrément au Game Over : écrit le fichier méta IMMÉDIATEMENT (il doit
# survivre au rechargement qui suit, et à un crash) puis ré-applique le
# nouveau nom à l'entité héros.
func incrementer_reconstruction() -> void:
	_charger_meta()
	_reconstructions += 1
	_ecrire_meta()
	_appliquer_nom_hero()

func _charger_meta() -> void:
	if _meta_chargee:
		return
	_meta_chargee = true
	if not FileAccess.file_exists(META_PATH):
		return   # première partie : R-001, fichier créé au premier Game Over
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK or not (json.get_data() is Dictionary):
		push_warning("SaveManager: fichier méta illisible — compteur reparti à R-001")
		return
	_reconstructions = maxi(1, int((json.get_data() as Dictionary).get("reconstructions", 1)))

func _ecrire_meta() -> void:
	_write_text_atomic(META_PATH, JSON.stringify({
		"version": META_VER,
		"reconstructions": _reconstructions,
	}, "\t"))

# Le nom affiché du héros = compteur méta, branché à la SOURCE UNIQUE des
# noms (l'entité « hero » de GameData — Translations.entity_name et le pont
# CTB lisent nom_affichage_*). Appliqué au boot et à chaque incrément ;
# identique FR/EN (matricule, pas un mot).
func _appliquer_nom_hero() -> void:
	var hero := GameData.get_entity("hero")
	if hero.is_empty():
		return
	var nom := nom_reconstruction()
	hero["nom_affichage_fr"] = nom
	hero["nom_affichage_en"] = nom

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
