extends Node

func _ready() -> void:
	# Attendre que GameData ait fini de charger les entités
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all_tests()

func _run_all_tests() -> void:
	print("=== TESTS XP SYSTEM ===")
	_test_xp_produced()
	_test_distribution_no_gap()
	_test_buffer_cap()
	_test_evolution()
	print("=== FIN DES TESTS ===")

# XP produite par un événement = 10 × 1.6^palier de la cible (T0→10 … T4→66).
func _test_xp_produced() -> void:
	print("\n[TEST] XP produite par palier de la cible (10 × 1.6^tier)")
	# [palier_cible, XP produite arrondie attendue]
	var cases = [[0, 10], [1, 16], [2, 26], [3, 41], [4, 66]]
	var passed = 0
	for c in cases:
		var got      = Balance.xp_produced(c[0])
		var expected = c[1]
		var ok       = int(round(got)) == expected
		print("  tier=%d → %.3f (arrondi attendu %d) %s" % [c[0], got, expected, "OK" if ok else "ECHEC"])
		if ok:
			passed += 1
	print("  Résultat : %d/%d" % [passed, cases.size()])

# Pas de modificateur d'écart : une entité reçoit produced × coef, quel que soit
# l'écart entre son palier et celui de la cible. Coef créature ×1.0, héros ×0.05.
func _test_distribution_no_gap() -> void:
	print("\n[TEST] Distribution sans écart de palier (produced × coef)")
	var id := "creature_foret_surface"
	var e  := GameData.get_entity(id)
	if e.is_empty():
		print("  ECHEC : 'creature_foret_surface' introuvable")
		return
	# Même montant produit donné à la créature : reçoit le plein montant (coef 1.0),
	# indépendamment du palier de la cible (pas de gap).
	e["maitrise_actuelle"] = 0
	e["xp_maitrise_actuelle"] = 0.0
	MasterySystem.add_xp_to_entity(id, 50.0)
	var ok_full := absf(float(e.get("xp_maitrise_actuelle", 0.0)) - 50.0) < 0.001
	print("  Créature reçoit 50 (coef ×1.0) : %s (%.2f)" % ["OK" if ok_full else "ECHEC", e.get("xp_maitrise_actuelle", 0.0)])

	# Héros : coef ×0.05 → 50 produit = 2.5 reçu.
	var h := GameData.get_entity("hero")
	if not h.is_empty():
		h["maitrise_actuelle"] = 0
		h["xp_maitrise_actuelle"] = 0.0
		MasterySystem.add_xp_to_entity("hero", 50.0)
		var ok_hero := absf(float(h.get("xp_maitrise_actuelle", 0.0)) - 2.5) < 0.001
		print("  Héros reçoit 2.5 (coef ×0.05) : %s (%.3f)" % ["OK" if ok_hero else "ECHEC", h.get("xp_maitrise_actuelle", 0.0)])

# Buffer borné : l'XP est plafonnée à coût × (1 + EVOLVE_BUFFER_CAP) ; l'excédent
# est perdu. Coût T0→T1 créature = 100, cap 20% → plafond 120.
func _test_buffer_cap() -> void:
	print("\n[TEST] Buffer d'évolution borné (excédent perdu)")
	var id := "creature_foret_surface"
	var e  := GameData.get_entity(id)
	if e.is_empty():
		return
	# S'assurer que le biome ne bride pas (T1 atteignable).
	var biome := GameData.get_entity(str(e.get("biome_id", "")))
	var biome_save := int(biome.get("maitrise_actuelle", 0))
	biome["maitrise_actuelle"] = Balance.DEFAULT_MAX_TIER
	e["maitrise_actuelle"] = 0
	e["xp_maitrise_actuelle"] = 0.0
	var cost := Balance.evolve_cost(Enums.EntityType.CREATURE, 1)        # 100
	var ceiling := cost * (1.0 + Balance.EVOLVE_BUFFER_CAP)             # 120
	MasterySystem.add_xp_to_entity(id, 1000.0)                          # bien au-delà
	biome["maitrise_actuelle"] = biome_save
	var got := float(e.get("xp_maitrise_actuelle", 0.0))
	var ok  := absf(got - ceiling) < 0.001
	print("  XP plafonnée à %.0f (coût %.0f + buffer 20%%) : %s (%.2f)" % [ceiling, cost, "OK" if ok else "ECHEC", got])

func _test_evolution() -> void:
	print("\n[TEST] Évolution d'entité")

	var test_id = "creature_foret_surface"
	var entity  = GameData.get_entity(test_id)
	if entity.is_empty():
		print("  ECHEC : entité 'creature_foret_surface' introuvable")
		return

	# Biome non bridant + remise à zéro.
	var biome := GameData.get_entity(str(entity.get("biome_id", "")))
	var biome_save := int(biome.get("maitrise_actuelle", 0))
	biome["maitrise_actuelle"] = Balance.DEFAULT_MAX_TIER
	entity["maitrise_actuelle"] = 0
	entity["xp_maitrise_actuelle"]   = 0.0
	entity["unlocked_passives"] = []

	# Doit refuser l'évolution sans XP
	var refused = not MasterySystem.evolve_entity(test_id)
	print("  Refus sans XP suffisant : %s" % ("OK" if refused else "ECHEC"))

	# Donner exactement le coût du palier 1
	entity["xp_maitrise_actuelle"] = Balance.evolve_cost(Enums.EntityType.CREATURE, 1)
	var evolved = MasterySystem.evolve_entity(test_id)
	biome["maitrise_actuelle"] = biome_save
	print("  Évolution vers palier 1 : %s" % ("OK" if evolved else "ECHEC"))
	print("  Palier actuel = %d (%s)" % [entity["maitrise_actuelle"], GameData.get_tier_name(entity["maitrise_actuelle"])])
	print("  XP résiduel   = %.1f" % entity["xp_maitrise_actuelle"])

	# Palier monté à 1, coût exactement consommé → résidu nul (pas de buffer ici).
	var tier_ok = int(entity.get("maitrise_actuelle", -1)) == 1
	var residu_ok = absf(float(entity.get("xp_maitrise_actuelle", -1.0))) < 0.001
	print("  Palier = 1 après évolution : %s" % ("OK" if tier_ok else "ECHEC"))
	print("  XP résiduel = 0 (coût consommé) : %s" % ("OK" if residu_ok else "ECHEC"))
