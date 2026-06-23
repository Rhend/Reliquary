extends Node
# Tests du système de drop de ressources (Chantier 3) :
#   • constantes de taux (fréquent 60 % en quantité 1-4, rare par palier non linéaire),
#   • clamp du taux rare hors bornes,
#   • mapping biome → (ressource fréquente, rare) en donnée + ressources chargées,
#   • taux empiriques (statistique seedée) + INDÉPENDANCE des deux tirages,
#   • boss (créature Unique) → aucun drop de farm.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all()
	_print_report()
	get_tree().quit(1 if _results.any(func(r): return not r["ok"]) else 0)

# ─── Helpers ────────────────────────────────────────────────

func _assert(cond: bool, label: String, detail: String = "") -> void:
	_results.append({"ok": cond, "label": label})
	print(("  ✓ " if cond else "  ✗ ") + label + (" — " + detail if (detail != "" and not cond) else ""))

func _print_report() -> void:
	var passed := _results.filter(func(r): return r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, _results.size(), _results.size() - passed])
	print("════════════════════════════════\n")

# ─── Tests ──────────────────────────────────────────────────

func _run_all() -> void:
	print("\n=== TEST DROP RESSOURCES (Chantier 3) ===\n")
	_test_constants()
	_test_rate_clamp()
	_test_biome_mapping()
	_test_rates_and_independence()
	_test_boss_excluded()

func _test_constants() -> void:
	print("[TEST 1] Constantes de taux")
	_assert(is_equal_approx(Balance.DROP_FREQUENT_RATE, 0.60), "taux fréquent = 0.60",
			"obtenu %.3f" % Balance.DROP_FREQUENT_RATE)
	_assert(Balance.DROP_FREQUENT_QTY_MIN == 1 and Balance.DROP_FREQUENT_QTY_MAX == 4,
			"quantité fréquente = [1, 4]",
			"obtenu [%d, %d]" % [Balance.DROP_FREQUENT_QTY_MIN, Balance.DROP_FREQUENT_QTY_MAX])
	var expected := [0.02, 0.05, 0.10, 0.18, 0.30]
	var ok := Balance.DROP_RARE_RATE_BY_TIER.size() == expected.size()
	if ok:
		for i in expected.size():
			ok = ok and is_equal_approx(Balance.DROP_RARE_RATE_BY_TIER[i], expected[i])
	_assert(ok, "table rare = [0.02, 0.05, 0.10, 0.18, 0.30]",
			"obtenu %s" % str(Balance.DROP_RARE_RATE_BY_TIER))

func _test_rate_clamp() -> void:
	print("\n[TEST 2] Clamp du taux rare hors bornes")
	_assert(is_equal_approx(Balance.rare_drop_rate(-5), 0.02), "tier négatif → T0 (0.02)")
	_assert(is_equal_approx(Balance.rare_drop_rate(0), 0.02),  "tier 0 → 0.02")
	_assert(is_equal_approx(Balance.rare_drop_rate(4), 0.30),  "tier 4 → 0.30")
	_assert(is_equal_approx(Balance.rare_drop_rate(99), 0.30), "tier au-delà → T4 (0.30)")

func _test_biome_mapping() -> void:
	print("\n[TEST 3] Mapping biome → ressources (donnée) + ressources chargées")
	var expected := {
		"biome_foret":    ["res_fourrure", "res_venin"],
		"biome_marecage": ["res_slime",    "res_ecaille"],
		"biome_montagne": ["res_pierre",   "res_mineral_fer"],
	}
	for biome_id in expected:
		var b := GameData.get_entity(biome_id)
		var freq: String = str(b.get("ressource_frequente_id", ""))
		var rare: String = str(b.get("ressource_rare_id", ""))
		_assert(freq == expected[biome_id][0] and rare == expected[biome_id][1],
				"%s → (%s, %s)" % [biome_id, expected[biome_id][0], expected[biome_id][1]],
				"obtenu (%s, %s)" % [freq, rare])
		# Les deux ressources doivent exister comme entités chargées.
		_assert(not GameData.get_entity(freq).is_empty(), "ressource %s chargée" % freq)
		_assert(not GameData.get_entity(rare).is_empty(), "ressource %s chargée" % rare)

func _test_rates_and_independence() -> void:
	print("\n[TEST 4] Taux empiriques + indépendance (statistique seedée)")
	seed(20260620)
	var n := 40000
	for tier in [0, 2, 4]:
		var freq_hits := 0    # nb de tirages où la fréquente est présente (≥1)
		var freq_units := 0   # nb total d'exemplaires de fréquente (pour la moyenne 1-4)
		var rare_hits := 0
		var both_hits := 0
		for i in n:
			var ids := AdventureSystem.roll_biome_drops("res_fourrure", "res_venin", tier)
			var f_count := ids.count("res_fourrure")
			var got_f := f_count > 0
			var got_r := "res_venin" in ids
			if got_f:
				freq_hits += 1
				freq_units += f_count
				_assert_qty_range(f_count)  # chaque drop fréquent ∈ [1, 4]
			if got_r: rare_hits += 1
			if got_f and got_r: both_hits += 1
		var f_rate := float(freq_hits) / n
		var r_rate := float(rare_hits) / n
		var both_rate := float(both_hits) / n
		var exp_r := Balance.rare_drop_rate(tier)
		_assert(absf(f_rate - 0.60) < 0.02, "T%d : fréquent ≈ 0.60" % tier, "obtenu %.3f" % f_rate)
		_assert(absf(r_rate - exp_r) < 0.02, "T%d : rare ≈ %.2f" % [tier, exp_r], "obtenu %.3f" % r_rate)
		# Quantité moyenne par drop fréquent ≈ 2.5 (uniforme 1-4).
		var avg_qty := float(freq_units) / maxi(freq_hits, 1)
		_assert(absf(avg_qty - 2.5) < 0.05, "T%d : qté moyenne fréquente ≈ 2.5" % tier,
				"obtenu %.3f" % avg_qty)
		# Indépendance : P(les deux) ≈ P(fréquent) × P(rare).
		_assert(absf(both_rate - 0.60 * exp_r) < 0.02,
				"T%d : indépendance P(2) ≈ %.3f" % [tier, 0.60 * exp_r], "obtenu %.3f" % both_rate)

# Marque un échec si une quantité de fréquente sort de [1, 4] (un seul assert agrégé
# par appel serait trop bruyant : on n'enregistre QUE les violations).
func _assert_qty_range(qty: int) -> void:
	if qty < Balance.DROP_FREQUENT_QTY_MIN or qty > Balance.DROP_FREQUENT_QTY_MAX:
		_assert(false, "quantité fréquente hors [1, 4]", "obtenu %d" % qty)

func _test_boss_excluded() -> void:
	print("\n[TEST 5] Boss (créature Unique) → aucun drop de farm")
	AdventureSystem.current_biome_id = "biome_foret"
	GameData.player["resources"] = {}
	# Boss T4 : malgré le palier max, aucune ressource ne doit être créditée.
	AdventureSystem._drop_biome_resources({"est_unique": true, "maitrise_actuelle": 4, "name": "Oscar"})
	_assert(GameData.player["resources"].is_empty(),
			"aucune ressource créditée pour un boss",
			"obtenu %s" % str(GameData.player["resources"]))
