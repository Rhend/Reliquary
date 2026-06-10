extends Node
# Test du flux expédition → CycleSummaryScreen
# Vérifie : tracking stats (CycleStats), sauvegarde CycleData, clés du résumé.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all()
	_print_report()
	# Code de sortie ≠ 0 si au moins un échec → exploitable par la CI.
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST FLUX EXPÉDITION ===\n")
	_test_cycle_stats_init()
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

# Fabrique un CycleStats pré-rempli et l'injecte dans AdventureSystem.
func _inject_stats(values: Dictionary) -> void:
	var stats := AdventureSystem.CycleStats.new()
	for key in values:
		stats.set(key, values[key])
	AdventureSystem._stats = stats

# ─── Test 1 : CycleStats neuf = tous les compteurs à zéro ───────

func _test_cycle_stats_init() -> void:
	print("[TEST 1] CycleStats — valeurs initiales")

	var stats := AdventureSystem.CycleStats.new()
	_assert(stats.xp_total          == 0.0, "xp_total init = 0.0")
	_assert(stats.xp_hero           == 0.0, "xp_hero init = 0.0")
	_assert(stats.xp_biome          == 0.0, "xp_biome init = 0.0")
	_assert(stats.xp_passives_total == 0.0, "xp_passives_total init = 0.0")
	_assert(stats.xp_passives_detail.is_empty(), "xp_passives_detail init = {}")
	_assert(stats.events_total      == 0,   "events_total init = 0")
	_assert(stats.positive_events   == 0,   "positive_events init = 0")
	_assert(stats.traps_triggered   == 0,   "traps_triggered init = 0")
	_assert(stats.combats_won       == 0,   "combats_won init = 0")
	_assert(stats.loot_total        == 0,   "loot_total init = 0")
	_assert(stats.loot_detail.is_empty(),   "loot_detail init = {}")

# ─── Test 2 : stop_adventure() peuple CycleData ─────────────────

func _test_cycle_data_stop() -> void:
	print("\n[TEST 2] stop_adventure() → CycleData.last_cycle_summary")

	# Injecter un état minimal pour pouvoir appeler stop_adventure sans crash
	AdventureSystem.is_running       = true
	AdventureSystem.current_biome_id = "foret"
	AdventureSystem.current_modifier = {}
	AdventureSystem.current_hp       = 50.0
	_inject_stats({
		"xp_total":           42.0,
		"xp_hero":            8.4,
		"xp_biome":           16.8,
		"xp_passives_total":  5.0,
		"xp_passives_detail": {"regen": 5.0},
		"events_total":       3,
		"positive_events":    1,
		"traps_triggered":    1,
		"combats_won":        2,
		"loot_total":         1,
		"events":             2,
	})

	AdventureSystem.stop_adventure()

	var d := CycleData.last_cycle_summary
	_assert(not d.is_empty(),                "last_cycle_summary non vide après stop")
	_assert(d.get("victory") == false,       "victory = false (sortie manuelle)")
	_assert(d.get("interrupted") == true,    "interrupted = true (sortie manuelle)")
	_assert(d.get("xp_total")          == 42.0, "xp_total = 42.0")
	_assert(d.get("xp_hero")           == 8.4,  "xp_hero = 8.4")
	_assert(d.get("xp_biome")          == 16.8, "xp_biome = 16.8")
	_assert(d.get("xp_passives_total") == 5.0,  "xp_passives_total = 5.0")
	_assert(d.get("events_total")      == 3,    "events_total = 3")
	_assert(d.get("positive_events")   == 1,    "positive_events = 1")
	_assert(d.get("traps_triggered")   == 1,    "traps_triggered = 1")

# ─── Test 3 : _end_adventure() peuple CycleData ─────────────────

func _test_cycle_data_end() -> void:
	print("\n[TEST 3] _end_adventure() → CycleData.last_cycle_summary")

	CycleData.last_cycle_summary = {}
	AdventureSystem.is_running       = true
	AdventureSystem.current_biome_id = "foret"
	AdventureSystem.current_modifier = {}
	_inject_stats({
		"xp_total":        100.0,
		"xp_hero":         20.0,
		"xp_biome":        40.0,
		"events_total":    5,
		"positive_events": 2,
		"traps_triggered": 1,
		"combats_won":     3,
	})

	AdventureSystem._end_adventure(true)

	var d := CycleData.last_cycle_summary
	_assert(not d.is_empty(),             "_end_adventure peuple last_cycle_summary")
	_assert(d.get("victory") == true,     "victory = true")
	_assert(d.get("xp_hero") == 20.0,     "xp_hero = 20.0")
	_assert(d.get("xp_biome") == 40.0,    "xp_biome = 40.0")
	_assert(d.get("events_total") == 5,   "events_total = 5")
	_assert(d.get("combats_won") == 3,    "combats_won = 3")

# ─── Test 4 : CycleSummaryScreen lit toutes les clés attendues ──

func _test_cycle_summary_screen_keys() -> void:
	print("\n[TEST 4] CycleSummaryScreen — clés CycleData requises")

	# Clés lues par CycleSummaryScreen (data.get) + clés du récap standard.
	var required := [
		"victory", "interrupted", "biome_id", "hero_id", "modifier",
		"xp_total", "xp_hero", "xp_biome", "xp_passives_total", "xp_passives_detail",
		"xp_entities_detail", "xp_equip_detail", "loot_total", "loot_detail",
		"combats_won", "events", "events_total", "positive_events", "traps_triggered",
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
