extends Node
# Tests de l'ÉCONOMIE DE RÉCOMPENSE (Rework Combat — chantier 6) : XP de
# niveau du héros + Euren. Vérifie :
#   • courbe de niveau (.tres) : seuils exacts, multi-niveaux en un gain,
#     signaux heros_xp_gagnee / heros_niveau_change ;
#   • xp_reward du bestiaire lu tel quel et crédité IMMÉDIATEMENT à la
#     victoire d'un combat d'expédition — jamais à la défaite ;
#   • bonus plats de niveau injectés dans CtbPont.combattant_depuis_heros
#     AVANT les % ; combattant en cours de run inchangé (pas à chaud —
#     le niveau compte au prochain LANCEMENT, recalcul entre nœuds non
#     implémenté, cf. recap) ;
#   • Euren : accumulé en run ≠ crédité — extraction crédite, complétion
#     crédite, défaite ne crédite rien (signal euren_change) ;
#   • persistance : champs dans GameData.player, round-trip
#     _save_player/_load_player sans toucher le disque ;
#   • recap d'expédition étendu (xp_gagnee, euren_gagne, euren_credite).
# Ne charge JAMAIS la sauvegarde et n'écrit jamais (déclencheurs déconnectés).

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST ÉCONOMIE DE RÉCOMPENSE (XP + EUREN) ===\n")
	_test_courbe_niveaux()
	_test_gagner_xp_signaux()
	_test_bonus_niveau_dans_pont()
	_test_victoire_credite_immediatement()
	_test_pas_a_chaud_en_cours_de_run()
	_test_defaite_ne_credite_rien()
	_test_extraction_credite()
	_test_completion_credite()
	_test_persistance_sauvegarde()
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

# Remet la progression à zéro (état de test, jamais sauvé).
func _reset_progression() -> void:
	GameData.player["heros_xp"] = 0.0
	GameData.player["euren"] = 0.0

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

# Config 100 % Combat : chaque nœud intermédiaire est un combat.
func _cfg_tout_combat() -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = 1.0
	c.poids_mystere = 0.0
	c.poids_coffre = 0.0
	return c

# Config 100 % Coffre : aucun combat (stubs) — pour piloter l'Euren à la main.
func _cfg_sans_combat() -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = 0.0
	c.poids_mystere = 0.0
	c.poids_coffre = 1.0
	return c

func _run(cfg: ExpeCarteConfigData, graine: int, avatar: CombattantCtbData) -> ExpeRun:
	var r := ExpeRun.new(cfg, load("res://data/expedition/palier_enceinte.tres"),
			"lieu_test", graine, avatar,
			load("res://data/expedition/pool_defaut.tres"),
			load("res://data/expedition/config_combat.tres"))
	r.demarrer()
	return r

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

# Marche jusqu'à la Fin d'étage courante (combats auto-résolus en chemin).
func _marcher_vers_fin(run: ExpeRun) -> void:
	for nid in _chemin_vers(run, run.carte.fin_id):
		if run.est_terminee:
			return
		_pas(run, nid)

# Avance (étage par étage si besoin) jusqu'au PREMIER combat résolu — sans
# jamais rebondir entre nœuds résolus (le chemin vers la Fin est dirigé).
func _jusqu_au_premier_combat(run: ExpeRun) -> void:
	var garde := 0
	while run.nb_combats == 0 and not run.est_terminee and garde < 10:
		garde += 1
		_marcher_vers_fin(run)
		if run.choix_ouvert:
			run.continuer()

# Somme attendue des récompenses des vaincus d'un recap moteur (xp_reward lu
# tel quel au palier courant ; Euren = config base × mult. de palier) —
# recalcul INDÉPENDANT de ExpeRun._recompenses_pour.
func _attendu_pour(vaincus: Array) -> Dictionary:
	var cfg: EurenConfigData = load("res://data/progression/euren.tres")
	var xp := 0.0
	var euren := 0.0
	for d: CombattantCtbData in vaincus:
		var entity: Dictionary = GameData.get_entity(d.id)
		var tier := int(entity.get("maitrise_actuelle", 0))
		xp += float(GameData.stats_at_tier(entity, tier).get("xp_reward", 0.0))
		euren += cfg.base_par_ennemi * float(cfg.multiplicateurs_par_palier.get(tier, 1.0))
	return {"xp": xp, "euren": euren}

# ─── Courbe de niveaux ──────────────────────────────────────

# Seuils exacts de la courbe .tres : XP totale pour atteindre n =
# round(100 × n^1.5) — niveau plancher 1.
func _test_courbe_niveaux() -> void:
	print("[TEST] Courbe de niveau — seuils exacts (.tres, base 100, exposant 1.5)")
	var cfg := ProgressionHeros.CONFIG
	_assert(absf(cfg.seuil_xp(2) - 283.0) < 0.001, "seuil niveau 2 : round(100×2^1.5) = 283")
	_assert(absf(cfg.seuil_xp(3) - 520.0) < 0.001, "seuil niveau 3 : round(100×3^1.5) = 520")
	_assert(absf(cfg.seuil_xp(4) - 800.0) < 0.001, "seuil niveau 4 : round(100×4^1.5) = 800")
	_assert(cfg.niveau_pour_xp(0.0) == 1, "0 XP → niveau 1 (plancher)")
	_assert(cfg.niveau_pour_xp(282.0) == 1, "282 XP → toujours niveau 1")
	_assert(cfg.niveau_pour_xp(283.0) == 2, "283 XP → niveau 2 (seuil exact)")
	_assert(cfg.niveau_pour_xp(519.0) == 2, "519 XP → niveau 2")
	_assert(cfg.niveau_pour_xp(520.0) == 3, "520 XP → niveau 3 (seuil exact)")
	_assert(cfg.niveau_pour_xp(800.0) == 4, "800 XP → niveau 4")

# gagner_xp : cumul jamais perdu, signaux, multi-niveaux en un seul gain.
func _test_gagner_xp_signaux() -> void:
	print("\n[TEST] gagner_xp — signaux + multi-niveaux en un gain")
	_reset_progression()
	var xp_events: Array = []
	var niveau_events: Array = []
	var cb_xp := func(montant: float, totale: float) -> void:
		xp_events.append([montant, totale])
	var cb_niv := func(avant: int, apres: int) -> void:
		niveau_events.append([avant, apres])
	EventBus.heros_xp_gagnee.connect(cb_xp)
	EventBus.heros_niveau_change.connect(cb_niv)
	var r1: Dictionary = ProgressionHeros.gagner_xp(100.0)
	_assert(int(r1["avant"]) == 1 and int(r1["apres"]) == 1,
			"+100 XP : niveau inchangé (100 < 283)")
	_assert(xp_events.size() == 1 and niveau_events.is_empty(),
			"heros_xp_gagnee émis, heros_niveau_change NON émis")
	var r2: Dictionary = ProgressionHeros.gagner_xp(700.0)
	_assert(int(r2["avant"]) == 1 and int(r2["apres"]) == 4,
			"+700 XP (total 800) : niveau 1 → 4 en UN gain (multi-niveaux)")
	_assert(niveau_events == [[1, 4]], "heros_niveau_change(1, 4) émis une fois",
			str(niveau_events))
	_assert(absf(ProgressionHeros.xp_totale() - 800.0) < 0.001,
			"XP totale cumulée : 800 (jamais perdue)")
	EventBus.heros_xp_gagnee.disconnect(cb_xp)
	EventBus.heros_niveau_change.disconnect(cb_niv)
	_reset_progression()

# ─── Bonus de niveau dans le pont héros ─────────────────────

# Les bonus plats ((niveau−1) × gain .tres) s'injectent AVANT les % — delta
# attendu = bonus × (1 + pct), pct relus indépendamment des mêmes systèmes.
func _test_bonus_niveau_dans_pont() -> void:
	print("\n[TEST] Pont héros — bonus plats de niveau avant les %")
	_reset_progression()
	var a1 := CtbPont.combattant_depuis_heros()
	GameData.player["heros_xp"] = 800.0   # niveau 4 → 3 paliers de gains
	var a2 := CtbPont.combattant_depuis_heros()
	var g := ProgressionHeros.CONFIG
	var hp_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_HP_MAX_PCT) \
			+ ForgeSystem.get_stat_bonus("hp_max_pct")
	var atk_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT) \
			+ ForgeSystem.get_stat_bonus("atk_pct")
	var def_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT) \
			+ ForgeSystem.get_stat_bonus("def_pct")
	var equip: Dictionary = GameData.get_equipment_bonuses()
	var vit_pct: float = float(equip.get("attack_speed_pct", 0.0)) / 100.0 \
			+ ForgeSystem.get_stat_bonus("atb_pct")
	_assert(absf((a2.pv_max - a1.pv_max) - 3.0 * g.gain_pv_max_par_niveau * (1.0 + hp_pct)) < 0.001,
			"PV max : +3 × %.1f avant les %%" % g.gain_pv_max_par_niveau,
			"delta=%.2f" % (a2.pv_max - a1.pv_max))
	_assert(absf((a2.atk - a1.atk) - 3.0 * g.gain_atk_par_niveau * (1.0 + atk_pct)) < 0.001,
			"ATK : +3 × %.1f avant les %%" % g.gain_atk_par_niveau)
	_assert(absf((a2.def - a1.def) - 3.0 * g.gain_def_par_niveau * (1.0 + def_pct)) < 0.001,
			"DEF : +3 × %.1f (fractions cumulées, non arrondies)" % g.gain_def_par_niveau)
	_assert(absf((a2.vit - a1.vit) - 3.0 * g.gain_vit_par_niveau * (1.0 + vit_pct)) < 0.001,
			"VIT : +3 × %.1f avant les %%" % g.gain_vit_par_niveau)
	_assert(absf(a2.crit_chance - a1.crit_chance) < 0.001,
			"crit inchangé (aucun gain de niveau sur le crit)")
	_reset_progression()

# ─── Crédit à la victoire (expédition) ──────────────────────

# xp_reward lu tel quel, crédité IMMÉDIATEMENT à la victoire ; Euren accumulé
# dans la run mais PAS crédité avant la sortie.
func _test_victoire_credite_immediatement() -> void:
	print("\n[TEST] Victoire — XP créditée immédiatement, Euren seulement accumulé")
	_reset_progression()
	var run := _run(_cfg_tout_combat(), 4242, _avatar(100000.0, 100000.0, 60.0))
	var vaincus: Array = []            # cumul de la run (plusieurs combats possibles)
	var derniers: Array = []           # vaincus du DERNIER combat gagné
	var cb := func(m: CtbMoteur, _d: Dictionary) -> void:
		m.victoire.connect(func(r: Dictionary) -> void:
			vaincus.append_array(r["ennemis_vaincus"])
			derniers.assign(r["ennemis_vaincus"]), CONNECT_ONE_SHOT)
	run.combat_demarre.connect(cb)
	_jusqu_au_premier_combat(run)
	_assert(run.nb_combats >= 1 and not vaincus.is_empty(), "un combat a été gagné")
	var attendu := _attendu_pour(vaincus)
	_assert(absf(ProgressionHeros.xp_totale() - float(attendu["xp"])) < 0.001,
			"XP créditée immédiatement = Σ xp_reward des vaincus (lu tel quel)",
			"xp=%.1f attendu=%.1f" % [ProgressionHeros.xp_totale(), attendu["xp"]])
	_assert(absf(run.xp_gagnee - float(attendu["xp"])) < 0.001,
			"run.xp_gagnee reflète le total de la run")
	_assert(absf(run.euren_accumule - float(attendu["euren"])) < 0.001,
			"Euren accumulé = Σ base × mult. de palier (config, pas bestiaire)",
			"acc=%.1f attendu=%.1f" % [run.euren_accumule, attendu["euren"]])
	_assert(absf(ProgressionHeros.euren()) < 0.001,
			"Euren PAS crédité en cours de run (sortie uniquement)")
	var attendu_dernier := _attendu_pour(derniers)
	_assert(absf(float(run.dernier_combat_recompenses.get("xp", -1.0))
			- float(attendu_dernier["xp"])) < 0.001,
			"dernier_combat_recompenses porte l'XP du DERNIER combat (écran d'issue)")
	_reset_progression()

# Le combattant CTB d'une run en cours ne change PAS à chaud après un niveau
# up ; le nouveau niveau compte au prochain LANCEMENT (pont reconstruit) —
# le recalcul entre nœuds n'est PAS implémenté (arbitrage, cf. recap).
func _test_pas_a_chaud_en_cours_de_run() -> void:
	print("\n[TEST] Niveau up en cours de run — pas à chaud, au prochain lancement")
	_reset_progression()
	GameData.player["heros_xp"] = 280.0   # à 3 XP du niveau 2
	var avatar := CtbPont.combattant_depuis_heros()
	var atk_avant := avatar.atk
	var run := _run(_cfg_tout_combat(), 777, avatar)
	_jusqu_au_premier_combat(run)
	_assert(ProgressionHeros.niveau() >= 2, "le héros a monté de niveau en cours de run",
			"xp=%.1f" % ProgressionHeros.xp_totale())
	_assert("\n".join(run.journal).contains("⭐ Niveau 1 → 2"),
			"journal de run : « Niveau 1 → 2 »")
	_assert(absf(run.avatar_data.atk - atk_avant) < 0.001,
			"combattant de la run INCHANGÉ (pas de recalcul à chaud ni entre nœuds)")
	var prochain := CtbPont.combattant_depuis_heros()
	_assert(prochain.atk > atk_avant + 0.5,
			"pont reconstruit (prochain lancement) : bonus de niveau visibles",
			"avant=%.1f apres=%.1f" % [atk_avant, prochain.atk])
	_reset_progression()

# ─── Les trois sorties d'expédition ─────────────────────────

# Victoire d'abord (XP créditée, Euren accumulé), puis DÉFAITE : l'Euren
# accumulé est PERDU (0 crédité), l'XP déjà créditée reste acquise.
func _test_defaite_ne_credite_rien() -> void:
	print("\n[TEST] Défaite — Euren accumulé perdu, XP déjà créditée conservée")
	_reset_progression()
	# VIT 1 : les ennemis agissent toujours d'abord ; gros PV/ATK : gagne quand
	# même le 1er combat. PV forcés à 0.5 ensuite : mort au 1er coup reçu.
	var run := _run(_cfg_tout_combat(), 999, _avatar(100000.0, 100000.0, 1.0))
	_jusqu_au_premier_combat(run)
	var xp_apres_victoire := ProgressionHeros.xp_totale()
	var euren_accumule := run.euren_accumule
	_assert(run.nb_combats >= 1 and xp_apres_victoire > 0.0 and euren_accumule > 0.0,
			"mise en place : une victoire créditée (XP) et de l'Euren accumulé")
	run.pv_avatar = 0.5   # prochain combat : le premier coup reçu tue (MIN_DAMAGE ≥ 1)
	# Marcher vers la Fin (nœuds 100 % Combat) jusqu'à la défaite — jamais de
	# ping-pong entre nœuds résolus. Garde-fou : étages suivants si besoin.
	var garde := 0
	while not run.est_terminee and garde < 10:
		garde += 1
		_marcher_vers_fin(run)
		if run.choix_ouvert:
			run.continuer()
	_assert(run.defaite, "la run se termine en défaite")
	var recap := run._recap(false)
	_assert(absf(float(recap["euren_credite"])) < 0.001 and absf(run.euren_credite) < 0.001,
			"défaite : euren_credite = 0")
	_assert(absf(ProgressionHeros.euren()) < 0.001,
			"défaite : rien n'arrive au portefeuille (Euren perdu)")
	_assert(float(recap["euren_gagne"]) >= euren_accumule - 0.001,
			"recap : euren_gagne (accumulé) reste visible à titre d'information")
	_assert(absf(ProgressionHeros.xp_totale() - xp_apres_victoire) < 0.001,
			"l'XP créditée aux victoires précédentes reste acquise")
	_reset_progression()

# Extraction : l'Euren accumulé est crédité (signal euren_change).
func _test_extraction_credite() -> void:
	print("\n[TEST] Extraction — Euren accumulé crédité")
	_reset_progression()
	var run := _run(_cfg_sans_combat(), 31337, _avatar(1000.0, 10.0, 20.0))
	# Aucun combat sur cette carte : Euren injecté à la main (white-box) pour
	# isoler le CRÉDIT de l'accumulation (testée par ailleurs).
	run.euren_accumule = 42.0
	var totaux: Array = []
	var cb := func(total: float) -> void: totaux.append(total)
	EventBus.euren_change.connect(cb)
	_marcher_vers_fin(run)
	_assert(run.choix_ouvert, "choix Extraire / Continuer ouvert sur la Fin d'étage")
	run.extraire()
	EventBus.euren_change.disconnect(cb)
	_assert(absf(run.euren_credite - 42.0) < 0.001, "extraction : euren_credite = accumulé")
	_assert(absf(ProgressionHeros.euren() - 42.0) < 0.001, "portefeuille crédité de 42")
	_assert(totaux == [42.0], "euren_change émis une fois avec le total", str(totaux))
	_reset_progression()

# Complétion (dernier étage bouclé) : crédité aussi — flux réel avec combats.
func _test_completion_credite() -> void:
	print("\n[TEST] Complétion — Euren crédité en flux réel (3 étages)")
	_reset_progression()
	var run := _run(_cfg_tout_combat(), 2024, _avatar(1000000.0, 100000.0, 60.0))
	var garde := 0
	while not run.est_terminee and garde < 20:
		garde += 1
		_marcher_vers_fin(run)
		if run.choix_ouvert:
			run.continuer()
	_assert(run.est_terminee and not run.defaite, "expédition bouclée sans défaite")
	var recap := run._recap(false)
	_assert(bool(recap["complete"]), "recap : complete = true")
	_assert(run.euren_accumule > 0.0, "de l'Euren a été accumulé en chemin")
	_assert(absf(run.euren_credite - run.euren_accumule) < 0.001,
			"complétion : la totalité de l'accumulé est créditée")
	_assert(absf(ProgressionHeros.euren() - run.euren_credite) < 0.001,
			"portefeuille = crédité")
	_assert(absf(float(recap["xp_gagnee"]) - run.xp_gagnee) < 0.001
			and run.xp_gagnee > 0.0, "recap : xp_gagnee (information) > 0")
	_reset_progression()

# ─── Persistance ────────────────────────────────────────────

# Round-trip _save_player/_load_player SANS disque : les champs heros_xp et
# euren voyagent dans le dict player (persistance automatique par conception).
func _test_persistance_sauvegarde() -> void:
	print("\n[TEST] Persistance — heros_xp / euren dans GameData.player")
	_reset_progression()
	GameData.player["heros_xp"] = 520.0
	GameData.player["euren"] = 77.0
	var sauve: Dictionary = SaveManager._save_player()
	_assert(absf(float(sauve.get("heros_xp", -1.0)) - 520.0) < 0.001
			and absf(float(sauve.get("euren", -1.0)) - 77.0) < 0.001,
			"_save_player emporte heros_xp et euren")
	GameData.player["heros_xp"] = 0.0
	GameData.player["euren"] = 0.0
	SaveManager._load_player({"player": sauve})
	_assert(absf(ProgressionHeros.xp_totale() - 520.0) < 0.001
			and absf(ProgressionHeros.euren() - 77.0) < 0.001,
			"_load_player restaure heros_xp (niveau 3) et euren")
	_assert(ProgressionHeros.niveau() == 3, "niveau DÉRIVÉ de l'XP restaurée (520 → 3)")
	_reset_progression()

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ économie de récompense conforme")
	print("════════════════════════════════\n")
