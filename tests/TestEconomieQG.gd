extends Node
# ============================================================
# TestEconomieQG — Économie du QG (Rework Combat, chantier 12) :
#   • Module : +1 par PREMIÈRE arrivée sur chaque Fin d'étage (revisite
#     inerte, max 3 par raid de 3 étages, 0 en assaut),
#   • crédit des Modules à la SORTIE seulement (défaite = rien), round-trip
#     de persistance par le vrai fichier,
#   • objet de Lieutenant (« Sceau ») au premier kill d'un VRAI assaut,
#     re-kill sans double, annulé par le Game Over (cohérence chantier 11),
#   • voies à ORDRE FIXE (chantier 13, refonte du « voie par Lieu » du
#     ch.12) : 1 Sceau libre (interchangeable) = 1 voie, ouverture 1→6
#     séquentielle, signal numéroté, round-trip + migration v13→v14,
#   • Atelier SCELLÉ derrière la voie 1 (chantier 13, supersède l'ouverture
#     d'emblée du ch.12) : hex absent, verrou du panneau, déverrouillage,
#   • panneau Expéditions rebranché : « Évoluer biomes » ABSENT,
#     « Évoluer créatures » fonctionnel,
#   • rendu des panneaux VOIES / Forge / Expéditions (fume-tests).
#
# ⚠ Écrit réellement la sauvegarde (round-trip = l'objet) — protocole des
# chantiers 8/9/11 : fichiers réels mis de côté (.avant_test) puis restaurés.
# ============================================================

const SAUV := "user://IdleEvolutionSave.json"
const META := SaveManager.META_PATH
const FICHIERS: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_proteger()
	SaveManager.load_save()   # aucun fichier (protégé) : marque juste « chargé »
	_run_all()
	_restaurer()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST ÉCONOMIE DU QG (chantier 12) ===\n")
	_test_module_drop_complet()
	_test_module_revisite_et_extraction()
	_test_module_defaite()
	_test_module_assaut()
	_test_module_round_trip()
	_test_objet_premier_kill()
	_test_objet_game_over()
	_test_voies_ordre_fixe()
	_test_atelier_scelle()
	_test_panneau_voies()
	_test_panneau_expeditions()

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

# Remise à zéro de l'état chantiers 11/12/13 entre les tests.
func _reset_etat() -> void:
	GameData.player["expe_completions"] = {}
	GameData.player["lieutenants_vaincus"] = {}
	GameData.player["objets_lieutenants"] = {}
	GameData.player["voies_ouvertes"] = 0
	GameData.player["modules"] = 0

func _palier() -> PalierProfondeurData:
	return load("res://data/expedition/palier_peripherie.tres")

func _pool() -> PoolEnnemisData:
	return load("res://data/expedition/pool_defaut.tres")

func _cfg_carte() -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = 1.0   # 100 % Combat : trajets déterministes
	c.poids_mystere = 0.0
	c.poids_coffre = 0.0
	return c

func _cfg_combat() -> ExpeCombatConfigData:
	var c := ExpeCombatConfigData.new()
	c.poids_nb_ennemis = {1: 1.0}
	return c

func _avatar(pv: float, atk: float, vit: float) -> CombattantCtbData:
	var a := CombattantCtbData.new()
	a.id = "avatar_test"
	a.nom_affichage_fr = "Avatar de test"
	a.pv_max = pv
	a.atk = atk
	a.def = 0.0
	a.vit = vit
	a.crit_chance = 0.0
	return a

func _lieutenant_data() -> CombattantCtbData:
	var d := CombattantCtbData.new()
	d.id = "lieutenant_test"
	d.nom_affichage_fr = "Lieutenant de test"
	d.pv_max = 40.0
	d.atk = 1.0
	d.def = 0.0
	d.vit = 10.0
	d.crit_chance = 0.0
	return d

# Run prête à démarrer (assaut optionnel). Avatar costaud par défaut.
func _run(lieu: String, graine: int, assaut: bool = false,
		avatar: CombattantCtbData = null) -> ExpeRun:
	var av := avatar if avatar != null else _avatar(100000.0, 5000.0, 100.0)
	var r := ExpeRun.new(_cfg_carte(), _palier(), lieu, graine, av, _pool(), _cfg_combat())
	if assaut:
		r.est_assaut = true
		r.lieutenant = _lieutenant_data()
	r.demarrer()
	return r

# Plus court chemin (BFS brut, tous nœuds) de la position vers `cible`.
func _chemin_brut(run: ExpeRun, cible: int) -> Array[int]:
	var pred := {run.position_joueur: -1}
	var file: Array[int] = [run.position_joueur]
	while not file.is_empty():
		var cur: int = file.pop_front()
		if cur == cible:
			break
		for v in run.carte.noeud(cur).voisins:
			if not pred.has(v):
				pred[v] = cur
				file.append(v)
	var chemin: Array[int] = []
	var n := cible
	while n != -1 and pred.has(n):
		chemin.push_front(n)
		n = pred[n]
	chemin.pop_front()
	return chemin

# Un pas + auto-résolution du combat éventuel.
func _pas(run: ExpeRun, nid: int) -> void:
	run.deplacer_vers(nid)
	if run.combat_en_cours != null:
		run.combat_en_cours.derouler_auto()

# Marche jusqu'à la Fin/Boss de l'étage courant, combats auto-résolus.
func _aller_a_la_fin(run: ExpeRun) -> void:
	for nid in _chemin_brut(run, run.carte.fin_id):
		_pas(run, nid)
		if run.est_terminee:
			return

# Boucle une expédition complète (tous les étages).
func _boucler(run: ExpeRun) -> void:
	while not run.est_terminee:
		_aller_a_la_fin(run)
		if run.choix_ouvert:
			run.continuer()

# Premier Button du sous-arbre dont le texte contient `motif` (ou null).
func _bouton_contenant(racine: Node, motif: String) -> Button:
	for n in racine.get_children():
		if n is Button and motif in (n as Button).text:
			return n
		var trouve := _bouton_contenant(n, motif)
		if trouve != null:
			return trouve
	return null

# Un Label du sous-arbre porte-t-il exactement (ou contient-il) `texte` ?
func _contient_label(racine: Node, texte: String) -> bool:
	for n in racine.get_children():
		if n is Label and texte in (n as Label).text:
			return true
		if _contient_label(n, texte):
			return true
	return false

# Nombre de Buttons du sous-arbre dont le texte est exactement `texte`.
func _compter_boutons(racine: Node, texte: String) -> int:
	var n := 0
	for c in racine.get_children():
		if c is Button and (c as Button).text == texte:
			n += 1
		n += _compter_boutons(c, texte)
	return n

# ─── 1. Module : drop déterministe sur chaque Fin d'étage ───

func _test_module_drop_complet() -> void:
	print("[TEST 1] Raid bouclé (3 étages) → 3 Modules, crédités à la sortie")
	_reset_etat()
	var r := _run("lieu_m1", 121)
	_assert(r.config.nb_etages == 3, "précondition : 3 étages par raid")
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "raid bouclé sans défaite (précondition)")
	_assert(r.modules_accumules == 3, "3 Fin d'étage = 3 Modules accumulés (max du raid)",
			"obtenu %d" % r.modules_accumules)
	_assert(r.modules_credites == 3, "3 Modules crédités à la complétion")
	_assert(ProgressionHeros.modules() == 3, "solde joueur = 3",
			"obtenu %d" % ProgressionHeros.modules())
	var recap := r._recap(false)
	_assert(int(recap["modules_gagnes"]) == 3 and int(recap["modules_credites"]) == 3,
			"recap : modules_gagnes=3, modules_credites=3")

# ─── 2. Revisite inerte + crédit à la sortie seulement ──────

func _test_module_revisite_et_extraction() -> void:
	print("\n[TEST 2] Revisite de la Fin d'étage inerte ; crédit à l'extraction")
	_reset_etat()
	var r := _run("lieu_m2", 232)
	_aller_a_la_fin(r)
	_assert(r.choix_ouvert, "choix ouvert sur la Fin d'étage (précondition)")
	_assert(r.modules_accumules == 1, "première arrivée → 1 Module accumulé")
	_assert(ProgressionHeros.modules() == 0, "rien de crédité en cours de run")
	# Repartir sur un voisin résolu puis revenir : le nœud est inerte.
	var retour := -1
	for v in r.carte.noeud(r.position_joueur).voisins:
		if r.carte.noeud(v).resolu:
			retour = v
			break
	if retour >= 0:
		_pas(r, retour)
		_pas(r, r.carte.fin_id)
		_assert(r.modules_accumules == 1, "revisite de la Fin d'étage → toujours 1 Module",
				"obtenu %d" % r.modules_accumules)
	else:
		_fail("aucun voisin résolu pour tester la revisite (carte inattendue)")
	r.extraire()
	_assert(r.est_terminee and r.modules_credites == 1 and ProgressionHeros.modules() == 1,
			"extraction à l'étage 1 → 1 Module crédité",
			"credites %d, solde %d" % [r.modules_credites, ProgressionHeros.modules()])

# ─── 3. Défaite : Modules accumulés PERDUS ──────────────────

func _test_module_defaite() -> void:
	print("\n[TEST 3] Défaite → aucun Module crédité (accumulés perdus)")
	_reset_etat()
	var av := _avatar(100000.0, 5000.0, 100.0)
	var r := _run("lieu_m3", 343, false, av)
	_aller_a_la_fin(r)
	_assert(r.modules_accumules == 1, "étage 1 bouclé → 1 Module accumulé (précondition)")
	r.continuer()
	# L'avatar devient mourant et inoffensif : prochain combat = défaite
	# (jeté sur un nœud intérieur — 100 % Combat ; secours : marche complète).
	av.atk = 0.0
	av.vit = 1.0
	r.pv_avatar = 1.0
	for v in r.carte.noeud(r.position_joueur).voisins:
		if v != r.carte.fin_id:
			_pas(r, v)
			break
	if not r.defaite:
		_boucler(r)
	_assert(r.defaite, "défaite après l'étage 1 (précondition)")
	var recap := r._recap(false)
	_assert(int(recap["modules_gagnes"]) >= 1 and int(recap["modules_credites"]) == 0,
			"recap : ≥1 gagné, 0 crédité",
			"gagnes %d, credites %d" % [int(recap["modules_gagnes"]), int(recap["modules_credites"])])
	_assert(ProgressionHeros.modules() == 0, "solde joueur inchangé (0)",
			"obtenu %d" % ProgressionHeros.modules())

# ─── 4. Assaut : pas de Fin d'étage → 0 Module ──────────────

func _test_module_assaut() -> void:
	print("\n[TEST 4] Assaut (Boss remplace la Fin d'étage) → 0 Module")
	_reset_etat()
	var r := _run("biome_foret", 454, true)
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "assaut gagné (précondition)")
	_assert(r.modules_accumules == 0 and r.modules_credites == 0,
			"aucun Module accumulé ni crédité en assaut",
			"acc %d, cred %d" % [r.modules_accumules, r.modules_credites])
	_assert(ProgressionHeros.modules() == 0, "solde joueur = 0")

# ─── 5. Persistance : round-trip disque ─────────────────────

func _test_module_round_trip() -> void:
	print("\n[TEST 5] Modules persistés (round-trip par le vrai fichier)")
	_reset_etat()
	ProgressionHeros.crediter_modules(5)
	_assert(ProgressionHeros.modules() == 5, "5 Modules crédités (précondition)")
	SaveManager.sauvegarder_maintenant()
	_assert(FileAccess.file_exists(SAUV), "sauvegarde écrite (fichiers réels protégés)")
	GameData.player["modules"] = 0
	SaveManager.recharger()
	_assert(ProgressionHeros.modules() == 5, "Modules survivants au round-trip disque",
			"obtenu %d" % ProgressionHeros.modules())
	_reset_etat()

# ─── 6. Objet de Lieutenant au premier kill (vrai assaut) ───

func _test_objet_premier_kill() -> void:
	print("\n[TEST 6] Sceau au premier kill, pas de double au re-kill")
	_reset_etat()
	_assert(not GameData.possede_objet_lieutenant("biome_foret"), "pas d'objet au départ")
	var r := _run("biome_foret", 565, true)
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "assaut gagné (précondition)")
	_assert(GameData.possede_objet_lieutenant("biome_foret"),
			"premier kill → objet du Lieutenant obtenu")
	_assert(GameData.objets_lieutenants().size() == 1, "exactement 1 objet")
	# Re-kill : récompenses normales, pas de second objet.
	var r2 := _run("biome_foret", 676, true)
	_boucler(r2)
	_assert(r2.est_terminee and not r2.defaite, "re-assaut gagné (précondition)")
	_assert(GameData.objets_lieutenants().size() == 1, "re-kill → toujours 1 objet")

# ─── 7. Game Over : objet annulé par le rechargement ────────

func _test_objet_game_over() -> void:
	print("\n[TEST 7] Game Over d'assaut : objet gagné pendant la run annulé")
	_reset_etat()
	# Sauvegarde de RÉFÉRENCE du lancement : aucun objet.
	SaveManager.sauvegarder_maintenant()
	SaveManager.suspendre_ecritures()
	# Pendant la run : premier kill (comme le ferait la victoire de boss)...
	GameData.marquer_lieutenant_vaincu("biome_foret")
	_assert(GameData.possede_objet_lieutenant("biome_foret"), "objet accordé pendant la run")
	# ... puis run PERDUE → séquence Game Over : reprise sans flush + rechargement.
	SaveManager.reprendre_ecritures(false)
	SaveManager.recharger()
	_assert(not GameData.possede_objet_lieutenant("biome_foret"),
			"rechargement → objet annulé (mêmes rails que le slot d'Alarme)")
	_assert(GameData.objets_lieutenants().is_empty(), "aucun objet résiduel")

# ─── 8. Voies à ordre fixe (chantier 13) ────────────────────

func _test_voies_ordre_fixe() -> void:
	print("\n[TEST 8] Voies : ordre fixe 1→6, 1 Sceau libre = 1 voie, round-trip")
	_reset_etat()
	_assert(not GameData.ouvrir_voie_suivante(), "sans Sceau → ouverture refusée")
	_assert(GameData.nb_voies_ouvertes() == 0, "compteur à 0")
	# 2 Sceaux (2 Lieutenants distincts) → 2 voies ouvrables, SÉQUENTIELLEMENT.
	GameData.player["objets_lieutenants"] = {"biome_foret": true, "biome_montagne": true}
	_assert(GameData.sceaux_libres() == 2, "2 Sceaux libres")
	_assert(not GameData.atelier_ouvert(),
			"voie 2 impossible avant la voie 1 : même avec 2 Sceaux, rien n'est ouvert")
	var signaux: Array = []
	var cb := func(numero: int) -> void: signaux.append(numero)
	EventBus.voie_ouverte.connect(cb)
	_assert(GameData.ouvrir_voie_suivante(), "1er clic → une voie s'ouvre")
	_assert(signaux == [1], "c'est la voie 1 (ordre fixe — jamais la 2 d'abord)")
	_assert(GameData.atelier_ouvert(), "voie 1 = Atelier déverrouillé")
	_assert(GameData.sceaux_libres() == 1, "1 Sceau engagé, 1 libre")
	_assert(GameData.ouvrir_voie_suivante(), "2e clic → voie 2 (2e Sceau)")
	_assert(signaux == [1, 2], "ouvertures dans l'ordre 1 puis 2")
	_assert(not GameData.ouvrir_voie_suivante(), "0 Sceau libre → voie 3 refusée")
	_assert(GameData.nb_voies_ouvertes() == 2 and GameData.sceaux_libres() == 0,
			"compteur source unique = 2, plus de Sceau libre")
	_assert(GameData.voie_ouverte(1) and GameData.voie_ouverte(2)
			and not GameData.voie_ouverte(3), "voie_ouverte(n) : 1-2 oui, 3 non")
	EventBus.voie_ouverte.disconnect(cb)
	# Round-trip disque (compteur int).
	SaveManager.sauvegarder_maintenant()
	GameData.player["voies_ouvertes"] = 0
	GameData.player["objets_lieutenants"] = {}
	SaveManager.recharger()
	_assert(GameData.nb_voies_ouvertes() == 2, "voies survivantes au round-trip disque")
	_assert(GameData.nb_sceaux() == 2, "Sceaux (provenance) survivants au round-trip")
	# Migration v13 → v14 : ancien dict « voie par Lieu » → compteur.
	var v13 := {"player": {"voies_ouvertes": {"biome_foret": true, "biome_marecage": true}}}
	SaveManager._migrate_v13_to_v14(v13)
	_assert(int(v13["player"]["voies_ouvertes"]) == 2,
			"migration v13→v14 : dict de 2 voies → compteur 2")
	_reset_etat()

# ─── 9. Atelier scellé derrière la voie 1 (chantier 13) ─────

func _test_atelier_scelle() -> void:
	print("\n[TEST 9] Atelier SCELLÉ : hex absent sans voie 1, déverrouillé après")
	_reset_etat()
	var forge_def: Array = []
	var voies_min := -1
	for d: Array in Village.MENU_ITEMS:
		if d[4] == "forge":
			forge_def = d
		if d[4] == "voies":
			voies_min = int(d[2])
	_assert(not forge_def.is_empty(), "entrée FORGE au menu (précondition)")
	_assert(voies_min == 0, "hex VOIES présent dès le Village T0 (tier_min 0)")
	_assert(not Village._hex_disponible(forge_def, 5),
			"0 voie ouverte → hex FORGE ABSENT (même Village T5 — jamais grisé)")
	# Panneau : verrou propre indexé sur la voie 1 (défense en profondeur).
	var v := Village.new()
	v.rp_content = VBoxContainer.new()
	ForgePanel.build(v)
	_assert(_contient_label(v.rp_content, Translations.T("forge.scelle")),
			"panneau Forge → message de verrou (voie 1 requise)")
	v.rp_content.free()
	# Voie 1 ouverte → hex présent + panneau fonctionnel.
	GameData.player["objets_lieutenants"] = {"biome_foret": true}
	GameData.ouvrir_voie_suivante()
	_assert(Village._hex_disponible(forge_def, 0),
			"voie 1 ouverte → hex FORGE présent dès Village T0")
	v.rp_content = VBoxContainer.new()
	ForgePanel.build(v)
	_assert(not _contient_label(v.rp_content, Translations.T("forge.scelle"))
			and v.rp_content.get_child_count() > 0,
			"panneau Forge déverrouillé (contenu, plus de verrou)")
	v.rp_content.free()
	v.free()
	_reset_etat()

# ─── 10. Panneau VOIES : ordre affiché + clic « Restaurer » ─

func _test_panneau_voies() -> void:
	print("\n[TEST 10] Panneau VOIES : 6 voies ordonnées, Restaurer si Sceau libre")
	_reset_etat()
	var v := Village.new()
	v.rp_content = VBoxContainer.new()
	VoiesPanel.build(v)
	_assert(v.rp_content.get_child_count() > 0, "panneau VOIES rendu")
	_assert(GameData.NB_VOIES == 6, "6 voies (une par Lieutenant)")
	_assert(_bouton_contenant(v.rp_content, Translations.T("voies.restaurer_btn")) == null,
			"sans Sceau libre : aucun bouton Restaurer")
	_assert(_contient_label(v.rp_content, Translations.T("voies.nom_atelier")),
			"la voie 1 est nommée Atelier (Forge)")
	v.rp_content.free()

	GameData.player["objets_lieutenants"] = {"biome_foret": true}
	v.rp_content = VBoxContainer.new()
	VoiesPanel.build(v)
	var btn := _bouton_contenant(v.rp_content, Translations.T("voies.restaurer_btn"))
	_assert(btn != null, "avec 1 Sceau libre : bouton Restaurer présent (prêt → clic)")
	if btn != null:
		btn.pressed.emit()
		_assert(GameData.nb_voies_ouvertes() == 1 and GameData.atelier_ouvert(),
				"clic → voie 1 ouverte (Atelier)")
	v.rp_content.free()
	# Re-rendu : la voie 1 restaurée, plus de bouton (0 Sceau libre), voie 2 en attente.
	v.rp_content = VBoxContainer.new()
	VoiesPanel.build(v)
	_assert(_contient_label(v.rp_content, Translations.T("voies.atelier_restaure")),
			"re-rendu : Atelier affiché restauré")
	_assert(_bouton_contenant(v.rp_content, Translations.T("voies.restaurer_btn")) == null,
			"0 Sceau libre restant → plus de bouton Restaurer")
	v.rp_content.free()
	v.free()
	_reset_etat()

# ─── 11. Panneau Expéditions : Évoluer biomes absent ────────

func _test_panneau_expeditions() -> void:
	print("\n[TEST 11] Expéditions : Évoluer biomes ABSENT, Évoluer créatures OK")
	_reset_etat()
	var evolve_txt := Translations.T("btn.evolve")
	var biome := GameData.get_entity("biome_foret")
	var tier_avant := int(biome.get("maitrise_actuelle", 0))
	var xp_avant := float(biome.get("xp_maitrise_actuelle", 0.0))

	# Biome gorgé d'XP : il serait « prêt à évoluer » — aucun bouton ne doit
	# pourtant apparaître (les Lieux n'évoluent plus, décision actée).
	biome["maitrise_actuelle"] = 0
	biome["xp_maitrise_actuelle"] = 1000000.0
	_assert(MasterySystem.can_evolve("biome_foret"),
			"précondition : le biome aurait pu évoluer (XP suffisante)")
	var v := Village.new()
	v.rp_content = VBoxContainer.new()
	AdventurePanel.build(v)
	_assert(_compter_boutons(v.rp_content, evolve_txt) == 0,
			"biome prêt → AUCUN bouton Évoluer (Évoluer biomes supprimé)")
	v.rp_content.free()

	# Créature découverte et gorgée d'XP (plafond relevé par le biome T4) :
	# son bouton Évoluer, lui, doit être là.
	biome["maitrise_actuelle"] = 4
	var pools: Dictionary = MasteryRegistry.get_biome_entity_pools("biome_foret")
	var cid := str((pools["creatures"] as Array)[0].get("id", ""))
	_assert(cid != "", "précondition : une créature au pool de la Forêt")
	var creature := GameData.get_entity(cid)
	var c_tier_avant := int(creature.get("maitrise_actuelle", 0))
	var c_xp_avant := float(creature.get("xp_maitrise_actuelle", 0.0))
	var etait_connue: bool = GameData.player["bestiary"].has(cid)
	if not etait_connue:
		GameData.player["bestiary"][cid] = {"name": cid, "type": "creature",
				"biome_id": "biome_foret", "biome_name": "", "count": 1, "xp": 0.0, "tier": 0}
	creature["xp_maitrise_actuelle"] = 1000000.0
	_assert(MasterySystem.can_evolve(cid), "précondition : la créature peut évoluer")
	v.rp_content = VBoxContainer.new()
	AdventurePanel.build(v)
	_assert(_compter_boutons(v.rp_content, evolve_txt) >= 1,
			"créature prête → bouton Évoluer présent (fonctionnel)")
	v.rp_content.free()
	v.free()

	# Remise en état (entités partagées entre suites).
	biome["maitrise_actuelle"] = tier_avant
	biome["xp_maitrise_actuelle"] = xp_avant
	creature["maitrise_actuelle"] = c_tier_avant
	creature["xp_maitrise_actuelle"] = c_xp_avant
	if not etait_connue:
		GameData.player["bestiary"].erase(cid)

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
