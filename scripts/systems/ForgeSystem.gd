# ============================================================
# ForgeSystem.gd — Évolution & arbre d'équipement (Chantier 5).
#
# La Forge gère TOUT l'équipement : montée en palier (Maîtrise par XP, SANS
# ingrédient) ET arbre d'amélioration par nœuds (points de Forge ; seuls les
# keystones consomment l'ingrédient rare du biome).
#
# Palier (A) : l'équipement gagne de l'XP en expédition (MasterySystem, buffer
# DÉSACTIVÉ pour l'équipement → l'excédent n'est pas perdu). À l'évolution
# (action joueur), il (1) ouvre une strate de l'arbre et (2) octroie un lot de
# points + convertit l'XP excédentaire en points (1 / FORGE_XP_PER_POINT).
#
# Arbre (B/C/D/E) : nœuds achetés aux points sous DEUX contraintes cumulées —
# connexité (un voisin acquis ; racine ouverte) et gate de strate (palier requis).
# Les % de stat (F) passent par l'agrégateur additif, SÉPARÉS par stat. Les effets
# de règle des notables/keystones sont fournis au combat.
#
# État joueur : GameData.player.forge[equipment_id] = { points, nodes[] }.
# Bonus du village (Chantier 4) : forge_points_reduction_* / forge_xp_reduction_*
# s'appliquent ici comme modificateurs de coût.
# ============================================================
extends Node

# Slot d'équipement (int) → clé de canal Forge du village (Chantier 4).
const SLOT_FORGE_KEY: Dictionary = { 0: "arme", 1: "anneau", 2: "armure" }

# Nom de stat d'un nœud → canal de bonus agrégé (partagé avec le village).
const STAT_CHANNEL: Dictionary = {
	"atk": "atk_pct", "def": "def_pct", "crit": "crit_pct",
	"atb": "atb_pct", "hp": "hp_max_pct", "regen": "regen_pct", "drop": "drop_rare_pct",
}

var _trees_by_equipment: Dictionary = {}  # equipment_id → tree dict (cache)
var _stat_bonus: Dictionary = {}          # canal → % cumulé (équipements ÉQUIPÉS)
var _rules:      Dictionary = {}           # effets de règle agrégés (cf. _empty_rules)

func _ready() -> void:
	_index_trees()
	EventBus.load_completed.connect(refresh_bonuses)
	EventBus.equipment_changed.connect(refresh_bonuses)
	refresh_bonuses()

func _index_trees() -> void:
	_trees_by_equipment.clear()
	for eid in GameData.entities:
		var e: Dictionary = GameData.entities[eid]
		if e.get("entity_type", "") == Enums.EntityType.FORGE_TREE:
			_trees_by_equipment[str(e.get("equipment_id", ""))] = e

# ═══════════════════════════════════════════════════════════
#  État
# ═══════════════════════════════════════════════════════════

func tree_for(equipment_id: String) -> Dictionary:
	return _trees_by_equipment.get(equipment_id, {})

# État de Forge d'un équipement (créé à la volée), { points, nodes[] }.
func forge_state(equipment_id: String) -> Dictionary:
	var forge: Dictionary = GameData.player.get("forge", {})
	if not forge.has(equipment_id):
		forge[equipment_id] = { "points": 0, "nodes": [] }
		GameData.player["forge"] = forge
	return forge[equipment_id]

func points(equipment_id: String) -> int:
	return int(forge_state(equipment_id).get("points", 0))

func node_owned(equipment_id: String, node_id: String) -> bool:
	return node_id in forge_state(equipment_id).get("nodes", [])

func _equip_tier(equipment_id: String) -> int:
	return int(GameData.get_entity(equipment_id).get("maitrise_actuelle", 0))

func _node_in_tree(tree: Dictionary, node_id: String) -> Dictionary:
	for n in tree.get("nodes", []):
		if str(n.get("id", "")) == node_id:
			return n
	return {}

# ═══════════════════════════════════════════════════════════
#  Palier d'équipement (A)
# ═══════════════════════════════════════════════════════════

# Coût d'XP EFFECTIF pour évoluer (réduction forge_xp du village appliquée).
func effective_evolve_cost(equipment_id: String) -> float:
	var tier := _equip_tier(equipment_id)
	if tier >= GameData.get_max_tier_for_type(Enums.EntityType.EQUIPMENT):
		return -1.0
	var base := Balance.evolve_cost(Enums.EntityType.EQUIPMENT, tier + 1)
	var red  := VillageBuildings.get_bonus("forge_xp_reduction_" + _slot_key(equipment_id))
	return base * (1.0 - clampf(red, 0.0, 0.95))

func can_evolve_equipment(equipment_id: String) -> bool:
	var cost := effective_evolve_cost(equipment_id)
	if cost < 0.0:
		return false
	return float(GameData.get_entity(equipment_id).get("xp_maitrise_actuelle", 0.0)) >= cost

# Évolue l'équipement d'un palier : ouvre une strate + octroie le lot de points +
# convertit l'XP excédentaire en points (1 / FORGE_XP_PER_POINT), SANS buffer.
# Retourne le nouveau palier, ou -1 si impossible.
func evolve_equipment(equipment_id: String) -> int:
	if not can_evolve_equipment(equipment_id):
		return -1
	var equip := GameData.get_entity(equipment_id)
	var cost  := effective_evolve_cost(equipment_id)
	var tier  := int(equip.get("maitrise_actuelle", 0))
	var new_tier := tier + 1

	# Points : lot de palier + conversion de l'XP au-delà du seuil (sans buffer).
	var overflow := maxf(float(equip.get("xp_maitrise_actuelle", 0.0)) - cost, 0.0)
	var minted   := Balance.forge_palier_lot(new_tier) + int(floor(overflow / Balance.FORGE_XP_PER_POINT))

	equip["maitrise_actuelle"]          = new_tier
	equip["xp_maitrise_actuelle"]       = 0.0
	equip["xp_maitrise_palier_suivant"] = GameData.palier_suivant_cost(Enums.EntityType.EQUIPMENT, new_tier)

	var st: Dictionary = forge_state(equipment_id)
	st["points"] = int(st.get("points", 0)) + minted

	refresh_bonuses()
	EventBus.equipement_evolue.emit(equipment_id, new_tier)
	EventBus.forge_tree_changed.emit(equipment_id)
	return new_tier

# ═══════════════════════════════════════════════════════════
#  Achat de nœuds (B/C/D/E)
# ═══════════════════════════════════════════════════════════

# "owned" | "available" | "locked_strate" | "locked_connexite"
func node_state(equipment_id: String, node_id: String) -> String:
	var tree := tree_for(equipment_id)
	var node := _node_in_tree(tree, node_id)
	if node.is_empty():
		return "locked_strate"
	if node_owned(equipment_id, node_id):
		return "owned"
	if _equip_tier(equipment_id) < int(node.get("strate", 1)):
		return "locked_strate"
	if node.get("root", false):
		return "available"
	for other in tree.get("nodes", []):
		if _adjacent(node, other) and node_owned(equipment_id, str(other.get("id", ""))):
			return "available"
	return "locked_connexite"

func _adjacent(a: Dictionary, b: Dictionary) -> bool:
	var aid := str(a.get("id", "")); var bid := str(b.get("id", ""))
	if aid == bid:
		return false
	return bid in a.get("adj", []) or aid in b.get("adj", [])

# Coût en points d'un nœud (réduction forge_points du village appliquée), arrondi.
func node_point_cost(equipment_id: String, node: Dictionary) -> int:
	var base := Balance.forge_node_point_cost(int(node.get("strate", 1)), str(node.get("type", "")))
	var red  := VillageBuildings.get_bonus("forge_points_reduction_" + _slot_key(equipment_id))
	return int(round(float(base) * (1.0 - clampf(red, 0.0, 0.95))))

# Ingrédient rare requis par un keystone : { res_id, qty }, {} si non-keystone.
func node_ingredient_cost(equipment_id: String, node: Dictionary) -> Dictionary:
	if str(node.get("type", "")) != "keystone":
		return {}
	var qty := Balance.forge_keystone_ingredient_qty(int(node.get("strate", 1)))
	if qty <= 0:
		return {}
	var biome := GameData.get_entity(str(GameData.get_entity(equipment_id).get("biome_source_id", "")))
	var rid := str(biome.get("ressource_rare_id", ""))
	if rid == "":
		return {}
	return { "res_id": rid, "qty": qty }

func can_buy_node(equipment_id: String, node_id: String) -> bool:
	if node_state(equipment_id, node_id) != "available":
		return false
	var node := _node_in_tree(tree_for(equipment_id), node_id)
	if points(equipment_id) < node_point_cost(equipment_id, node):
		return false
	var ing := node_ingredient_cost(equipment_id, node)
	if not ing.is_empty():
		if int(GameData.player.get("resources", {}).get(ing["res_id"], 0)) < int(ing["qty"]):
			return false
	return true

# Achète un nœud : consomme points (+ ingrédient si keystone), l'ajoute aux acquis.
func buy_node(equipment_id: String, node_id: String) -> bool:
	if not can_buy_node(equipment_id, node_id):
		return false
	var node := _node_in_tree(tree_for(equipment_id), node_id)
	var st: Dictionary = forge_state(equipment_id)
	st["points"] = int(st["points"]) - node_point_cost(equipment_id, node)

	var ing := node_ingredient_cost(equipment_id, node)
	if not ing.is_empty():
		var res: Dictionary = GameData.player.get("resources", {})
		res[ing["res_id"]] = maxi(0, int(res.get(ing["res_id"], 0)) - int(ing["qty"]))
		GameData.player["resources"] = res
		EventBus.resources_changed.emit()

	(st["nodes"] as Array).append(node_id)
	refresh_bonuses()
	EventBus.forge_tree_changed.emit(equipment_id)
	return true

# ═══════════════════════════════════════════════════════════
#  Agrégation des bonus (F + effets de règle)
# ═══════════════════════════════════════════════════════════

func _empty_rules() -> Dictionary:
	return {
		"def_ignore_pct": 0.0, "crit_mult": 0.0, "gauge_start": 0.0,
		"endurcissement_counter_pct": 0.0, "poison_stack_reduction": 0,
		"ambush_negate": false, "cond_atk_hp_above": [], "residual": {},
	}

# Recalcule les bonus depuis les nœuds acquis des équipements ÉQUIPÉS uniquement.
func refresh_bonuses() -> void:
	_stat_bonus = {}
	_rules = _empty_rules()
	for item_id in GameData.player.get("equipped", {}).values():
		if item_id == "" or not _trees_by_equipment.has(item_id):
			continue
		_aggregate_equipment(str(item_id))

func _aggregate_equipment(equipment_id: String) -> void:
	var tree := tree_for(equipment_id)
	var tier := _equip_tier(equipment_id)
	for node_id in forge_state(equipment_id).get("nodes", []):
		var node := _node_in_tree(tree, str(node_id))
		if node.is_empty():
			continue
		# % de base (mineur/notable) sur la stat du nœud.
		var stat := str(node.get("stat", ""))
		if stat != "" and STAT_CHANNEL.has(stat):
			_add_stat(STAT_CHANNEL[stat], Balance.forge_node_stat_pct(int(node.get("strate", 1)), str(node.get("type", ""))))
		_apply_effect(node, tier)

func _apply_effect(node: Dictionary, tier: int) -> void:
	var eff := node.get("effect", {}) as Dictionary
	if eff.is_empty():
		return
	match str(eff.get("kind", "")):
		"stat_pct":
			if STAT_CHANNEL.has(str(eff.get("stat", ""))):
				_add_stat(STAT_CHANNEL[eff["stat"]], float(eff.get("value", 0.0)))
		"per_tier":
			if STAT_CHANNEL.has(str(eff.get("stat", ""))):
				_add_stat(STAT_CHANNEL[eff["stat"]], float(eff.get("value", 0.0)) * float(tier))
		"crit_mult":
			_rules["crit_mult"] += float(eff.get("value", 0.0))
		"gauge_start":
			_rules["gauge_start"] += float(eff.get("value", 0.0))
		"def_ignore":
			_rules["def_ignore_pct"] += float(eff.get("value", 0.0))
		"endurcissement_counter":
			_rules["endurcissement_counter_pct"] += float(eff.get("value", 0.0))
		"poison_stack_reduction":
			_rules["poison_stack_reduction"] += int(eff.get("value", 0))
		"ambush_negate":
			_rules["ambush_negate"] = true
		"cond_atk_hp_above":
			# Le % conditionnel = barème notable de la strate du nœud.
			(_rules["cond_atk_hp_above"] as Array).append({
				"hp_frac": float(eff.get("hp_frac", 0.8)),
				"pct": Balance.forge_node_stat_pct(int(node.get("strate", 1)), "notable"),
			})
		"residual":
			# Un seul résidu géré (rail poison passif) ; on garde le plus fort.
			var cur := _rules["residual"] as Dictionary
			if cur.is_empty() or float(eff.get("damage_pct", 0.0)) > float(cur.get("damage_pct", 0.0)):
				_rules["residual"] = {
					"chance": float(eff.get("chance", 1.0)),
					"damage_pct": float(eff.get("damage_pct", 0.0)),
					"duration": int(eff.get("duration", 2)),
				}

func _add_stat(channel: String, value: float) -> void:
	_stat_bonus[channel] = float(_stat_bonus.get(channel, 0.0)) + value

# Bonus de stat % agrégé d'un canal (équipements équipés).
func get_stat_bonus(channel: String) -> float:
	return float(_stat_bonus.get(channel, 0.0))

# Effets de règle agrégés (copie défensive) pour le combat.
func combat_rules() -> Dictionary:
	return _rules.duplicate(true)

# ═══════════════════════════════════════════════════════════
#  Utilitaires
# ═══════════════════════════════════════════════════════════

func _slot_key(equipment_id: String) -> String:
	return SLOT_FORGE_KEY.get(int(GameData.get_entity(equipment_id).get("slot", 0)), "arme")
