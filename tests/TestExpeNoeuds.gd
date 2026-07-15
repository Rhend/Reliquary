extends Node
# Tests des NŒUDS RÉELS d'expédition (Rework Combat — chantier 7) :
# Bénédiction = affixe positif de run, Piège = affixe négatif, Coffre =
# consommables de run. Vérifie :
#   • affixe appliqué au combat SUIVANT son acquisition (deltas % exacts sur
#     le combattant CTB), cumul additif de deux affixes identiques ;
#   • Bénédiction obtenue / Piège subi via de VRAIS nœuds (« ? » forcé) ;
#   • PV courants conservés en absolu, clampés si le pv_max effectif descend ;
#   • Coffre crédite l'inventaire (pondération 1-2, cap = excédent perdu) ;
#   • consommer() décrémente et trace ; purge en fin de run (extraction,
#     défaite, complétion) ; recap étendu (affixes, consommables_*) ;
#   • payloads noeud_resolu enrichis ("contenu").
# Ne charge JAMAIS la sauvegarde ; déclencheurs de sauvegarde déconnectés.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST NŒUDS RÉELS (AFFIXES + CONSOMMABLES) ===\n")
	_test_affixe_au_combat_suivant()
	_test_cumul_additif_double()
	_test_benediction_et_piege_reels()
	_test_clamp_pv_max()
	_test_coffre_et_cap()
	_test_consommer()
	_test_purge_toutes_sorties()
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

func _affixe(id: String, positif: bool, bonus: Dictionary) -> AffixeData:
	var a := AffixeData.new()
	a.id = id
	a.nom_affichage_fr = id
	a.est_positif = positif
	a.bonus = bonus
	return a

func _conso(id: String, effet: Enums.EffetConsommable, valeur: float) -> ConsommableData:
	var c := ConsommableData.new()
	c.id = id
	c.nom_affichage_fr = id
	c.effet = effet
	c.valeur = valeur
	return c

func _cfg_noeuds(pos: Array, neg: Array, pool: Array,
		poids: Dictionary = {1: 1.0}, cap := 0) -> ExpeNoeudsConfigData:
	var cfg := ExpeNoeudsConfigData.new()
	cfg.affixes_positifs.assign(pos)
	cfg.affixes_negatifs.assign(neg)
	cfg.pool_consommables.assign(pool)
	cfg.poids_nb_consommables = poids
	cfg.cap_inventaire = cap
	return cfg

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

# Config carte : poids des types + contenu forcé des « ? ».
func _cfg_carte(combat: float, mystere: float, coffre: float,
		m_bene := 0.0, m_piege := 0.0) -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = combat
	c.poids_mystere = mystere
	c.poids_coffre = coffre
	c.mystere_poids_coffre = 0.0
	c.mystere_poids_benediction = m_bene
	c.mystere_poids_piege = m_piege
	c.mystere_poids_attaque_surprise = 0.0
	return c

func _run(cfg: ExpeCarteConfigData, graine: int, avatar: CombattantCtbData,
		noeuds: ExpeNoeudsConfigData = null) -> ExpeRun:
	var r := ExpeRun.new(cfg, load("res://data/expedition/palier_enceinte.tres"),
			"lieu_test", graine, avatar,
			load("res://data/expedition/pool_defaut.tres"),
			load("res://data/expedition/config_combat.tres"))
	if noeuds != null:
		r.cfg_noeuds = noeuds
	r.demarrer()
	return r

func _pas(run: ExpeRun, nid: int) -> bool:
	var ok := run.deplacer_vers(nid)
	if run.combat_en_cours != null:
		run.combat_en_cours.derouler_auto()
	return ok

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
	chemin.pop_front()
	return chemin

func _marcher_vers_fin(run: ExpeRun) -> void:
	for nid in _chemin_vers(run, run.carte.fin_id):
		if run.est_terminee:
			return
		_pas(run, nid)

# Avance jusqu'au premier combat résolu (étages suivants si besoin).
func _jusqu_au_premier_combat(run: ExpeRun) -> void:
	var garde := 0
	while run.nb_combats == 0 and not run.est_terminee and garde < 10:
		garde += 1
		_marcher_vers_fin(run)
		if run.choix_ouvert:
			run.continuer()

# ─── Affixes : application au combat ────────────────────────

# Un affixe acquis AVANT un combat compte dans le combattant CTB créé pour
# ce combat : stat_finale = nue × (1 + fraction) — delta % exact.
func _test_affixe_au_combat_suivant() -> void:
	print("[TEST] Affixe — appliqué au combattant du combat suivant")
	var run := _run(_cfg_carte(1.0, 0.0, 0.0), 4242, _avatar(100000.0, 200.0, 60.0))
	run.ajouter_affixe(_affixe("test_surtension", true, {"atk": 0.15}))
	run.ajouter_affixe(_affixe("test_servos", false, {"vit": -0.08}))
	var moteurs: Array = []
	run.combat_demarre.connect(func(m: CtbMoteur, _d: Dictionary) -> void:
		moteurs.append(m))
	_jusqu_au_premier_combat(run)
	_assert(moteurs.size() >= 1, "un combat a été créé")
	var av: CtbCombattant = (moteurs[0] as CtbMoteur).avatar()
	_assert(absf(av.stat_finale("atk") - 200.0 * 1.15) < 0.001,
			"ATK finale = 200 × 1.15 = 230 (affixe +15 %)",
			"atk=%.2f" % av.stat_finale("atk"))
	_assert(absf(av.stat_finale("vit") - 60.0 * 0.92) < 0.001,
			"VIT finale = 60 × 0.92 = 55.2 (affixe −8 %, positif et négatif coexistent)",
			"vit=%.2f" % av.stat_finale("vit"))

# Le même affixe tiré deux fois s'additionne : × (1 + 0.15 + 0.15) = × 1.30
# (empilement ADDITIF universel — pas 1.15² = 1.3225).
func _test_cumul_additif_double() -> void:
	print("\n[TEST] Affixe — cumul additif de deux affixes identiques")
	var run := _run(_cfg_carte(1.0, 0.0, 0.0), 777, _avatar(100000.0, 200.0, 60.0))
	var a := _affixe("test_surtension", true, {"atk": 0.15})
	run.ajouter_affixe(a)
	run.ajouter_affixe(a)
	var moteurs: Array = []
	run.combat_demarre.connect(func(m: CtbMoteur, _d: Dictionary) -> void:
		moteurs.append(m))
	_jusqu_au_premier_combat(run)
	var av: CtbCombattant = (moteurs[0] as CtbMoteur).avatar()
	_assert(absf(av.stat_finale("atk") - 260.0) < 0.001,
			"deux fois +15 % : 200 × 1.30 = 260 (additif, pas 1.15²)",
			"atk=%.2f" % av.stat_finale("atk"))

# ─── Bénédiction / Piège via de vrais nœuds « ? » ───────────

func _test_benediction_et_piege_reels() -> void:
	print("\n[TEST] Nœuds réels — Bénédiction obtenue, Piège subi")
	var pos := _affixe("bene_test", true, {"atk": 0.15})
	var neg := _affixe("piege_test", false, {"def": -0.10})
	# Carte 100 % « ? », tous résolus en BÉNÉDICTION.
	var run := _run(_cfg_carte(0.0, 1.0, 0.0, 1.0, 0.0), 31337,
			_avatar(1000.0, 10.0, 20.0), _cfg_noeuds([pos], [neg], []))
	var payloads: Array = []
	run.noeud_resolu.connect(func(d: Dictionary) -> void:
		if d.has("contenu"):
			payloads.append(d["contenu"]))
	var premier: int = run.carte.noeud(run.carte.entree_id).voisins[0]
	_pas(run, premier)
	if run.carte.noeud(premier).type == Enums.TypeNoeud.FIN_ETAGE:
		_pas(run, run.carte.noeud(premier).voisins[0])   # éviter la Fin adjacente
	_assert(run.affixes.size() == 1 and run.affixes[0].id == "bene_test",
			"Bénédiction : affixe positif du pool actif jusqu'à la fin de run")
	_assert(payloads.size() == 1 and bool(payloads[0]["positif"])
			and str(payloads[0]["affixe_id"]) == "bene_test",
			"payload noeud_resolu enrichi : contenu.affixe_id + positif", str(payloads))
	# Carte 100 % « ? » PIÈGE.
	var run2 := _run(_cfg_carte(0.0, 1.0, 0.0, 0.0, 1.0), 31338,
			_avatar(1000.0, 10.0, 20.0), _cfg_noeuds([pos], [neg], []))
	var premier2: int = run2.carte.noeud(run2.carte.entree_id).voisins[0]
	_pas(run2, premier2)
	if run2.carte.noeud(premier2).type == Enums.TypeNoeud.FIN_ETAGE:
		_pas(run2, run2.carte.noeud(premier2).voisins[0])
	_assert(run2.affixes.size() == 1 and run2.affixes[0].id == "piege_test"
			and not run2.affixes[0].est_positif,
			"Piège : affixe négatif du pool SUBI (aucun choix)")

# ─── PV max modifié en cours de run ─────────────────────────

func _test_clamp_pv_max() -> void:
	print("\n[TEST] PV — conservés en absolu, clampés si le pv_max descend")
	var run := _run(_cfg_carte(1.0, 0.0, 0.0), 55, _avatar(100.0, 10.0, 20.0))
	_assert(absf(run.pv_avatar - 100.0) < 0.001, "départ : PV pleins (100)")
	run.ajouter_affixe(_affixe("chassis_test", true, {"pv_max": 0.10}))
	_assert(absf(run.pv_avatar - 100.0) < 0.001
			and absf(run.pv_max_effectif() - 110.0) < 0.001,
			"pv_max monte (110) : PV courants conservés en ABSOLU (100, pas de soin)")
	run.ajouter_affixe(_affixe("fuite_test", false, {"pv_max": -0.30}))
	_assert(absf(run.pv_max_effectif() - 80.0) < 0.001,
			"pv_max effectif : 100 × (1 + 0.10 − 0.30) = 80 (additif)")
	_assert(absf(run.pv_avatar - 80.0) < 0.001,
			"PV clampés au nouveau pv_max : 100 → 80", "pv=%.1f" % run.pv_avatar)

# ─── Coffre : inventaire + cap ──────────────────────────────

func _test_coffre_et_cap() -> void:
	print("\n[TEST] Coffre — crédite l'inventaire, cap = excédent perdu")
	var bombe := _conso("bombe_test", Enums.EffetConsommable.DEGATS_CIBLE, 50.0)
	# Carte 100 % Coffre, toujours 2 consommables.
	var run := _run(_cfg_carte(0.0, 0.0, 1.0), 2024, _avatar(1000.0, 10.0, 20.0),
			_cfg_noeuds([], [], [bombe], {2: 1.0}))
	var payloads: Array = []
	run.noeud_resolu.connect(func(d: Dictionary) -> void:
		if d.has("contenu"):
			payloads.append(d["contenu"]))
	var premier: int = run.carte.noeud(run.carte.entree_id).voisins[0]
	_pas(run, premier)
	if run.carte.noeud(premier).type == Enums.TypeNoeud.FIN_ETAGE:
		_pas(run, run.carte.noeud(premier).voisins[0])
	_assert(run.inventaire.size() == 2, "Coffre (poids {2: 1}) : 2 consommables en inventaire",
			"inv=%d" % run.inventaire.size())
	_assert(payloads.size() == 1
			and (payloads[0]["consommable_ids"] as Array).size() == 2,
			"payload noeud_resolu : contenu.consommable_ids (2 ids)")
	# Cap 1 : le 2e tirage du coffre est PERDU.
	var run2 := _run(_cfg_carte(0.0, 0.0, 1.0), 2025, _avatar(1000.0, 10.0, 20.0),
			_cfg_noeuds([], [], [bombe], {2: 1.0}, 1))
	var premier2: int = run2.carte.noeud(run2.carte.entree_id).voisins[0]
	_pas(run2, premier2)
	if run2.carte.noeud(premier2).type == Enums.TypeNoeud.FIN_ETAGE:
		_pas(run2, run2.carte.noeud(premier2).voisins[0])
	_assert(run2.inventaire.size() == 1,
			"cap_inventaire = 1 : un seul gardé, l'excédent est perdu (journalisé)",
			"inv=%d" % run2.inventaire.size())

# ─── consommer() ────────────────────────────────────────────

func _test_consommer() -> void:
	print("\n[TEST] consommer — décrémente l'inventaire et trace l'usage")
	var bombe := _conso("bombe_test", Enums.EffetConsommable.DEGATS_CIBLE, 50.0)
	var run := _run(_cfg_carte(1.0, 0.0, 0.0), 7, _avatar(1000.0, 10.0, 20.0))
	run.inventaire.append(bombe)
	run.inventaire.append(bombe)
	_assert(run.consommer(bombe), "consommer() retire une occurrence (true)")
	_assert(run.inventaire.size() == 1, "il en reste une (les doublons sont distincts)")
	var autre := _conso("inconnu", Enums.EffetConsommable.DEGATS_CIBLE, 1.0)
	_assert(not run.consommer(autre), "objet absent de l'inventaire → false")
	var recap := run._recap(false)
	_assert((recap["consommables_utilises"] as Array) == ["bombe_test"],
			"recap : consommables_utilises trace l'usage", str(recap["consommables_utilises"]))

# ─── Purge en fin de run (toutes sorties) ───────────────────

func _test_purge_toutes_sorties() -> void:
	print("\n[TEST] Purge — extraction, défaite, complétion : rien ne persiste")
	var a := _affixe("affixe_purge", true, {"atk": 0.15})
	var bombe := _conso("bombe_purge", Enums.EffetConsommable.DEGATS_CIBLE, 50.0)
	# Extraction (carte sans combat).
	var run := _run(_cfg_carte(0.0, 0.0, 1.0), 111, _avatar(1000.0, 10.0, 20.0),
			_cfg_noeuds([], [], []))
	run.ajouter_affixe(a)
	run.inventaire.append(bombe)
	run._conso_obtenus.append(bombe)
	var recaps: Array = []
	run.terminee.connect(func(r: Dictionary) -> void: recaps.append(r))
	_marcher_vers_fin(run)
	run.extraire()
	_assert(recaps.size() == 1 and (recaps[0]["affixes"] as Array) == ["affixe_purge"]
			and (recaps[0]["consommables_obtenus"] as Array) == ["bombe_purge"],
			"recap d'extraction : affixes actifs + consommables_obtenus (ids)")
	_assert(run.affixes.is_empty() and run.inventaire.is_empty(),
			"extraction : affixes ET inventaire purgés (les consommables sont « de run »)")
	# Défaite (combat perdu d'entrée).
	var run2 := _run(_cfg_carte(1.0, 0.0, 0.0), 222, _avatar(1.0, 1.0, 1.0))
	run2.ajouter_affixe(a)
	run2.inventaire.append(bombe)
	_jusqu_au_premier_combat(run2)
	_assert(run2.est_terminee and run2.defaite, "la run se termine en défaite")
	_assert(run2.affixes.is_empty() and run2.inventaire.is_empty(),
			"défaite : purge aussi (toutes les sorties)")
	# Complétion (3 étages sans combat).
	var run3 := _run(_cfg_carte(0.0, 0.0, 1.0), 333, _avatar(1000.0, 10.0, 20.0),
			_cfg_noeuds([], [], []))
	run3.ajouter_affixe(a)
	var garde := 0
	while not run3.est_terminee and garde < 10:
		garde += 1
		_marcher_vers_fin(run3)
		if run3.choix_ouvert:
			run3.continuer()
	_assert(run3.est_terminee and not run3.defaite, "expédition bouclée (complétion)")
	_assert(run3.affixes.is_empty(), "complétion : purge aussi")

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ nœuds réels conformes")
	print("════════════════════════════════\n")
