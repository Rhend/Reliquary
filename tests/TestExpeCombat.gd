extends Node
# Tests du branchement combat CTB ↔ nœuds d'expédition (Rework Combat —
# chantiers 3-4). Pont bestiaire → CTB et pont HÉROS réel (stats effectives
# recalculées indépendamment, avec/sans équipement, sans toucher la sauvegarde),
# suspension de la run sur un nœud Combat, persistance des PV entre les
# nœuds, purge des statuts en fin de combat, malus d'embuscade (attaque
# surprise), défaite = fin d'expédition, agrégat des combats au recap,
# pondération du nombre d'ennemis, stubs Coffre/Bénédiction/Piège inchangés.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	# Chantier 6 : les victoires d'ExpeRun créditent XP/Euren (signaux de
	# progression) — déconnexion des déclencheurs de sauvegarde (règle : un
	# test n'écrit JAMAIS la sauvegarde).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST COMBAT D'EXPÉDITION (CTB ↔ nœuds) ===\n")
	_test_conversion_bestiaire()
	_test_pont_heros()
	_test_malus_embuscade()
	_test_purge_statuts()
	_test_combat_noeud()
	_test_attaque_surprise()
	_test_pv_persistants()
	_test_defaite()
	_test_agregat_combats()
	_test_ponderation_nb_ennemis()
	_test_stubs_inchanges()
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

func _palier() -> PalierProfondeurData:
	return load("res://data/expedition/palier_enceinte.tres")

func _pool() -> PoolEnnemisData:
	return load("res://data/expedition/pool_defaut.tres")

# Config de carte à proportions forcées (ex. 100 % Combat) pour amener le
# joueur à coup sûr sur le type de nœud visé.
func _cfg_carte(combat: float, mystere: float, coffre: float) -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = combat
	c.poids_mystere = mystere
	c.poids_coffre = coffre
	return c

func _cfg_combat(poids_nb: Dictionary) -> ExpeCombatConfigData:
	var c := ExpeCombatConfigData.new()
	c.poids_nb_ennemis = poids_nb
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

func _combattant(id: String, pv: float, atk: float, vit: float) -> CombattantCtbData:
	var d := _avatar(pv, atk, vit)
	d.id = id
	d.nom_affichage_fr = id
	return d

func _run(cfg: ExpeCarteConfigData, graine: int, avatar: CombattantCtbData,
		cfg_combat: ExpeCombatConfigData) -> ExpeRun:
	var r := ExpeRun.new(cfg, _palier(), "lieu_test", graine, avatar, _pool(), cfg_combat)
	r.demarrer()
	return r

# Premier voisin de l'entrée du type demandé (ou -1).
func _voisin_type(run: ExpeRun, type: int) -> int:
	for v in run.carte.noeud(run.carte.entree_id).voisins:
		if run.carte.noeud(v).type == type:
			return v
	return -1

# Un pas + auto-résolution du combat éventuel.
func _pas(run: ExpeRun, nid: int) -> bool:
	var ok := run.deplacer_vers(nid)
	if run.combat_en_cours != null:
		run.combat_en_cours.derouler_auto()
	return ok

# Plus court chemin (BFS) de la position du joueur vers `cible`.
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

# ─── Pont bestiaire → CTB ───────────────────────────────────

# Le combattant CTB porte EXACTEMENT les stats effectives de l'entité
# (GameData.get_effective_stats, palier de Maîtrise courant) : hp → pv_max,
# atk/def/vit/crit_* inchangés — aucun rééquilibrage.
func _test_conversion_bestiaire() -> void:
	print("[TEST] Conversion bestiaire → combattant CTB (stats telles quelles)")
	for cid in ["creature_foret_surface", "creature_marecage_surface",
			"creature_montagne_surface", "creature_gorlab"]:
		var d := CtbPont.combattant_depuis_entite(cid)
		if d == null:
			_fail("conversion %s" % cid, "entité introuvable")
			continue
		var s: Dictionary = GameData.get_effective_stats(cid)
		var e: Dictionary = GameData.get_entity(cid)
		_assert(d.pv_max == float(s["hp"]) and d.atk == float(s["atk"])
				and d.def == float(s["def"]) and d.vit == float(s["vit"])
				and d.crit_chance == float(s["crit_chance"])
				and d.crit_multiplier == float(s["crit_multiplier"])
				and d.id == cid and d.nom_affichage_fr == str(e["nom_affichage_fr"]),
				"%s : hp→pv_max, atk, def, vit, crit ×2, id, nom identiques" % cid)
	_assert(CtbPont.combattant_depuis_entite("id_inexistant_xyz") == null,
			"entité inconnue → null (erreur console)")

# ─── Pont héros réel → CTB (chantier 4) ─────────────────────

# Stats attendues du héros, recalculées INDÉPENDAMMENT depuis les mêmes
# systèmes (formule de l'ancien combat_player : plats puis % additifs).
# Le test ne charge JAMAIS la sauvegarde : l'état comparé est l'état runtime
# courant, des deux côtés — indépendant de la machine.
func _heros_conforme(d: CombattantCtbData) -> bool:
	var stats: Dictionary = GameData.get_effective_stats("hero")
	var pas: Dictionary = PassiveSystem.get_combat_bonuses()
	var eq: Dictionary = GameData.get_equipment_bonuses()
	var atk_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT) \
			+ ForgeSystem.get_stat_bonus("atk_pct")
	var def_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT) \
			+ ForgeSystem.get_stat_bonus("def_pct")
	var hp_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_HP_MAX_PCT) \
			+ ForgeSystem.get_stat_bonus("hp_max_pct")
	var crit_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_CRIT_PCT) \
			+ ForgeSystem.get_stat_bonus("crit_pct")
	var hp_att := StatStacker.final_stat(float(stats["hp"]) + float(pas.get("hp_bonus", 0.0))
			+ float(eq.get("hp", 0.0)), [hp_pct], "hp")
	var atk_att := StatStacker.final_stat(float(stats["atk"]) + float(pas.get("atk_bonus", 0.0))
			+ float(eq.get("atk", 0.0)), [atk_pct], "atk")
	var def_att := StatStacker.final_stat(float(stats["def"]) + float(pas.get("def_bonus", 0.0))
			+ float(eq.get("def", 0.0)), [def_pct], "def")
	var vit_att := StatStacker.final_stat(float(stats["vit"]),
			[float(eq.get("attack_speed_pct", 0.0)) / 100.0,
			ForgeSystem.get_stat_bonus("atb_pct")], "vit")
	return absf(d.pv_max - hp_att) < 0.001 and absf(d.atk - atk_att) < 0.001 \
			and absf(d.def - def_att) < 0.001 and absf(d.vit - vit_att) < 0.001 \
			and absf(d.crit_chance - (float(stats["crit_chance"]) + crit_pct)) < 0.001 \
			and absf(d.crit_multiplier - float(stats["crit_multiplier"])) < 0.001 \
			and d.id == "hero"

func _test_pont_heros() -> void:
	print("\n[TEST] Pont héros réel → CTB (stats effectives, équipement compris)")
	var equips_avant: Dictionary = (GameData.player["equipped"] as Dictionary).duplicate()
	# SANS équipement (manipulation directe du dict — aucun signal, donc aucune
	# écriture de sauvegarde possible).
	for slot in GameData.player["equipped"]:
		GameData.player["equipped"][slot] = ""
	var d := CtbPont.combattant_depuis_heros()
	if d == null:
		_fail("pont héros : conversion null")
		GameData.player["equipped"] = equips_avant
		return
	_assert(_heros_conforme(d), "sans équipement : identique champ à champ à l'agrégation")
	var atk_nu := d.atk
	var vit_nu := d.vit
	# AVEC équipement : Lame de Pierre (atk +3) + Anneau de Forêt (attack_speed 10 %).
	GameData.player["equipped"]["arme"] = "equipment_arme"
	GameData.player["equipped"]["anneau"] = "equipment_anneau"
	var d2 := CtbPont.combattant_depuis_heros()
	_assert(d2 != null and _heros_conforme(d2),
			"avec équipement : identique champ à champ à l'agrégation")
	_assert(d2 != null and d2.atk > atk_nu and d2.vit > vit_nu,
			"changer l'équipement change les stats CTB au prochain lancement (ATK, VIT)",
			"atk %f→%f, vit %f→%f" % [atk_nu, d2.atk, vit_nu, d2.vit])
	var nom_attendu := str(GameData.get_entity("hero").get("nom_affichage_fr", ""))
	_assert(d.nom_affichage_fr == nom_attendu and d.id == "hero",
			"identité : id 'hero' + nom d'affichage de l'entité")
	# L'avatar FACTICE reste disponible et inchangé (TestExpeCarte/sandbox).
	var factice: CombattantCtbData = load("res://data/combat_ctb/avatar.tres")
	_assert(factice != null and factice.id == "ctb_avatar" and factice.pv_max == 100.0
			and factice.atk == 20.0 and factice.def == 5.0 and factice.vit == 20.0,
			"avatar factice (avatar.tres) disponible et inchangé")
	GameData.player["equipped"] = equips_avant   # remise en état stricte

# ─── Malus d'embuscade (moteur) ─────────────────────────────

# Première horloge du camp joueur × 1.5 ; l'adverse n'est pas touché ;
# le réarmement suivant est NORMAL (K / VIT, sans malus).
func _test_malus_embuscade() -> void:
	print("\n[TEST] Embuscade : première horloge joueur ×1.5, réarmement normal")
	var m := CtbMoteur.new()
	m.malus_horloge_initiale_joueur = 1.5
	var av := m.ajouter(_combattant("avatar", 100000.0, 10.0, 20.0), Enums.CampCtb.JOUEUR)
	var en := m.ajouter(_combattant("ennemi", 100000.0, 10.0, 20.0), Enums.CampCtb.ADVERSE)
	m.demarrer()
	_assert(absf(av.horloge - 75.0) < 0.001, "horloge initiale Avatar : 50 × 1.5 = 75",
			"obtenu %.1f" % av.horloge)
	_assert(absf(en.horloge - 50.0) < 0.001, "horloge initiale ennemi : 50 (sans malus)",
			"obtenu %.1f" % en.horloge)
	_assert("\n".join(m.journal).contains("EMBUSCADE"),
			"le journal mentionne l'embuscade et le malus")
	# L'ennemi (50) joue d'abord, puis l'Avatar (75) : son réarmement est
	# normal → 75 + 1000/20 = 125.
	for i in 4:
		var c := m.activer_suivant()
		if c == null:
			continue
		m.jouer(m.action_auto(c))
		if c == av:
			break
	_assert(absf(av.horloge - 125.0) < 0.001,
			"réarmement suivant normal : 75 + 50 = 125", "obtenu %.1f" % av.horloge)

# ─── Purge des statuts en fin de combat ─────────────────────

func _test_purge_statuts() -> void:
	print("\n[TEST] Statuts purgés en fin de combat (aucune persistance)")
	var m := CtbMoteur.new()
	var av := m.ajouter(_combattant("avatar", 100000.0, 100.0, 40.0), Enums.CampCtb.JOUEUR)
	var en := m.ajouter(_combattant("ennemi", 150.0, 5.0, 20.0), Enums.CampCtb.ADVERSE)
	m.demarrer()
	var statut := StatutCtbData.new()
	statut.id = "statut_test_long"
	statut.nom_affichage_fr = "Statut de test"
	statut.timing = Enums.TimingStatut.FIN_ACTIVATION
	statut.degats_pct_atk = 0.001
	statut.stacks_max = 3
	statut.duree_activations = 99   # survit largement au combat
	m.appliquer_statut(en, statut, av)
	m.appliquer_statut(av, statut, en)
	m.derouler_auto()
	_assert(m.termine and m.victoire_joueur, "combat gagné (précondition)")
	_assert(av.statuts.is_empty() and en.statuts.is_empty(),
			"tous les stacks purgés à la fin (vainqueur ET vaincus)")
	_assert("\n".join(m.journal).contains("purgés"), "le journal mentionne la purge")

# ─── Nœud Combat : combat CTB réel, run suspendue ───────────

func _test_combat_noeud() -> void:
	print("\n[TEST] Nœud Combat : combat réel, suspension, reprise à la victoire")
	for g in range(1, 60):
		var run := _run(_cfg_carte(1.0, 0.0, 0.0), g, _avatar(1000000.0, 1000000.0, 50.0),
				_cfg_combat({1: 1.0}))
		var cible := _voisin_type(run, Enums.TypeNoeud.COMBAT)
		if cible < 0:
			continue
		var payloads := []
		run.noeud_resolu.connect(func(d: Dictionary) -> void: payloads.append(d))
		var demarres := []
		run.combat_demarre.connect(func(_m: CtbMoteur, d: Dictionary) -> void:
			demarres.append(d))
		run.deplacer_vers(cible)
		_assert(run.combat_en_cours != null, "entrer sur un nœud Combat lance un CTB")
		_assert(demarres.size() == 1 and not demarres[0]["embuscade"],
				"signal combat_demarre émis (embuscade=false)")
		_assert(not run.carte.noeud(cible).resolu and payloads.is_empty(),
				"le nœud n'est PAS résolu tant que le combat n'est pas gagné")
		var autre := run.carte.noeud(run.carte.entree_id).id
		_assert(not run.deplacer_vers(autre), "run SUSPENDUE : déplacement refusé en combat")
		run.combat_en_cours.derouler_auto()
		_assert(run.combat_en_cours == null and run.carte.noeud(cible).resolu,
				"victoire → nœud résolu, run reprise")
		_assert(run.nb_combats == 1 and payloads.size() == 1 and payloads[0].has("combat")
				and payloads[0]["combat"]["ennemis_vaincus"].size() == 1,
				"payload noeud_resolu enrichi du recap de combat (1 vaincu)")
		_assert(run.deplacer_vers(run.carte.entree_id), "déplacement à nouveau accepté")
		return
	_fail("aucune graine avec un Combat voisin de l'entrée en 60 essais (improbable)")

# ─── Attaque surprise (contenu du « ? ») ────────────────────

func _test_attaque_surprise() -> void:
	print("\n[TEST] Attaque surprise : combat CTB avec malus d'embuscade")
	var cfg := _cfg_carte(0.0, 1.0, 0.0)
	cfg.mystere_poids_coffre = 0.0
	cfg.mystere_poids_benediction = 0.0
	cfg.mystere_poids_piege = 0.0
	cfg.mystere_poids_attaque_surprise = 1.0
	for g in range(1, 60):
		var run := _run(cfg, g, _avatar(1000000.0, 1000000.0, 50.0), _cfg_combat({1: 1.0}))
		var cible := _voisin_type(run, Enums.TypeNoeud.MYSTERE)
		if cible < 0:
			continue
		var payloads := []
		run.noeud_resolu.connect(func(d: Dictionary) -> void: payloads.append(d))
		run.deplacer_vers(cible)
		var nd := run.carte.noeud(cible)
		_assert(run.combat_en_cours != null
				and nd.contenu_mystere == Enums.ContenuMystere.ATTAQUE_SURPRISE,
				"« ? » → Attaque surprise : combat lancé")
		_assert(absf(run.combat_en_cours.malus_horloge_initiale_joueur - 1.5) < 0.001,
				"malus d'initiative ×1.5 posé sur le moteur (.tres)")
		_assert("\n".join(run.combat_en_cours.journal).contains("EMBUSCADE"),
				"journal du combat : embuscade mentionnée")
		run.combat_en_cours.derouler_auto()
		_assert(nd.resolu and payloads.size() == 1 and payloads[0]["combat"]["embuscade"],
				"victoire → « ? » résolu, payload combat.embuscade=true")
		return
	_fail("aucune graine avec un « ? » voisin de l'entrée en 60 essais (improbable)")

# ─── PV persistants entre les nœuds ─────────────────────────

func _test_pv_persistants() -> void:
	print("\n[TEST] PV persistants : entamer chaque combat avec les PV sortants")
	# Avatar LENT (vit 10 < 30 des créatures) : les ennemis frappent d'abord,
	# des dégâts sont garantis ; ATK énorme : la victoire aussi.
	for g in range(1, 60):
		var run := _run(_cfg_carte(1.0, 0.0, 0.0), g, _avatar(100000.0, 1000000.0, 10.0),
				_cfg_combat({1: 1.0}))
		var voisins := run.carte.noeud(run.carte.entree_id).voisins
		var combats: Array[int] = []
		for v in voisins:
			if run.carte.noeud(v).type == Enums.TypeNoeud.COMBAT:
				combats.append(v)
		if combats.is_empty():
			continue
		_assert(absf(run.pv_avatar - 100000.0) < 0.001, "PV pleins au lancement (provisoire)")
		# Combat 1 : des dégâts sont pris.
		run.deplacer_vers(combats[0])
		run.combat_en_cours.derouler_auto()
		var pv_sortants := run.pv_avatar
		_assert(pv_sortants < 100000.0, "combat 1 : l'Avatar a pris des dégâts",
				"PV %f" % pv_sortants)
		# Combat 2 (le prochain nœud Combat atteignable) : PV d'entame = PV sortants.
		var cible2 := -1
		for nd in run.carte.noeuds:
			if nd.type == Enums.TypeNoeud.COMBAT and not nd.resolu:
				cible2 = nd.id
				break
		if cible2 < 0:
			continue
		var chemin := _chemin_vers(run, cible2)
		for i in chemin.size() - 1:
			_pas(run, chemin[i])   # nœuds intermédiaires (auto-résolus)
		var pv_avant_combat2 := run.pv_avatar
		run.deplacer_vers(chemin[chemin.size() - 1])
		if run.combat_en_cours == null:
			continue   # (défensif : le nœud a pu être résolu en chemin)
		_assert(absf(run.combat_en_cours.avatar().pv - pv_avant_combat2) < 0.001,
				"combat suivant entamé avec les PV sortants (aucune régénération)",
				"entame %f vs sortants %f" % [run.combat_en_cours.avatar().pv, pv_avant_combat2])
		run.combat_en_cours.derouler_auto()
		return
	_fail("aucune graine exploitable pour la persistance des PV en 60 essais (improbable)")

# ─── Défaite : fin d'expédition immédiate ───────────────────

func _test_defaite() -> void:
	print("\n[TEST] Défaite en combat : fin d'expédition immédiate, recap étendu")
	for g in range(1, 60):
		# Avatar moribond : PV 1, plus lent que les créatures → il meurt au 1er coup.
		var run := _run(_cfg_carte(1.0, 0.0, 0.0), g, _avatar(1.0, 1.0, 1.0),
				_cfg_combat({1: 1.0}))
		var cible := _voisin_type(run, Enums.TypeNoeud.COMBAT)
		if cible < 0:
			continue
		var recaps := []
		run.terminee.connect(func(r: Dictionary) -> void: recaps.append(r))
		run.deplacer_vers(cible)
		run.combat_en_cours.derouler_auto()
		_assert(run.est_terminee and run.defaite, "PV Avatar à 0 → expédition terminée")
		_assert(not run.carte.noeud(cible).resolu, "le nœud perdu n'est PAS résolu")
		_assert(recaps.size() == 1 and recaps[0]["defaite"]
				and not recaps[0]["complete"] and not recaps[0]["extraction"]
				and recaps[0]["nb_combats"] == 1,
				"recap : defaite=true, complete=false, extraction=false, nb_combats=1")
		_assert(not run.deplacer_vers(run.carte.entree_id),
				"plus aucun déplacement après la défaite")
		return
	_fail("aucune graine avec un Combat voisin de l'entrée en 60 essais (improbable)")

# ─── Agrégat des combats au recap ───────────────────────────

func _test_agregat_combats() -> void:
	print("\n[TEST] Recap : ennemis_vaincus cumulés + nb_combats sur toute la run")
	var run := _run(_cfg_carte(1.0, 0.0, 0.0), 4242, _avatar(1000000.0, 1000000.0, 50.0),
			_cfg_combat({2: 1.0}))   # exactement 2 ennemis par combat
	# Visite TOUS les nœuds de l'étage 1 (tout l'intérieur est Combat).
	for nd in run.carte.noeuds:
		if not nd.resolu and nd.id != run.carte.fin_id:
			for pas in _chemin_vers(run, nd.id):
				_pas(run, pas)
	var nb_interieurs := run.carte.noeuds.size() - 2   # hors Entrée / Fin d'étage
	_assert(run.nb_combats == nb_interieurs,
			"%d nœuds intérieurs = %d combats livrés" % [nb_interieurs, run.nb_combats])
	# Extraction à la Fin d'étage → recap.
	var recaps := []
	run.terminee.connect(func(r: Dictionary) -> void: recaps.append(r))
	for pas in _chemin_vers(run, run.carte.fin_id):
		_pas(run, pas)
	run.extraire()
	_assert(recaps.size() == 1, "extraction → recap émis")
	if recaps.size() == 1:
		var vaincus: Array = recaps[0]["ennemis_vaincus"]
		_assert(vaincus.size() == nb_interieurs * 2
				and vaincus.all(func(d) -> bool: return d is CombattantCtbData),
				"ennemis_vaincus : %d × 2 = %d références CombattantCtbData" % [
						nb_interieurs, vaincus.size()])
		_assert(recaps[0]["nb_combats"] == nb_interieurs and not recaps[0]["defaite"],
				"recap : nb_combats agrégé, defaite=false")

# ─── Pondération du nombre d'ennemis ────────────────────────

func _test_ponderation_nb_ennemis() -> void:
	print("\n[TEST] Nombre d'ennemis : 1→50 % / 2→35 % / 3→15 % (3000 tirages, ±5 pts)")
	var cfg_combat: ExpeCombatConfigData = load("res://data/expedition/config_combat.tres")
	var run := ExpeRun.new(_cfg_carte(1.0, 0.0, 0.0), _palier(), "lieu_test", 777,
			_avatar(100.0, 10.0, 20.0), _pool(), cfg_combat)
	var compte := {1: 0, 2: 0, 3: 0}
	for i in 3000:
		compte[run.tirer_nb_ennemis()] += 1
	for nb in [1, 2, 3]:
		var attendu := float(cfg_combat.poids_nb_ennemis[nb])
		var obtenu := float(compte[nb]) / 3000.0
		_assert(absf(obtenu - attendu) < 0.05,
				"%d ennemi(s) : %.1f %% (attendu %.0f %%)" % [nb, obtenu * 100.0, attendu * 100.0])

# ─── Stubs inchangés (Coffre / Bénédiction / Piège) ─────────

func _test_stubs_inchanges() -> void:
	print("\n[TEST] Coffre / Bénédiction / Piège : toujours des stubs (aucun combat)")
	# Coffre en dur sur la carte.
	var coffre_teste := false
	for g in range(1, 60):
		var run := _run(_cfg_carte(0.0, 0.0, 1.0), g, _avatar(100.0, 10.0, 20.0),
				_cfg_combat({1: 1.0}))
		var cible := _voisin_type(run, Enums.TypeNoeud.COFFRE)
		if cible < 0:
			continue
		var payloads := []
		run.noeud_resolu.connect(func(d: Dictionary) -> void: payloads.append(d))
		run.deplacer_vers(cible)
		_assert(run.combat_en_cours == null and run.carte.noeud(cible).resolu
				and payloads.size() == 1 and not payloads[0].has("combat")
				and run.nb_combats == 0,
				"Coffre : résolu en stub, aucun combat, payload sans clé combat")
		coffre_teste = true
		break
	if not coffre_teste:
		_fail("aucune graine avec un Coffre voisin de l'entrée en 60 essais (improbable)")
	# Bénédiction puis Piège via un « ? » forcé.
	for contenu in [Enums.ContenuMystere.BENEDICTION, Enums.ContenuMystere.PIEGE]:
		var cfg := _cfg_carte(0.0, 1.0, 0.0)
		cfg.mystere_poids_coffre = 0.0
		cfg.mystere_poids_benediction = 1.0 if contenu == Enums.ContenuMystere.BENEDICTION else 0.0
		cfg.mystere_poids_piege = 1.0 if contenu == Enums.ContenuMystere.PIEGE else 0.0
		cfg.mystere_poids_attaque_surprise = 0.0
		var mystere_teste := false
		for g in range(1, 60):
			var run := _run(cfg, g, _avatar(100.0, 10.0, 20.0), _cfg_combat({1: 1.0}))
			var cible := _voisin_type(run, Enums.TypeNoeud.MYSTERE)
			if cible < 0:
				continue
			run.deplacer_vers(cible)
			var nd := run.carte.noeud(cible)
			_assert(run.combat_en_cours == null and nd.resolu and nd.contenu_mystere == contenu,
					"« ? » → %s : résolu en stub, aucun combat" % (
							"Bénédiction" if contenu == Enums.ContenuMystere.BENEDICTION else "Piège"))
			mystere_teste = true
			break
		if not mystere_teste:
			_fail("aucune graine avec un « ? » voisin de l'entrée en 60 essais (improbable)")

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ branchement combat ↔ expédition conforme")
	print("════════════════════════════════\n")
