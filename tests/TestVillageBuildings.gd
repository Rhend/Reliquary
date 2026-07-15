extends Node
# Tests du système Quartiers / Routes / Bâtiments (Chantier 4) :
#   • chargement des 10 bâtiments,
#   • courbe de coût UNIQUE résolue contre l'assignation de biome,
#   • reconstruction de route (consommation + gate Forge),
#   • amélioration de bâtiment (route requise, consommation, palier max),
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
	GameData.village["routes"]    = {}
	VillageBuildings.refresh_bonuses()

func _set_tier(building_id: String, tier: int) -> void:
	GameData.village["buildings"][building_id] = tier

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

# ─── Tests ──────────────────────────────────────────────────

func _run_all() -> void:
	print("\n=== TEST VILLAGE BUILDINGS (Chantier 4) ===\n")
	_test_loaded()
	_test_cost_curve_constants()
	_test_building_cost_resolution()
	_test_route_rebuild()
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

func _test_cost_curve_constants() -> void:
	print("\n[TEST 2] Constantes de courbe")
	_assert(_approx(Balance.BUILDING_COST_BASE, 20.0), "base = 20")
	_assert(_approx(Balance.BUILDING_COST_GROWTH, 1.6), "raison = 1.6")
	var freq := []
	for s in Balance.BUILDING_COST_STEPS:
		freq.append(int(s["freq"]))
	_assert(freq == [20, 32, 40, 52, 68, 90], "fréquentes = [20,32,40,52,68,90]", str(freq))
	_assert(Balance.BUILDING_MAX_TIER == 5 and Balance.BUILDING_TIER_DELABRE == -1,
			"max=5, Délabré=-1")

func _test_building_cost_resolution() -> void:
	print("\n[TEST 3] Résolution du coût (Maison : Forêt + Marécage + Montagne)")
	# Maison : principal Forêt (fourrure/venin), additionnels [marécage(slime), montagne(pierre)].
	var expected := {
		-1: {"res_fourrure": 20},
		0:  {"res_fourrure": 32},
		1:  {"res_fourrure": 40, "res_venin": 3},
		2:  {"res_fourrure": 52, "res_venin": 5, "res_slime": 10},
		3:  {"res_fourrure": 68, "res_venin": 7, "res_slime": 14, "res_pierre": 14},
		4:  {"res_fourrure": 90, "res_venin": 10, "res_slime": 18, "res_pierre": 18},
	}
	for cur in expected:
		_set_tier_isolated("bat_maison", cur)
		var got := VillageBuildings.building_cost("bat_maison")
		_assert(got == expected[cur], "palier %d → %s" % [cur, str(expected[cur])], "obtenu %s" % str(got))
	# Au palier max : plus de coût.
	_set_tier_isolated("bat_maison", 5)
	_assert(VillageBuildings.building_cost("bat_maison").is_empty(), "palier max → coût vide")

func _set_tier_isolated(building_id: String, tier: int) -> void:
	GameData.village["buildings"] = { building_id: tier }

func _test_route_rebuild() -> void:
	print("\n[TEST 4] Reconstruction de route")
	GameData.village["routes"] = {}
	GameData.village["maitrise_actuelle"] = 0
	_assert(VillageBuildings.route_cost("hero") == {"res_fourrure": 12}, "coût route Héros = 12 fourrure")

	GameData.player["resources"] = {"res_fourrure": 20}
	_assert(VillageBuildings.can_rebuild_route("hero"), "route Héros reconstructible avec ressources")
	_assert(VillageBuildings.rebuild_route("hero"), "rebuild_route Héros → true")
	_assert(VillageBuildings.route_built("hero"), "route Héros marquée reconstruite")
	_assert(int(GameData.player["resources"]["res_fourrure"]) == 8, "12 fourrure consommées (reste 8)",
			str(GameData.player["resources"]))
	_assert(not VillageBuildings.can_rebuild_route("hero"), "route déjà faite → non reconstructible")

	# Route Forge : gated tant que le Village n'est pas Peu Commun (T1).
	GameData.player["resources"] = {"res_pierre": 50}
	GameData.village["maitrise_actuelle"] = 0
	_assert(not VillageBuildings.can_rebuild_route("forge"), "route Forge bloquée (Village T0)")
	GameData.village["maitrise_actuelle"] = 1
	_assert(VillageBuildings.can_rebuild_route("forge"), "route Forge dispo (Village T1) avec ressources")

func _test_building_upgrade() -> void:
	print("\n[TEST 5] Amélioration de bâtiment")
	GameData.village["buildings"] = {}
	GameData.village["routes"]    = {}
	GameData.player["resources"]  = {"res_fourrure": 100}
	# Sans route : pas d'amélioration possible.
	_assert(not VillageBuildings.can_upgrade_building("bat_maison"), "sans route → non améliorable")
	GameData.village["routes"] = {"hero": true}
	_assert(VillageBuildings.can_upgrade_building("bat_maison"), "avec route + ressources → améliorable")
	var nt := VillageBuildings.upgrade_building("bat_maison")
	_assert(nt == 0, "Maison Délabré → T0", "obtenu %d" % nt)
	_assert(VillageBuildings.building_tier("bat_maison") == 0, "palier persisté = 0")
	_assert(int(GameData.player["resources"]["res_fourrure"]) == 80, "20 fourrure consommées (reste 80)",
			str(GameData.player["resources"]))

func _test_bonus_aggregation() -> void:
	print("\n[TEST 6] Agrégation des bonus (cumul incrémental)")
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
	print("\n[TEST 7] Canaux MAX / OR + accesseurs dérivés")
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
	print("\n[TEST 8] Gelé (Couturier) & registre sans bonus (Reliquaire)")
	GameData.village["buildings"] = {"bat_couturier": -1}
	GameData.village["routes"]    = {"forge": true}
	GameData.player["resources"]  = {"res_pierre": 999, "res_slime": 999, "res_fourrure": 999}
	_assert(VillageBuildings.building_cost("bat_couturier").is_empty(), "Couturier gelé → coût vide")
	_assert(not VillageBuildings.can_upgrade_building("bat_couturier"), "Couturier gelé → non améliorable")
	# Reliquaire : améliorable mais aucun bonus de stat.
	_set_only("bat_reliquaire", 5)
	_assert(VillageBuildings.building_effects("bat_reliquaire", 5).is_empty(),
			"Reliquaire → aucun bonus de stat (registre)")

# Fume-test du rendu : BuildingPanel ne touche que host.rp_content → on le pilote
# avec une instance Village nue (hors arbre, _ready non déclenché). Couvre les
# trois états (route à faire, gelé, gestion) sans crash de mise en page.
func _test_panel_smoke() -> void:
	print("\n[TEST 9] Rendu BuildingPanel (3 états)")
	var v := Village.new()
	var cases := [
		["route non reconstruite", func() -> void:
			GameData.village["routes"] = {}; GameData.village["buildings"] = {}],
		["gelé (Couturier)", func() -> void:
			GameData.village["routes"] = {"forge": true}],
		["gestion (route faite)", func() -> void:
			GameData.village["routes"] = {"hero": true}
			GameData.village["buildings"] = {"bat_salle": 2}],
	]
	GameData.player["resources"] = {"res_pierre": 999, "res_fourrure": 999, "res_venin": 999}
	for case in cases:
		(case[1] as Callable).call()
		v.rp_content = VBoxContainer.new()
		var bid := "bat_couturier" if case[0] == "gelé (Couturier)" else \
				("bat_salle" if case[0] == "gestion (route faite)" else "bat_maison")
		BuildingPanel.build(v, bid)
		_assert(v.rp_content.get_child_count() > 0, "panneau « %s » : contenu rendu" % case[0],
				"0 enfant")
		v.rp_content.free()
	v.free()
