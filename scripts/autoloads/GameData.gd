# ============================================================
# GameData.gd — Source de vérité unique pour les données du jeu.
#
# Responsabilités :
#   1. Charger les entités depuis les fichiers JSON au démarrage.
#   2. Maintenir l'état runtime du joueur (stats, inventaire, etc.).
#   3. Exposer des méthodes typées pour lire / modifier ces données.
#
# Structure des entités :
#   • Entités à maîtrise (creature / biome / passive / equipment) :
#     dict JSON + entity_type + maitrise_actuelle + xp_maitrise_actuelle + unlocked_passives
#   • Données statiques (resource / recipe) :
#     dict JSON + entity_type  (pas de progression)
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

# Labels des paliers dans l'ordre croissant (index = tier).
const MASTERY_TIERS: Array[String] = [
	"Commun", "Peu Commun", "Rare", "Épique", "Légendaire", "Unique"
]
const MAX_TIER: int = 5

# ─── Données de progression (source : Balance.gd) ───────────
# Référencées ici pour rester le point d'accès runtime habituel
# (GameData.xp_thresholds) ; la source de vérité reste Balance.

# XP cumulatif requis pour atteindre chaque tier [0, 100, 500, …]
var xp_thresholds: Array = []
# Dictionnaire écart_de_tier (int) → multiplicateur d'XP reçu (float)
var xp_modifiers: Dictionary = {}

# ─── Catalogue d'entités ────────────────────────────────────

# Toutes les entités du jeu, indexées par leur id.
# Fusionnent définition JSON et état runtime.
var entities: Dictionary = {}

# ─── État courant du joueur ─────────────────────────────────

var pending_evolution: Dictionary = {}

# Biome dont l'évolution vient de libérer un Fragment (transient, non sauvé).
# Lu par EvolutionRitual pour afficher « libère un Fragment » seulement quand
# c'est vrai (à T4/T5 le Fragment du biome peut déjà être parti à T2).
var last_freed_fragment_biome: String = ""

var village: Dictionary = {
	"maitrise_actuelle":   0,     # 0→5 — palier de Maîtrise du Village, progressé par Fragments
	"fragments_collectes": [],
	"eclos":               false, # le Village n'existe pas tant qu'il n'a pas éclos (phase préliminaire)
	"clics_eclosion":      0,     # progression de la phase d'éclosion (→ Balance.ECLOSION_CLICS)
}

var player: Dictionary = {
	"resources":          {},          # item_id → quantité possédée
	"active_biome_id":    "",
	"active_passives":    [],
	"equipped": {
		"arme":     "",
		"anneau":   "",
		"armure":   "",
		"ceinture": "",
		"bouclier": "",
		"talisman": ""
	},
	"equipment_inventory": [],
	"bestiary": {}   # enc_id → { name, type, biome_id, biome_name, count, xp, tier }
}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_init_progression_constants()
	_load_all_entities()
	_validate_entities()
	EventBus.entity_evolved.connect(_on_entity_evolved)

# Référence les constantes de progression depuis Balance (source unique).
func _init_progression_constants() -> void:
	xp_thresholds = Balance.XP_THRESHOLDS
	xp_modifiers  = Balance.XP_GAP_MODIFIERS

# Charge toutes les entités depuis leurs dossiers respectifs.
func _load_all_entities() -> void:
	# Entités à Maîtrise (progression XP + évolution manuelle)
	_load_tres_folder("res://data/biomes/",          Enums.EntityType.BIOME)
	_load_tres_folder("res://data/creatures/",       Enums.EntityType.CREATURE)
	_load_tres_folder("res://data/passifs_uniques/", Enums.EntityType.PASSIF_UNIQUE)
	_load_tres_folder("res://data/pieges/",          Enums.EntityType.TRAP)
	_load_tres_folder("res://data/benedictions/",    Enums.EntityType.BENEDICTION)
	# Données statiques JSON — chargées EN PREMIER pour que les .tres les écrasent si même ID
	_load_data_from_folder("res://data/resources/", Enums.EntityType.RESOURCE)
	_load_data_from_folder("res://data/forge/",     Enums.EntityType.RECIPE)
	# Données statiques .tres (sans progression) — écrasent les resources/ si ID partagé
	_load_tres_folder("res://data/ingredients/", Enums.EntityType.INGREDIENT, false)
	_load_tres_folder("res://data/fragments/",   Enums.EntityType.FRAGMENT,   false)
	# Héros, passifs et équipements : entités à Maîtrise
	_load_tres_folder("res://data/hero/",        Enums.EntityType.HERO)
	_load_tres_folder("res://data/passives/",    Enums.EntityType.PASSIVE)
	_load_tres_folder("res://data/equipements/", Enums.EntityType.EQUIPMENT)

# Charge tous les .tres d'un dossier dans le catalogue d'entités.
# with_mastery = true → initialise les champs de progression de Maîtrise
# (maitrise_actuelle, xp_maitrise_actuelle, unlocked_passives, coût du palier suivant).
# with_mastery = false → données statiques telles quelles (ingrédients, fragments).
func _load_tres_folder(path: String, entity_type: String, with_mastery: bool = true) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res := load(path + file_name)
			var id_val = res.get("id") if res != null else null
			if id_val != null and id_val != "":
				var data := _resource_to_dict(res)
				data["entity_type"] = entity_type
				if with_mastery:
					# maitrise_actuelle / xp_maitrise_actuelle proviennent du .tres (source de vérité).
					if not data.has("maitrise_actuelle"):
						data["maitrise_actuelle"] = 0
					if not data.has("xp_maitrise_actuelle"):
						data["xp_maitrise_actuelle"] = 0.0
					data["unlocked_passives"] = []
					data["xp_maitrise_palier_suivant"] = palier_suivant_cost(entity_type, int(data["maitrise_actuelle"]))
				entities[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Convertit un Resource en Dictionary en extrayant toutes ses propriétés de script.
# Les sous-Resources et tableaux de Resources sont convertis récursivement.
func _resource_to_dict(res: Resource) -> Dictionary:
	var data: Dictionary = {}
	var skip := ["script", "resource_path", "resource_name", "resource_local_to_scene"]
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE and not skip.has(prop.name):
			var val = res.get(prop.name)
			if val is Resource:
				data[prop.name] = _resource_to_dict(val)
			elif val is Array:
				var arr: Array = []
				for item in val:
					if item is Resource:
						arr.append(_resource_to_dict(item))
					else:
						arr.append(item)
				data[prop.name] = arr
			else:
				data[prop.name] = val
	return data

# Charge un dossier de données statiques (sans champs de progression).
func _load_data_from_folder(path: String, entity_type: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data = _read_json(path + file_name)
			if not data.is_empty() and data.has("id"):
				data["entity_type"] = entity_type
				entities[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# Vérifie la cohérence minimale des données chargées : champs obligatoires
# manquants ou valeurs inattendues → push_warning. Ne bloque jamais le jeu ;
# ce filet sert à repérer les .tres incomplets ou mal remplis pendant le
# développement (les .get(..., défaut) masqueraient l'erreur silencieusement).
func _validate_entities() -> void:
	for eid in entities:
		var e: Dictionary = entities[eid]
		var etype: String = e.get("entity_type", "")

		# Toute entité affichée à l'écran doit avoir un nom.
		# `name` est accepté en repli (convention des passifs, ex-JSON), et les
		# placeholders pas encore débloqués (est_debloque = false) sont ignorés.
		if etype not in [Enums.EntityType.RESOURCE, Enums.EntityType.RECIPE] \
				and e.get("est_debloque", true) \
				and str(e.get("nom_affichage_fr", "")) == "" \
				and str(e.get("name", "")) == "":
			push_warning("GameData: %s (%s) sans nom_affichage_fr ni name" % [eid, etype])

		match etype:
			Enums.EntityType.CREATURE:
				if (e.get("stats_par_palier", {}) as Dictionary).is_empty():
					push_warning("GameData: créature %s sans stats_par_palier" % eid)
				if str(e.get("biome_id", "")) == "":
					push_warning("GameData: créature %s sans biome_id (plafond de Maîtrise incalculable)" % eid)
			Enums.EntityType.BENEDICTION:
				var eff := str(e.get("effet", ""))
				if eff not in [Enums.BlessEffect.HEAL, Enums.BlessEffect.XP_BONUS]:
					push_warning("GameData: bénédiction %s — effet inconnu « %s »" % [eid, eff])

# Lit et parse un fichier JSON. Retourne {} en cas d'erreur.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err  = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("GameData: erreur parsing JSON — " + path)
		return {}
	return json.get_data()

# ═══════════════════════════════════════════════════════════
#  Village
# ═══════════════════════════════════════════════════════════

# Hook entity_evolved : équipement du biome (Peu Commun), Fragment (Rare),
# biome secondaire révélé (Légendaire).
func _on_entity_evolved(entity_id: String, new_tier: int) -> void:
	var entity := get_entity(entity_id)
	if entity.get("entity_type", "") != Enums.EntityType.BIOME:
		return

	# Le plafond des créatures du biome vient de monter : réévaluer leur XP stockée
	# pour signaler les paliers redevenus franchissables (cf. plafonnement créature/biome).
	MasterySystem.reevaluate_creatures_for_biome(entity_id)

	# Peu Commun (T1) → l'équipement du biome est obtenu (au palier Commun/T0)
	if new_tier >= Balance.EQUIPMENT_UNLOCK_BIOME_TIER:
		unlock_biome_equipment(entity_id)

	# Rare (T2), Légendaire (T4), Unique (T5) → libération d'un Fragment
	if new_tier in Balance.FRAGMENT_RELEASE_TIERS:
		var fid := uncollected_fragment_for(entity_id)
		if fid != "":
			entities[fid]["est_collecte"] = true
			village["fragments_collectes"].append(fid)
			last_freed_fragment_biome = entity_id
			EventBus.fragment_libere.emit(fid, entity_id)

	# Légendaire (tier 4) → révélation du biome secondaire
	if new_tier == Balance.SECONDARY_BIOME_REVEAL_TIER:
		var secondary_id := entity.get("biome_secondaire_id", "") as String
		if secondary_id == "":
			return
		var secondary := get_entity(secondary_id)
		if secondary.is_empty() or secondary.get("est_decouvert", false):
			return
		secondary["est_decouvert"] = true
		EventBus.biome_revele.emit(secondary_id)

# Premier Fragment encore non collecté lié à ce biome ("" si tous collectés).
# Sert à la libération (_on_entity_evolved) ET à l'UI (annonce des jalons :
# « le prochain palier libère un Fragment » seulement s'il en reste un).
func uncollected_fragment_for(biome_id: String) -> String:
	for fid in entities:
		var frag: Dictionary = entities[fid]
		if frag.get("entity_type", "") != Enums.EntityType.FRAGMENT:
			continue
		if frag.get("biome_source_id", "") != biome_id:
			continue
		if frag.get("est_collecte", false):
			continue
		return fid
	return ""

# Clé de slot (player.equipped) par index `slot` des EquipmentData.
const EQUIP_SLOT_KEYS: Array[String] = [
	"arme", "anneau", "armure", "ceinture", "bouclier", "talisman",
]

# Débloque et équipe l'équipement lié à un biome — règle : biome Peu
# Commun (T1) → équipement obtenu au palier Commun (T0). Ne fait rien si
# déjà débloqué ou si l'équipement est un placeholder sans contenu.
func unlock_biome_equipment(biome_id: String) -> void:
	for eid in entities:
		var equip: Dictionary = entities[eid]
		if equip.get("entity_type", "") != Enums.EntityType.EQUIPMENT:
			continue
		if equip.get("biome_source_id", "") != biome_id:
			continue
		if equip.get("est_debloque", false):
			continue
		if str(equip.get("nom_affichage_fr", "")) == "":
			continue
		equip["est_debloque"] = true
		var slot_idx := int(equip.get("slot", 0))
		if slot_idx < EQUIP_SLOT_KEYS.size():
			var slot_key := EQUIP_SLOT_KEYS[slot_idx]
			if str(player["equipped"].get(slot_key, "")) == "":
				player["equipped"][slot_key] = eid
		EventBus.equipment_unlocked.emit(eid)
		EventBus.equipment_changed.emit()

# Rattrapage (anciennes sauvegardes / changement de règle), appelé après
# load : biome Peu Commun+ → équipement livré ; biome en dessous →
# équipement repris (la règle s'applique rétroactivement).
func reconcile_equipment_unlocks() -> void:
	for eid in entities:
		var equip: Dictionary = entities[eid]
		if equip.get("entity_type", "") != Enums.EntityType.EQUIPMENT:
			continue
		var bid := str(equip.get("biome_source_id", ""))
		if bid == "" or str(equip.get("nom_affichage_fr", "")) == "":
			continue   # placeholder sans contenu
		var btier := int(get_entity(bid).get("maitrise_actuelle", 0))
		if btier >= Balance.EQUIPMENT_UNLOCK_BIOME_TIER:
			unlock_biome_equipment(bid)
		elif equip.get("est_debloque", false):
			equip["est_debloque"] = false
			var slot_idx := int(equip.get("slot", 0))
			if slot_idx < EQUIP_SLOT_KEYS.size() \
					and str(player["equipped"].get(EQUIP_SLOT_KEYS[slot_idx], "")) == eid:
				player["equipped"][EQUIP_SLOT_KEYS[slot_idx]] = ""

# Retourne true si le Village peut passer au palier de Maîtrise suivant.
# Condition unique : Fragments collectés ≥ coût du palier courant (Balance.VILLAGE_FRAGMENT_COSTS).
func can_upgrade_village() -> bool:
	var current := int(village.get("maitrise_actuelle", 0))
	if current >= Balance.VILLAGE_FRAGMENT_COSTS.size():
		return false
	var req := Balance.VILLAGE_FRAGMENT_COSTS[current]
	return village.get("fragments_collectes", []).size() >= req

# Passe le Village au palier de Maîtrise suivant. Retourne false si impossible.
func upgrade_village() -> bool:
	if not can_upgrade_village():
		return false
	village["maitrise_actuelle"] = int(village.get("maitrise_actuelle", 0)) + 1
	EventBus.village_tier_change.emit(village["maitrise_actuelle"])
	return true

# ═══════════════════════════════════════════════════════════
#  Accesseurs — Entités
# ═══════════════════════════════════════════════════════════

# Retourne le dict d'une entité par son id, ou {} si introuvable.
func get_entity(entity_id: String) -> Dictionary:
	return entities.get(entity_id, {})

# Retourne le nom du palier correspondant à un tier (0–5).
func get_tier_name(tier: int) -> String:
	if tier < 0 or tier >= MASTERY_TIERS.size():
		return Translations.T("tier.unknown")
	return Translations.T("tier." + str(tier))

# Palier maximum d'un type d'entité (créatures → Légendaire 4 ; reste → Unique 5).
func get_max_tier_for_type(entity_type: String) -> int:
	return int(Balance.ENTITY_MAX_TIER.get(entity_type, Balance.DEFAULT_MAX_TIER))

# Coût d'XP pour franchir le palier suivant (courbe Balance), ou 0.0 si palier max
# de type atteint / hors courbe. Sert à alimenter xp_maitrise_palier_suivant.
func palier_suivant_cost(entity_type: String, tier: int) -> float:
	var next_idx := tier + 1
	if tier >= get_max_tier_for_type(entity_type) or next_idx >= xp_thresholds.size():
		return 0.0
	return float(xp_thresholds[next_idx])

# Stats brutes d'une entité pour un palier donné, lues dans stats_par_palier.
# Si le palier exact n'est pas défini dans le .tres, descend au palier
# inférieur le plus proche. Retourne {} si aucun palier n'est défini.
# Source unique de cette règle de descente (combat, pool de créatures, stats).
func stats_at_tier(entity: Dictionary, tier: int) -> Dictionary:
	var spp := entity.get("stats_par_palier", {}) as Dictionary
	var t   := tier
	while t >= 0:
		if spp.has(t):
			return spp[t] as Dictionary
		t -= 1
	return {}

# Stats effectives d'une entité au palier courant.
# Héros          → tables Balance.HERO_*_PER_TIER (non-linéaires, source unique).
# Créatures     → stats_par_palier[tier] du .tres (descend jusqu'au tier 0 si nécessaire).
# Équipements   → inchangé (géré par get_equipment_bonuses).
# Autres entités→ formule linéaire (atk_base + tier × atk_par_tier).
func get_effective_stats(entity_id: String) -> Dictionary:
	var entity = get_entity(entity_id)
	if entity.is_empty():
		return {}
	var tier := int(entity.get("maitrise_actuelle", 0))

	if entity.get("entity_type", "") == Enums.EntityType.HERO:
		var t := clampi(tier, 0, Balance.HERO_HP_PER_TIER.size() - 1)
		return {
			"atk":             Balance.HERO_ATK_PER_TIER[t],
			"def":             Balance.HERO_DEF_PER_TIER[t],
			"hp":              Balance.HERO_HP_PER_TIER[t],
			"vit":             Balance.HERO_VIT,
			"crit_chance":     float(entity.get("crit_chance",     Balance.CRIT_CHANCE)),
			"crit_multiplier": float(entity.get("crit_multiplier", Balance.CRIT_MULTIPLIER)),
		}

	var s := stats_at_tier(entity, tier)
	if not s.is_empty():
		return {
			"atk":             int(s.get("atk", 0)),
			"def":             int(s.get("def", 0)),
			"hp":              int(s.get("hp",  0)),
			"vit":             int(s.get("vit", 20)),
			"crit_chance":     float(entity.get("crit_chance",     Balance.CRIT_CHANCE)),
			"crit_multiplier": float(entity.get("crit_multiplier", Balance.CRIT_MULTIPLIER)),
		}

	return {
		"atk":             int(entity.get("atk", 0)) + tier * int(entity.get("atk_par_tier", 0)),
		"def":             int(entity.get("def", 0)) + tier * int(entity.get("def_par_tier", 0)),
		"hp":              int(entity.get("hp",  0)) + tier * int(entity.get("hp_par_tier",  0)),
		"vit":             int(entity.get("vit", 0)) + tier * int(entity.get("vit_par_tier", 0)),
		"crit_chance":     float(entity.get("crit_chance",     Balance.CRIT_CHANCE)),
		"crit_multiplier": float(entity.get("crit_multiplier", Balance.CRIT_MULTIPLIER)),
	}

# Bonus cumulés de tous les équipements portés.
# Retourne au minimum { atk:0, hp:0, attack_speed_pct:0 }.
func get_equipment_bonuses() -> Dictionary:
	var bonuses: Dictionary = {"atk": 0.0, "hp": 0.0, "attack_speed_pct": 0.0}
	for item_id in player.get("equipped", {}).values():
		if item_id == "":
			continue
		var item = get_entity(item_id)
		if item.is_empty():
			continue
		var tier     := int(item.get("maitrise_actuelle", 0))
		var spm      := item.get("stats_par_palier", {}) as Dictionary
		var item_stats: Dictionary = spm.get(tier, spm.get(0, {}))
		for key in item_stats:
			bonuses[key] = bonuses.get(key, 0.0) + float(item_stats[key])
	return bonuses

# Retourne la recette (Array de {ingredient_id, quantite}) pour le palier cible,
# ou [] si aucune recette n'est définie.
func get_forge_recipe(equipment_id: String, target_tier: int) -> Array:
	var equip := get_entity(equipment_id)
	if equip.is_empty():
		return []
	return (equip.get("recettes_evolution", {}) as Dictionary).get(target_tier, []) as Array

# Retourne true si l'équipement peut être forgé au palier suivant.
# Conditions : XP barre pleine (MasterySystem) + ingrédients disponibles.
func can_forge(equipment_id: String) -> bool:
	var equip := get_entity(equipment_id)
	if equip.is_empty():
		return false
	var current := int(equip.get("maitrise_actuelle", 0))
	if current >= get_max_tier_for_type(Enums.EntityType.EQUIPMENT):
		return false
	if not MasterySystem.can_evolve(equipment_id):
		return false
	var recipe := get_forge_recipe(equipment_id, current + 1)
	if recipe.is_empty():
		return false
	for req in recipe:
		var ingr_id := req.get("ingredient_id", "") as String
		if ingr_id.is_empty() or int(player["resources"].get(ingr_id, 0)) < int(req.get("quantite", 1)):
			return false
	return true

# Retourne true si l'XP de l'équipement est pleine (barre remplie) pour le palier suivant.
func equipment_xp_full(equipment_id: String) -> bool:
	return MasterySystem.can_evolve(equipment_id)

# Forge l'équipement au palier suivant : consomme les ingrédients, monte le palier, reset XP.
# Retourne false si impossible.
func forge(equipment_id: String) -> bool:
	if not can_forge(equipment_id):
		return false
	var equip   := get_entity(equipment_id)
	var current := int(equip.get("maitrise_actuelle", 0))
	var recipe  := get_forge_recipe(equipment_id, current + 1)
	for req in recipe:
		var ingr_id := req.get("ingredient_id", "") as String
		var consume := int(req.get("quantite", 1))
		player["resources"][ingr_id] = maxi(0, int(player["resources"].get(ingr_id, 0)) - consume)
	equip["maitrise_actuelle"]           = current + 1
	equip["xp_maitrise_actuelle"]        = 0.0
	equip["xp_maitrise_palier_suivant"]  = palier_suivant_cost(Enums.EntityType.EQUIPMENT, current + 1)
	EventBus.equipement_evolue.emit(equipment_id, current + 1)
	EventBus.resources_changed.emit()
	return true

# ═══════════════════════════════════════════════════════════
#  Hall des Évolutions (Bestiaire)
# ═══════════════════════════════════════════════════════════

# Crée ou met à jour une entrée dans le Hall des Évolutions.
#
# xp_reward == 0 : début de rencontre (compteur incrémenté, pas d'XP).
# xp_reward  > 0 : rencontre terminée — XP distribué, tier vérifié.
#
# Le tier du Hall est indépendant du tier de l'entité dans le jeu :
# il mesure la familiarité du joueur avec cette rencontre spécifique.
func record_encounter(enc_id: String, enc_name: String, enc_type: String,
		biome_id: String, xp_reward: float) -> void:
	if enc_id == "":
		return

	var hall: Dictionary = player.get("bestiary", {})

	# Première rencontre : création de l'entrée
	var is_new := not hall.has(enc_id)
	if is_new:
		var biome = get_entity(biome_id)
		hall[enc_id] = {
			"name":       enc_name,
			"type":       enc_type,
			"biome_id":   biome_id,
			"biome_name": biome.get("nom_affichage_fr", biome_id),
			"count":      0,
			"xp":         0.0,
			"tier":       0
		}

	var entry: Dictionary = hall[enc_id]

	# count n'est incrémenté qu'à la complétion (xp_reward > 0) pour éviter
	# le double-comptage : l'entrée est créée au début du combat (xp=0)
	# mais le kill n'est confirmé qu'à la victoire (xp>0).
	if xp_reward > 0.0:
		entry["count"] += 1
		entry["xp"]    += xp_reward
		var tier: int = entry.get("tier", 0)
		while tier < MAX_TIER:
			var next_idx: int = tier + 1
			if next_idx >= xp_thresholds.size():
				break
			if entry["xp"] < float(xp_thresholds[next_idx]):
				break
			entry["xp"]   -= float(xp_thresholds[next_idx])
			entry["tier"] += 1
			tier            = entry["tier"]

	# Pas de player["bestiary"] = hall : hall est déjà la même référence
	EventBus.bestiary_updated.emit(enc_id)
	if is_new:
		EventBus.entity_discovered.emit(enc_id)

# ═══════════════════════════════════════════════════════════
#  Ressources
# ═══════════════════════════════════════════════════════════

# Ajoute qty unités d'une ressource à l'inventaire du joueur.
func add_resource(item_id: String, qty: int) -> void:
	player["resources"][item_id] = int(player["resources"].get(item_id, 0)) + qty
	EventBus.resources_changed.emit()

# ═══════════════════════════════════════════════════════════
#  Combat — Bonus de maîtrise spécifique à un ennemi
# ═══════════════════════════════════════════════════════════

# Retourne un bonus d'ATK basé sur la maîtrise accumulée face à cet ennemi précis.
# Formule : tier_hall × Balance.MASTERY_COMBAT_ATK_PER_TIER.
# Récompense les joueurs qui s'acharnent sur le même type d'ennemi.
func get_mastery_combat_bonus(enemy_id: String) -> float:
	var entry = player.get("bestiary", {}).get(enemy_id, {})
	return float(entry.get("tier", 0)) * Balance.MASTERY_COMBAT_ATK_PER_TIER
