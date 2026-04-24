extends Node

func _ready() -> void:
	# Attendre que GameData ait fini de charger les entités
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all_tests()

func _run_all_tests() -> void:
	print("=== TESTS XP SYSTEM ===")
	_test_xp_modifiers()
	_test_evolution()
	_test_xp_distribution()
	print("=== FIN DES TESTS ===")

func _test_xp_modifiers() -> void:
	print("\n[TEST] Modificateurs XP")
	# [generator_tier, receiver_tier, base_xp, expected_result]
	var cases = [
		[0, 0, 10.0, 10.0 ],   # même palier       → 100%
		[1, 0, 10.0,  7.0 ],   # générateur +1     →  70%
		[0, 1, 10.0, 15.0 ],   # générateur -1     → 150%
		[4, 0, 10.0,  0.5 ],   # générateur +4     →   5%
		[0, 4, 10.0, 50.0 ],   # générateur -4     → 500%
		[2, 0, 10.0,  4.0 ],   # générateur +2     →  40%
		[0, 2, 10.0, 20.0 ],   # générateur -2     → 200%
	]
	var passed = 0
	for c in cases:
		var result   = MasterySystem.calculate_xp(c[2], c[0], c[1])
		var expected = c[3]
		var ok       = abs(result - expected) < 0.001
		print("  gen=%d rec=%d base=%.1f → %.3f (attendu %.3f) %s" % [
			c[0], c[1], c[2], result, expected, "OK" if ok else "ECHEC"
		])
		if ok:
			passed += 1
	print("  Résultat : %d/%d" % [passed, cases.size()])

func _test_evolution() -> void:
	print("\n[TEST] Évolution d'entité")

	var test_id = "creature_rat"
	var entity  = GameData.get_entity(test_id)
	if entity.is_empty():
		print("  ECHEC : entité 'creature_rat' introuvable")
		return

	# Remise à zéro
	entity["current_tier"] = 0
	entity["current_xp"]   = 0.0
	entity["unlocked_passives"] = []

	# Doit refuser l'évolution sans XP
	var refused = not MasterySystem.evolve_entity(test_id)
	print("  Refus sans XP suffisant : %s" % ("OK" if refused else "ECHEC"))

	# Donner exactement le seuil du palier 1
	entity["current_xp"] = float(GameData.xp_thresholds[1])
	var evolved = MasterySystem.evolve_entity(test_id)
	print("  Évolution vers palier 1 : %s" % ("OK" if evolved else "ECHEC"))
	print("  Palier actuel = %d (%s)" % [entity["current_tier"], GameData.get_tier_name(entity["current_tier"])])
	print("  XP résiduel   = %.1f" % entity["current_xp"])

	# Vérifier le déverrouillage du passif au palier 1
	var has_passive = "passive_regeneration" in entity.get("unlocked_passives", [])
	print("  Passif 'régénération' déverrouillé : %s" % ("OK" if has_passive else "ECHEC"))

func _test_xp_distribution() -> void:
	print("\n[TEST] Distribution XP à toutes les entités actives")

	var creature_id = "creature_rat"
	GameData.player["active_creature_id"] = creature_id
	GameData.player["active_passives"]    = []

	var entity = GameData.get_entity(creature_id)
	entity["current_tier"] = 0
	entity["current_xp"]   = 0.0

	MasterySystem.add_xp_to_all_active(100.0, 0)

	var xp_after = entity.get("current_xp", 0.0)
	var ok       = abs(xp_after - 100.0) < 0.001
	print("  Créature reçoit 100 XP (même palier) : %s (valeur=%.1f)" % ["OK" if ok else "ECHEC", xp_after])
