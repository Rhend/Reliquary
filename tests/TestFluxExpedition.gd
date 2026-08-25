extends Node
# ============================================================
# TestFluxExpedition — Branchement au flux de jeu principal (chantier 8).
#
# Couvre le flux COMPLET dans le vrai jeu :
#   QG (Village) → « Partir en expédition » ouvre la HoloMap → clic Lieu →
#   panneau de lancement (palier) → ExpeditionScreen (vrai héros, pool de la
#   destination) → run jouée → sortie → recap → retour au QG → crédits
#   XP/Euren PERSISTÉS (round-trip par le VRAI fichier de sauvegarde).
# Plus : défaite sans crédit, et sandbox toujours débranché de la sauvegarde.
#
# ⚠ Ce test ÉCRIT réellement la sauvegarde — c'est son objet (exception
# unique à la règle « jamais d'écriture dans un test »). Protocole de
# protection : les fichiers réels sont MIS DE CÔTÉ au démarrage (renommés
# .avant_test → le flux part d'une partie neuve, déterministe) puis
# RESTAURÉS avant de quitter, échecs compris.
# ============================================================

const SAUV := SaveManager.SAVE_PATH
const META := SaveManager.META_PATH
# Protocole de protection (chantier 8, ÉTENDU au fichier méta au chantier 9).
const FICHIERS_SAUV: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]
const PALIER_ENCEINTE: PalierProfondeurData = preload("res://data/expedition/palier_enceinte.tres")
const PALIER_PERIPHERIE: PalierProfondeurData = preload("res://data/expedition/palier_peripherie.tres")
# Graine de la run de DÉFAITE (reproductible : le RNG Godot est déterministe
# multi-plateforme) — vérifiée : l'étage 1 contient un combat atteignable.
const GRAINE_DEFAITE := 424242

var _results: Array = []
var village: Village

func _ready() -> void:
	# Fenêtre headless : 64×64 par défaut — le Village se construit sur la
	# taille du viewport, on rétablit la taille projet.
	get_tree().root.size = Vector2i(1280, 720)
	_proteger_sauvegarde()
	# Le méta RÉEL a déjà été lu par SaveManager._ready (avant la protection) :
	# repartir d'une partie neuve, compteur R-001 compris.
	SaveManager._meta_chargee = true
	SaveManager._reconstructions = 1
	SaveManager._appliquer_nom_hero()
	await _run_all()
	_restaurer_sauvegarde()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("\n=== TEST FLUX EXPÉDITION RÉELLE (chantier 8) ===\n")
	await _test_qg_vers_holomap()
	await _test_lieu_vers_lancement()
	await _test_lancement_vers_expedition()
	await _test_run_victoire_et_credits()
	await _test_persistance_round_trip()
	await _test_defaite_sans_credit()
	await _test_sandbox_sans_ecriture()   # EN DERNIER : débranche SaveManager

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

# Sauvegarde réelle mise de côté (le flux part d'une partie neuve).
func _proteger_sauvegarde() -> void:
	for f: String in FICHIERS_SAUV:
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f),
					ProjectSettings.globalize_path(f) + ".avant_test")

# Restauration inconditionnelle : les fichiers du test sont supprimés, les
# fichiers réels reprennent leur place.
func _restaurer_sauvegarde() -> void:
	for f: String in FICHIERS_SAUV:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if FileAccess.file_exists(f + ".avant_test"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f) + ".avant_test",
					ProjectSettings.globalize_path(f))

# Lit le fichier de sauvegarde réel → dict `player` ({} si absent/illisible).
func _joueur_du_fichier() -> Dictionary:
	if not FileAccess.file_exists(SAUV):
		return {}
	var f := FileAccess.open(SAUV, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not (json.get_data() is Dictionary):
		f.close()
		return {}
	f.close()
	return (json.get_data() as Dictionary).get("player", {})

# Premier EcranMessage vivant sous `racine` (récursif) — séquence Game Over.
func _ecran_message_sous(racine: Node) -> EcranMessage:
	for child in racine.get_children():
		if child is EcranMessage:
			return child
		var trouve := _ecran_message_sous(child)
		if trouve != null:
			return trouve
	return null

# Tous les Buttons sous `racine` (récursif) — pour presser les vrais boutons.
func _boutons_sous(racine: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in racine.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_boutons_sous(child))
	return out

func _bouton_texte(racine: Node, texte: String) -> Button:
	for b in _boutons_sous(racine):
		if b.text == texte:
			return b
	return null

# BFS sur la carte de la run : chemin (liste de nids, départ exclu) du joueur
# vers le PREMIER nœud satisfaisant `cible`. Vide si aucun.
func _chemin_vers(run: ExpeRun, cible: Callable) -> Array[int]:
	var depart := run.position_joueur
	var file: Array[int] = [depart]
	var parent := {depart: -1}
	while not file.is_empty():
		var nid: int = file.pop_front()
		if nid != depart and cible.call(run.carte.noeud(nid)):
			var chemin: Array[int] = []
			var cur := nid
			while cur != depart:
				chemin.push_front(cur)
				cur = parent[cur]
			return chemin
		for v in run.carte.noeud(nid).voisins:
			if not parent.has(v):
				parent[v] = nid
				file.append(v)
	return []

# Joue l'étage courant : résout tous les nœuds atteignables (hors Fin), puis
# rejoint la Fin d'étage. Retourne quand choix_ouvert ou run terminée.
func _jouer_etage(screen: ExpeditionScreen) -> void:
	var run: ExpeRun = screen.run
	var etage_courant := run.etage
	while not run.est_terminee and run.etage == etage_courant and not run.choix_ouvert:
		var chemin := _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
			return not nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			chemin = _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
				return nd.type == Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			return   # rien d'atteignable (ne doit pas arriver : carte connexe)
		for nid in chemin:
			screen.jouer_deplacement(nid)
			if run.est_terminee or run.choix_ouvert:
				return

# ─── 1. QG → HoloMap ────────────────────────────────────────

func _test_qg_vers_holomap() -> void:
	print("[TEST 1] QG → « Partir en expédition » ouvre la HoloMap")
	# Village ÉCLOS : sans ça la partie neuve démarre sur la BirthSequence et le
	# hub (donc les panneaux) n'existe pas. Un joueur qui atteint la HoloMap a
	# forcément éclos — c'est l'état réaliste pour ce flux.
	GameData.village["eclos"] = true
	village = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	add_child(village)   # enfant du nœud de test (la racine est occupée pendant _ready)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(SaveManager.est_chargee(), "SaveManager.load_save() a tourné (Village)")

	# Régression : partir de la carte alors qu'un panneau du QG est ouvert
	# laissait ce panneau vivre derrière l'overlay (hub réduit + hex
	# sélectionné), et il réapparaissait tel quel au retour de la carte.
	village._open_panel("adventure")
	await get_tree().process_frame
	_assert(village._rp_root != null and village._active_panel_id == "adventure",
			"pré-requis : un panneau du QG est bien ouvert")

	village.start_selected_expedition()
	await get_tree().process_frame
	_assert(village._active_panel_id == "",
			"ouvrir la carte ferme le panneau du QG (plus d'hex sélectionné)")
	# La fermeture glisse (0,25 s) avant de libérer le panneau.
	await get_tree().create_timer(0.45).timeout
	_assert(village._rp_root == null,
			"le panneau du QG est libéré, pas juste masqué derrière la carte")

	_assert(village._holo_overlay != null and is_instance_valid(village._holo_overlay),
			"start_selected_expedition ouvre la carte holo")
	_assert(village._holo_overlay is HoloMap3DOverlay, "l'overlay est la HoloMap 3D")
	_assert(not AdventureSystem.is_running,
			"l'ancienne boucle idle n'est PAS lancée (AdventureSystem débranché de l'UI)")

# ─── 2. Lieu → panneau de lancement ─────────────────────────

func _test_lieu_vers_lancement() -> void:
	print("\n[TEST 2] Clic Lieu → panneau de lancement (destination + palier)")
	village._holo_cache.lieu_selectionne.emit("biome_foret")
	await get_tree().process_frame
	var panneau: ExpeLancementPanel = village._expe_lancement
	_assert(panneau != null and is_instance_valid(panneau),
			"le clic Lieu ouvre le panneau de lancement")
	_assert(panneau.lieu_id == "biome_foret", "destination = le Lieu cliqué")
	# Progression verrouillée (retour Rhend 07/2026) : partie neuve → seule
	# la Périphérie est proposée ; chaque strate complétée (3 étages) ouvre
	# la suivante. Palier verrouillé = ABSENT (pas grisé) + indice 🔒.
	_assert(panneau._boutons_palier.size() == 1,
			"partie neuve : seul le palier Périphérie est proposé")
	_assert(panneau._palier_idx == 0, "Périphérie présélectionnée")
	_assert(village.adv_selected_biome_id == "biome_foret",
			"le biome du panneau Expéditions suit la destination")
	panneau.annuler()
	await get_tree().process_frame
	GameData.marquer_strate_completee("biome_foret", "palier_peripherie")
	village._holo_cache.lieu_selectionne.emit("biome_foret")
	await get_tree().process_frame
	panneau = village._expe_lancement
	_assert(panneau._boutons_palier.size() == 2,
			"Périphérie complétée → l'Enceinte s'ajoute (le Noyau reste absent)")
	GameData.marquer_strate_completee("biome_foret", "palier_enceinte")
	panneau.annuler()
	await get_tree().process_frame
	village._holo_cache.lieu_selectionne.emit("biome_foret")
	await get_tree().process_frame
	panneau = village._expe_lancement
	_assert(panneau._boutons_palier.size() == 3,
			"Enceinte complétée → les 3 paliers sont proposés")
	# Remise à neuf : la suite du flux repart d'une partie vierge.
	GameData.player["expe_completions"] = {}

	# Annuler referme le modal, la carte reste ouverte.
	var btn_annuler := _bouton_texte(panneau, Translations.T("expe.annuler_btn"))
	_assert(btn_annuler != null, "bouton Annuler présent")
	btn_annuler.pressed.emit()
	await get_tree().process_frame
	_assert(village._expe_lancement == null or not is_instance_valid(village._expe_lancement),
			"Annuler referme le panneau de lancement")
	_assert(village._holo_overlay != null and is_instance_valid(village._holo_overlay),
			"la carte holo reste ouverte après Annuler")

# ─── 3. Lancement → écran d'expédition ──────────────────────

func _test_lancement_vers_expedition() -> void:
	print("\n[TEST 3] PARTIR → ExpeditionScreen (vrai héros, pool destination)")
	# Progression verrouillée : l'Enceinte exige la Périphérie complétée.
	GameData.marquer_strate_completee("biome_foret", "palier_peripherie")
	village._holo_cache.lieu_selectionne.emit("biome_foret")
	await get_tree().process_frame
	var panneau: ExpeLancementPanel = village._expe_lancement
	# Choix du palier Enceinte (bouton radio réel) puis PARTIR (bouton réel).
	panneau._boutons_palier[1].button_pressed = true
	var btn_partir := _bouton_texte(panneau, Translations.T("expe.partir_btn"))
	_assert(btn_partir != null, "bouton PARTIR présent")
	btn_partir.pressed.emit()
	await get_tree().process_frame

	var screen: ExpeditionScreen = village._expedition_screen
	_assert(screen != null and is_instance_valid(screen), "écran d'expédition créé")
	_assert(village._expe_lancement == null or not is_instance_valid(village._expe_lancement),
			"panneau de lancement refermé au départ")
	_assert(village._holo_overlay == null, "HoloMap refermée (veille) au départ")
	if screen == null:
		return
	_assert(screen.run != null and not screen.run.est_terminee, "run démarrée")
	_assert(screen.run.avatar_data.id == "hero",
			"camp joueur = VRAI héros (CtbPont.combattant_depuis_heros)")
	_assert(screen.pool != null and screen.pool.id == "pool_defaut",
			"pool résolu par la destination (provisoire : pool_defaut partagé)")
	_assert(screen.run.palier.id == "palier_enceinte",
			"le palier choisi au lancement circule dans la run")
	# Sauvegarde de RÉFÉRENCE au lancement (chantier 9) + écritures suspendues.
	_assert(FileAccess.file_exists(SAUV), "sauvegarde de lancement écrite (flush explicite)")
	_assert(is_equal_approx(float(_joueur_du_fichier().get("heros_xp", -1.0)),
			ProgressionHeros.xp_totale()),
			"la sauvegarde de lancement porte l'état exact du départ")
	_assert(SaveManager._suspendue, "écritures suspendues pendant la run")
	_assert(screen.run.avatar_data.nom_journal() == SaveManager.nom_reconstruction(),
			"nom du héros en combat = compteur R-XXX (%s)" % SaveManager.nom_reconstruction())

# ─── 4. Run jouée → sortie → crédits ────────────────────────

func _test_run_victoire_et_credits() -> void:
	print("\n[TEST 4] Run jouée → sortie → XP/Euren crédités, retour au QG")
	var screen: ExpeditionScreen = village._expedition_screen
	var run: ExpeRun = screen.run
	var xp_avant: float = ProgressionHeros.xp_totale()
	var euren_avant: float = ProgressionHeros.euren()

	# Hook de test : combats auto-résolus, héros rendu invincible (le calibrage
	# n'est pas l'objet — on veut la mécanique de crédit, pas l'issue du duel).
	screen.combat_auto = true
	run.avatar_data.pv_max = 99999.0
	run.avatar_data.atk = 9999.0
	run.pv_avatar = 99999.0

	# Joue étage par étage jusqu'à avoir gagné au moins un combat, puis sort
	# (extraction) ; complétion au dernier étage sinon (crédit identique).
	var suspension_verifiee := false
	while not run.est_terminee:
		_jouer_etage(screen)
		# Suspension (chantier 9) : de l'XP a été créditée en runtime, mais le
		# FICHIER porte toujours l'état du lancement — même un flush simulé
		# (fermeture de la fenêtre en pleine run) n'écrit rien.
		if not suspension_verifiee and run.xp_gagnee > 0.0 and not run.est_terminee:
			suspension_verifiee = true
			SaveManager._flush_save()
			_assert(is_equal_approx(float(_joueur_du_fichier().get("heros_xp", -1.0)),
					xp_avant), "aucune écriture pendant la run (fermeture comprise)")
		if run.est_terminee:
			break
		if run.choix_ouvert:
			if run.nb_combats > 0:
				screen._btn_extraire.pressed.emit()
			else:
				screen._btn_continuer.pressed.emit()
	await get_tree().process_frame

	_assert(run.est_terminee and not run.defaite, "run terminée sans défaite")
	_assert(run.nb_combats > 0, "au moins un combat gagné pendant la run")
	_assert(run.xp_gagnee > 0.0, "XP de niveau gagnée pendant la run")
	_assert(run.euren_credite > 0.0, "Euren crédité à la sortie")
	_assert(is_equal_approx(ProgressionHeros.xp_totale(), xp_avant + run.xp_gagnee),
			"ProgressionHeros.xp_totale reflète l'XP de la run")
	_assert(is_equal_approx(ProgressionHeros.euren(), euren_avant + run.euren_credite),
			"ProgressionHeros.euren reflète l'Euren crédité")
	_assert(run.affixes.is_empty() and run.inventaire.is_empty(),
			"affixes et consommables purgés en fin de run")

	# Recap placeholder affiché, puis retour au QG (bouton réel).
	_assert(not screen._recap_final.is_empty(), "recap de fin d'expédition affiché")
	var btn_retour := _bouton_texte(screen, Translations.T("expe.retour_btn"))
	_assert(btn_retour != null, "bouton « Retour au QG » présent")
	btn_retour.pressed.emit()
	await get_tree().process_frame
	_assert(village._expedition_screen == null, "retour au QG : écran d'expédition libéré")

# ─── 5. Persistance round-trip ──────────────────────────────

func _test_persistance_round_trip() -> void:
	print("\n[TEST 5] Crédits persistés (round-trip par le fichier de sauvegarde)")
	# Chantier 9 : la reprise des écritures au retour a DÉJÀ flushé les
	# crédits de la run (plus de debounce en attente).
	_assert(not SaveManager._suspendue, "écritures reprises au retour au QG")
	_assert(not SaveManager._save_dirty, "crédits déjà flushés à la reprise (rien en attente)")
	_assert(FileAccess.file_exists(SAUV), "fichier de sauvegarde écrit")

	var f := FileAccess.open(SAUV, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	_assert(err == OK and json.get_data() is Dictionary, "sauvegarde JSON lisible")
	var data: Dictionary = json.get_data()
	var joueur: Dictionary = data.get("player", {})
	_assert(is_equal_approx(float(joueur.get("heros_xp", -1.0)), ProgressionHeros.xp_totale()),
			"heros_xp du FICHIER == XP runtime (round-trip)")
	_assert(is_equal_approx(float(joueur.get("euren", -1.0)), ProgressionHeros.euren()),
			"euren du FICHIER == Euren runtime (round-trip)")

# ─── 6. Défaite : SÉQUENCE DE GAME OVER (chantier 9) ────────

func _test_defaite_sans_credit() -> void:
	print("\n[TEST 6] Défaite → Game Over : 2 messages, R-XXX incrémenté, état rechargé")
	var xp_lancement: float = ProgressionHeros.xp_totale()
	var euren_avant: float = ProgressionHeros.euren()
	_assert(SaveManager.compteur_reconstruction() == 1,
			"compteur NON incrémenté par l'extraction/complétion (toujours R-001)")
	var nom_avant := SaveManager.nom_reconstruction()

	# Même rail que le bouton PARTIR (lancer_expedition), graine fixée pour
	# une carte reproductible ; héros sabré (PV 1) → première morsure = mort.
	village.lancer_expedition("biome_foret", PALIER_PERIPHERIE, GRAINE_DEFAITE)
	await get_tree().process_frame
	var screen: ExpeditionScreen = village._expedition_screen
	_assert(screen != null and is_instance_valid(screen), "écran d'expédition (run de défaite) créé")
	var run: ExpeRun = screen.run
	screen.combat_auto = true
	run.avatar_data.pv_max = 1.0
	run.avatar_data.atk = 1.0
	run.avatar_data.def = 0.0
	run.pv_avatar = 1.0

	# XP « de run » simulée (crédit de victoire) : elle doit DISPARAÎTRE au
	# rechargement — elle n'existait pas à la sauvegarde de lancement.
	ProgressionHeros.gagner_xp(50.0)
	_assert(is_equal_approx(ProgressionHeros.xp_totale(), xp_lancement + 50.0),
			"XP de run créditée en runtime avant la mort")

	# Marche vers le combat le plus proche, étage par étage, jusqu'à la mort.
	while not run.est_terminee:
		var chemin := _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
			return not nd.resolu and nd.type == Enums.TypeNoeud.COMBAT)
		if chemin.is_empty():
			chemin = _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
				return not nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			chemin = _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
				return nd.type == Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			break
		for nid in chemin:
			screen.jouer_deplacement(nid)
			if run.est_terminee or run.choix_ouvert:
				break
		if run.choix_ouvert and not run.est_terminee:
			screen._btn_continuer.pressed.emit()
	await get_tree().process_frame

	_assert(run.est_terminee and run.defaite, "défaite survenue (graine %d)" % GRAINE_DEFAITE)
	_assert(run.euren_credite == 0.0, "aucun Euren crédité en défaite")

	# Message 1 — « R-001 est détruit... » (compteur COURANT, avant incrément).
	var msg1 := _ecran_message_sous(screen)
	_assert(msg1 != null, "écran Game Over (message 1) affiché sur l'écran d'expédition")
	if msg1 == null:
		return
	_assert(msg1.message == Translations.T("gameover.detruit") % nom_avant,
			"message 1 = « %s est détruit... » (compteur AVANT incrément)" % nom_avant)
	_assert(SaveManager.compteur_reconstruction() == 1,
			"compteur pas encore incrémenté à l'affichage du message 1")
	msg1.confirmer()
	await get_tree().process_frame

	# Incrément + rechargement + message 2 — « Reconstruction de R-002 complète. »
	_assert(village._expedition_screen == null, "écran d'expédition libéré après confirmation")
	_assert(SaveManager.compteur_reconstruction() == 2, "compteur incrémenté au Game Over (R-002)")
	_assert(SaveManager.nom_reconstruction() == "R-002", "formatage R-%03d (R-002)")
	var msg2 := _ecran_message_sous(village)
	_assert(msg2 != null, "message 2 affiché sur le Village après rechargement")
	if msg2 != null:
		_assert(msg2.message == Translations.T("gameover.reconstruit") % "R-002",
				"message 2 = « Reconstruction de R-002 complète. » (NOUVEAU compteur)")
		msg2.confirmer()
		await get_tree().process_frame
		_assert(_ecran_message_sous(village) == null, "message 2 refermé → retour au QG")

	# État RECHARGÉ = état exact du lancement : XP de run perdue, Euren intact.
	_assert(is_equal_approx(ProgressionHeros.xp_totale(), xp_lancement),
			"XP créditée pendant la run PERDUE au rechargement")
	_assert(is_equal_approx(ProgressionHeros.euren(), euren_avant),
			"Euren possédé inchangé après le Game Over")

	# Nom du héros à jour PARTOUT (source unique : l'entité hero).
	_assert(Translations.entity_name(GameData.get_entity("hero")) == "R-002",
			"nom du héros (entité/Translations) = R-002 après reconstruction")
	var transitoire := CtbPont.combattant_depuis_heros()
	_assert(transitoire != null and transitoire.nom_affichage_fr == "R-002",
			"prochain combattant héros (pont CTB) nommé R-002")

	# Méta-persistance : le compteur survit au rechargement ET vit dans son
	# propre fichier (round-trip réel : relecture forcée depuis le disque).
	SaveManager.recharger()
	_assert(SaveManager.compteur_reconstruction() == 2,
			"le compteur survit à un rechargement de sauvegarde supplémentaire")
	_assert(FileAccess.file_exists(META), "fichier méta écrit (séparé de la sauvegarde)")
	SaveManager._meta_chargee = false
	SaveManager._reconstructions = 1
	_assert(SaveManager.compteur_reconstruction() == 2,
			"round-trip méta : relecture du fichier → compteur 2")

# ─── 7. Sandbox : toujours aucune écriture ──────────────────

func _test_sandbox_sans_ecriture() -> void:
	print("\n[TEST 7] SandboxExpe reste débranché de la sauvegarde (outil dev)")
	# EN DERNIER : le sandbox déconnecte les déclencheurs de SaveManager pour
	# tout le process — plus aucune écriture possible ensuite.
	var sandbox: Control = (load("res://scenes/expedition/SandboxExpe.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(sandbox)
	await get_tree().process_frame

	var encore_connectes := 0
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			encore_connectes += 1
	_assert(encore_connectes == 0, "tous les déclencheurs de sauvegarde déconnectés",
			"%d encore connectés" % encore_connectes)

	SaveManager._save_dirty = false
	EventBus.euren_change.emit(999999.0)   # signal de progression factice
	EventBus.heros_xp_gagnee.emit(1.0, 1.0)
	await get_tree().process_frame
	_assert(not SaveManager._save_dirty,
			"une progression émise depuis le sandbox ne marque PAS la sauvegarde dirty")
	_assert(SaveManager._save_timer.is_stopped(), "timer de sauvegarde arrêté")
	sandbox.queue_free()

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
