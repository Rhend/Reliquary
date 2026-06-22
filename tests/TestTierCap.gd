extends Node
# Test du garde-fou « Plafond DUR global » (Balance.GLOBAL_MAX_TIER).
# Vérifie qu'aucune entité ne peut dépasser ce palier :
#   • bornage du palier max par type (UI / évolution),
#   • arrêt de l'XP de Maîtrise au plafond (et flux normal en dessous),
#   • can_evolve / evolve_entity refusés au plafond,
#   • familiarité du Hall (bestiaire) plafonnée + XP stoppée,
#   • Village plafonné via village_max_tier().

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST PLAFOND DUR GLOBAL (T%d) ===\n" % Balance.GLOBAL_MAX_TIER)
	_test_max_tier_by_type()
	_test_effective_max_tier()
	_test_xp_stops_at_cap()
	_test_xp_flows_below_cap()
	_test_evolution_blocked_at_cap()
	_test_evolution_works_below_cap()
	_test_hall_familiarity_capped()
	_test_village_capped()

# ─── Helpers ────────────────────────────────────────────────

func _ok(label: String) -> void:
	_results.append({"ok": true, "label": label})
	print("  ✓ " + label)

func _fail(label: String, detail: String = "") -> void:
	_results.append({"ok": false, "label": label})
	print("  ✗ " + label + (" — " + detail if detail != "" else ""))

func _assert(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_ok(label)
	else:
		_fail(label, detail)

func _print_report() -> void:
	var total  := _results.size()
	var passed := _results.filter(func(r): return r["ok"]).size()
	var failed := total - passed
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, total, failed])
	if failed > 0:
		print("ÉCHECS :")
		for r in _results:
			if not r["ok"]:
				print("  ✗ " + r["label"])
	print("════════════════════════════════\n")

# ─── Tests ──────────────────────────────────────────────────

func _test_max_tier_by_type() -> void:
	print("[TEST 1] get_max_tier_for_type borné au plafond")
	var cap := Balance.GLOBAL_MAX_TIER
	for t in [Enums.EntityType.CREATURE, Enums.EntityType.EQUIPMENT,
			Enums.EntityType.HERO, Enums.EntityType.BIOME,
			Enums.EntityType.PASSIVE, "type_inconnu"]:
		var m := GameData.get_max_tier_for_type(t)
		_assert(m == cap, "max(%s) = %d" % [t, cap], "obtenu %d" % m)

func _test_effective_max_tier() -> void:
	print("\n[TEST 2] effective_max_tier ne dépasse jamais le plafond")
	var cap := Balance.GLOBAL_MAX_TIER
	# Une créature dont le biome est à fond → plafond de biome élevé, doit rester borné.
	var creature := GameData.get_entity("creature_foret_surface")
	if creature.is_empty():
		_fail("creature_foret_surface introuvable")
		return
	var biome := GameData.get_entity(str(creature.get("biome_id", "")))
	var biome_tier_save := int(biome.get("maitrise_actuelle", 0))
	biome["maitrise_actuelle"] = Balance.DEFAULT_MAX_TIER
	var em := MasterySystem.effective_max_tier(creature)
	biome["maitrise_actuelle"] = biome_tier_save
	_assert(em <= cap, "effective_max_tier(créature) ≤ %d" % cap, "obtenu %d" % em)

func _test_xp_stops_at_cap() -> void:
	print("\n[TEST 3] Aucune XP de Maîtrise gagnée au plafond")
	var id := "creature_foret_surface"
	var e := GameData.get_entity(id)
	if e.is_empty():
		_fail("creature_foret_surface introuvable")
		return
	e["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	e["xp_maitrise_actuelle"] = 0.0
	MasterySystem.add_xp_to_entity(id, 1000.0)
	_assert(e.get("xp_maitrise_actuelle", -1.0) == 0.0,
			"XP reste à 0 au palier max", "obtenu %.1f" % e.get("xp_maitrise_actuelle", -1.0))

func _test_xp_flows_below_cap() -> void:
	print("\n[TEST 4] L'XP s'accumule encore en dessous du plafond")
	var id := "creature_foret_surface"
	var e := GameData.get_entity(id)
	e["maitrise_actuelle"] = 0
	e["xp_maitrise_actuelle"] = 0.0
	MasterySystem.add_xp_to_entity(id, 100.0)  # créature coef ×1.0 → 100 (sous le plafond du buffer)
	_assert(e.get("xp_maitrise_actuelle", 0.0) > 0.0,
			"XP > 0 sous le plafond", "obtenu %.1f" % e.get("xp_maitrise_actuelle", 0.0))

func _test_evolution_blocked_at_cap() -> void:
	print("\n[TEST 5] Évolution impossible au plafond")
	var id := "creature_foret_surface"
	var e := GameData.get_entity(id)
	e["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	e["xp_maitrise_actuelle"] = 999999.0  # XP largement suffisante
	_assert(not MasterySystem.can_evolve(id), "can_evolve = false au plafond")
	_assert(not MasterySystem.evolve_entity(id), "evolve_entity = false au plafond")
	_assert(int(e.get("maitrise_actuelle", -1)) == Balance.GLOBAL_MAX_TIER,
			"palier inchangé après tentative", "obtenu %d" % e.get("maitrise_actuelle", -1))

func _test_evolution_works_below_cap() -> void:
	print("\n[TEST 6] Évolution possible jusqu'au plafond")
	var id := "creature_foret_surface"
	var e := GameData.get_entity(id)
	# S'assure que le biome ne bride pas la créature sous le plafond.
	var biome := GameData.get_entity(str(e.get("biome_id", "")))
	var biome_tier_save := int(biome.get("maitrise_actuelle", 0))
	biome["maitrise_actuelle"] = Balance.DEFAULT_MAX_TIER
	e["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER - 1
	e["xp_maitrise_actuelle"] = float(GameData.xp_thresholds[Balance.GLOBAL_MAX_TIER])
	var evolved := MasterySystem.evolve_entity(id)
	biome["maitrise_actuelle"] = biome_tier_save
	_assert(evolved, "evolve_entity réussit en atteignant le plafond")
	_assert(int(e.get("maitrise_actuelle", -1)) == Balance.GLOBAL_MAX_TIER,
			"palier = %d après évolution" % Balance.GLOBAL_MAX_TIER,
			"obtenu %d" % e.get("maitrise_actuelle", -1))

func _test_hall_familiarity_capped() -> void:
	print("\n[TEST 7] Familiarité du Hall plafonnée + XP stoppée")
	var id := "creature_foret_surface"
	GameData.player.get("bestiary", {}).erase(id)
	GameData.record_encounter(id, "Rat", Enums.EntityType.CREATURE, "biome_foret", 100000.0)
	var entry: Dictionary = GameData.player.get("bestiary", {}).get(id, {})
	_assert(int(entry.get("tier", -1)) == Balance.GLOBAL_MAX_TIER,
			"tier Hall plafonné à %d" % Balance.GLOBAL_MAX_TIER,
			"obtenu %d" % entry.get("tier", -1))
	var xp_at_cap: float = entry.get("xp", -1.0)
	var count_before: int = entry.get("count", 0)
	GameData.record_encounter(id, "Rat", Enums.EntityType.CREATURE, "biome_foret", 100000.0)
	_assert(entry.get("xp", -1.0) == xp_at_cap,
			"XP du Hall n'augmente plus au plafond", "obtenu %.1f" % entry.get("xp", -1.0))
	_assert(int(entry.get("count", 0)) == count_before + 1,
			"compteur de rencontres continue d'avancer")

func _test_village_capped() -> void:
	print("\n[TEST 8] Village plafonné (montée automatique par largeur)")
	var cap := Balance.GLOBAL_MAX_TIER
	_assert(GameData.village_max_tier() == cap, "village_max_tier() = %d" % cap,
			"obtenu %d" % GameData.village_max_tier())
	# Largeur énorme → le palier calculé reste borné au plafond DUR global.
	_assert(Balance.village_tier_for_building_count(9999) == cap,
			"village_tier_for_building_count plafonné à GLOBAL_MAX_TIER",
			"obtenu %d" % Balance.village_tier_for_building_count(9999))
	# recompute_village_tier ne dépasse jamais le plafond, même au plafond.
	var tier_save := int(GameData.village.get("maitrise_actuelle", 0))
	var eclos_save = GameData.village.get("eclos", false)
	GameData.village["eclos"] = true
	GameData.village["maitrise_actuelle"] = cap
	GameData.recompute_village_tier()
	var blocked := int(GameData.village.get("maitrise_actuelle", 0)) == cap
	GameData.village["maitrise_actuelle"] = tier_save
	GameData.village["eclos"] = eclos_save
	_assert(blocked, "recompute_village_tier ne dépasse pas le plafond")
