extends Node
# Test du flux expédition → CycleSummaryScreen
# Vérifie : tracking stats, sauvegarde CycleData, navigation

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all()
	_print_report()
	get_tree().quit()

func _run_all() -> void:
	print("\n=== TEST FLUX EXPÉDITION ===\n")
	_test_adventure_system_tracking()
	_test_cycle_data_stop()
	_test_cycle_data_end()
	_test_cycle_summary_screen_keys()

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

# ─── Test 1 : variables de tracking déclarées et initialisées ───

func _test_adventure_system_tracking() -> void:
	print("[TEST 1] Variables de tracking AdventureSystem")

	# Vérifie que les propriétés existent (accès sans erreur)
	var ok := true
	var props := [
		"_cycle_events_total", "_cycle_positive_events", "_cycle_traps_triggered",
		"_cycle_xp_hero", "_cycle_xp_biome", "_cycle_xp_passives_total",
		"_cycle_xp_passives_detail"
	]
	for p in props:
		if not p in AdventureSystem:
			_fail("AdventureSystem." + p + " existe", "propriété manquante")
			ok = false
	if ok:
		_ok("Toutes les 7 variables de tracking déclarées")

	# Vérifie les valeurs initiales
	_assert(AdventureSystem._cycle_events_total    == 0,   "_cycle_events_total init = 0")
	_assert(AdventureSystem._cycle_positive_events == 0,   "_cycle_positive_events init = 0")
	_assert(AdventureSystem._cycle_xp_hero         == 0.0, "_cycle_xp_hero init = 0.0")
	_assert(AdventureSystem._cycle_xp_biome        == 0.0, "_cycle_xp_biome init = 0.0")
	_assert(AdventureSystem._cycle_xp_passives_total == 0.0, "_cycle_xp_passives_total init = 0.0")
	_assert(AdventureSystem._cycle_xp_passives_detail.is_empty(), "_cycle_xp_passives_detail init = {}")

# ─── Test 2 : stop_adventure() peuple CycleData ─────────────────

func _test_cycle_data_stop() -> void:
	print("\n[TEST 2] stop_adventure() → CycleData.last_cycle_summary")

	# Injecter un état minimal pour pouvoir appeler stop_adventure sans crash
	AdventureSystem.is_running       = true
	AdventureSystem.current_biome_id = "foret"
	AdventureSystem._cycle_xp        = 42.0
	AdventureSystem._cycle_xp_hero   = 8.4
	AdventureSystem._cycle_xp_biome  = 16.8
	AdventureSystem._cycle_xp_passives_total  = 5.0
	AdventureSystem._cycle_xp_passives_detail = {"regen": 5.0}
	AdventureSystem._cycle_events_total       = 3
	AdventureSystem._cycle_positive_events    = 1
	AdventureSystem._cycle_traps_triggered    = 1
	AdventureSystem._cycle_combats_won        = 2
	AdventureSystem._cycle_combo_max          = 0
	AdventureSystem._cycle_loot               = 1
	AdventureSystem._cycle_luck               = 0
	AdventureSystem._cycle_events             = 2
	AdventureSystem.current_modifier          = {}
	AdventureSystem.current_hp                = 50.0

	# stop_adventure appelle CombatPlayer.stop() si is_playing — on ignore ça
	AdventureSystem.stop_adventure()

	var d := CycleData.last_cycle_summary
	_assert(not d.is_empty(),                          "last_cycle_summary non vide après stop")
	_assert(d.has("victory"),                          "clé 'victory' présente")
	_assert(d.get("victory") == false,                 "victory = false (sortie manuelle)")
	_assert(d.has("xp_hero"),                          "clé 'xp_hero' présente")
	_assert(d.has("xp_biome"),                         "clé 'xp_biome' présente")
	_assert(d.has("xp_passives_total"),                "clé 'xp_passives_total' présente")
	_assert(d.has("xp_passives_detail"),               "clé 'xp_passives_detail' présente")
	_assert(d.has("events_total"),                     "clé 'events_total' présente")
	_assert(d.has("positive_events"),                  "clé 'positive_events' présente")
	_assert(d.has("traps_triggered"),                  "clé 'traps_triggered' présente")
	_assert(d.get("xp_hero")          == 8.4,          "xp_hero = 8.4")
	_assert(d.get("xp_biome")         == 16.8,         "xp_biome = 16.8")
	_assert(d.get("xp_passives_total") == 5.0,         "xp_passives_total = 5.0")
	_assert(d.get("events_total")     == 3,            "events_total = 3")
	_assert(d.get("positive_events")  == 1,            "positive_events = 1")
	_assert(d.get("traps_triggered")  == 1,            "traps_triggered = 1")

# ─── Test 3 : _end_adventure() peuple CycleData ─────────────────

func _test_cycle_data_end() -> void:
	print("\n[TEST 3] _end_adventure() → CycleData.last_cycle_summary")

	CycleData.last_cycle_summary = {}
	AdventureSystem.is_running       = true
	AdventureSystem.current_biome_id = "foret"
	AdventureSystem._cycle_xp        = 100.0
	AdventureSystem._cycle_xp_hero   = 20.0
	AdventureSystem._cycle_xp_biome  = 40.0
	AdventureSystem._cycle_events_total    = 5
	AdventureSystem._cycle_positive_events = 2
	AdventureSystem._cycle_traps_triggered = 1
	AdventureSystem.current_modifier  = {}
	AdventureSystem._cycle_combo_max  = 0
	AdventureSystem._cycle_combats_won = 3

	AdventureSystem._end_adventure(true)

	var d := CycleData.last_cycle_summary
	_assert(not d.is_empty(),              "_end_adventure peuple last_cycle_summary")
	_assert(d.get("victory") == true,      "victory = true")
	_assert(d.get("xp_hero") == 20.0,     "xp_hero = 20.0")
	_assert(d.get("xp_biome") == 40.0,    "xp_biome = 40.0")
	_assert(d.get("events_total") == 5,   "events_total = 5")
	_assert(d.get("combats_won") == 3,    "combats_won = 3")

# ─── Test 4 : CycleSummaryScreen lit toutes les clés attendues ──

func _test_cycle_summary_screen_keys() -> void:
	print("\n[TEST 4] CycleSummaryScreen — clés CycleData requises")

	var required := [
		"victory", "biome_id", "creature_id", "modifier",
		"xp_total", "xp_hero", "xp_biome", "xp_passives_total", "xp_passives_detail",
		"loot_total", "combo_max", "combats_won", "events",
		"events_total", "positive_events", "traps_triggered", "cycle_luck"
	]
	var d := CycleData.last_cycle_summary
	var missing := []
	for k in required:
		if not d.has(k):
			missing.append(k)
	_assert(missing.is_empty(), "Toutes les clés requises présentes",
		"manquantes: " + str(missing))

# ─── Rapport final ───────────────────────────────────────────────

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
