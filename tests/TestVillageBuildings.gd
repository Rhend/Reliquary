extends Node
# Tests du système Quartiers / Bâtiments (Chantier 4 ; coûts refondus au
# chantier 12 — rework économique du QG) :
#   • chargement des 10 bâtiments,
#   • courbe de coût UNIQUE Euren + Modules (couts_batiments.tres) — plus
#     JAMAIS de ressource de biome demandée par un bâtiment,
#   • amélioration de bâtiment (payable/refusée selon les soldes, débit
#     exact, palier max, plus aucun gate de route),
#   • agrégation des bonus par canal (sum / max / or) + accesseurs dérivés,
#   • bâtiment gelé (Couturier) et registre sans bonus (Reliquaire).
#
# Aucune écriture de sauvegarde : les listeners de SaveManager sont coupés.

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

# ─── Helpers ────────────────────────────────────────────────

func _assert(cond: bool, label: String, detail: String = "") -> void:
	_results.append({"ok": cond, "label": label})
	print(("  ✓ " if cond else "  ✗ ") + label + (" — " + detail if (detail != "" and not cond) else ""))

func _print_report() -> void:
	var passed := _results.filter(func(r): return r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, _results.size(), _results.size() - passed])
	print("════════════════════════════════\n")

# Réinitialise l'état village et place UN bâtiment au palier `tier`, puis
# recalcule le cache de bonus global.
func _set_only(building_id: String, tier: int) -> void:
	GameData.village["buildings"] = { building_id: tier }
	VillageBuildings.refresh_bonuses()

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _set_soldes(euren: float, modules: int) -> void:
	GameData.player["euren"] = euren
	GameData.player["modules"] = modules

# ─── Tests ──────────────────────────────────────────────────

func _run_all() -> void:
	print("\n=== TEST VILLAGE BUILDINGS (Chantier 4 + coûts chantier 12) ===\n")
	_test_loaded()
	_test_cost_curve()
	_test_building_upgrade()
	_test_bonus_aggregation()
	_test_gauge_and_special()
	_test_frozen_and_registry()
	_test_panel_smoke()

func _test_loaded() -> void:
	print("[TEST 1] Bâtiments chargés")
	var ids := ["bat_maison", "bat_jardin", "bat_salle", "bat_reliquaire",
			"bat_tour", "bat_palissade", "bat_forgeron", "bat_armurier",
			"bat_joaillier", "bat_couturier"]
	for bid in ids:
		var b := GameData.get_entity(bid)
		_assert(not b.is_empty() and b.get("entity_type", "") == Enums.EntityType.BUILDING,
				"%s chargé (type building)" % bid)

func _test_cost_curve() -> void:
	print("\n[TEST 2] Courbe de coût Euren + Modules (chantier 12, table actée)")
	var euren_attendu := [100.0, 160.0, 260.0, 420.0, 670.0, 1070.0]
	var modules_attendu := [0, 0, 1, 2, 3, 4]
	for cible in 6:
		var c := VillageBuildings.COUTS.cout(cible)
		_assert(_approx(float(c.get("euren", -1.0)), euren_attendu[cible])
				and int(c.get("modules", -1)) == modules_attendu[cible],
				"palier cible %d → %d Euren + %d Module(s)" % [cible,
						int(euren_attendu[cible]), modules_attendu[cible]],
				"obtenu %s" % str(c))
	_assert(VillageBuildings.COUTS.cout(-1).is_empty()
			and VillageBuildings.COUTS.cout(6).is_empty(), "hors courbe → {}")
	_assert(Balance.BUILDING_MAX_TIER == 5 and Balance.BUILDING_TIER_DELABRE == -1,
			"max=5, Délabré=-1")

	# building_cost : courbe COMMUNE (même coût quel que soit le bâtiment) et
	# plus JAMAIS de ressource de biome dans le coût.
	for bid in ["bat_maison", "bat_tour", "bat_forgeron"]:
		GameData.village["buildings"] = { bid: 1 }
		var cost := VillageBuildings.building_cost(bid)
		_assert(_approx(float(cost.get("euren", 0.0)), 260.0)
				and int(cost.get("modules", 0)) == 1,
				"%s (T1→T2) → 260 Euren + 1 Module (courbe commune)" % bid,
				"obtenu %s" % str(cost))
		var sans_res := true
		for k in cost:
			if str(k).begins_with("res_"):
				sans_res = false
		_assert(sans_res, "%s : aucune ressource de biome demandée" % bid, str(cost))
	# Au palier max : plus de coût.
	GameData.village["buildings"] = { "bat_maison": 5 }
	_assert(VillageBuildings.building_cost("bat_maison").is_empty(), "palier max → coût vide")

func _test_building_upgrade() -> void:
	print("\n[TEST 3] Amélioration : soldes vérifiés, débit exact, refus")
	GameData.village["buildings"] = {}
	# Délabré → T0 : 100 Euren, 0 Module. Les ressources de biome à ZÉRO :
	# elles ne doivent jouer aucun rôle.
	GameData.player["resources"] = {}
	_set_soldes(99.0, 0)
	_assert(not VillageBuildings.can_upgrade_building("bat_maison"),
			"99 Euren < 100 → refus")
	_assert(VillageBuildings.upgrade_building("bat_maison") == Balance.BUILDING_TIER_DELABRE - 1,
			"upgrade refusé (retour -2)")
	_set_soldes(150.0, 0)
	_assert(VillageBuildings.can_upgrade_building("bat_maison"),
			"150 Euren, 0 Module → payable (aucune route requise, ressources à 0)")
	var nt := VillageBuildings.upgrade_building("bat_maison")
	_assert(nt == 0, "Maison Délabré → T0", "obtenu %d" % nt)
	_assert(_approx(ProgressionHeros.euren(), 50.0), "débit exact : 150 − 100 = 50 Euren",
			"%f" % ProgressionHeros.euren())
	_assert(ProgressionHeros.modules() == 0, "0 Module débité (palier sans Module)")

	# T1 → T2 : le Module entre en jeu. Euren suffisant mais 0 Module → refus.
	GameData.village["buildings"] = { "bat_maison": 1 }
	_set_soldes(1000.0, 0)
	_assert(not VillageBuildings.can_upgrade_building("bat_maison"),
			"1000 Euren mais 0 Module → refus (T2 exige 1 Module)")
	_set_soldes(1000.0, 3)
	_assert(VillageBuildings.can_upgrade_building("bat_maison"), "1000 Euren + 3 Modules → payable")
	_assert(VillageBuildings.upgrade_building("bat_maison") == 2, "Maison T1 → T2")
	_assert(_approx(ProgressionHeros.euren(), 740.0) and ProgressionHeros.modules() == 2,
			"débit exact : −260 Euren, −1 Module",
			"euren %f, modules %d" % [ProgressionHeros.euren(), ProgressionHeros.modules()])
	_set_soldes(0.0, 0)

func _test_bonus_aggregation() -> void:
	print("\n[TEST 4] Agrégation des bonus (cumul incrémental)")
	# Salle d'entraînement à T4 : atk_pct 0.03+0.05+0.08, def_pct 0.03+0.05.
	_set_only("bat_salle", 4)
	_assert(_approx(VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT), 0.16),
			"Salle T4 → ATK% = 0.16", "%.3f" % VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT))
	_assert(_approx(VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT), 0.08),
			"Salle T4 → DEF% = 0.08", "%.3f" % VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT))
	# building_effects (par bâtiment) cohérent avec le cache global ici.
	var eff := VillageBuildings.building_effects("bat_salle", 4)
	_assert(_approx(float(eff.get(VillageBuildings.CH_ATK_PCT, 0.0)), 0.16),
			"building_effects Salle T4 ATK% = 0.16")
	# Jardin T5 : bless_effect_pct cumulé = 0.50.
	_set_only("bat_jardin", 5)
	_assert(_approx(VillageBuildings.get_bonus(VillageBuildings.CH_BLESS_EFFECT_PCT), 0.50),
			"Jardin T5 → effet bénédiction = 0.50",
			"%.3f" % VillageBuildings.get_bonus(VillageBuildings.CH_BLESS_EFFECT_PCT))
	_assert(int(VillageBuildings.get_bonus(VillageBuildings.CH_DEBUFF_REDUCTION)) == 1,
			"Jardin T5 → réduction debuff = 1")

func _test_gauge_and_special() -> void:
	print("\n[TEST 5] Canaux MAX / OR + accesseurs dérivés")
	# Tour de Guet : jauge anti-embuscade prend le MAX (0.25@T1, 0.50@T3) = 0.50.
	_set_only("bat_tour", 3)
	_assert(_approx(VillageBuildings.get_bonus(VillageBuildings.CH_AMBUSH_GAUGE), 0.50),
			"Tour T3 → jauge embuscade = 0.50 (max, pas somme)")
	_assert(_approx(VillageBuildings.hero_gauge_start(true), 0.50), "gauge_start(embuscade) = 0.50")
	_assert(_approx(VillageBuildings.hero_gauge_start(false), 0.0), "gauge_start(hors embuscade) = 0 (avant T5)")
	# Tour T5 : 0.25 sur toute expédition ; embuscade reste à 0.50.
	_set_only("bat_tour", 5)
	_assert(_approx(VillageBuildings.hero_gauge_start(false), 0.25), "T5 → 0.25 toute expédition")
	_assert(_approx(VillageBuildings.hero_gauge_start(true), 0.50), "T5 → 0.50 sous embuscade (max)")
	# Palissade T5 : filet anti-mort (OR).
	_set_only("bat_palissade", 4)
	_assert(not VillageBuildings.has_lethal_shield(), "Palissade T4 → pas de filet")
	_set_only("bat_palissade", 5)
	_assert(VillageBuildings.has_lethal_shield(), "Palissade T5 → filet anti-mort actif")
	# Jardin T5 : immunité aux debuffs des créatures ≤ T3.
	_set_only("bat_jardin", 5)
	_assert(VillageBuildings.poison_immune_for_tier(3), "Jardin T5 → immunité créature T3")
	_assert(not VillageBuildings.poison_immune_for_tier(4), "Jardin T5 → PAS d'immunité créature T4")
	_set_only("bat_jardin", 4)
	_assert(not VillageBuildings.poison_immune_for_tier(3), "Jardin T4 → pas encore d'immunité")

func _test_frozen_and_registry() -> void:
	print("\n[TEST 6] Gelé (Couturier) & registre sans bonus (Reliquaire)")
	GameData.village["buildings"] = {"bat_couturier": -1}
	_set_soldes(99999.0, 99)
	_assert(VillageBuildings.building_cost("bat_couturier").is_empty(), "Couturier gelé → coût vide")
	_assert(not VillageBuildings.can_upgrade_building("bat_couturier"), "Couturier gelé → non améliorable")
	# Reliquaire : améliorable mais aucun bonus de stat.
	_set_only("bat_reliquaire", 5)
	_assert(VillageBuildings.building_effects("bat_reliquaire", 5).is_empty(),
			"Reliquaire → aucun bonus de stat (registre)")
	_set_soldes(0.0, 0)

# Fume-test du rendu : BuildingPanel ne touche que host.rp_content → on le pilote
# avec une instance Village nue (hors arbre, _ready non déclenché). Couvre les
# deux états (gelé, gestion) sans crash de mise en page.
func _test_panel_smoke() -> void:
	print("\n[TEST 7] Rendu BuildingPanel (2 états)")
	var v := Village.new()
	var cases := [
		["gelé (Couturier)", "bat_couturier", func() -> void:
			GameData.village["buildings"] = {}],
		["gestion", "bat_salle", func() -> void:
			GameData.village["buildings"] = {"bat_salle": 2}],
	]
	_set_soldes(500.0, 2)
	for case in cases:
		(case[2] as Callable).call()
		v.rp_content = VBoxContainer.new()
		BuildingPanel.build(v, case[1] as String)
		_assert(v.rp_content.get_child_count() > 0, "panneau « %s » : contenu rendu" % case[0],
				"0 enfant")
		v.rp_content.free()
	_set_soldes(0.0, 0)
	v.free()
