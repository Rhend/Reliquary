extends Node
# ============================================================
# TestGameOver — Sanction de mort, briques unitaires (chantier 9) :
# compteur R-XXX méta-persistant (init R-001, incrément, plafond 999,
# formatage R-%03d, round-trip par le VRAI fichier méta), nom du héros
# branché à la source unique (entité hero), rechargement de sauvegarde
# (recharger) et suspension des écritures pendant une run.
#
# La séquence COMPLÈTE en jeu (2 messages, ordre, XP de run perdue) est
# couverte par TestFluxExpedition (test 6).
#
# ⚠ Écrit réellement sauvegarde ET fichier méta (c'est l'objet) — protocole
# de protection du chantier 8 : fichiers réels mis de côté (.avant_test)
# puis restaurés avant de quitter, échecs compris.
# ============================================================

const SAUV := "user://IdleEvolutionSave.json"
const META := SaveManager.META_PATH
const FICHIERS: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_proteger()
	_run_all()
	_restaurer()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST GAME OVER / COMPTEUR R-XXX (chantier 9) ===\n")
	_test_format_et_plafond()
	_test_init_sans_fichier()
	_test_increment_et_round_trip()
	_test_nom_hero_source_unique()
	_test_recharger_restaure()
	_test_suspension_ecritures()

# ─── Helpers ────────────────────────────────────────────────

func _ok(label: String) -> void:
	_results.append({"ok": true,  "label": label})
	print("  ✓ " + label)

func _fail(label: String, detail: String = "") -> void:
	_results.append({"ok": false, "label": label})
	print("  ✗ " + label + (" — " + detail if detail != "" else ""))

func _assert(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_ok(label)
	else:
		_fail(label, detail)

func _proteger() -> void:
	for f: String in FICHIERS:
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f),
					ProjectSettings.globalize_path(f) + ".avant_test")

func _restaurer() -> void:
	for f: String in FICHIERS:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if FileAccess.file_exists(f + ".avant_test"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f) + ".avant_test",
					ProjectSettings.globalize_path(f))

# Force l'état interne du compteur (le méta réel a pu être lu au boot des
# autoloads, AVANT la protection des fichiers).
func _forcer_compteur(n: int) -> void:
	SaveManager._meta_chargee = true
	SaveManager._reconstructions = n

# ─── 1. Formatage R-%03d + plafond d'affichage 999 ──────────

func _test_format_et_plafond() -> void:
	print("[TEST 1] Formatage R-%03d, plafond d'affichage R-999")
	_forcer_compteur(1)
	_assert(SaveManager.nom_reconstruction() == "R-001", "compteur 1 → R-001")
	_forcer_compteur(42)
	_assert(SaveManager.nom_reconstruction() == "R-042", "compteur 42 → R-042 (3 chiffres)")
	_forcer_compteur(999)
	_assert(SaveManager.nom_reconstruction() == "R-999", "compteur 999 → R-999")
	_forcer_compteur(999)
	SaveManager.incrementer_reconstruction()
	_assert(SaveManager.compteur_reconstruction() == 1000,
			"l'interne continue de compter au-delà de 999 (au plus simple)")
	_assert(SaveManager.nom_reconstruction() == "R-999",
			"le NOM reste R-999 au-delà du plafond")

# ─── 2. Valeur initiale sans fichier méta ───────────────────

func _test_init_sans_fichier() -> void:
	print("\n[TEST 2] Première partie : pas de fichier méta → R-001")
	for f: String in [META, META + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	SaveManager._meta_chargee = false
	SaveManager._reconstructions = 1
	_assert(SaveManager.compteur_reconstruction() == 1, "compteur initial = 1")
	_assert(SaveManager.nom_reconstruction() == "R-001", "nom initial = R-001")
	_assert(not FileAccess.file_exists(META),
			"aucun fichier méta créé avant le premier Game Over")

# ─── 3. Incrément → écriture immédiate + round-trip réel ────

func _test_increment_et_round_trip() -> void:
	print("\n[TEST 3] Incrément : fichier méta écrit, round-trip disque")
	_forcer_compteur(1)
	SaveManager.incrementer_reconstruction()
	_assert(SaveManager.compteur_reconstruction() == 2, "incrément 1 → 2")
	_assert(FileAccess.file_exists(META), "fichier méta écrit IMMÉDIATEMENT à l'incrément")

	# Round-trip : relecture forcée depuis le disque (état interne écrasé).
	SaveManager._meta_chargee = false
	SaveManager._reconstructions = 1
	_assert(SaveManager.compteur_reconstruction() == 2, "relecture disque → compteur 2")

	# Le fichier est bien un JSON méta séparé, pas la sauvegarde de partie.
	var f := FileAccess.open(META, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	_assert(err == OK and json.get_data() is Dictionary, "fichier méta JSON lisible")
	var data: Dictionary = json.get_data()
	_assert(int(data.get("reconstructions", -1)) == 2, "clé reconstructions = 2")
	_assert(not data.has("player") and not data.has("entities"),
			"le méta ne contient PAS la partie (fichier séparé)")

# ─── 4. Nom du héros : source unique (entité hero) ──────────

func _test_nom_hero_source_unique() -> void:
	print("\n[TEST 4] Nom du héros branché à l'entité (Translations + pont CTB)")
	_forcer_compteur(7)
	SaveManager._appliquer_nom_hero()
	var hero := GameData.get_entity("hero")
	_assert(Translations.entity_name(hero) == "R-007",
			"Translations.entity_name(hero) = R-007")
	_assert(str(hero.get("nom_affichage_en", "")) == "R-007",
			"nom EN identique (matricule, pas un mot)")
	var d := CtbPont.combattant_depuis_heros()
	_assert(d != null and d.nom_affichage_fr == "R-007",
			"combattant CTB du héros nommé R-007 (copie du pont)")
	SaveManager.incrementer_reconstruction()
	_assert(Translations.entity_name(GameData.get_entity("hero")) == "R-008",
			"incrément → nom ré-appliqué partout (R-008)")

# ─── 5. recharger() : la sauvegarde écrase l'état runtime ───

func _test_recharger_restaure() -> void:
	print("\n[TEST 5] recharger() restaure l'état sauvegardé (pas le méta)")
	SaveManager.load_save()   # aucun fichier (protégé) : marque juste « chargé »
	GameData.player["heros_xp"] = 100.0
	GameData.player["euren"] = 40.0
	SaveManager.sauvegarder_maintenant()
	_assert(FileAccess.file_exists(SAUV), "sauvegarde de référence écrite")

	GameData.player["heros_xp"] = 987.0   # « progression de run » à perdre
	GameData.player["euren"] = 999.0
	_forcer_compteur(5)
	SaveManager.recharger()
	_assert(is_equal_approx(float(GameData.player.get("heros_xp", -1.0)), 100.0),
			"heros_xp restauré à la valeur sauvegardée")
	_assert(is_equal_approx(float(GameData.player.get("euren", -1.0)), 40.0),
			"euren restauré à la valeur sauvegardée")
	_assert(SaveManager.compteur_reconstruction() == 5,
			"le compteur méta ne recule PAS avec le rechargement")

# ─── 6. Suspension des écritures (pendant une run) ──────────

func _test_suspension_ecritures() -> void:
	print("\n[TEST 6] Suspension : aucune écriture en run, dirty conservé")
	GameData.player["heros_xp"] = 200.0
	SaveManager.sauvegarder_maintenant()
	SaveManager.suspendre_ecritures()

	GameData.player["heros_xp"] = 300.0
	SaveManager._save_dirty = true
	SaveManager._flush_save()             # flush « fermeture de fenêtre »
	SaveManager.sauvegarder_maintenant()  # même un flush explicite est bloqué
	var f := FileAccess.open(SAUV, FileAccess.READ)
	var json := JSON.new()
	json.parse(f.get_as_text())
	f.close()
	var fichier: Dictionary = (json.get_data() as Dictionary).get("player", {})
	_assert(is_equal_approx(float(fichier.get("heros_xp", -1.0)), 200.0),
			"fichier inchangé pendant la suspension (flush bloqués)")

	_assert(SaveManager._save_dirty, "le dirty est CONSERVÉ pendant la suspension")
	SaveManager.reprendre_ecritures(true)
	f = FileAccess.open(SAUV, FileAccess.READ)
	json = JSON.new()
	json.parse(f.get_as_text())
	f.close()
	fichier = (json.get_data() as Dictionary).get("player", {})
	_assert(is_equal_approx(float(fichier.get("heros_xp", -1.0)), 300.0),
			"reprise avec flush : la progression conservée en dirty est écrite")
	_assert(not SaveManager._suspendue and not SaveManager._save_dirty,
			"état propre après reprise")

# ─── Rapport final ──────────────────────────────────────────

func _print_report() -> void:
	var total   := _results.size()
	var passed  := _results.filter(func(r): return r["ok"]).size()
	var failed  := total - passed
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, total, failed])
	if failed > 0:
		print("ÉCHECS :")
		for r in _results:
			if not r["ok"]:
				print("  ✗ " + r["label"])
	print("════════════════════════════════\n")
