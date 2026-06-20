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
	_test_speed_modifier()
	_test_endurcissement()
	_test_poison_biome()
	_test_bouclier()
	_test_poison_passif()
	_test_garde_fou_max_steps()
	_test_def_reduction_curve()
	_test_stat_stacker_additif()
	_test_stat_stacker_ordre_independant()
	_test_cadence_relative()
	_test_simultaneite_priorite_hero()
	_test_horodatage_croissant()
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
	# Dégâts critiques = round(mitigated_damage(ATK, DEF) × crit_mult).
	# ATK 12, DEF 2 → réduction ≈ 0.0196 → 12×0.9804 ≈ 11.765 ; ×2 ≈ 23.53 → 24.
	var expected_crit := int(roundf(Balance.mitigated_damage(12.0, 2.0) * 2.0))
	_assert(int((hero_steps[0] as CombatStep).damage) == expected_crit,
			"dégâts critiques = round(mitigated_damage × multiplicateur)",
			"damage=%d attendu=%d" % [(hero_steps[0] as CombatStep).damage, expected_crit])

	steps = CombatResolver.resolve(_hero(), _enemy({"hp": 100.0}))
	_assert(steps.all(func(s): return not (s as CombatStep).is_crit),
			"crit_chance 0.0 → aucun critique")

# Embuscade : la créature démarre sa jauge ATB pleine → elle frappe en premier,
# à t = 0, AVANT le héros (exprimé via le modèle de jauge, pas un step spécial).
func _test_embuscade() -> void:
	print("\n[TEST] Embuscade (Forêt Sombre)")
	var steps := CombatResolver.resolve(_hero(), _enemy(), {"ambush": true})
	var first := steps[0] as CombatStep
	_assert(first.attacker == "enemy", "la créature frappe en premier (embuscade)")
	_assert(is_zero_approx(first.time_sec), "1er coup à t = 0 s (jauge ennemie pleine au départ)")
	_assert(first.is_ambush, "1er coup ennemi tagué is_ambush")
	# À vit égale SANS embuscade, le héros frappe en premier : l'embuscade inverse bien l'ordre.
	var normal := CombatResolver.resolve(_hero(), _enemy())
	_assert((normal[0] as CombatStep).attacker == "hero",
			"sans embuscade, le héros frappe en premier (témoin)")

# Rail de vitesse : un modificateur temporaire accélérant augmente le nombre de
# coups du combattant DANS sa fenêtre (puis la cadence revient à la normale).
func _test_speed_modifier() -> void:
	print("\n[TEST] Rail de vitesse (modificateur temporaire)")
	# Ennemi increvable → combat long. On compte les coups héros avant t = 5 s.
	var base := CombatResolver.resolve(
			_hero({"hp": 1.0e9, "hp_max": 1.0e9, "atk": 1.0}),
			_enemy({"hp": 1.0e9, "atk": 1.0, "def": 50.0}))
	var hasted := CombatResolver.resolve(
			_hero({"hp": 1.0e9, "hp_max": 1.0e9, "atk": 1.0}),
			_enemy({"hp": 1.0e9, "atk": 1.0, "def": 50.0}),
			{"hero_speed_mods": [{"factor": 3.0, "start": 0.0, "duration": 5.0}]})
	var base_n   := _hero_hits_before(base, 5.0)
	var hasted_n := _hero_hits_before(hasted, 5.0)
	_assert(base_n > 0, "des coups héros de référence dans la fenêtre", "base=%d" % base_n)
	_assert(hasted_n >= base_n * 2,
			"hâte ×3 → bien plus de coups dans la fenêtre (≥ 2× le témoin)",
			"base=%d hasted=%d" % [base_n, hasted_n])
	# Hors fenêtre la cadence revient à la normale : l'écart par seconde se resserre.
	var late_base   := _hero_hits_before(base, 20.0) - _hero_hits_before(base, 10.0)
	var late_hasted := _hero_hits_before(hasted, 20.0) - _hero_hits_before(hasted, 10.0)
	_assert(absi(late_hasted - late_base) <= 2,
			"après la fenêtre, cadence revenue à la normale",
			"late_base=%d late_hasted=%d" % [late_base, late_hasted])

# Nombre de coups d'attaque du héros dont l'horodatage est < t.
func _hero_hits_before(steps: Array, t: float) -> int:
	return steps.filter(func(s):
		var st := s as CombatStep
		return st.attacker == "hero" and not st.is_passive_poison and st.time_sec < t
	).size()

# Endurcissement (Montagne) : dégâts héros réduits de 20 %.
func _test_endurcissement() -> void:
	print("\n[TEST] Endurcissement (Montagne)")
	var steps := CombatResolver.resolve(
			_hero({"atk": 102.0}), _enemy({"hp": 1000.0}), {"endurcissement": true})
	var hero_steps := steps.filter(func(s): return (s as CombatStep).attacker == "hero")
	# (102 − 2) × 0.8 = 80
	_assert(int((hero_steps[0] as CombatStep).damage) == 80,
			"dégâts héros ×0.8", "damage=%d" % (hero_steps[0] as CombatStep).damage)

# Poison biome (Marécage) : mécanique HOSTILE — le marais empoisonne le HÉROS.
# Des ticks is_poison (portés par l'ennemi) rongent les PV du héros.
func _test_poison_biome() -> void:
	print("\n[TEST] Poison de biome (Marécage)")
	var steps := CombatResolver.resolve(
			_hero({"atk": 10.0, "hp": 600.0}), _enemy({"hp": 5000.0, "atk": 20.0}), {"poison": true})
	var poison_steps := steps.filter(func(s): return (s as CombatStep).is_poison)
	_assert(not poison_steps.is_empty(), "des ticks de poison sont produits")
	var first_p := poison_steps[0] as CombatStep
	_assert(first_p.attacker == "enemy", "le poison de biome frappe le héros (porté par l'ennemi)")
	# 1er tick = 1 stack = ATK ENNEMI × BIOME_POISON_DMG_PCT (20 × 0.05 = 1)
	var expected := int(maxf(roundf(20.0 * Balance.BIOME_POISON_DMG_PCT), 1.0))
	_assert(int(first_p.damage) == expected,
			"dégâts du 1er tick = 1 stack (ATK ennemi)", "damage=%d" % first_p.damage)

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

# Référentiel temps réel : un combattant 2× plus rapide (vit double) frappe
# ~2× plus souvent. Combat sans mort (faibles dégâts, gros PV) → on compte les
# coups de chacun jusqu'au garde-fou MAX_STEPS.
func _test_cadence_relative() -> void:
	print("\n[TEST] Cadence relative (vit ×2 → ~2× plus de coups)")
	# Héros vit 40 (aps 2,0) vs ennemi vit 20 (aps 1,0). Personne ne meurt.
	var steps := CombatResolver.resolve(
			_hero({"hp": 1.0e9, "hp_max": 1.0e9, "atk": 1.0, "vit": 40.0}),
			_enemy({"hp": 1.0e9, "atk": 1.0, "def": 50.0, "vit": 20.0}))
	var hero_n := steps.filter(func(s): return (s as CombatStep).attacker == "hero").size()
	var enemy_n := steps.filter(func(s): return (s as CombatStep).attacker == "enemy").size()
	_assert(enemy_n > 0, "l'ennemi a frappé au moins une fois", "enemy_n=%d" % enemy_n)
	var ratio := float(hero_n) / float(maxi(enemy_n, 1))
	_assert(ratio >= 1.8 and ratio <= 2.2,
			"héros ~2× plus de coups que l'ennemi (ratio≈2)",
			"hero=%d enemy=%d ratio=%.2f" % [hero_n, enemy_n, ratio])

# Simultanéité : à vit égale, héros et ennemi atteignent leur seuil au même
# instant → le héros frappe en premier, au même horodatage.
func _test_simultaneite_priorite_hero() -> void:
	print("\n[TEST] Simultanéité → priorité héros")
	# Faibles dégâts, gros PV : les deux survivent aux premiers coups.
	var steps := CombatResolver.resolve(
			_hero({"hp": 1000.0, "hp_max": 1000.0, "atk": 1.0, "vit": 20.0}),
			_enemy({"hp": 1000.0, "atk": 1.0, "def": 0.0, "vit": 20.0}))
	_assert(steps.size() >= 2, "au moins deux coups produits", "steps=%d" % steps.size())
	var s0 := steps[0] as CombatStep
	var s1 := steps[1] as CombatStep
	_assert(s0.attacker == "hero",  "premier coup porté par le héros")
	_assert(s1.attacker == "enemy", "second coup porté par l'ennemi")
	_assert(is_equal_approx(s0.time_sec, s1.time_sec),
			"héros et ennemi frappent au même instant (priorité héros)",
			"t_hero=%.3f t_enemy=%.3f" % [s0.time_sec, s1.time_sec])

# Les horodatages des steps sont monotones croissants (jamais en arrière).
func _test_horodatage_croissant() -> void:
	print("\n[TEST] Horodatage croissant")
	var steps := CombatResolver.resolve(
			_hero({"hp": 5000.0, "hp_max": 5000.0, "atk": 2.0, "vit": 26.0}),
			_enemy({"hp": 5000.0, "atk": 2.0, "def": 0.0, "vit": 14.0}))
	var monotone := true
	for i in range(1, steps.size()):
		if (steps[i] as CombatStep).time_sec < (steps[i - 1] as CombatStep).time_sec - 1.0e-6:
			monotone = false
			break
	_assert(steps.size() > 2, "plusieurs steps produits", "steps=%d" % steps.size())
	_assert(monotone, "time_sec monotone croissant sur toute la séquence")

# Deux combattants incapables de se tuer → la résolution s'arrête à MAX_STEPS.
func _test_garde_fou_max_steps() -> void:
	print("\n[TEST] Garde-fou MAX_STEPS")
	var steps := CombatResolver.resolve(
			_hero({"hp": 100000.0, "hp_max": 100000.0, "atk": 1.0}),
			_enemy({"hp": 100000.0, "atk": 1.0, "def": 50.0}))
	_assert(steps.size() == CombatResolver.MAX_STEPS,
			"la résolution s'arrête à MAX_STEPS (%d)" % CombatResolver.MAX_STEPS,
			"steps=%d" % steps.size())

# Courbe de réduction par la DEF (Balance.def_reduction) : repères du référentiel
# + invariant DUR « MONOTONE CROISSANTE » — plus de DEF ⇒ jamais moins de réduction
# (une stat de défense ne doit JAMAIS régresser), et saturation sous le plafond.
func _test_def_reduction_curve() -> void:
	print("\n[TEST] Courbe de réduction par la DEF")
	var cas := {0: 0.0, 25: 0.1923, 50: 0.2778, 84: 0.3387, 100: 0.3571, 150: 0.3947}
	for d in cas:
		var got := Balance.def_reduction(float(d))
		_assert(absf(got - float(cas[d])) < 0.005,
				"réduction(DEF %d) ≈ %.4f" % [d, float(cas[d])],
				"got=%.4f" % got)
	# Monotonie stricte : la réduction ne recule jamais quand la DEF augmente.
	var prev := -1.0
	for d in [0, 10, 25, 50, 84, 100, 150, 300, 1000]:
		var r := Balance.def_reduction(float(d))
		_assert(r >= prev, "réduction monotone croissante à DEF %d" % d,
				"r=%.4f < prev=%.4f" % [r, prev])
		prev = r
	# Saturation : la réduction reste sous le plafond (asymptote, jamais atteint).
	_assert(Balance.def_reduction(1000.0) < Balance.DEF_REDUCTION_CAP,
			"la réduction sature sous le plafond DEF_REDUCTION_CAP",
			"r1000=%.4f cap=%.4f" % [Balance.def_reduction(1000.0), Balance.DEF_REDUCTION_CAP])

# Empilement ADDITIF : stat_finale = nue × (1 + Σ%). Exemple du référentiel
# (DEF 50, +16/+9/+43 % = +68 % → 84) ET interdiction du produit multiplicatif.
func _test_stat_stacker_additif() -> void:
	print("\n[TEST] Empilement additif des bonus %")
	var got := StatStacker.final_stat(50.0, [0.16, 0.09, 0.43], "def")
	_assert(is_equal_approx(got, 84.0),
			"50 × (1 + 0,16 + 0,09 + 0,43) = 84", "got=%.4f" % got)
	# Le produit séquentiel (faux) donnerait 50 × 1,16 × 1,09 × 1,43 ≈ 90,4.
	var multiplicatif := 50.0 * 1.16 * 1.09 * 1.43
	_assert(absf(got - multiplicatif) > 1.0,
			"résultat additif ≠ résultat multiplicatif (pas d'emballement)",
			"additif=%.2f multiplicatif=%.2f" % [got, multiplicatif])

# Non-régression : permuter l'ordre des sources de bonus donne un résultat
# IDENTIQUE au bit près (l'ordre d'acquisition ne doit jamais compter).
func _test_stat_stacker_ordre_independant() -> void:
	print("\n[TEST] Empilement additif : indépendant de l'ordre")
	var a := StatStacker.final_stat(50.0, [0.16, 0.09, 0.43], "def")
	var b := StatStacker.final_stat(50.0, [0.43, 0.16, 0.09], "def")
	var c := StatStacker.final_stat(50.0, [0.09, 0.43, 0.16], "def")
	_assert(a == b and b == c,
			"permuter les bonus → résultat identique au bit près",
			"a=%.17f b=%.17f c=%.17f" % [a, b, c])

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
