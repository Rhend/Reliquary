extends Node
# Tests de la carte d'expédition (Rework Combat — chantier 2).
# Génération (connexité, bornes, proportions statistiques, reproductibilité),
# brouillard (Fin visible d'emblée, non-découverts absents, révélation par
# adjacence, « ? » tiré à l'entrée), navigation (retour arrière, inertie),
# enchaînement des étages (Extraire / Continuer, fin au dernier étage),
# circulation du palier de profondeur.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TEST CARTE D'EXPÉDITION ===\n")
	_test_connexite()
	_test_bornes_nb_noeuds()
	_test_proportions_types()
	_test_proportions_mystere()
	_test_reproductibilite()
	_test_brouillard_initial()
	_test_revelation_adjacence()
	_test_mystere_tire_a_l_entree()
	_test_retour_arriere_et_inertie()
	_test_extraction()
	_test_trois_etages()
	_test_choix_rouvert()
	_test_palier_circule()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

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

func _config() -> ExpeCarteConfigData:
	return load("res://data/expedition/config_carte.tres")

func _palier() -> PalierProfondeurData:
	return load("res://data/expedition/palier_enceinte.tres")   # ×1.5 (non trivial)

func _rng(graine: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = graine
	return r

# Avatar SURPUISSANT : les combats (réels depuis le chantier 3) se gagnent
# toujours — cette suite teste la CARTE, pas le combat (cf. TestExpeCombat).
func _avatar_costaud() -> CombattantCtbData:
	var a := CombattantCtbData.new()
	a.id = "avatar_test"
	a.nom_affichage_fr = "Avatar de test"
	a.pv_max = 1000000.0
	a.atk = 1000000.0
	a.def = 0.0
	a.vit = 50.0
	a.crit_chance = 0.0
	return a

func _run(graine: int) -> ExpeRun:
	var r := ExpeRun.new(_config(), _palier(), "lieu_test", graine,
			_avatar_costaud(), load("res://data/expedition/pool_defaut.tres"),
			load("res://data/expedition/config_combat.tres"))
	r.demarrer()
	return r

# Un pas de navigation + auto-résolution du combat éventuel (la run est
# suspendue sur un nœud Combat / Attaque surprise tant qu'il n'est pas joué).
func _pas(run: ExpeRun, nid: int) -> bool:
	var ok := run.deplacer_vers(nid)
	if run.combat_en_cours != null:
		run.combat_en_cours.derouler_auto()
	return ok

# Plus court chemin (BFS) de la position du joueur vers `cible` — le test
# connaît tout le graphe, le joueur avance ensuite nœud par nœud.
func _chemin_vers(run: ExpeRun, cible: int) -> Array[int]:
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
	chemin.pop_front()   # retire la position de départ
	return chemin

func _marcher_vers_fin(run: ExpeRun) -> void:
	for pas in _chemin_vers(run, run.carte.fin_id):
		_pas(run, pas)

# ─── Génération ─────────────────────────────────────────────

func _test_connexite() -> void:
	print("[TEST] Connexité du graphe (100 graines)")
	var ok := true
	for g in range(1, 101):
		var carte := ExpeCarte.generer(_config(), _rng(g))
		if not carte.est_connexe():
			ok = false
			_fail("graphe non connexe", "graine %d" % g)
			break
	if ok:
		_ok("100 générations : tout nœud atteignable depuis l'entrée")

func _test_bornes_nb_noeuds() -> void:
	print("\n[TEST] Bornes du nombre de nœuds")
	var cfg := _config()
	var ok := true
	for g in range(1, 101):
		var n := ExpeCarte.generer(cfg, _rng(g)).noeuds.size()
		if n < cfg.noeuds_min or n > cfg.noeuds_max:
			ok = false
			_fail("N hors bornes", "graine %d : %d ∉ [%d;%d]" % [g, n, cfg.noeuds_min, cfg.noeuds_max])
			break
	if ok:
		_ok("100 générations : N ∈ [%d;%d]" % [cfg.noeuds_min, cfg.noeuds_max])

# Proportions des nœuds intérieurs sur 300 générations (tolérance ±5 points).
func _test_proportions_types() -> void:
	print("\n[TEST] Proportions des types (300 générations, ±5 pts)")
	var cfg := _config()
	var compte := {Enums.TypeNoeud.COMBAT: 0, Enums.TypeNoeud.MYSTERE: 0, Enums.TypeNoeud.COFFRE: 0}
	var total := 0
	for g in range(1, 301):
		for nd in ExpeCarte.generer(cfg, _rng(g)).noeuds:
			if compte.has(nd.type):
				compte[nd.type] += 1
				total += 1
	var attendus := {
		Enums.TypeNoeud.COMBAT:  cfg.poids_combat,
		Enums.TypeNoeud.MYSTERE: cfg.poids_mystere,
		Enums.TypeNoeud.COFFRE:  cfg.poids_coffre,
	}
	for t: int in attendus:
		var obtenu := float(compte[t]) / float(total)
		_assert(absf(obtenu - float(attendus[t])) < 0.05,
				"type %d : %.1f %% (attendu %.0f %%)" % [t, obtenu * 100.0, attendus[t] * 100.0])

# Proportions du contenu « ? » (4000 tirages, tolérance ±5 points).
func _test_proportions_mystere() -> void:
	print("\n[TEST] Proportions du « ? » (4000 tirages, ±5 pts)")
	var run := _run(42)
	var compte := {}
	for i in 4000:
		var c: int = run._tirer_mystere()
		compte[c] = int(compte.get(c, 0)) + 1
	for c in [Enums.ContenuMystere.COFFRE, Enums.ContenuMystere.BENEDICTION,
			Enums.ContenuMystere.PIEGE, Enums.ContenuMystere.ATTAQUE_SURPRISE]:
		var obtenu := float(compte.get(c, 0)) / 4000.0
		_assert(absf(obtenu - 0.25) < 0.05, "contenu %d : %.1f %% (attendu 25 %%)" % [c, obtenu * 100.0])

func _test_reproductibilite() -> void:
	print("\n[TEST] Reproductibilité par graine")
	var a := ExpeCarte.generer(_config(), _rng(1337)).empreinte()
	var b := ExpeCarte.generer(_config(), _rng(1337)).empreinte()
	var c := ExpeCarte.generer(_config(), _rng(7331)).empreinte()
	_assert(a == b, "même graine → carte identique (positions, types, arêtes)")
	_assert(a != c, "graine différente → carte différente")

# ─── Brouillard ─────────────────────────────────────────────

func _test_brouillard_initial() -> void:
	print("\n[TEST] Brouillard à l'initialisation de l'étage")
	var run := _run(1337)
	var carte := run.carte
	_assert(carte.noeud(carte.fin_id).decouvert, "Fin d'étage VISIBLE dès le début (type inclus)")
	_assert(carte.noeud(carte.entree_id).decouvert, "Entrée découverte (position du joueur)")
	var attendus := {carte.entree_id: true, carte.fin_id: true}
	for v in carte.noeud(carte.entree_id).voisins:
		attendus[v] = true
	var ok := true
	for nd in carte.noeuds:
		if nd.decouvert != attendus.has(nd.id):
			ok = false
			_fail("brouillard incohérent", "nœud %d : decouvert=%s" % [nd.id, str(nd.decouvert)])
			break
	if ok:
		_ok("seuls Entrée + voisins + Fin sont découverts, TOUT le reste est absent")

func _test_revelation_adjacence() -> void:
	print("\n[TEST] Révélation par adjacence")
	var run := _run(1337)
	var premier: int = run.carte.noeud(run.carte.entree_id).voisins[0]
	_pas(run, premier)
	var ok := true
	for v in run.carte.noeud(premier).voisins:
		if not run.carte.noeud(v).decouvert:
			ok = false
			break
	_assert(ok, "arriver sur un nœud révèle tous ses voisins directs")

func _test_mystere_tire_a_l_entree() -> void:
	print("\n[TEST] « ? » : contenu tiré à l'ENTRÉE seulement")
	# Cherche une graine dont l'étage 1 contient un Mystère atteignable.
	for g in range(1, 60):
		var run := _run(g)
		var cible := -1
		for nd in run.carte.noeuds:
			if nd.type == Enums.TypeNoeud.MYSTERE:
				cible = nd.id
				break
		if cible < 0:
			continue
		var nd := run.carte.noeud(cible)
		_assert(nd.contenu_mystere == -1, "avant l'entrée : contenu_mystere = -1 (rien à révéler)")
		for pas in _chemin_vers(run, cible):
			_pas(run, pas)
		_assert(nd.contenu_mystere >= 0 and nd.contenu_mystere <= 3,
				"après l'entrée : contenu résolu (%d)" % nd.contenu_mystere)
		return
	_fail("aucune graine avec un Mystère en 60 essais (improbable)")

# ─── Navigation ─────────────────────────────────────────────

func _test_retour_arriere_et_inertie() -> void:
	print("\n[TEST] Retour en arrière + inertie des nœuds résolus")
	var run := _run(1337)
	var signaux := [0]
	run.noeud_resolu.connect(func(_d: Dictionary) -> void: signaux[0] += 1)
	var entree := run.carte.entree_id
	var premier: int = run.carte.noeud(entree).voisins[0]
	_assert(_pas(run, premier), "déplacement vers un voisin accepté")
	var apres_premier: int = signaux[0]
	_assert(apres_premier == 1, "1re entrée : résolution émise")
	_assert(_pas(run, entree), "RETOUR EN ARRIÈRE autorisé")
	_assert(_pas(run, premier), "re-traversée du nœud résolu autorisée (inerte)")
	_assert(signaux[0] == apres_premier, "aucune re-résolution à la re-traversée")
	# Déplacement illégal : nœud non adjacent.
	var lointain := -1
	for nd in run.carte.noeuds:
		if nd.id != run.position_joueur and not nd.id in run.carte.noeud(run.position_joueur).voisins:
			lointain = nd.id
			break
	if lointain >= 0:
		_assert(not _pas(run, lointain), "déplacement non adjacent refusé")

# ─── Étages & fins ──────────────────────────────────────────

func _test_extraction() -> void:
	print("\n[TEST] Extraire à la fin de l'étage 1")
	var run := _run(1337)
	var recaps := []
	run.terminee.connect(func(r: Dictionary) -> void: recaps.append(r))
	_marcher_vers_fin(run)
	_assert(run.choix_ouvert, "arrivée sur la Fin d'étage : choix ouvert")
	_assert(not run.est_terminee, "l'expédition n'est pas finie (étage 1/3)")
	run.extraire()
	_assert(run.est_terminee and recaps.size() == 1, "Extraire → expédition terminée, recap émis")
	if recaps.size() == 1:
		_assert(recaps[0]["extraction"] and not recaps[0]["complete"] \
				and recaps[0]["etage_atteint"] == 1,
				"recap : extraction=true, complete=false, etage_atteint=1")

func _test_trois_etages() -> void:
	print("\n[TEST] Enchaînement des 3 étages (Continuer ×2, fin au 3e)")
	var run := _run(4242)
	var fins := []
	var recaps := []
	var bus_recaps := []
	run.etage_termine.connect(func(d: Dictionary) -> void: fins.append(d["etage"]))
	run.terminee.connect(func(r: Dictionary) -> void: recaps.append(r))
	var cb := func(r: Dictionary) -> void: bus_recaps.append(r)
	EventBus.expe_terminee.connect(cb)
	_marcher_vers_fin(run)
	run.continuer()
	_assert(run.etage == 2, "Continuer → étage 2 (nouvelle carte générée)")
	_marcher_vers_fin(run)
	run.continuer()
	_assert(run.etage == 3, "Continuer → étage 3")
	_marcher_vers_fin(run)
	EventBus.expe_terminee.disconnect(cb)
	_assert(fins == [1, 2, 3], "etage_termine émis aux 3 fins d'étage", str(fins))
	_assert(run.est_terminee and recaps.size() == 1,
			"Fin d'étage du 3e = fin d'expédition immédiate (pas de choix)")
	_assert(bus_recaps.size() == 1, "EventBus.expe_terminee émis")
	if recaps.size() == 1:
		_assert(recaps[0]["complete"] and not recaps[0]["extraction"] \
				and recaps[0]["etage_atteint"] == 3,
				"recap : complete=true, extraction=false, etage_atteint=3")

func _test_choix_rouvert() -> void:
	print("\n[TEST] Choix refermé en repartant, rouvert au retour (free-roam)")
	var run := _run(1337)
	var signaux := [0]
	run.noeud_resolu.connect(func(_d: Dictionary) -> void: signaux[0] += 1)
	_marcher_vers_fin(run)
	var avant: int = signaux[0]
	var voisin: int = run.carte.noeud(run.carte.fin_id).voisins[0]
	_pas(run, voisin)
	_assert(not run.choix_ouvert, "repartir explorer referme le choix")
	_pas(run, run.carte.fin_id)
	_assert(run.choix_ouvert, "revenir sur la Fin rouvre le choix")
	# La Fin est inerte : revenir dessus n'émet PAS de re-résolution (le retour
	# a pu résoudre le voisin lui-même, on ne compte que la Fin).
	_assert(signaux[0] <= avant + 1, "pas de re-résolution de la Fin d'étage")

func _test_palier_circule() -> void:
	print("\n[TEST] Palier de profondeur : le multiplicateur circule")
	var run := _run(1337)
	var payloads := []
	run.noeud_resolu.connect(func(d: Dictionary) -> void: payloads.append(d))
	_pas(run, run.carte.noeud(run.carte.entree_id).voisins[0])
	_assert(payloads.size() == 1, "signal noeud_resolu émis")
	if payloads.size() == 1:
		var d: Dictionary = payloads[0]
		_assert(d["palier_id"] == "palier_enceinte" and absf(float(d["multiplicateur"]) - 1.5) < 0.001,
				"payload : palier_id + multiplicateur (×1.5) présents")
		_assert(d["lieu_id"] == "lieu_test" and d["etage"] == 1 and d.has("type"),
				"payload : lieu_id / etage / type présents")

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ carte d'expédition conforme")
	print("════════════════════════════════\n")
