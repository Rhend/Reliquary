extends Node

# Calcule le XP effectif reçu selon l'écart de palier entre générateur et récepteur.
# écart = generator_tier - receiver_tier
# Valeurs positives : générateur plus fort → moins d'XP (diminishing returns)
# Valeurs négatives : générateur plus faible → plus d'XP (catch-up)
func calculate_xp(base_xp: float, generator_tier: int, receiver_tier: int) -> float:
	var ecart    = clampi(generator_tier - receiver_tier, -4, 4)
	var modifier = float(GameData.xp_modifiers.get(str(ecart), 1.0))
	return base_xp * modifier

# Distribue de l'XP à une entité unique et vérifie si elle peut évoluer.
func add_xp_to_entity(entity_id: String, base_xp: float, generator_tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return

	var xp_gained = calculate_xp(base_xp, generator_tier, entity.get("current_tier", 0))
	entity["current_xp"] = entity.get("current_xp", 0.0) + xp_gained
	EventBus.xp_gained.emit(entity_id, xp_gained)
	_check_evolution(entity_id)

# Distribue de l'XP à toutes les entités actives (créature + passifs actifs).
# Les passifs reçoivent 50% de la mise de base pour ralentir légèrement leur progression.
func add_xp_to_all_active(base_xp: float, generator_tier: int) -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id != "":
		add_xp_to_entity(creature_id, base_xp, generator_tier)

	for passive_id in GameData.player.get("active_passives", []):
		add_xp_to_entity(passive_id, base_xp * 0.5, generator_tier)

# Déclenche le signal d'évolution possible sans faire évoluer automatiquement.
# L'évolution est toujours déclenchée manuellement par le joueur.
func _check_evolution(entity_id: String) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var tier = entity.get("current_tier", 0)
	if tier >= GameData.MAX_TIER:
		return
	var next_idx = tier + 1
	if next_idx >= GameData.xp_thresholds.size():
		return
	if entity.get("current_xp", 0.0) >= float(GameData.xp_thresholds[next_idx]):
		EventBus.entity_ready_to_evolve.emit(entity_id)

# Fait évoluer une entité d'un palier. Retourne false si impossible.
# À appeler sur action explicite du joueur uniquement.
func evolve_entity(entity_id: String) -> bool:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return false

	var tier = entity.get("current_tier", 0)
	if tier >= GameData.MAX_TIER:
		return false

	var next_idx = tier + 1
	if next_idx >= GameData.xp_thresholds.size():
		return false

	var threshold = float(GameData.xp_thresholds[next_idx])
	if entity.get("current_xp", 0.0) < threshold:
		return false

	entity["current_tier"] = tier + 1
	entity["current_xp"]   = entity["current_xp"] - threshold

	_unlock_passives_for_tier(entity_id, tier + 1)
	EventBus.entity_evolved.emit(entity_id, tier + 1)
	PassiveSystem.refresh_active_passives()
	return true

func _unlock_passives_for_tier(entity_id: String, tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	for slot in entity.get("passive_slots", []):
		if slot.get("unlock_tier", 99) == tier:
			var passive_id = slot.get("passive_id", "")
			if passive_id != "" and passive_id not in entity.get("unlocked_passives", []):
				entity["unlocked_passives"].append(passive_id)
				EventBus.passive_unlocked.emit(entity_id, passive_id)
