# ============================================================
# MasterySystem.gd — Gestion de la progression par Maîtrise.
#
# Principes :
#   • Toutes les entités progressent en Maîtrise par paliers.
#   • À chaque événement résolu, l'XP de base est distribuée à toutes
#     les entités actives : XP = base × modificateur d'écart × coef de type.
#   • Écart de Maîtrise = (palier de l'entité − palier de l'événement),
#     clampé à ±4. Entité plus FAIBLE que l'événement → plus d'XP (catch-up).
#   • Palier max selon le type (créatures → Légendaire ; autres → Unique)
#     et, pour les créatures, un plafond imposé par le palier du biome + la zone.
#   • L'évolution est TOUJOURS manuelle : le système accumule l'XP (même
#     au-delà du plafond, elle reste stockée) et signale via
#     entity_ready_to_evolve qu'un palier est disponible. C'est une action
#     joueur explicite (evolve_entity) qui consomme le seuil et fait monter.
# ============================================================
extends Node

# ─── Calcul XP ──────────────────────────────────────────────

# Applique le modificateur d'écart à l'XP de base.
# écart = receiver_tier − event_tier, clampé à ±XP_GAP_CLAMP.
func calculate_xp(base_xp: float, event_tier: int, receiver_tier: int) -> float:
	var ecart    = clampi(receiver_tier - event_tier, -Balance.XP_GAP_CLAMP, Balance.XP_GAP_CLAMP)
	var modifier = float(Balance.XP_GAP_MODIFIERS.get(ecart, 1.0))
	return base_xp * modifier

# ─── Paliers : max de type + plafond créature/biome ─────────

# Palier maximum effectif d'une entité : min(plafond de type, plafond créature).
func effective_max_tier(entity: Dictionary) -> int:
	var type_max := GameData.get_max_tier_for_type(entity.get("entity_type", ""))
	if entity.get("entity_type", "") != Enums.EntityType.CREATURE:
		return type_max
	return mini(type_max, _creature_biome_cap(entity))

# Plafond imposé à une créature par le palier de Maîtrise de son biome + sa zone.
# Profondeur sous Rare → zone non débloquée (−1, aucun palier franchissable).
func _creature_biome_cap(creature: Dictionary) -> int:
	var biome      := GameData.get_entity(str(creature.get("biome_id", "")))
	var biome_tier := int(biome.get("maitrise_actuelle", 0))
	var zone       := int(creature.get("zone_associee", 0))
	if zone == Enums.Zone.PROFONDEUR:
		return int(Balance.CREATURE_CAP_PROFONDEUR.get(biome_tier, -1))
	if zone == Enums.Zone.SURFACE:
		return int(Balance.CREATURE_CAP_SURFACE.get(biome_tier, 0))
	# Zone Abysse / créature unique : pas de plafond de biome (limité au max de type).
	return Balance.DEFAULT_MAX_TIER

# Seuil d'XP pour franchir le palier courant, ou -1 s'il n'y a pas de palier
# suivant (palier max de type atteint, plafond créature atteint, ou hors courbe).
# Convention "pas de palier suivant" unifiée pour toutes les entités.
func _next_threshold(entity: Dictionary) -> float:
	var tier := int(entity.get("maitrise_actuelle", 0))
	if tier >= effective_max_tier(entity):
		return -1.0
	var next_idx := tier + 1
	if next_idx >= GameData.xp_thresholds.size():
		return -1.0
	return float(GameData.xp_thresholds[next_idx])

# ─── Distribution d'XP ──────────────────────────────────────

# Retourne true si l'entité a atteint le seuil de son palier suivant
# (et qu'un palier suivant existe — plafond de type/biome compris).
func can_evolve(entity_id: String) -> bool:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return false
	var threshold := _next_threshold(entity)
	if threshold < 0.0:
		return false
	return entity.get("xp_maitrise_actuelle", 0.0) >= threshold

# Distribue de l'XP de Maîtrise à une entité : base × écart × coef de type.
# event_tier = palier de Maîtrise de l'entité rencontrée (générateur de l'XP).
# L'XP s'accumule même si l'entité est plafonnée (elle reste stockée).
func add_xp_to_entity(entity_id: String, base_xp: float, event_tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var receiver_tier := int(entity.get("maitrise_actuelle", 0))
	var coef          := float(Balance.ENTITY_XP_COEF.get(entity.get("entity_type", ""), Balance.DEFAULT_XP_COEF))
	var xp_gained     := calculate_xp(base_xp, event_tier, receiver_tier) * coef
	if xp_gained <= 0.0:
		return
	var xp_before = entity.get("xp_maitrise_actuelle", 0.0)
	entity["xp_maitrise_actuelle"] = xp_before + xp_gained
	EventBus.xp_gained.emit(entity_id, xp_gained)
	_check_evolution(entity_id, xp_before)

# Distribue de l'XP à tous les passifs actifs du joueur (coef passif = ×1.0).
#
# Deux sources de passifs actifs :
#   1. player["active_passives"]        — passifs activés manuellement
#   2. entity["unlocked_passives"] (*)  — passifs débloqués sur héros/biomes
# (*) Dédoublonnés pour éviter qu'un même passif partagé reçoive l'XP plusieurs fois.
func add_xp_to_all_active(base_xp: float, event_tier: int) -> void:
	var seen: Dictionary = {}

	for passive_id in GameData.player.get("active_passives", []):
		if not seen.has(passive_id):
			seen[passive_id] = true
			add_xp_to_entity(passive_id, base_xp, event_tier)

	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") not in [Enums.EntityType.HERO, Enums.EntityType.BIOME]:
			continue
		for passive_id in e.get("unlocked_passives", []):
			if not seen.has(passive_id):
				seen[passive_id] = true
				add_xp_to_entity(passive_id, base_xp, event_tier)

# ─── Contrôle d'évolution ───────────────────────────────────

# Émet entity_ready_to_evolve une seule fois, au franchissement du seuil.
# xp_before = XP de l'entité AVANT l'ajout courant.
func _check_evolution(entity_id: String, xp_before: float) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var threshold := _next_threshold(entity)
	if threshold < 0.0:
		return
	# Émet uniquement au franchissement (avant < seuil, maintenant ≥ seuil).
	if xp_before < threshold and entity.get("xp_maitrise_actuelle", 0.0) >= threshold:
		EventBus.entity_ready_to_evolve.emit(entity_id)

# Réévalue les créatures d'un biome après son évolution : le plafond ayant monté,
# l'XP stockée peut rendre de nouveaux paliers franchissables → on (re)signale.
func reevaluate_creatures_for_biome(biome_id: String) -> void:
	for eid in GameData.entities:
		var e = GameData.entities[eid]
		if e.get("entity_type", "") != Enums.EntityType.CREATURE:
			continue
		if str(e.get("biome_id", "")) != biome_id:
			continue
		if can_evolve(eid):
			EventBus.entity_ready_to_evolve.emit(eid)

# Fait monter une entité d'un palier sur action explicite du joueur.
# Retourne true si l'évolution a réussi, false sinon (XP insuffisant, plafond/tier max).
func evolve_entity(entity_id: String) -> bool:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return false
	var threshold := _next_threshold(entity)
	if threshold < 0.0:
		return false
	if entity.get("xp_maitrise_actuelle", 0.0) < threshold:
		return false

	# Monte le palier et soustrait l'XP dépensée (le surplus est conservé).
	var tier := int(entity.get("maitrise_actuelle", 0))
	entity["maitrise_actuelle"] = tier + 1
	entity["xp_maitrise_actuelle"]   = entity["xp_maitrise_actuelle"] - threshold
	entity["xp_maitrise_palier_suivant"] = GameData.palier_suivant_cost(entity.get("entity_type", ""), tier + 1)

	_unlock_passives_for_tier(entity_id, tier + 1)
	EventBus.entity_evolved.emit(entity_id, tier + 1)
	return true

# Débloque les passifs configurés pour se débloquer au tier atteint.
func _unlock_passives_for_tier(entity_id: String, tier: int) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var passifs := entity.get("passifs_par_palier", {}) as Dictionary
	if not passifs.has(tier):
		return
	var passive_id := str(passifs[tier])
	if passive_id != "" and passive_id not in entity.get("unlocked_passives", []):
		entity["unlocked_passives"].append(passive_id)
		EventBus.passive_unlocked.emit(entity_id, passive_id)
