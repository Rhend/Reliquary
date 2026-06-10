extends Node
# Tests unitaires de CombatResolver (résolution VIT-based pure).
# Déterministes : crit_chance forcée à 0.0 ou 1.0 selon le cas testé.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TEST COMBAT RESOLVER ===\n")
	_test_victoire_simple()
	_test_degats_plancher()
	_test_crit_deterministe()
	_test_embuscade()
	_test_endurcissement()
	_test_poison_biome()
	_test_bouclier()
	_test_poison_passif()
	_test_garde_fou_max_steps()
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

# Stats de base sans critique (combat 100 % déterministe).
func _hero(overrides: Dictionary = {}) -> Dictionary:
	var h := {"hp": 100.0, "hp_max": 100.0, "atk": 20.0, "def": 5.0, "vit": 20.0,
			"crit_chance": 0.0, "crit_multiplier": 2.0}
	h.merge(overrides, true)
	return h

func _enemy(overrides: Dictionary = {}) -> Dictionary:
	var e := {"hp": 50.0, "atk": 10.0, "def": 2.0, "vit": 20.0,
			"crit_chance": 0.0, "crit_multiplier": 2.0}
	e.merge(overrides, true)
	return e

# Dernier step de la séquence (ou null).
func _last(steps: Array) -> CombatStep:
	return steps.back() as CombatStep if not steps.is_empty() else null

# ─── Tests ──────────────────────────────────────────────────

# Héros bien plus fort : il doit gagner, dernier coup = killing blow héros.
func _test_victoire_simple() -> void:
	print("[TEST] Victoire simple")
	var steps := CombatResolver.resolve(_hero({"atk": 100.0}), _enemy({"hp": 50.0}))
	_assert(not steps.is_empty(), "des steps sont produits")
	var last := _last(steps)
	_assert(last.is_killing_blow,        "dernier step = coup fatal")
	_assert(last.attacker == "hero",     "coup fatal porté par le héros")
	_assert(last.target_hp_after == 0,   "PV de la cible à 0 après le coup fatal")
	# Même VIT → le héros agit en premier : ATK 100 − DEF 2 = 98 ≥ 50 PV → 1 step.
	_assert(steps.size() == 1, "ennemi one-shot (1 seul step)", "steps=%d" % steps.size())

# ATK < DEF → les dégâts ne descendent jamais sous MIN_DAMAGE.
func _test_degats_plancher() -> void:
	print("\n[TEST] Dégâts plancher (ATK < DEF)")
	var steps := CombatResolver.resolve(
			_hero({"atk": 1.0}), _enemy({"def": 50.0, "hp": 3.0}))
	var hero_steps := steps.filter(func(s): return (s as CombatStep).attacker == "hero")
	_assert(not hero_steps.is_empty(), "le héros a attaqué")
	var all_min: bool = hero_steps.all(
			func(s): return (s as CombatStep).damage == int(Balance.MIN_DAMAGE))
	_assert(all_min, "tous les coups héros = MIN_DAMAGE (%d)" % int(Balance.MIN_DAMAGE))

# crit_chance 1.0 → tous les coups héros critiques ; 0.0 → aucun.
func _test_crit_deterministe() -> void:
	print("\n[TEST] Critiques déterministes")
	var steps := CombatResolver.resolve(
			_hero({"crit_chance": 1.0, "atk": 12.0}), _enemy({"hp": 100.0, "atk": 1.0}))
	var hero_steps := steps.filter(func(s): return (s as CombatStep).attacker == "hero")
	_assert(hero_steps.all(func(s): return (s as CombatStep).is_crit),
			"crit_chance 1.0 → tous les coups héros critiques")
	# Dégâts critiques = (ATK − DEF) × crit_multiplier = (12 − 2) × 2 = 20
	_assert(int((hero_steps[0] as CombatStep).damage) == 20,
			"dégâts critiques = (ATK − DEF) × multiplicateur",
			"damage=%d" % (hero_steps[0] as CombatStep).damage)

	steps = CombatResolver.resolve(_hero(), _enemy({"hp": 100.0}))
	_assert(steps.all(func(s): return not (s as CombatStep).is_crit),
			"crit_chance 0.0 → aucun critique")

# Option ambush : le premier step est un tour ennemi gratuit (tick 0).
func _test_embuscade() -> void:
	print("\n[TEST] Embuscade (Forêt Sombre)")
	var steps := CombatResolver.resolve(_hero(), _enemy(), {"ambush": true})
	var first := steps[0] as CombatStep
	_assert(first.is_ambush,           "premier step marqué is_ambush")
	_assert(first.attacker == "enemy", "embuscade portée par l'ennemi")
	_assert(first.tick_time == 0,      "embuscade au tick 0 (avant le cycle VIT)")
	# Dégâts embuscade = ATK ennemi 10 − DEF héros 5 = 5 → héros à 95 PV.
	_assert(first.target_hp_after == 95, "dégâts d'embuscade corrects",
			"hp_after=%d" % first.target_hp_after)

# Endurcissement (Montagne) : dégâts héros réduits de 20 %.
func _test_endurcissement() -> void:
	print("\n[TEST] Endurcissement (Montagne)")
	var steps := CombatResolver.resolve(
			_hero({"atk": 102.0}), _enemy({"hp": 1000.0}), {"endurcissement": true})
	var hero_steps := steps.filter(func(s): return (s as CombatStep).attacker == "hero")
	# (102 − 2) × 0.8 = 80
	_assert(int((hero_steps[0] as CombatStep).damage) == 80,
			"dégâts héros ×0.8", "damage=%d" % (hero_steps[0] as CombatStep).damage)

# Poison biome (Marécage) : des ticks is_poison apparaissent après les coups ennemis.
func _test_poison_biome() -> void:
	print("\n[TEST] Poison de biome (Marécage)")
	var steps := CombatResolver.resolve(
			_hero({"atk": 10.0}), _enemy({"hp": 500.0, "atk": 1.0}), {"poison": true})
	var poison_steps := steps.filter(func(s): return (s as CombatStep).is_poison)
	_assert(not poison_steps.is_empty(), "des ticks de poison sont produits")
	# 1er tick = 1 stack = ATK héros × BIOME_POISON_DMG_PCT (10 × 0.05 = 0.5 → arrondi min 1)
	var expected := int(maxf(roundf(10.0 * Balance.BIOME_POISON_DMG_PCT), 1.0))
	_assert(int((poison_steps[0] as CombatStep).damage) == expected,
			"dégâts du 1er tick = 1 stack", "damage=%d" % (poison_steps[0] as CombatStep).damage)

# Bouclier d'urgence : proc une seule fois sous le seuil de PV, absorbe les dégâts.
func _test_bouclier() -> void:
	print("\n[TEST] Bouclier d'urgence (Résilience)")
	var shield_cfg := {"available": true, "threshold": 0.99, "value_pct": 0.50}
	var steps := CombatResolver.resolve(
			_hero({"atk": 2.0, "hp": 100.0, "hp_max": 100.0}),
			_enemy({"hp": 300.0, "atk": 10.0}),
			{"passive_shield": shield_cfg})
	var procs := steps.filter(func(s): return (s as CombatStep).is_shield_proc)
	_assert(procs.size() == 1, "le bouclier proc exactement une fois",
			"procs=%d" % procs.size())
	_assert(int((procs[0] as CombatStep).shield_value) == 50,
			"valeur du bouclier = 50 %% des PV max")
	var absorbed := steps.filter(func(s): return (s as CombatStep).shield_absorbed > 0)
	_assert(not absorbed.is_empty(), "des dégâts sont absorbés ensuite")

# Poison passif (Contact Venimeux) : chance 1.0 → proc à chaque coup héros.
func _test_poison_passif() -> void:
	print("\n[TEST] Poison passif (Contact Venimeux)")
	var pp_cfg := {"chance": 1.0, "damage_per_turn": 5.0, "duration_turns": 2}
	var steps := CombatResolver.resolve(
			_hero({"atk": 5.0}), _enemy({"hp": 200.0, "atk": 1.0}),
			{"passive_poison": pp_cfg})
	var procs := steps.filter(func(s): return (s as CombatStep).passive_poison_proc)
	var ticks := steps.filter(func(s): return (s as CombatStep).is_passive_poison)
	_assert(not procs.is_empty(), "le poison passif proc sur les coups héros")
	_assert(not ticks.is_empty(), "des ticks de poison passif sont appliqués")
	_assert(int((ticks[0] as CombatStep).damage) == 5, "dégâts du tick = damage_per_turn")

# Deux combattants incapables de se tuer → la résolution s'arrête à MAX_STEPS.
func _test_garde_fou_max_steps() -> void:
	print("\n[TEST] Garde-fou MAX_STEPS")
	var steps := CombatResolver.resolve(
			_hero({"hp": 100000.0, "hp_max": 100000.0, "atk": 1.0}),
			_enemy({"hp": 100000.0, "atk": 1.0, "def": 50.0}))
	_assert(steps.size() == CombatResolver.MAX_STEPS,
			"la résolution s'arrête à MAX_STEPS (%d)" % CombatResolver.MAX_STEPS,
			"steps=%d" % steps.size())

# ─── Rapport final ──────────────────────────────────────────

func _print_report() -> void:
	var total  := _results.size()
	var passed := _results.filter(func(r): return r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, total, total - passed])
	for r in _results:
		if not r["ok"]:
			print("  ✗ " + r["label"])
	print("════════════════════════════════\n")
