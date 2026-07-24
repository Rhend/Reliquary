extends Node
# ============================================================
# TestButin — Butin de matériaux d'expédition (chantier 14).
#
# Couvre : tirage par victoire (fréquente + rare du biome du Lieu, bornes et
# chances PAR PALIER), hors-bestiaire et Lieu sans biome → rien, coffre
# (paquet fréquent), boss d'assaut (rare GARANTIE à chaque kill),
# accumulation ≠ crédit (sortie seulement — défaite = rien), recap et
# dernier_combat_recompenses. Configs FORCÉES (min = max, chances 0/1) →
# assertions exactes, pas de flottant statistique.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

var _fail: Array[String] = []
var _nb_ok := 0

func _ready() -> void:
	# JAMAIS d'écriture de sauvegarde dans un test (règle projet).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST BUTIN D'EXPÉDITION (chantier 14) ===\n")
	_test_tirage_victoire()
	_test_gates_et_absents()
	_test_credit_sortie()
	_test_defaite_sans_credit()
	_test_coffre()
	_test_boss_assaut()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── 1. Tirage par victoire ──────────────────────────────────

func _test_tirage_victoire() -> void:
	print("[1] Tirage par victoire : fréquente (bornes du palier) + rare (chance)")
	var run := _run("biome_foret", 11, _butin_exact(2, 1.0))
	var vaincus: Array = [_du_bestiaire("creature_foret_surface")]
	var b := run._butin_pour_victoire(vaincus)
	_check("fréquente : 2 (bornes 2-2)", int(b.get("res_fourrure", 0)) == 2)
	_check("rare : 1 (chance 100 %)", int(b.get("res_venin", 0)) == 1)
	var b2 := run._butin_pour_victoire([_du_bestiaire("creature_foret_surface"),
			_du_bestiaire("creature_marecage_surface")])
	_check("2 vaincus → fréquente ×2 (4)", int(b2.get("res_fourrure", 0)) == 4)
	_check("2 vaincus → rare ×2", int(b2.get("res_venin", 0)) == 2)
	var run0 := _run("biome_foret", 11, _butin_exact(3, 0.0))
	var b0 := run0._butin_pour_victoire(vaincus)
	_check("chance rare 0 → fréquente seule", int(b0.get("res_fourrure", 0)) == 3
			and not b0.has("res_venin"))

func _test_gates_et_absents() -> void:
	print("\n[2] Gates : hors-bestiaire, Lieu sans biome, palier sans entrée")
	var run := _run("biome_foret", 12, _butin_exact(2, 1.0))
	var fantome := CombattantCtbData.new()
	fantome.id = "hors_bestiaire_xyz"
	_check("vaincu hors bestiaire → rien", run._butin_pour_victoire([fantome]).is_empty())
	var run_sans := _run("lieu_test", 12, _butin_exact(2, 1.0))
	_check("Lieu sans biome → rien",
			run_sans._butin_pour_victoire([_du_bestiaire("creature_foret_surface")]).is_empty())
	var cfg_vide := ButinConfigData.new()
	cfg_vide.qte_frequente_par_palier = {}
	cfg_vide.chance_rare_par_palier = {}
	var run_vide := _run("biome_foret", 12, cfg_vide)
	_check("palier absent de la config → rien",
			run_vide._butin_pour_victoire([_du_bestiaire("creature_foret_surface")]).is_empty())

# ─── 3. Accumulation ≠ crédit (sortie seulement) ─────────────

func _test_credit_sortie() -> void:
	print("\n[3] Accumulé pendant la run, crédité à l'EXTRACTION seulement")
	var avant := _solde("res_fourrure")
	var run := _run("biome_foret", 4242, _butin_exact(2, 0.0), 100000.0)
	_jusqua_choix(run)
	_check("des combats ont été gagnés", run.nb_combats > 0 and not run.defaite)
	var accumule := int(run.butin_accumule.get("res_fourrure", 0))
	_check("butin accumulé pendant la run", accumule > 0)
	_check("dernier_combat_recompenses porte le butin",
			not (run.dernier_combat_recompenses.get("butin", {}) as Dictionary).is_empty())
	_check("RIEN crédité avant la sortie", _solde("res_fourrure") == avant)
	run.extraire()
	_check("extraction → crédit du butin", _solde("res_fourrure") == avant + accumule)
	var recap := _dernier_recap
	_check("recap : butin_credite = accumulé",
			int((recap.get("butin_credite", {}) as Dictionary).get("res_fourrure", 0)) == accumule)

func _test_defaite_sans_credit() -> void:
	print("\n[4] Défaite = rien (mêmes rails que l'Euren)")
	var avant := _solde("res_fourrure")
	var run := _run("biome_foret", 4242, _butin_exact(2, 0.0), 1.0, 0.1)
	_jusqua_choix(run)
	_check("la run s'est soldée par une défaite", run.defaite and run.est_terminee)
	_check("défaite → aucun crédit", _solde("res_fourrure") == avant)
	_check("recap : butin_credite vide",
			(_dernier_recap.get("butin_credite", {}) as Dictionary).is_empty())

# ─── 5. Coffre ───────────────────────────────────────────────

func _test_coffre() -> void:
	print("\n[5] Coffre : paquet de ressource fréquente (bornes du palier)")
	var cfg := _butin_exact(0, 0.0)
	cfg.coffre_frequente_par_palier = {"palier_enceinte": Vector2i(3, 3)}
	var run := ExpeRun.new(_cfg_carte(0.0, 0.0, 1.0), _palier(), "biome_foret", 33,
			_avatar(1000.0, 100.0, 10.0), _pool(), _cfg_combat())
	run.cfg_butin = cfg
	var contenus: Array = []
	run.noeud_resolu.connect(func(d: Dictionary) -> void: contenus.append(d))
	run.demarrer()
	var nid := _voisin_type(run, Enums.TypeNoeud.COFFRE)
	_check("un Coffre voisin de l'entrée (carte 100 % coffre)", nid >= 0)
	if nid < 0:
		return
	run.deplacer_vers(nid)
	_check("coffre → +3 fréquente accumulée",
			int(run.butin_accumule.get("res_fourrure", 0)) == 3)
	var contenu: Dictionary = contenus.back().get("contenu", {})
	_check("payload du nœud porte le butin du coffre",
			int((contenu.get("butin", {}) as Dictionary).get("res_fourrure", 0)) == 3)

# ─── 6. Boss d'assaut : rare garantie ────────────────────────

func _test_boss_assaut() -> void:
	print("\n[6] Boss d'assaut : ressource rare GARANTIE (re-kill = source fiable)")
	var avant := _solde("res_venin")
	var cfg := _butin_exact(0, 0.0)
	cfg.qte_frequente_par_palier = {}
	cfg.qte_rare_boss = 2
	var run := ExpeRun.new(_cfg_carte(1.0, 0.0, 0.0),
			load("res://data/expedition/palier_assaut.tres"), "biome_foret", 77,
			_avatar(100000.0, 5000.0, 100.0), _pool(), _cfg_combat())
	run.cfg_butin = cfg
	run.est_assaut = true
	var lt := CombattantCtbData.new()
	lt.id = "lieutenant_test"
	lt.nom_affichage_fr = "Lieutenant de test"
	lt.pv_max = 50.0
	lt.atk = 1.0
	lt.vit = 10.0
	run.lieutenant = lt
	run.terminee.connect(func(r: Dictionary) -> void: _dernier_recap = r)
	run.demarrer()
	_jusqua_fin_assaut(run)
	_check("assaut bouclé par la victoire", run.est_terminee and not run.defaite)
	_check("rare garantie ×2 accumulée puis créditée",
			_solde("res_venin") == avant + 2)
	_check("recap d'assaut : butin_credite porte la rare",
			int((_dernier_recap.get("butin_credite", {}) as Dictionary).get("res_venin", 0)) == 2)

# ─── Helpers ─────────────────────────────────────────────────

var _dernier_recap: Dictionary = {}

func _butin_exact(qte_freq: int, chance_rare: float) -> ButinConfigData:
	var c := ButinConfigData.new()
	c.qte_frequente_par_palier = {"palier_enceinte": Vector2i(qte_freq, qte_freq),
			"palier_assaut": Vector2i(qte_freq, qte_freq)}
	c.chance_rare_par_palier = {"palier_enceinte": chance_rare, "palier_assaut": chance_rare}
	c.qte_rare = 1
	c.coffre_frequente_par_palier = {}
	return c

func _run(lieu: String, graine: int, cfg_butin: ButinConfigData,
		pv := 1000.0, atk := 100.0) -> ExpeRun:
	var r := ExpeRun.new(_cfg_carte(1.0, 0.0, 0.0), _palier(), lieu, graine,
			_avatar(pv, atk, 10.0), _pool(), _cfg_combat())
	r.cfg_butin = cfg_butin
	r.terminee.connect(func(rec: Dictionary) -> void: _dernier_recap = rec)
	r.demarrer()
	return r

# Avance jusqu'au choix de Fin d'étage (ou fin de run) en résolvant tout.
func _jusqua_choix(run: ExpeRun) -> void:
	var garde := 0
	while not run.choix_ouvert and not run.est_terminee and garde < 200:
		garde += 1
		var chemin := _chemin_vers_type(run, Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			return
		for nid in chemin:
			run.deplacer_vers(nid)
			if run.combat_en_cours != null:
				run.combat_en_cours.derouler_auto()
			if run.choix_ouvert or run.est_terminee:
				return

func _jusqua_fin_assaut(run: ExpeRun) -> void:
	var garde := 0
	while not run.est_terminee and garde < 200:
		garde += 1
		var chemin := _chemin_vers_type(run, Enums.TypeNoeud.BOSS)
		if chemin.is_empty():
			return
		for nid in chemin:
			run.deplacer_vers(nid)
			if run.combat_en_cours != null:
				run.combat_en_cours.derouler_auto()
			if run.est_terminee:
				return

# BFS sur le graphe COMPLET de la carte vers le premier nœud du type donné.
func _chemin_vers_type(run: ExpeRun, type: int) -> Array[int]:
	var depart := run.position_joueur
	var file: Array[int] = [depart]
	var parent := {depart: -1}
	while not file.is_empty():
		var nid: int = file.pop_front()
		if nid != depart and run.carte.noeud(nid).type == type:
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

func _voisin_type(run: ExpeRun, type: int) -> int:
	for v in run.carte.noeud(run.carte.entree_id).voisins:
		if run.carte.noeud(v).type == type:
			return v
	return -1

func _du_bestiaire(id: String) -> CombattantCtbData:
	var d := CtbPont.combattant_depuis_entite(id)
	assert(d != null, "entité de bestiaire attendue : " + id)
	return d

func _solde(res_id: String) -> int:
	return int((GameData.player.get("resources", {}) as Dictionary).get(res_id, 0))

func _cfg_carte(combat: float, mystere: float, coffre: float) -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = combat
	c.poids_mystere = mystere
	c.poids_coffre = coffre
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

func _palier() -> PalierProfondeurData:
	return load("res://data/expedition/palier_enceinte.tres")

func _pool() -> PoolEnnemisData:
	return load("res://data/expedition/pool_defaut.tres")

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
