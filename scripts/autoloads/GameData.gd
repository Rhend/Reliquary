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

# Courbe de coût d'évolution PAR DÉFAUT (type ×1.0 : créature/héros/piège/…),
# index = palier visé : [0, 100, 180, 324, 583, 1050]. Dérivée de Balance.evolve_cost.
# Le biome (×3) NE PASSE PAS par ce tableau : utiliser palier_suivant_cost(type, tier).
var xp_thresholds: Array = []

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
	"maitrise_actuelle":   0,     # 0→5 — palier de Maîtrise du Village (montée AUTO, critère par palier)
	"fragments_collectes": [],
	"kills_total":         0,     # créatures de farm vaincues (hors boss) — seuil Commun→Peu Commun
	"eclos":               false, # le Village n'existe pas tant qu'il n'a pas éclos (phase préliminaire)
	"clics_eclosion":      0,     # progression de la phase d'éclosion (→ Balance.ECLOSION_CLICS)
	# Chantier 4 — Quartiers & bâtiments. Sauvegardés avec le reste du village
	# (merge tolérant dans SaveManager) : aucune migration requise.
	# (La clé "routes" du chantier 4 a été supprimée au chantier 12 — les
	# quartiers de base sont ouverts d'emblée ; une vieille sauvegarde peut
	# encore la porter, elle est inerte via le merge tolérant.)
	"buildings":           {},    # building_id → palier (Balance.BUILDING_TIER_DELABRE = Délabré par défaut)
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
	"bestiary": {},  # enc_id → { name, type, biome_id, biome_name, count, xp, tier }
	# Forge (Chantier 5) : equipment_id → { points: int, nodes: [node_id] }.
	# Sauvegardé automatiquement (sous-dict de player).
	"forge": {},
	# Économie de récompense (Rework Combat, chantier 6) — état BRUT ; toute
	# la logique (courbe de niveau, crédit) vit dans ProgressionHeros.
	"heros_xp": 0.0,   # XP de NIVEAU du héros, totale cumulée (jamais perdue)
	"euren":    0.0,   # Euren possédé (crédité à la sortie d'expédition)
	# Économie du QG (Rework Combat, chantier 12) : Modules (devise rare —
	# +1 par première Fin d'étage, crédités à la sortie comme l'Euren).
	"modules":  0,
	# Alarme & assauts (Rework Combat, chantier 11) — dans la SAUVEGARDE DE
	# PARTIE (pas le méta) : la sauvegarde de lancement les capture, un Game
	# Over annule donc un kill fait PENDANT la run perdue (cohérent, testé).
	"expe_completions":    {},   # lieu_id → { palier_id: true } (strates complétées jusqu'au bout)
	"lieutenants_vaincus": {},   # lieu_id → true (premier kill = slot d'Alarme)
	# Chantier 12 : objets uniques de Lieutenants (« Sceau du <Lieu> »,
	# accordés au PREMIER kill — mêmes rails que le slot d'Alarme : crédités
	# au kill, annulés par le Game Over qui recharge la sauvegarde).
	"objets_lieutenants":  {},   # lieu_id → true (Sceau possédé — provenance narrative)
	# Chantier 13 (refonte du modèle « voie par Lieu » du ch.12) : les voies
	# s'ouvrent dans un ORDRE FIXE 1→6, 1 Sceau libre (interchangeable) = 1
	# voie — voies_ouvertes est un COMPTEUR (migration v13→v14 : ancien dict
	# lieu_id→true converti en taille). Voie 1 = Atelier/Forge.
	"voies_ouvertes":      0,
}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_init_progression_constants()
	_load_all_entities()
	_validate_entities()
	EventBus.entity_evolved.connect(_on_entity_evolved)

# Dérive la courbe de coût par défaut depuis Balance.evolve_cost (source unique).
# Index = palier visé ; index 0 inutilisé (pas de palier −1→0).
func _init_progression_constants() -> void:
	xp_thresholds = [0.0]
	for t in range(1, MAX_TIER + 1):
		xp_thresholds.append(Balance.evolve_cost(Enums.EntityType.CREATURE, t))

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
	# Bâtiments de quartier (Chantier 4) : données pures ; leur palier/état vit
	# dans GameData.village (buildings/routes), pas dans la progression de Maîtrise.
	_load_tres_folder("res://data/batiments/",   Enums.EntityType.BUILDING,   false)
	# Arbres de Forge (Chantier 5) : définition statique ; les points/nœuds acquis
	# vivent dans GameData.player.forge, pas dans la progression de Maîtrise.
	_load_tres_folder("res://data/forge_trees/", Enums.EntityType.FORGE_TREE, false)
	# Héros, passifs et équipements : entités à Maîtrise
	_load_tres_folder("res://data/hero/",        Enums.EntityType.HERO)
	_load_tres_folder("res://data/passives/",    Enums.EntityType.PASSIVE)
	_load_tres_folder("res://data/equipements/", Enums.EntityType.EQUIPMENT)

# Ramène un nom de fichier listé par DirAccess à son chemin source.
# En éditeur : « foret.tres » → « foret.tres » (inchangé).
# En build exporté : « foret.tres.remap »/« foo.json.import » → « foret.tres »/« foo.json »
# (l'export convertit/duplique les ressources ; load() et _read_json() acceptent
# le chemin source d'origine).
func _strip_export_suffix(file_name: String) -> String:
	if file_name.ends_with(".remap"):
		return file_name.trim_suffix(".remap")
	if file_name.ends_with(".import"):
		return file_name.trim_suffix(".import")
	return file_name

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
		# En build exporté, les ressources texte sont converties en binaire :
		# le dossier liste « foret.tres.remap » (et « .import »), pas « foret.tres ».
		# On normalise vers le chemin source, qui reste chargeable via le remap.
		var src_name := _strip_export_suffix(file_name)
		if src_name.ends_with(".tres"):
			var res := load(path + src_name)
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
		var src_name := _strip_export_suffix(file_name)
		if src_name.ends_with(".json"):
			var data = _read_json(path + src_name)
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
		if etype not in [Enums.EntityType.RESOURCE, Enums.EntityType.RECIPE, Enums.EntityType.FORGE_TREE] \
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
				if eff not in [Enums.BlessEffect.HEAL, Enums.BlessEffect.XP_BONUS, Enums.BlessEffect.HASTE]:
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

# (Le rattrapage reconcile_equipment_unlocks — « biome Peu Commun →
# équipement livré / repris » — a été SUPPRIMÉ au chantier 13 : l'équipement
# Commun est présent dès la partie neuve (appliquer_equipement_depart) et sa
# reprise rétroactive aurait dépouillé le joueur à chaque chargement, les
# biomes n'évoluant plus. Le hook unlock_biome_equipment reste en place.)

# Palier max du Village : plafond DUR global (« Palier Max atteint »).
func village_max_tier() -> int:
	return Balance.GLOBAL_MAX_TIER

# Largeur courante : nombre de bâtiments du Village reconstruits (palier T0+).
func village_building_count() -> int:
	return VillageBuildings.count_buildings_tier0_plus()

# Enregistre une créature de farm vaincue (hors boss) : incrémente le compteur de
# kills (condition Commun → Peu Commun). NE fait PAS monter le Village — l'évolution
# est MANUELLE (comme toute entité), déclenchée par le joueur via upgrade_village().
func register_creature_kill() -> void:
	village["kills_total"] = int(village.get("kills_total", 0)) + 1

# Le Village peut-il évoluer MAINTENANT ? La CONDITION dépend du palier (kills ≥ seuil
# pour → Peu Commun, bâtiments T0+ ≥ seuil pour → Rare). C'est un GATE, pas une montée
# automatique : tant que le joueur ne déclenche pas upgrade_village(), le Village reste
# à son palier même si la condition est remplie.
func can_upgrade_village() -> bool:
	var current := int(village.get("maitrise_actuelle", 0))
	if current >= village_max_tier():
		return false
	return Balance.village_target_tier(
			int(village.get("kills_total", 0)), village_building_count()) > current

# Fait évoluer le Village d'UN palier (action MANUELLE du joueur). Aucun coût consommé
# (la condition kills/bâtiments est le seul gate). Émet village_tier_change → déblocage
# du secteur (Sanctuaire à Rare — la Forge/Atelier est ouverte d'emblée depuis
# le chantier 12). Retourne false si la condition
# n'est pas remplie.
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

# Palier maximum d'un type d'entité (créatures → Légendaire 4 ; reste → Unique 5),
# borné par le plafond DUR global (Balance.GLOBAL_MAX_TIER) — garde-fou empêchant
# toute entité de dépasser ce palier.
func get_max_tier_for_type(entity_type: String) -> int:
	var type_max := int(Balance.ENTITY_MAX_TIER.get(entity_type, Balance.DEFAULT_MAX_TIER))
	return mini(type_max, Balance.GLOBAL_MAX_TIER)

# Coût d'XP pour franchir le palier suivant (Balance.evolve_cost, type-aware :
# biome ×3), ou 0.0 si palier max de type atteint. Sert à alimenter
# xp_maitrise_palier_suivant et tous les affichages de coût d'évolution.
func palier_suivant_cost(entity_type: String, tier: int) -> float:
	if tier >= get_max_tier_for_type(entity_type):
		return 0.0
	return Balance.evolve_cost(entity_type, tier + 1)

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
		# Garde-fou plafond DUR global : au palier max absolu, l'entrée du Hall
		# n'accumule plus d'XP (« Palier Max atteint »). Le compteur de rencontres
		# continue lui d'avancer.
		var tier: int = entry.get("tier", 0)
		if tier < Balance.GLOBAL_MAX_TIER:
			entry["xp"] += xp_reward
		while tier < Balance.GLOBAL_MAX_TIER:
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

# ═══════════════════════════════════════════════════════════
#  Expéditions : complétion Lieu × strate + Lieutenants / Alarme
#  (Rework Combat — chantier 11)
# ═══════════════════════════════════════════════════════════

const NB_SLOTS_ALARME := 6   # un slot par Lieutenant (règle actée 06/07/2026)

# Marque une strate (palier de profondeur) d'un Lieu comme COMPLÉTÉE jusqu'au
# bout (fin du 3e étage). L'extraction anticipée et la défaite ne passent
# jamais ici (l'appelant — ExpeRun — ne marque que les complétions).
func marquer_strate_completee(lieu_id: String, palier_id: String) -> void:
	if lieu_id == "" or palier_id == "":
		return
	var completions: Dictionary = player.get("expe_completions", {})
	var strates: Dictionary = completions.get(lieu_id, {})
	strates[palier_id] = true
	completions[lieu_id] = strates
	player["expe_completions"] = completions

func strate_completee(lieu_id: String, palier_id: String) -> bool:
	return bool(player.get("expe_completions", {}).get(lieu_id, {}).get(palier_id, false))

# Nombre de strates complétées d'un Lieu (0-3) — 3/3 débloque l'Assaut.
func nb_strates_completees(lieu_id: String) -> int:
	return (player.get("expe_completions", {}).get(lieu_id, {}) as Dictionary).size()

# Marque le Lieutenant d'un Lieu comme vaincu. Retourne true si c'est le
# PREMIER kill (le slot d'Alarme se remplit — les kills suivants ne
# re-remplissent rien). Émet lieutenant_vaincu (déclencheur de sauvegarde),
# et alarme_sonnee quand le 6e slot se remplit (déclencheur de fin de jeu —
# la 7e expédition elle-même est hors scope). Chantier 12 : le premier kill
# accorde AUSSI l'objet unique du Lieutenant (même moment, même persistance
# → même annulation par le Game Over qui recharge la sauvegarde).
func marquer_lieutenant_vaincu(lieu_id: String) -> bool:
	if lieu_id == "":
		return false
	var vaincus: Dictionary = player.get("lieutenants_vaincus", {})
	var premier: bool = not vaincus.get(lieu_id, false)
	if premier:
		vaincus[lieu_id] = true
		player["lieutenants_vaincus"] = vaincus
		var objets: Dictionary = player.get("objets_lieutenants", {})
		objets[lieu_id] = true
		player["objets_lieutenants"] = objets
	EventBus.lieutenant_vaincu.emit(lieu_id, premier)
	if premier and nb_lieutenants_vaincus() >= NB_SLOTS_ALARME:
		EventBus.alarme_sonnee.emit()
	return premier

func lieutenant_vaincu(lieu_id: String) -> bool:
	return bool(player.get("lieutenants_vaincus", {}).get(lieu_id, false))

# Nombre de slots d'Alarme remplis (0-6) = niveau d'Alarme (cf. Alarme.gd).
func nb_lieutenants_vaincus() -> int:
	return (player.get("lieutenants_vaincus", {}) as Dictionary).size()

# ═══════════════════════════════════════════════════════════
#  Économie du QG : objets de Lieutenants & voies
#  (Rework Combat — chantier 12 ; ordre fixe au chantier 13)
# ═══════════════════════════════════════════════════════════

const NB_VOIES := 6       # une voie par Lieutenant (même compte que l'Alarme)
const VOIE_ATELIER := 1   # la voie 1 est l'Atelier/Forge (acté 06/07/2026)

# Le joueur possède-t-il l'objet unique du Lieutenant d'un Lieu (« Sceau du
# <Lieu> », placeholder — nommage réel à la session narration) ? Accordé au
# premier kill (marquer_lieutenant_vaincu). Tracé PAR LIEU pour la narration
# future, mais DÉPENSÉ comme un compteur interchangeable (chantier 13).
func possede_objet_lieutenant(lieu_id: String) -> bool:
	return bool(player.get("objets_lieutenants", {}).get(lieu_id, false))

# Lieux dont l'objet de Lieutenant est possédé (pour l'affichage sobre au QG).
func objets_lieutenants() -> Array:
	return (player.get("objets_lieutenants", {}) as Dictionary).keys()

func nb_sceaux() -> int:
	return (player.get("objets_lieutenants", {}) as Dictionary).size()

# Sceaux non encore dépensés dans une voie (1 voie ouverte = 1 Sceau engagé).
func sceaux_libres() -> int:
	return maxi(0, nb_sceaux() - nb_voies_ouvertes())

# Nombre de quartiers restaurés (voies ouvertes, 0-6) — SOURCE UNIQUE du
# compteur « quartiers ouverts » (l'évolution visuelle du QG s'y branchera).
func nb_voies_ouvertes() -> int:
	return int(player.get("voies_ouvertes", 0))

# La voie `numero` (1-based) est-elle ouverte ? Ordre fixe : la voie n est
# ouverte ssi n ≤ nb_voies_ouvertes().
func voie_ouverte(numero: int) -> bool:
	return numero >= 1 and numero <= nb_voies_ouvertes()

# L'Atelier (Forge) est-il déverrouillé ? = la voie 1 est ouverte.
func atelier_ouvert() -> bool:
	return voie_ouverte(VOIE_ATELIER)

# La voie suivante est-elle ouvrable ? (pas toutes ouvertes + 1 Sceau libre)
func peut_ouvrir_voie_suivante() -> bool:
	return nb_voies_ouvertes() < NB_VOIES and sceaux_libres() >= 1

# Ouvre la voie SUIVANTE (action MANUELLE du joueur : « prêt → clic ») —
# ordre fixe 1→6, exige 1 Sceau libre (interchangeable). Persisté avec la
# partie ; émet voie_ouverte(numero) (déclencheur de sauvegarde + UI).
func ouvrir_voie_suivante() -> bool:
	if not peut_ouvrir_voie_suivante():
		return false
	player["voies_ouvertes"] = nb_voies_ouvertes() + 1
	EventBus.voie_ouverte.emit(nb_voies_ouvertes())
	return true

# ═══════════════════════════════════════════════════════════
#  Équipement de départ (chantier 13)
# ═══════════════════════════════════════════════════════════

# Liste de dotation data-driven (les équipements Commun existants, un par
# slot couvert — ne jamais en inventer ici : compléter le .tres).
const EQUIPEMENT_DEPART: EquipementDepartData = \
		preload("res://data/progression/equipement_depart.tres")

# Dote une PARTIE NEUVE de son équipement de départ : chaque équipement de
# la config est débloqué et équipé dans son slot (rareté Commun = palier 0
# des .tres). Appelé par SaveManager.load_save UNIQUEMENT quand aucune
# sauvegarde n'existe — une partie en cours n'est jamais touchée. Un id
# inconnu ou un placeholder sans contenu (nom vide) est ignoré avec warning
# (jamais inventé en silence).
func appliquer_equipement_depart() -> void:
	for eid: String in EQUIPEMENT_DEPART.equipement_ids:
		var equip := get_entity(eid)
		if equip.is_empty() or str(equip.get("nom_affichage_fr", "")) == "":
			push_warning("GameData: équipement de départ « %s » introuvable ou vide — ignoré" % eid)
			continue
		equip["est_debloque"] = true
		var slot_idx := int(equip.get("slot", 0))
		if slot_idx < EQUIP_SLOT_KEYS.size():
			player["equipped"][EQUIP_SLOT_KEYS[slot_idx]] = eid
	EventBus.equipment_changed.emit()
