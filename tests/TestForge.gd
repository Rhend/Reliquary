extends Node
# Tests de la Forge (Chantier 5) :
#   • évolution de palier (XP-seuil, lot de points + conversion overflow, sans buffer),
#   • achat de nœuds (connexité, gate de strate, coût en points, ingrédient keystone),
#   • agrégation des bonus par stat (équipement ÉQUIPÉ seulement) + effets de règle,
#   • réduction de coût par les bonus Forge du village (Chantier 4).
#
# Aucune écriture de sauvegarde (listeners SaveManager coupés).

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_disable_save_writes()
	_run_all()
	_print_report()
	get_tree().quit(1 if _results.any(func(r): return not r["ok"]) else 0)

func _disable_save_writes() -> void:
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false

func _assert(cond: bool, label: String, detail: String = "") -> void:
	_results.append({"ok": cond, "label": label})
	print(("  ✓ " if cond else "  ✗ ") + label + (" — " + detail if (detail != "" and not cond) else ""))

func _print_report() -> void:
	var passed := _results.filter(func(r): return r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, _results.size(), _results.size() - passed])
	print("════════════════════════════════\n")

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

# Remet l'arme à un état neuf (palier, XP, forge, équipée), village/ressources nets.
func _reset_arme(tier: int) -> void:
	var arme := GameData.get_entity("equipment_arme")
	arme["est_debloque"] = true
	arme["maitrise_actuelle"] = tier
	arme["xp_maitrise_actuelle"] = 0.0
	GameData.player["equipped"] = {"arme": "equipment_arme", "anneau": "", "armure": "",
			"ceinture": "", "bouclier": "", "talisman": ""}
	GameData.player["forge"] = {}
	GameData.player["resources"] = {}
	GameData.village["buildings"] = {}
	VillageBuildings.refresh_bonuses()
	ForgeSystem.refresh_bonuses()

# ─── Tests ──────────────────────────────────────────────────

func _run_all() -> void:
	print("\n=== TEST FORGE (Chantier 5) ===\n")
	_test_trees_loaded()
	_test_palier_evolution()
	_test_node_access()
	_test_keystone_ingredient()
	_test_bonus_aggregation()
	_test_combat_rules()
	_test_village_reduction()
	_test_tree_overlay_smoke()

func _test_trees_loaded() -> void:
	print("[TEST 1] Arbres chargés")
	for tid in ["tree_arme", "tree_anneau", "tree_armure"]:
		var t := GameData.get_entity(tid)
		_assert(not t.is_empty() and (t.get("nodes", []) as Array).size() == 12,
				"%s : 12 nœuds (S1=5 + S2=7)" % tid,
				"obtenu %d" % (t.get("nodes", []) as Array).size())

func _test_palier_evolution() -> void:
	print("\n[TEST 2] Évolution de palier (lot + conversion overflow, sans buffer)")
	_reset_arme(0)
	var arme := GameData.get_entity("equipment_arme")
	arme["xp_maitrise_actuelle"] = 60.0  # < coût 100
	_assert(not ForgeSystem.can_evolve_equipment("equipment_arme"), "XP insuffisante → pas d'évolution")
	arme["xp_maitrise_actuelle"] = 150.0  # coût 100, overflow 50 → +2 pts
	_assert(ForgeSystem.can_evolve_equipment("equipment_arme"), "XP suffisante → évolution possible")
	var nt := ForgeSystem.evolve_equipment("equipment_arme")
	_assert(nt == 1, "Arme T0 → T1", "obtenu %d" % nt)
	_assert(_approx(float(arme["xp_maitrise_actuelle"]), 0.0), "XP remise à 0 (pas de buffer)")
	_assert(ForgeSystem.points("equipment_arme") == 122,
			"points = lot 120 + floor(50/25)=2 → 122", "obtenu %d" % ForgeSystem.points("equipment_arme"))

func _test_node_access() -> void:
	print("\n[TEST 3] Accès aux nœuds (connexité + gate de strate)")
	_reset_arme(1)  # strate 1 ouverte, strate 2 non
	GameData.player["forge"] = {"equipment_arme": {"points": 200, "nodes": []}}
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s1_tranchant1") == "available",
			"racine S1 disponible à T1")
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s1_tranchant3") == "locked_connexite",
			"nœud S1 sans voisin acquis → connexité verrouillée")
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s2_tranchant4") == "locked_strate",
			"nœud S2 verrouillé tant que l'équip. n'est pas T2")
	# Achat racine puis voisin.
	_assert(ForgeSystem.buy_node("equipment_arme", "arme_s1_tranchant1"), "achat racine")
	_assert(ForgeSystem.points("equipment_arme") == 185, "coût mineur S1 = 15 (200→185)",
			"obtenu %d" % ForgeSystem.points("equipment_arme"))
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s1_tranchant2") == "available",
			"voisin de la racine devient disponible")
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s1_tranchant3") == "locked_connexite",
			"nœud encore non connecté reste verrouillé")

func _test_keystone_ingredient() -> void:
	print("\n[TEST 4] Keystone : points + ingrédient rare")
	_reset_arme(2)  # strate 2 ouverte
	# Chemin jusqu'au keystone déjà acquis (voisin Saignée), points abondants.
	GameData.player["forge"] = {"equipment_arme": {"points": 500, "nodes": ["arme_s2_saignee"]}}
	_assert(ForgeSystem.node_state("equipment_arme", "arme_s2_fendoir") == "available",
			"keystone disponible (voisin acquis + strate ouverte)")
	GameData.player["resources"] = {}
	_assert(not ForgeSystem.can_buy_node("equipment_arme", "arme_s2_fendoir"),
			"sans ingrédient rare → keystone non achetable")
	GameData.player["resources"] = {"res_mineral_fer": 3}
	_assert(ForgeSystem.can_buy_node("equipment_arme", "arme_s2_fendoir"),
			"avec 3 ingrédients rares → achetable")
	ForgeSystem.buy_node("equipment_arme", "arme_s2_fendoir")
	_assert(ForgeSystem.node_owned("equipment_arme", "arme_s2_fendoir"), "keystone acquis")
	_assert(int(GameData.player["resources"].get("res_mineral_fer", 0)) == 0,
			"3 ingrédients consommés", str(GameData.player["resources"]))
	_assert(ForgeSystem.points("equipment_arme") == 410, "90 pts consommés (500→410)",
			"obtenu %d" % ForgeSystem.points("equipment_arme"))

func _test_bonus_aggregation() -> void:
	print("\n[TEST 5] Agrégation des bonus (équipement équipé)")
	_reset_arme(1)
	# Deux mineurs ATK de S1 (barème 0.15 chacun) → +30 % ATK.
	GameData.player["forge"] = {"equipment_arme": {"points": 0,
			"nodes": ["arme_s1_tranchant1", "arme_s1_tranchant2"]}}
	ForgeSystem.refresh_bonuses()
	_assert(_approx(ForgeSystem.get_stat_bonus("atk_pct"), 0.30),
			"2 mineurs ATK S1 → atk_pct = 0.30", "%.3f" % ForgeSystem.get_stat_bonus("atk_pct"))
	# Mordant (notable S1, atk 0.33 + crit annexe 0.01).
	GameData.player["forge"]["equipment_arme"]["nodes"].append("arme_s1_mordant")
	ForgeSystem.refresh_bonuses()
	_assert(_approx(ForgeSystem.get_stat_bonus("atk_pct"), 0.63),
			"+ Mordant → atk_pct = 0.63", "%.3f" % ForgeSystem.get_stat_bonus("atk_pct"))
	_assert(_approx(ForgeSystem.get_stat_bonus("crit_pct"), 0.01),
			"Mordant → crit_pct annexe = 0.01", "%.3f" % ForgeSystem.get_stat_bonus("crit_pct"))
	# Déséquiper l'arme → plus aucun bonus.
	GameData.player["equipped"]["arme"] = ""
	ForgeSystem.refresh_bonuses()
	_assert(_approx(ForgeSystem.get_stat_bonus("atk_pct"), 0.0),
			"arme déséquipée → atk_pct = 0")

func _test_combat_rules() -> void:
	print("\n[TEST 6] Effets de règle (notables / keystones)")
	_reset_arme(2)
	GameData.player["forge"] = {"equipment_arme": {"points": 0,
			"nodes": ["arme_s2_briseur", "arme_s2_saignee", "arme_s2_fendoir"]}}
	ForgeSystem.refresh_bonuses()
	var r := ForgeSystem.combat_rules()
	_assert(_approx(float(r.get("def_ignore_pct", 0.0)), 0.05),
			"Briseur de garde → def_ignore_pct = 0.05")
	_assert(_approx(float(r.get("endurcissement_counter_pct", 0.0)), 0.15),
			"Fendoir → endurcissement_counter_pct = 0.15")
	_assert(not (r.get("residual", {}) as Dictionary).is_empty(),
			"Saignée → résidu présent")

func _test_village_reduction() -> void:
	print("\n[TEST 7] Réduction de coût par le village (Forgeron T0 : −5 % pts Arme)")
	_reset_arme(1)
	GameData.village["buildings"] = {"bat_forgeron": 0}
	VillageBuildings.refresh_bonuses()
	var node := {"strate": 1, "type": "mineur"}
	# 15 × (1 − 0.05) = 14.25 → arrondi 14.
	_assert(ForgeSystem.node_point_cost("equipment_arme", node) == 14,
			"coût mineur S1 réduit à 14", "obtenu %d" % ForgeSystem.node_point_cost("equipment_arme", node))

func _test_tree_overlay_smoke() -> void:
	print("\n[TEST 8] Rendu ForgeTreeOverlay (spatial)")
	_reset_arme(2)
	GameData.player["forge"] = {"equipment_arme": {"points": 200,
			"nodes": ["arme_s1_tranchant1", "arme_s1_tranchant2"]}}
	var overlay := ForgeTreeOverlay.new()
	overlay.equipment_id = "equipment_arme"
	add_child(overlay)
	await get_tree().process_frame
	_assert(overlay.get_child_count() > 0, "overlay : contenu rendu sans crash",
			"%d enfants" % overlay.get_child_count())
	overlay.free()
