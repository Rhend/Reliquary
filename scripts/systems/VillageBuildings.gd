# ============================================================
# VillageBuildings.gd — Quartiers & bâtiments (Chantier 4 ; coûts refondus
# au chantier 12 — rework économique du QG).
#
# Responsabilités :
#   1. État : palier de chaque bâtiment (Délabré → T5). Vit dans
#      GameData.village (buildings) → sauvegardé avec le reste du village
#      (merge tolérant SaveManager), aucune migration.
#   2. Coûts (chantier 12) : courbe UNIQUE Euren + Modules, data-driven
#      (data/progression/couts_batiments.tres). Les anciennes ressources
#      silotées par biome ne sont PLUS JAMAIS demandées par les bâtiments
#      (elles existent toujours en jeu — rework des drops au fil de l'eau).
#   3. Actions : améliorer un bâtiment — débite Euren/Modules via
#      ProgressionHeros (source unique des soldes).
#   4. Bonus : agrège les effets passifs débloqués palier par palier en canaux
#      nommés. Tous les % passent ensuite par l'agrégateur additif (StatStacker)
#      aux points de consommation (combat, régén, XP, drops…). Encodage
#      INCRÉMENTAL dans les .tres : un bâtiment au palier T cumule les paliers 0..T.
#
# ROUTES : SUPPRIMÉES au chantier 12 (les quartiers de base — Avatar,
# Expédition, Atelier — sont accessibles d'emblée, le QG n'a plus de palier
# de rareté propre). Neutralisé : coût des routes (Balance.VILLAGE_ROUTE_COSTS),
# gate Forge (Balance.FORGE_HUB_UNLOCK_VILLAGE_TIER), route_built/rebuild_route
# et la section route des panneaux. GameData.village["routes"] des anciennes
# sauvegardes est ignoré (merge tolérant, clé inerte).
#
# Bonus NON traités ici (Chantier 5 — Forge) : les canaux forge_points_* /
# forge_xp_* sont agrégés (get_bonus) mais inertes tant que la Forge (points,
# seuil d'XP, arbres d'équipement) n'existe pas.
# ============================================================
extends Node

# Courbe de coût Euren + Modules (chantier 12) — data-driven, provisoire.
const COUTS: BatimentsCoutsData = preload("res://data/progression/couts_batiments.tres")

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
#  Coûts (chantier 12 : Euren + Modules, courbe unique data-driven)
# ═══════════════════════════════════════════════════════════

# Coût pour amener un bâtiment à son palier SUIVANT :
# { "euren": float, "modules": int }. {} si gelé, au palier max, ou inconnu.
# Courbe COMMUNE à tous les bâtiments — plus aucune ressource de biome.
func building_cost(building_id: String) -> Dictionary:
	var b := GameData.get_entity(building_id)
	if b.is_empty() or b.get("gele", false):
		return {}
	var target := building_tier(building_id) + 1
	if target < 0 or target > Balance.BUILDING_MAX_TIER:
		return {}
	return COUTS.cout(target)

# Le joueur peut-il payer un coût { euren, modules } ? (soldes ProgressionHeros)
func can_afford(cost: Dictionary) -> bool:
	if cost.is_empty():
		return false
	return ProgressionHeros.euren() >= float(cost.get("euren", 0.0)) \
			and ProgressionHeros.modules() >= int(cost.get("modules", 0))

# ═══════════════════════════════════════════════════════════
#  Actions
# ═══════════════════════════════════════════════════════════

# Bâtiment améliorable ? (non gelé, sous le palier max, payable — les routes
# n'existent plus : aucun gate de quartier depuis le chantier 12)
func can_upgrade_building(building_id: String) -> bool:
	var b := GameData.get_entity(building_id)
	if b.is_empty() or b.get("gele", false):
		return false
	if building_tier(building_id) >= Balance.BUILDING_MAX_TIER:
		return false
	return can_afford(building_cost(building_id))

# Améliore un bâtiment d'un palier : débite Euren + Modules, monte le palier,
# recalcule les bonus. Retourne le NOUVEAU palier, ou Balance.BUILDING_TIER_DELABRE−1
# (= -2) si impossible.
func upgrade_building(building_id: String) -> int:
	if not can_upgrade_building(building_id):
		return Balance.BUILDING_TIER_DELABRE - 1
	var cost := building_cost(building_id)
	# can_afford vient de passer : les deux débits ne peuvent pas échouer.
	ProgressionHeros.depenser_euren(float(cost.get("euren", 0.0)))
	ProgressionHeros.depenser_modules(int(cost.get("modules", 0)))
	var new_tier := building_tier(building_id) + 1
	var buildings: Dictionary = GameData.village.get("buildings", {})
	buildings[building_id] = new_tier
	GameData.village["buildings"] = buildings
	refresh_bonuses()
	EventBus.village_buildings_changed.emit()
	return new_tier

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
