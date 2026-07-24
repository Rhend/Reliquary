# ============================================================
# SimulateurEquilibrage — Outil DEV : joue N runs d'expédition AUTOMATIQUES
# par (Lieu × palier) et imprime un rapport agrégé — la base MESURABLE du
# calibrage des valeurs provisoires (butin, Euren, XP, mécaniques, PV).
#
#   godot --headless --path . res://tools/SimulateurEquilibrage.tscn
#
# Variables d'environnement :
#   SIM_RUNS   — nb de runs par combinaison (défaut 20)
#   SIM_GRAINE — graine de base (défaut 1000 ; run i = graine + i)
#   SIM_HEROS  — "neuf" (défaut : héros de partie neuve, équipement de
#                départ ch.13, reproductible) ou "reel" (sauvegarde réelle)
#   SIM_POLITIQUE — "complet" (défaut : résout TOUT, continue toujours —
#                   le grind maximal) ou "prudent" (droit à la Fin
#                   d'étage 1, extraction — le run de survie minimal)
#
# Les chiffres n'ont de sens que RELATIVEMENT à la politique jouée.
# Combats déroulés en auto (IA du moteur des deux côtés).
#
# ⚠ N'ÉCRIT JAMAIS la sauvegarde : listeners SaveManager déconnectés
# (incident 2026-06-12 — règle absolue des outils de simulation). L'état
# GameData mutations (XP, ressources) reste local au process.
# ============================================================
extends Node

const LIEUX: Array[String] = ["biome_foret", "biome_marecage", "biome_montagne"]
const PALIERS: Array[String] = ["palier_peripherie", "palier_enceinte", "palier_noyau"]

func _ready() -> void:
	_deconnecter_sauvegarde()
	var nb_runs := maxi(int(OS.get_environment("SIM_RUNS").to_int()), 1) \
			if OS.get_environment("SIM_RUNS") != "" else 20
	var graine_base := int(OS.get_environment("SIM_GRAINE").to_int()) \
			if OS.get_environment("SIM_GRAINE") != "" else 1000
	var avatar := _heros()
	_prudent = OS.get_environment("SIM_POLITIQUE") == "prudent"
	print("\n═══ SIMULATEUR D'ÉQUILIBRAGE — %d runs × %d Lieux × %d paliers — politique %s ═══" % [
			nb_runs, LIEUX.size(), PALIERS.size(), "PRUDENTE" if _prudent else "COMPLÈTE"])
	print("Héros : %s — PV %d · ATK %d · DEF %d · VIT %d\n" % [
			avatar.nom_affichage_fr, int(avatar.pv_max), int(avatar.atk),
			int(avatar.def), int(avatar.vit)])
	for lieu in LIEUX:
		for palier_id in PALIERS:
			var stats := _simuler(lieu, palier_id, nb_runs, graine_base, avatar)
			_imprimer(lieu, palier_id, stats, nb_runs)
	get_tree().quit(0)

# ─── Simulation d'une combinaison ────────────────────────────

func _simuler(lieu: String, palier_id: String, nb: int, graine_base: int,
		avatar: CombattantCtbData) -> Dictionary:
	var s := {
		"victoires": 0, "defaites": 0, "etages": 0.0, "combats": 0.0,
		"xp": 0.0, "euren": 0.0, "butin": {}, "pv_fin_pct": 0.0,
	}
	for i in nb:
		# Les VRAIES configs du jeu (mêmes .tres qu'ExpeditionScreen).
		var run := ExpeRun.new(
				load("res://data/expedition/config_carte.tres"),
				load("res://data/expedition/%s.tres" % palier_id),
				lieu, graine_base + i, avatar,
				(load("res://data/expedition/destinations.tres") as ExpeDestinationsData)
						.pool_pour(lieu),
				load("res://data/expedition/config_combat.tres"))
		run.demarrer()
		_jouer(run)
		s["etages"] += run.etage
		s["combats"] += run.nb_combats
		s["xp"] += run.xp_gagnee
		s["euren"] += run.euren_credite
		if run.defaite:
			s["defaites"] += 1
		else:
			s["victoires"] += 1
			s["pv_fin_pct"] += run.pv_avatar / maxf(run.pv_max_effectif(), 1.0)
		for rid: String in run.butin_credite:
			s["butin"][rid] = int(s["butin"].get(rid, 0)) + int(run.butin_credite[rid])
	return s

var _prudent := false

# Politiques : COMPLÈTE = tout résoudre, toujours continuer (grind maximal) ;
# PRUDENTE = droit à la Fin d'étage, extraction dès que possible.
func _jouer(run: ExpeRun) -> void:
	var garde := 0
	while not run.est_terminee and garde < 500:
		garde += 1
		if run.choix_ouvert:
			if _prudent:
				run.extraire()
			else:
				run.continuer()
			continue
		var chemin: Array[int] = []
		if not _prudent:
			chemin = _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
				return not nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE)
		if chemin.is_empty():
			chemin = _chemin_vers(run, func(nd: ExpeNoeud) -> bool:
				return nd.type == Enums.TypeNoeud.FIN_ETAGE or nd.type == Enums.TypeNoeud.BOSS)
		if chemin.is_empty():
			return
		for nid in chemin:
			run.deplacer_vers(nid)
			if run.combat_en_cours != null:
				run.combat_en_cours.derouler_auto()
			if run.est_terminee or run.choix_ouvert:
				break

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

# ─── Rapport ─────────────────────────────────────────────────

func _imprimer(lieu: String, palier_id: String, s: Dictionary, nb: int) -> void:
	var v := int(s["victoires"])
	var butin_txt: PackedStringArray = []
	for rid: String in s["butin"]:
		butin_txt.append("%s %.1f/run" % [rid, float(s["butin"][rid]) / nb])
	print("%-16s %-18s | sorties vivantes %2d/%2d | étages %.1f | combats %4.1f | XP %6.0f | Euren %5.0f | PV fin %3.0f %% | %s" % [
			lieu, palier_id, v, nb,
			float(s["etages"]) / nb, float(s["combats"]) / nb,
			float(s["xp"]) / nb, float(s["euren"]) / nb,
			(float(s["pv_fin_pct"]) / maxf(v, 1)) * 100.0,
			", ".join(butin_txt) if not butin_txt.is_empty() else "aucun butin"])

# ─── Héros simulé ────────────────────────────────────────────

func _heros() -> CombattantCtbData:
	if OS.get_environment("SIM_HEROS") == "reel":
		SaveManager.load_save()
	else:
		# Partie NEUVE reproductible : équipement de départ Commun (ch.13).
		GameData.appliquer_equipement_depart()
	var h := CtbPont.combattant_depuis_heros()
	assert(h != null, "pont héros indisponible")
	return h

# Incident 2026-06-12 : un outil qui émet des signaux de progression peut
# déclencher une ÉCRITURE de la vraie sauvegarde. Déconnexion totale.
func _deconnecter_sauvegarde() -> void:
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
