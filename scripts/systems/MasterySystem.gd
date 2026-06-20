# ============================================================
# MasterySystem.gd — Gestion de la progression par Maîtrise.
#
# Principes (Chantier 2 — économie XP) :
#   • Toutes les entités progressent en Maîtrise par paliers.
#   • À chaque événement résolu, l'XP PRODUITE (selon le palier de la CIBLE)
#     est distribuée SIMULTANÉMENT à toutes les entités actives, chacune
#     recevant XP_produite × son coef de type. PAS de modificateur d'écart.
#   • Palier max selon le type (créatures → Légendaire ; autres → Unique)
#     et, pour les créatures, un plafond imposé par le palier du biome + la zone.
#   • L'évolution est TOUJOURS manuelle. Une entité accumule l'XP jusqu'au coût
#     de son palier suivant → PRÊTE. L'XP qui continue d'arriver entre dans un
#     BUFFER borné (EVOLVE_BUFFER_CAP × coût du palier visé) ; au-delà elle est
#     PERDUE. evolve_entity (action joueur) consomme le coût et reverse le buffer
#     dans la progression suivante. Mécanique décorrélée du biome et universelle.
# ============================================================
extends Node

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

# Coût du palier visé pour le BUFFER, SANS tenir compte du plafond de biome :
# −1 seulement si l'entité est à son palier max ABSOLU (type / plafond global).
# Une créature bloquée par son biome a donc un coût ≥ 0 → elle bufferise quand
# même (« prête mais non évoluée »), l'excédent au-delà du buffer étant perdu.
func _next_tier_cost(entity: Dictionary) -> float:
	var tier := int(entity.get("maitrise_actuelle", 0))
	if tier >= GameData.get_max_tier_for_type(entity.get("entity_type", "")):
		return -1.0
	return Balance.evolve_cost(entity.get("entity_type", ""), tier + 1)

# Coût du palier suivant ÉVOLUABLE (tient compte du plafond de biome) : −1 si
# l'entité ne peut pas monter maintenant (palier max effectif atteint). Sert à
# can_evolve, au signal « prêt à évoluer » et à evolve_entity.
func _evolvable_cost(entity: Dictionary) -> float:
	var tier := int(entity.get("maitrise_actuelle", 0))
	if tier >= effective_max_tier(entity):
		return -1.0
	return Balance.evolve_cost(entity.get("entity_type", ""), tier + 1)

# ─── Distribution d'XP ──────────────────────────────────────

# Retourne true si l'entité a atteint le seuil de son palier suivant
# (et qu'un palier suivant existe — plafond de type/biome compris).
func can_evolve(entity_id: String) -> bool:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return false
	var cost := _evolvable_cost(entity)
	if cost < 0.0:
		return false
	return entity.get("xp_maitrise_actuelle", 0.0) >= cost

# Crédite à une entité l'XP PRODUITE par un événement, modulée par son coef de
# type : XP reçue = produced_xp × coef. L'XP s'accumule jusqu'au coût du palier
# visé puis dans un buffer borné (EVOLVE_BUFFER_CAP × coût) ; l'excédent est
# PERDU. Au palier max absolu (type / plafond global), plus aucune XP n'entre.
func add_xp_to_entity(entity_id: String, produced_xp: float) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var cost := _next_tier_cost(entity)
	if cost < 0.0:
		return  # « Palier Max atteint » → plus d'accumulation
	var coef      := float(Balance.ENTITY_XP_COEF.get(entity.get("entity_type", ""), Balance.DEFAULT_XP_COEF))
	var xp_gained := produced_xp * coef
	if xp_gained <= 0.0:
		return
	var xp_before := float(entity.get("xp_maitrise_actuelle", 0.0))
	# Plafond mou = coût + buffer ; tout ce qui dépasse est perdu.
	var ceiling   := cost * (1.0 + Balance.EVOLVE_BUFFER_CAP)
	var xp_after  := minf(xp_before + xp_gained, ceiling)
	if xp_after <= xp_before:
		return  # buffer déjà plein → rien à créditer
	entity["xp_maitrise_actuelle"] = xp_after
	EventBus.xp_gained.emit(entity_id, xp_after - xp_before)
	_check_evolution(entity_id, xp_before)

# Distribue de l'XP à tous les passifs actifs du joueur (coef passif = ×1.0).
#
# Deux sources de passifs actifs :
#   1. player["active_passives"]        — passifs activés manuellement
#   2. entity["unlocked_passives"] (*)  — passifs débloqués sur héros/biomes
# (*) Dédoublonnés pour éviter qu'un même passif partagé reçoive l'XP plusieurs fois.
func add_xp_to_all_active(produced_xp: float) -> void:
	var seen: Dictionary = {}

	for passive_id in GameData.player.get("active_passives", []):
		if not seen.has(passive_id):
			seen[passive_id] = true
			add_xp_to_entity(passive_id, produced_xp)

	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") not in [Enums.EntityType.HERO, Enums.EntityType.BIOME]:
			continue
		for passive_id in e.get("unlocked_passives", []):
			if not seen.has(passive_id):
				seen[passive_id] = true
				add_xp_to_entity(passive_id, produced_xp)

# ─── Contrôle d'évolution ───────────────────────────────────

# Émet entity_ready_to_evolve une seule fois, au franchissement du seuil.
# xp_before = XP de l'entité AVANT l'ajout courant.
func _check_evolution(entity_id: String, xp_before: float) -> void:
	var entity = GameData.get_entity(entity_id)
	if entity.is_empty():
		return
	var cost := _evolvable_cost(entity)
	if cost < 0.0:
		return
	# Émet uniquement au franchissement (avant < coût, maintenant ≥ coût).
	if xp_before < cost and entity.get("xp_maitrise_actuelle", 0.0) >= cost:
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
	var cost := _evolvable_cost(entity)
	if cost < 0.0:
		return false
	if entity.get("xp_maitrise_actuelle", 0.0) < cost:
		return false

	# Monte le palier, consomme le coût et REVERSE le buffer (le surplus, borné à
	# EVOLVE_BUFFER_CAP × coût, est conservé comme avance réelle vers le palier
	# suivant ; étant < coût suivant, il ne déclenche jamais de cascade).
	var tier := int(entity.get("maitrise_actuelle", 0))
	entity["maitrise_actuelle"] = tier + 1
	entity["xp_maitrise_actuelle"]   = entity["xp_maitrise_actuelle"] - cost
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
