# ============================================================
# MasterySystem.gd — Gestion de la progression par maîtrise.
#
# Principes fondamentaux :
#   • Le héro lui-même n'évolue PAS — ce sont les entités
#     autour de lui (passifs, biomes) qui progressent.
#   • L'XP reçue est modulée par l'écart de tier entre le
#     générateur (l'ennemi vaincu) et le récepteur :
#       - Générateur plus fort → moins d'XP (diminishing returns)
#       - Générateur plus faible → plus d'XP (catch-up mechanic)
#   • L'évolution est toujours déclenchée manuellement par
#     le joueur ; le système ne fait que signaler quand c'est possible.
# ============================================================
extends Node

# ─── Calcul XP ──────────────────────────────────────────────

# Applique le modificateur d'écart de tier à l'XP de base.
# écart = generator_tier - receiver_tier, clampé entre -4 et +4.
func calculate_xp(base_xp: float, generator_tier: int, receiver_tier: int) -> float:
	var ecart    = clampi(generator_tier - receiver_tier, -4, 4)
	var modifier = float(GameData.xp_modifiers.get(str(ecart), 1.0))
	return base_xp * modifier

# ─── Distribution d'XP ──────────────────────────────────────

# Distribue de l'XP à une seule entité et vérifie si elle peut évoluer.
func add_xp_to_entity(entity_id: String, base_xp: float, generator_tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return

	var receiver_tier = entity.get("current_tier", 0)
	var xp_gained     = calculate_xp(base_xp, generator_tier, receiver_tier)
	var xp_before     = entity.get("current_xp", 0.0)
	entity["current_xp"] = xp_before + xp_gained
	EventBus.xp_gained.emit(entity_id, xp_gained)
	_check_evolution(entity_id, xp_before)

# Distribue de l'XP à tous les passifs actifs du joueur.
# Le héro (active_creature_id) est INTENTIONNELLEMENT exclu :
# sa progression passe par l'équipement forgé et les biomes explorés.
#
# Deux sources de passifs actifs :
#   1. player["active_passives"]        — passifs activés manuellement
#   2. entity["unlocked_passives"] (*)  — passifs débloqués sur créatures/biomes
# (*) Dédoublonnés pour éviter qu'un même passif partagé entre entités
#     reçoive de l'XP plusieurs fois.
func add_xp_to_all_active(base_xp: float, generator_tier: int) -> void:
	var seen: Dictionary = {}

	# Passifs directement activés par le joueur
	for passive_id in GameData.player.get("active_passives", []):
		if not seen.has(passive_id):
			seen[passive_id] = true
			add_xp_to_entity(passive_id, base_xp * 0.5, generator_tier)

	# Passifs débloqués via l'évolution de créatures et de biomes
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") not in ["creature", "biome"]:
			continue
		for passive_id in e.get("unlocked_passives", []):
			if not seen.has(passive_id):
				seen[passive_id] = true
				add_xp_to_entity(passive_id, base_xp * 0.5, generator_tier)

# ─── Contrôle d'évolution ───────────────────────────────────

# Vérifie si le seuil vient d'être franchi et émet le signal une seule fois.
# xp_before = XP de l'entité AVANT l'ajout courant.
# Le signal n'est émis que si on passe de "sous le seuil" à "au-dessus",
# évitant le spam de signal sur chaque XP ultérieur.
func _check_evolution(entity_id: String, xp_before: float) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var tier = entity.get("current_tier", 0)
	if tier >= GameData.MAX_TIER:
		return
	var next_idx = tier + 1
	if next_idx >= GameData.xp_thresholds.size():
		return
	var threshold = float(GameData.xp_thresholds[next_idx])
	# Émet uniquement au franchissement (avant < seuil, maintenant ≥ seuil)
	if xp_before < threshold and entity.get("current_xp", 0.0) >= threshold:
		EventBus.entity_ready_to_evolve.emit(entity_id)

# Fait monter une entité d'un tier sur action explicite du joueur.
# Retourne true si l'évolution a réussi, false sinon (XP insuffisant, tier max).
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

	# Monte le tier et soustrait l'XP dépensée (le surplus est conservé)
	entity["current_tier"]  = tier + 1
	entity["current_xp"]    = entity["current_xp"] - threshold

	_unlock_passives_for_tier(entity_id, tier + 1)
	EventBus.entity_evolved.emit(entity_id, tier + 1)
	return true

# Débloque les passifs configurés pour se débloquer au tier atteint.
func _unlock_passives_for_tier(entity_id: String, tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	for slot in entity.get("passive_slots", []):
		if slot.get("unlock_tier", 99) != tier:
			continue
		var passive_id = slot.get("passive_id", "")
		if passive_id != "" and passive_id not in entity.get("unlocked_passives", []):
			entity["unlocked_passives"].append(passive_id)
			EventBus.passive_unlocked.emit(entity_id, passive_id)
