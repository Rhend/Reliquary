# ============================================================
# VillageBuildings.gd — Quartiers, routes & bâtiments (Chantier 4).
#
# Responsabilités :
#   1. État : palier de chaque bâtiment (Délabré → T5) et reconstruction des
#      routes. Vit dans GameData.village (buildings/routes) → sauvegardé avec
#      le reste du village (merge tolérant SaveManager), aucune migration.
#   2. Coûts : la courbe UNIQUE (Balance.BUILDING_COST_STEPS) est résolue en
#      ressources concrètes contre l'assignation de biome de chaque bâtiment
#      (BuildingData.biome_principal_id / biomes_additionnels).
#   3. Actions : reconstruire une route, améliorer un bâtiment — consomment les
#      ressources droppées (Chantier 3) via GameData.player.resources.
#   4. Bonus : agrège les effets passifs débloqués palier par palier en canaux
#      nommés. Tous les % passent ensuite par l'agrégateur additif (StatStacker)
#      aux points de consommation (combat, régén, XP, drops…). Encodage
#      INCRÉMENTAL dans les .tres : un bâtiment au palier T cumule les paliers 0..T.
#
# Bonus NON traités ici (Chantier 5 — Forge) : les canaux forge_points_* /
# forge_xp_* sont agrégés (get_bonus) mais inertes tant que la Forge (points,
# seuil d'XP, arbres d'équipement) n'existe pas.
# ============================================================
extends Node

# ─── Canaux de bonus (clés stables, pas de string magique chez les appelants) ──
const CH_ATK_PCT            := "atk_pct"
const CH_DEF_PCT            := "def_pct"
const CH_HP_MAX_PCT         := "hp_max_pct"
const CH_CRIT_PCT           := "crit_pct"
const CH_REGEN_PCT          := "regen_pct"
const CH_XP_DISTRIBUTED_PCT := "xp_distributed_pct"
const CH_BLESS_EFFECT_PCT   := "bless_effect_pct"
const CH_DROP_RARE_PCT      := "drop_rare_pct"
const CH_AMBUSH_GAUGE       := "ambush_gauge_start_pct"
const CH_ALL_EXP_GAUGE      := "all_expedition_gauge_start_pct"
const CH_IGNORE_LETHAL      := "ignore_first_lethal"
const CH_DEBUFF_REDUCTION   := "debuff_start_reduction"
const CH_DEBUFF_IMMUNITY    := "debuff_immunity_tier"

# Règle d'agrégation par canal. Tout canal absent → "sum" (cumul additif).
#   "max" : on garde la plus forte valeur débloquée (jauge ATB, palier d'immunité)
#   "or"  : booléen (≥1 ⇒ actif), ex. ignore du 1er coup létal
const CHANNEL_RULE: Dictionary = {
	CH_AMBUSH_GAUGE:    "max",
	CH_ALL_EXP_GAUGE:   "max",
	CH_DEBUFF_IMMUNITY: "max",
	CH_IGNORE_LETHAL:   "or",
}

# room_panel_id (pièce de quartier, cf. Village.DISTRICTS) → building_id.
const ROOM_TO_BUILDING: Dictionary = {
	"district_house":      "bat_maison",
	"district_garden":     "bat_jardin",
	"district_training":   "bat_salle",
	"district_reliquaire": "bat_reliquaire",
	"district_tour":       "bat_tour",
	"district_palissade":  "bat_palissade",
	"district_forgeron":   "bat_forgeron",
	"district_armurier":   "bat_armurier",
	"district_joaillier":  "bat_joaillier",
	"district_couturier":  "bat_couturier",
}

# Cache des bonus agrégés : canal → valeur. Recalculé au load et à chaque action.
var _bonuses: Dictionary = {}

func _ready() -> void:
	EventBus.load_completed.connect(refresh_bonuses)
	refresh_bonuses()

# ═══════════════════════════════════════════════════════════
#  État (lecture)
# ═══════════════════════════════════════════════════════════

# Palier courant d'un bâtiment (Balance.BUILDING_TIER_DELABRE si jamais reconstruit).
func building_tier(building_id: String) -> int:
	return int(GameData.village.get("buildings", {}).get(building_id, Balance.BUILDING_TIER_DELABRE))

# Route d'un quartier reconstruite ?
func route_built(quartier: String) -> bool:
	return bool(GameData.village.get("routes", {}).get(quartier, false))

# building_id de la pièce de quartier `room_panel_id`, "" si inconnue.
func building_for_room(room_panel_id: String) -> String:
	return ROOM_TO_BUILDING.get(room_panel_id, "")

# Nombre de bâtiments RECONSTRUITS (palier T0 ou plus), tous quartiers confondus.
# Critère de LARGEUR pour la montée automatique du Village. Délabré ne compte pas ;
# les routes ne sont PAS des bâtiments → jamais comptées. Un bâtiment gelé reste
# Délabré (non reconstructible) donc s'exclut naturellement.
func count_buildings_tier0_plus() -> int:
	var n := 0
	for eid in GameData.entities:
		var b: Dictionary = GameData.entities[eid]
		if b.get("entity_type", "") != Enums.EntityType.BUILDING:
			continue
		if building_tier(eid) >= 0:
			n += 1
	return n

# ═══════════════════════════════════════════════════════════
#  Coûts
# ═══════════════════════════════════════════════════════════

# Coût (res_id → qté) pour reconstruire la route d'un quartier, {} si inconnue.
func route_cost(quartier: String) -> Dictionary:
	var def: Dictionary = Balance.VILLAGE_ROUTE_COSTS.get(quartier, {})
	if def.is_empty():
		return {}
	return { str(def.get("res_id", "")): int(def.get("qty", 0)) }

# Coût (res_id → qté) pour amener un bâtiment à son palier SUIVANT. {} si gelé,
# au palier max, ou bâtiment inconnu. Résout la courbe unique contre les biomes
# assignés (principal : fréquente à chaque palier + rare dès T2 ; additionnels :
# fréquente à T3/T4/T5 selon add_count).
func building_cost(building_id: String) -> Dictionary:
	var b := GameData.get_entity(building_id)
	if b.is_empty() or b.get("gele", false):
		return {}
	var target := building_tier(building_id) + 1
	if target < 0 or target > Balance.BUILDING_MAX_TIER:
		return {}
	var step: Dictionary = Balance.BUILDING_COST_STEPS[target]
	var cost: Dictionary = {}

	var biome := GameData.get_entity(str(b.get("biome_principal_id", "")))
	var freq_id := str(biome.get("ressource_frequente_id", ""))
	var rare_id := str(biome.get("ressource_rare_id", ""))
	if freq_id != "" and int(step.get("freq", 0)) > 0:
		cost[freq_id] = int(cost.get(freq_id, 0)) + int(step["freq"])
	if rare_id != "" and int(step.get("rare", 0)) > 0:
		cost[rare_id] = int(cost.get(rare_id, 0)) + int(step["rare"])

	var adds: Array = b.get("biomes_additionnels", [])
	var add_each := int(step.get("add_each", 0))
	for i in mini(int(step.get("add_count", 0)), adds.size()):
		var ab := GameData.get_entity(str(adds[i]))
		var afid := str(ab.get("ressource_frequente_id", ""))
		if afid != "" and add_each > 0:
			cost[afid] = int(cost.get(afid, 0)) + add_each
	return cost

# Le joueur possède-t-il toutes les ressources d'un coût (res_id → qté) ?
func can_afford(cost: Dictionary) -> bool:
	if cost.is_empty():
		return false
	var res: Dictionary = GameData.player.get("resources", {})
	for rid in cost:
		if int(res.get(rid, 0)) < int(cost[rid]):
			return false
	return true

# ═══════════════════════════════════════════════════════════
#  Actions
# ═══════════════════════════════════════════════════════════

# Route reconstructible ? (pas déjà faite, hub débloqué pour la Forge, payable)
func can_rebuild_route(quartier: String) -> bool:
	if route_built(quartier):
		return false
	if quartier == "forge" and int(GameData.village.get("maitrise_actuelle", 0)) < Balance.FORGE_HUB_UNLOCK_VILLAGE_TIER:
		return false
	return can_afford(route_cost(quartier))

# Reconstruit la route d'un quartier : consomme les ressources, déverrouille la
# couche gestion (bâtiments). Retourne false si impossible.
func rebuild_route(quartier: String) -> bool:
	if not can_rebuild_route(quartier):
		return false
	_consume(route_cost(quartier))
	var routes: Dictionary = GameData.village.get("routes", {})
	routes[quartier] = true
	GameData.village["routes"] = routes
	EventBus.resources_changed.emit()
	EventBus.village_buildings_changed.emit()
	return true

# Bâtiment améliorable ? (non gelé, route du quartier faite, sous le palier max, payable)
func can_upgrade_building(building_id: String) -> bool:
	var b := GameData.get_entity(building_id)
	if b.is_empty() or b.get("gele", false):
		return false
	if not route_built(str(b.get("quartier", ""))):
		return false
	if building_tier(building_id) >= Balance.BUILDING_MAX_TIER:
		return false
	return can_afford(building_cost(building_id))

# Améliore un bâtiment d'un palier : consomme les ressources, monte le palier,
# recalcule les bonus. Retourne le NOUVEAU palier, ou Balance.BUILDING_TIER_DELABRE−1
# (= -2) si impossible.
func upgrade_building(building_id: String) -> int:
	if not can_upgrade_building(building_id):
		return Balance.BUILDING_TIER_DELABRE - 1
	_consume(building_cost(building_id))
	var new_tier := building_tier(building_id) + 1
	var buildings: Dictionary = GameData.village.get("buildings", {})
	buildings[building_id] = new_tier
	GameData.village["buildings"] = buildings
	refresh_bonuses()
	# Largeur de reconstruction modifiée → le Village peut monter de palier
	# AUTOMATIQUEMENT (Délabré → T0 fait franchir un seuil). Émet village_tier_change.
	GameData.recompute_village_tier()
	EventBus.resources_changed.emit()
	EventBus.village_buildings_changed.emit()
	return new_tier

func _consume(cost: Dictionary) -> void:
	var res: Dictionary = GameData.player.get("resources", {})
	for rid in cost:
		res[rid] = maxi(0, int(res.get(rid, 0)) - int(cost[rid]))
	GameData.player["resources"] = res

# ═══════════════════════════════════════════════════════════
#  Bonus agrégés
# ═══════════════════════════════════════════════════════════

# Recalcule entièrement le cache de bonus depuis l'état courant des bâtiments.
func refresh_bonuses() -> void:
	_bonuses = {}
	for eid in GameData.entities:
		var b: Dictionary = GameData.entities[eid]
		if b.get("entity_type", "") != Enums.EntityType.BUILDING:
			continue
		if b.get("gele", false):
			continue
		var tier := building_tier(eid)
		if tier < 0:
			continue
		_accumulate_building(_bonuses, b, tier)

# Effets agrégés d'UN bâtiment jusqu'au palier `up_to_tier` (mêmes règles que le
# cache global). Pour l'UI : résumé des bonus actifs d'un bâtiment. {} si gelé.
func building_effects(building_id: String, up_to_tier: int) -> Dictionary:
	var out: Dictionary = {}
	var b := GameData.get_entity(building_id)
	if not b.is_empty() and not b.get("gele", false) and up_to_tier >= 0:
		_accumulate_building(out, b, up_to_tier)
	return out

# Cumule (selon CHANNEL_RULE) les effets des paliers 0..up_to_tier d'un bâtiment
# dans `target`. Statique : partagé par le cache global et l'agrégat par bâtiment.
static func _accumulate_building(target: Dictionary, b: Dictionary, up_to_tier: int) -> void:
	var bpp: Dictionary = b.get("bonus_par_palier", {})
	for t in range(0, up_to_tier + 1):
		for effect in bpp.get(t, []):
			var ch := str(effect.get("channel", ""))
			if ch == "":
				continue
			var value := float(effect.get("value", 0.0))
			match CHANNEL_RULE.get(ch, "sum"):
				"max":
					target[ch] = maxf(target.get(ch, value), value)
				"or":
					target[ch] = 1.0 if (target.get(ch, 0.0) >= 1.0 or value >= 1.0) else 0.0
				_:
					target[ch] = target.get(ch, 0.0) + value

# Valeur agrégée d'un canal. Défaut : 0, sauf le palier d'immunité aux debuffs
# (−1 = aucune immunité).
func get_bonus(channel: String) -> float:
	if channel == CH_DEBUFF_IMMUNITY:
		return _bonuses.get(channel, -1.0)
	return _bonuses.get(channel, 0.0)

# ─── Accesseurs dérivés (utilisés par le câblage combat/aventure) ──────────

# Jauge ATB de départ du héros (fraction 0..1) pour un combat : max entre la
# valeur d'embuscade (si embuscade) et la valeur « toute expédition » (Tour T5).
func hero_gauge_start(ambush: bool) -> float:
	var g := get_bonus(CH_ALL_EXP_GAUGE)
	if ambush:
		g = maxf(g, get_bonus(CH_AMBUSH_GAUGE))
	return clampf(g, 0.0, 1.0)

# Le héros dispose-t-il du filet « 1er coup létal annulé » (Palissade T5) ?
func has_lethal_shield() -> bool:
	return get_bonus(CH_IGNORE_LETHAL) >= 1.0

# Le poison de biome est-il neutralisé contre un ennemi de ce palier (Jardin T5) ?
func poison_immune_for_tier(enemy_tier: int) -> bool:
	return float(enemy_tier) <= get_bonus(CH_DEBUFF_IMMUNITY)
