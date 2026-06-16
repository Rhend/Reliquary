# ============================================================
# AdventureSystem.gd — Boucle principale d'aventure.
#
# Fonctionnement général :
#   1. start_adventure() initialise l'état et tire un modificateur.
#   2. _schedule_next_encounter() démarre un timer : FIRST_ENCOUNTER_DELAY
#      pour le premier événement ; Balance.TRANSITION après un combat ;
#      Balance.AFFICHAGE_EVENEMENT + Balance.TRANSITION après un piège/bénédiction.
#   3. À l'expiration, _process_encounter() tire le type de rencontre
#      (créature / bénédiction / piège) selon la table du biome.
#   4. Les rencontres de type créature délèguent à CombatPlayer et
#      attendent le signal combat_ended avant de continuer.
#   5. Après chaque rencontre, le héros régénère REGEN_PCT de
#      ses PV max (modifiable par le modificateur de cycle).
#
# Modificateurs de cycle :
#   Tirés aléatoirement au lancement, ils durent tout le cycle.
#   Exemples : XP ×1.5, régénération 30 %, pièges ignorés.
# ============================================================
extends Node

# ─── Constantes de cadence ──────────────────────────────────
# (Timings de boucle uniquement. Tout l'équilibrage chiffré — XP,
#  régén, zones, modificateurs de cycle, durées d'affichage — est dans Balance.gd.)

const FIRST_ENCOUNTER_DELAY: float = 1.0  # délai avant la toute première rencontre du cycle

# ─── État runtime ────────────────────────────────────────────

var is_running:               bool       = false  # vrai pendant qu'une aventure est en cours
var current_biome_id:         String     = ""     # id du biome actuellement exploré
var current_hp:               float      = 0.0    # PV courants du héros
var current_modifier:         Dictionary = {}     # modificateur de cycle actif
var zone_courante:            Enums.Zone = Enums.Zone.SURFACE
var combat_unique_en_cours:   bool       = false  # vrai pendant le combat contre la créature Unique

var _encounter_timer:         Timer              # timer qui cadence les rencontres
var _first_encounter_pending: bool  = false      # vrai uniquement pour la toute première rencontre du cycle
var _is_first_combat:         bool  = true       # vrai jusqu'au premier combat du cycle (embuscade)

# Créatures disponibles ce cycle avec leurs poids pondérés.
# Rempli une fois par cycle via _build_available_creatures().
# Format : [ { "data": {enemy_dict}, "weight": float }, … ]
var available_creatures: Array = []

# ─── Statistiques du cycle en cours ─────────────────────────

# Regroupe tous les compteurs accumulés pendant un cycle d'expédition.
# Réinitialisation en UN seul point : start_adventure() recrée l'objet.
# Pour ajouter un compteur : déclarer le champ ici, et l'exposer dans
# _build_summary() si le résumé de cycle doit l'afficher.
class CycleStats:
	var xp_total:          float = 0.0  # XP de base totale distribuée ce cycle
	var loot_total:        int   = 0    # nombre total d'objets droppés
	var combats_won:       int   = 0    # combats remportés
	var events:            int   = 0    # pièges + bénédictions réellement appliqués
	var events_total:      int   = 0    # rencontres totales (combats compris)
	var positive_events:   int   = 0    # bénédictions appliquées
	var traps_triggered:   int   = 0    # pièges subis (non ignorés)
	var xp_hero:           float = 0.0  # XP reçue par le héros
	var xp_biome:          float = 0.0  # XP reçue par le biome exploré
	var xp_passives_total: float = 0.0  # XP cumulée de tous les passifs actifs
	var xp_passives_detail: Dictionary = {}  # passive_id → XP reçue
	var xp_entities_detail: Dictionary = {}  # entité rencontrée → XP reçue
	var xp_equip_detail:    Dictionary = {}  # équipement porté → XP reçue
	var loot_detail:        Dictionary = {}  # item_id → quantité totale droppée
	var new_discoveries:    Array      = []  # entités vues pour la 1re fois CE cycle
	var unique_beaten:      bool       = false  # créature Unique vaincue CE cycle

var _stats := CycleStats.new()  # stats du cycle courant

# ─── États temporaires persistant entre rencontres ──────────

# Saignement : ticks restants (dégâts par tick = Balance.BLEED_DMG_PCT × PV max).
var _bleed_remaining: int   = 0
# Bénédiction XP : multiplicateur d'XP de base appliqué UNE fois sur le prochain événement.
var _bless_xp_mult:   float = 1.0

func _ready() -> void:
	_encounter_timer          = Timer.new()
	_encounter_timer.one_shot = true
	_encounter_timer.timeout.connect(_on_encounter_timer)
	add_child(_encounter_timer)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.entity_discovered.connect(_on_entity_discovered)
	EventBus.xp_gained.connect(_on_xp_gained_tracking)

# Accumule l'XP héros/biome/passifs/entités pour le résumé de cycle.
# Appelé par EventBus.xp_gained à chaque attribution MasterySystem.
func _on_xp_gained_tracking(entity_id: String, amount: float) -> void:
	if not is_running:
		return
	var entity := GameData.get_entity(entity_id)
	match entity.get("entity_type", ""):
		Enums.EntityType.HERO:
			_stats.xp_hero += amount
		Enums.EntityType.BIOME:
			_stats.xp_biome += amount
		Enums.EntityType.PASSIVE:
			_stats.xp_passives_total            += amount
			_stats.xp_passives_detail[entity_id] = \
				_stats.xp_passives_detail.get(entity_id, 0.0) + amount
		Enums.EntityType.EQUIPMENT:
			_stats.xp_equip_detail[entity_id] = \
				_stats.xp_equip_detail.get(entity_id, 0.0) + amount
		Enums.EntityType.CREATURE, Enums.EntityType.TRAP, Enums.EntityType.BENEDICTION:
			_stats.xp_entities_detail[entity_id] = \
				_stats.xp_entities_detail.get(entity_id, 0.0) + amount

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Lance une nouvelle aventure dans le biome donné. Réinitialise tous les stats du cycle.
func start_adventure(biome_id: String) -> void:
	var biome = GameData.get_entity(biome_id)
	var hero  = GameData.get_entity("hero")

	if biome.is_empty() or hero.is_empty():
		push_error("AdventureSystem: biome ou héros manquant pour démarrer")
		return

	current_biome_id = biome_id
	is_running       = true
	current_hp       = get_max_hp()

	_first_encounter_pending = true
	_is_first_combat         = true
	zone_courante            = _get_max_zone(biome_id)
	combat_unique_en_cours   = false

	BiomeMechanics.initialize_for_biome(biome_id)
	_build_available_creatures(biome_id)

	# Réinitialise les statistiques et états temporaires du cycle
	_stats           = CycleStats.new()
	_bleed_remaining = 0
	_bless_xp_mult   = 1.0

	_pick_modifier()

	GameData.player["active_biome_id"] = biome_id
	EventBus.adventure_started.emit(biome_id)
	_schedule_next_encounter()

# Interrompt l'aventure en cours (bouton "Mettre fin à l'expédition").
func stop_adventure() -> void:
	if not is_running:
		return
	is_running = false
	_encounter_timer.stop()
	if CombatPlayer.is_playing:
		CombatPlayer.stop()
	PassiveSystem.decrement_cooldowns()
	GameData.player["active_biome_id"] = ""
	CycleData.last_cycle_summary = _build_summary(false, true)
	EventBus.adventure_stopped.emit()

func get_modifier_bonuses() -> Dictionary:
	return {
		"atk_mult": float(current_modifier.get("atk_mult", 1.0)),
		"def_mult": float(current_modifier.get("def_mult", 1.0))
	}

# XP totale gagnée par le héros depuis le début du cycle courant (lecture seule, pour l'UI).
func get_cycle_xp() -> float:
	return _stats.xp_total

# ═══════════════════════════════════════════════════════════
#  Boucle de rencontres
# ═══════════════════════════════════════════════════════════

func _on_encounter_timer() -> void:
	if is_running:
		_process_encounter()

# Tire le type de rencontre et délègue au handler correspondant.
func _process_encounter() -> void:
	var enc_type = _roll_encounter_type()
	var enc_data = {
		"type":    enc_type,
		"biome_id": current_biome_id,
		"hero_id":  "hero"
	}

	_stats.events_total += 1

	match enc_type:
		Enums.EntityType.CREATURE:    _handle_creature_encounter("hero", enc_data)
		Enums.EntityType.BENEDICTION: _handle_benediction_encounter("hero", enc_data)
		Enums.EntityType.TRAP:        _handle_trap_encounter("hero", enc_data)

# ─── Rencontre Créature ───────────────────────────────────────

# Tire un ennemi aléatoire dans le pool du biome et lance le combat.
func _handle_creature_encounter(_hero_id: String, enc_data: Dictionary) -> void:
	var enemy := _weighted_random_creature()
	if enemy.is_empty():
		_schedule_next_encounter(Balance.TRANSITION)
		return
	enemy              = enemy.duplicate()
	enc_data["enemy"]  = enemy

	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, 0.0
	)
	EventBus.adventure_event_resolved.emit(enc_data)

	var combat_options := {
		"ambush":         _is_first_combat and BiomeMechanics.is_ambush_active(),
		"poison":         BiomeMechanics.is_mechanic_active("poison"),
		"endurcissement": BiomeMechanics.is_mechanic_active("endurcissement"),
	}
	_is_first_combat = false
	CombatPlayer.start_combat(enemy, current_hp, get_modifier_bonuses(), combat_options)

# ─── Rencontre Bénédiction ────────────────────────────────────

# Tire une bénédiction aléatoire et applique son effet immédiatement.
func _handle_benediction_encounter(hero_id: String, enc_data: Dictionary) -> void:
	var biome       = GameData.get_entity(current_biome_id)
	var benedictions = biome.get("benedictions", [])

	if not benedictions.is_empty():
		var bene             = benedictions[randi() % benedictions.size()]
		enc_data["effect"]   = bene
		_distribute_mastery_xp(bene.get("id", ""), Balance.XP_BASE_BENEDICTION)
		GameData.record_encounter(
			bene.get("id", ""), bene.get("nom_affichage_fr", "?"), "Bénédiction", current_biome_id, Balance.HALL_XP_EVENT
		)
		_apply_benediction_effect(bene)
		_stats.events          += 1
		_stats.positive_events += 1

	EventBus.adventure_event_resolved.emit(enc_data)
	_apply_regen(hero_id)
	_tick_bleed()
	if is_running:
		_schedule_next_encounter(Balance.AFFICHAGE_EVENEMENT + Balance.TRANSITION)

# Applique l'effet d'une bénédiction.
# heal     → % PV max depuis Balance (indépendant de la zone).
# xp_bonus → multiplie l'XP de base du prochain événement.
func _apply_benediction_effect(bene: Dictionary) -> void:
	var effect_type := bene.get("effet", "") as String

	match effect_type:
		Enums.BlessEffect.HEAL:
			var max_hp := get_max_hp()
			var healed := maxf(0.0, max_hp * Balance.BLESS_HEAL_PCT)
			current_hp  = minf(current_hp + healed, max_hp)
			EventBus.heal_applied.emit(healed, current_hp)

		Enums.BlessEffect.XP_BONUS:
			_bless_xp_mult = 1.0 + Balance.BLESS_XP_BONUS_PCT

# Distribue l'XP de Maîtrise d'un événement résolu à TOUTES les entités actives :
# l'entité rencontrée, le héros, le biome, le village et les passifs actifs.
# Pour chacune : XP = base × modificateur d'écart × coefficient de type (cf. MasterySystem).
# event_id   = id de l'entité rencontrée (créature / piège / bénédiction).
# event_base = XP de base du type d'événement (avant modificateur de cycle).
func _distribute_mastery_xp(event_id: String, event_base: float) -> void:
	if event_id == "":
		return
	var base         := event_base * float(current_modifier.get("xp_mult", 1.0)) * _bless_xp_mult
	_bless_xp_mult    = 1.0  # consommé une seule fois
	var event_entity := GameData.get_entity(event_id)
	var event_tier   := int(event_entity.get("maitrise_actuelle", 0))

	# Pas d'XP à l'entité si créature Unique d'Abysse (statique tier 5)
	if not (event_entity.get("est_unique", false) and int(event_entity.get("zone_associee", -1)) == Enums.Zone.ABYSSE):
		MasterySystem.add_xp_to_entity(event_id, base, event_tier)
	MasterySystem.add_xp_to_entity("hero", base, event_tier)                                         # héros
	MasterySystem.add_xp_to_entity(current_biome_id, base, event_tier)                               # biome
	MasterySystem.add_xp_to_all_active(base, event_tier)                                             # passifs actifs
	for item_id in GameData.player.get("equipped", {}).values():                                     # équipements actifs (biome_source_id défini)
		if item_id != "":
			var item := GameData.get_entity(item_id)
			if item.get("biome_source_id", "") != "":  # items sans biome = futurs biomes, pas encore actifs
				MasterySystem.add_xp_to_entity(item_id, base, event_tier)

	_stats.xp_total += base

# ─── Rencontre Piège ──────────────────────────────────────────

# Tire un piège aléatoire et applique ses dégâts (sauf si modificateur "Fantôme").
func _handle_trap_encounter(hero_id: String, enc_data: Dictionary) -> void:
	var biome = GameData.get_entity(current_biome_id)
	var traps = biome.get("pieges", [])

	if traps.is_empty():
		EventBus.adventure_event_resolved.emit(enc_data)
		_schedule_next_encounter(Balance.TRANSITION)
		return

	var trap           = traps[randi() % traps.size()]
	enc_data["trap"]   = trap
	_distribute_mastery_xp(trap.get("id", ""), Balance.XP_BASE_TRAP)

	# Dégâts du piège = pourcentage du PV max selon la zone (le champ `degats`
	# du .tres n'est pas utilisé). Stocké dans enc_data pour que l'affichage du
	# combat montre EXACTEMENT les PV perdus (sinon il lisait une clé absente → 0).
	var trap_dmg := int(round(get_max_hp() * _trap_dmg_pct()))
	enc_data["trap_damage"] = trap_dmg

	if current_modifier.get("ignore_traps", false):
		enc_data["ignored"] = true
		GameData.record_encounter(
			trap.get("id", ""), trap.get("nom_affichage_fr", "?"), "Piège", current_biome_id, Balance.HALL_XP_EVENT
		)
		EventBus.adventure_event_resolved.emit(enc_data)
		_apply_regen(hero_id)
		_schedule_next_encounter(Balance.AFFICHAGE_EVENEMENT + Balance.TRANSITION)
	else:
		_stats.events          += 1
		_stats.traps_triggered += 1
		current_hp  = maxf(current_hp - float(trap_dmg), 0.0)
		if trap.get("inflict_saignement", false):
			_bleed_remaining = Balance.BLEED_DURATION
			enc_data["saignement"] = true
		GameData.record_encounter(
			trap.get("id", ""), trap.get("nom_affichage_fr", "?"), "Piège", current_biome_id, Balance.HALL_XP_EVENT
		)
		EventBus.adventure_event_resolved.emit(enc_data)
		if current_hp <= 0.0:
			_end_adventure(false)
		else:
			_apply_regen(hero_id)
			_tick_bleed()
			if is_running:
				_schedule_next_encounter(Balance.AFFICHAGE_EVENEMENT + Balance.TRANSITION)

# ═══════════════════════════════════════════════════════════
#  Résultat de combat
# ═══════════════════════════════════════════════════════════

# Reçoit le résultat de combat et continue l'aventure ou l'arrête.
# Première rencontre d'une entité (création au bestiaire) : mémorisée dans
# les stats du cycle pour la section « Découvertes » du résumé.
func _on_entity_discovered(entity_id: String) -> void:
	if is_running and entity_id not in _stats.new_discoveries:
		_stats.new_discoveries.append(entity_id)

func _on_combat_ended(result: Dictionary) -> void:
	if not is_running:
		return

	current_hp = result.get("remaining_hero_hp", 0.0)

	if combat_unique_en_cours:
		combat_unique_en_cours = false
		if result.get("victory", false):
			_resolve_unique_victory(result.get("enemy", {}))
		else:
			_end_adventure(false)
		return

	if result.get("victory", false):
		_resolve_victory(result.get("enemy", {}))
	else:
		_end_adventure(false)

# Distribue l'XP, le loot et les ingrédients après une victoire.
func _resolve_victory(enemy: Dictionary) -> void:
	# XP de Maîtrise distribuée à toutes les entités actives (base de combat)
	_distribute_mastery_xp(enemy.get("id", ""), Balance.XP_BASE_COMBAT)

	# Hall des Évolutions
	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, Balance.XP_BASE_COMBAT
	)

	# Loot ennemi
	_drop_loot(enemy)
	_drop_ingredient_from_creature(enemy)

	# Ingrédients biome (uniquement une fois la Forge débloquée — Village T1)
	if int(GameData.village.get("maitrise_actuelle", 0)) >= 1:
		_drop_biome_ingredients()

	_stats.combats_won += 1

	_apply_regen("hero")
	_tick_bleed()
	if is_running:
		_schedule_next_encounter(Balance.TRANSITION)

# ═══════════════════════════════════════════════════════════
#  Utilitaires internes
# ═══════════════════════════════════════════════════════════

# Régénère regen_pct% des PV max après chaque rencontre.
# Sources : modificateur de cycle (regen_pct) + passifs actifs (hp_regen_pct).
func _apply_regen(_hero_id: String) -> void:
	var regen_pct := float(current_modifier.get("regen_pct", Balance.DEFAULT_REGEN_PCT)) \
			+ PassiveSystem.get_effect("hp_regen_pct")
	if regen_pct <= 0.0:
		return
	var max_hp := get_max_hp()
	current_hp  = minf(current_hp + max_hp * regen_pct, max_hp)

# Applique un tick de saignement (Balance.BLEED_DMG_PCT × PV max).
# Non-cumulatif : un nouveau piège saignant réinitialise la durée.
func _tick_bleed() -> void:
	if _bleed_remaining <= 0:
		return
	var max_hp := get_max_hp()
	var dmg    := max_hp * Balance.BLEED_DMG_PCT
	current_hp  = maxf(current_hp - dmg, 0.0)
	_bleed_remaining -= 1
	EventBus.bleed_ticked.emit(dmg, current_hp, _bleed_remaining)
	if current_hp <= 0.0:
		_end_adventure(false)

# Retourne le % de dégâts de piège pour la zone courante.
func _trap_dmg_pct() -> float:
	match zone_courante:
		Enums.Zone.PROFONDEUR: return Balance.TRAP_DMG_PCT_PROFONDEUR
		Enums.Zone.ABYSSE:     return Balance.TRAP_DMG_PCT_ABYSSE
		_:                     return Balance.TRAP_DMG_PCT_SURFACE

# Calcule les PV max effectifs du héros (stats de base + équipement + passifs).
func get_max_hp() -> float:
	var equip_hp = GameData.get_equipment_bonuses().get("hp", 0.0)
	var hp_bonus = PassiveSystem.get_combat_bonuses().get("hp_bonus", 0.0)
	return float(GameData.get_effective_stats("hero").get("hp", 100)) + equip_hp + hp_bonus

# Programme la prochaine rencontre.
# Utilise FIRST_ENCOUNTER_DELAY pour la toute première, sinon le délai fourni.
func _schedule_next_encounter(delay: float = 1.0) -> void:
	if not is_running:
		return
	var actual_delay := FIRST_ENCOUNTER_DELAY if _first_encounter_pending else delay
	_first_encounter_pending   = false
	_encounter_timer.wait_time = actual_delay
	_encounter_timer.start()

# Tire le type de rencontre selon les probabilités du biome.
func _roll_encounter_type() -> String:
	# Distribution standard pour toutes les zones (Surface, Profondeur, Abysse).
	var biome      = GameData.get_entity(current_biome_id)
	var base_table = biome.get("event_table", {
		Enums.EntityType.CREATURE: 0.70, Enums.EntityType.BENEDICTION: 0.15, Enums.EntityType.TRAP: 0.15
	})

	var creature_chance    = float(base_table.get(Enums.EntityType.CREATURE,    0.70))
	var benediction_chance = float(base_table.get(Enums.EntityType.BENEDICTION, 0.15))

	var roll = randf()
	if roll < creature_chance:
		return Enums.EntityType.CREATURE
	elif roll < creature_chance + benediction_chance:
		return Enums.EntityType.BENEDICTION
	else:
		return Enums.EntityType.TRAP

# Tire le modificateur de cycle par tirage pondéré.
func _pick_modifier() -> void:
	var total_weight: int = 0
	for m in Balance.CYCLE_MODIFIERS:
		total_weight += int(m.get("weight", 1))

	var roll       = randi() % total_weight
	var cumulative = 0
	for m in Balance.CYCLE_MODIFIERS:
		cumulative += int(m.get("weight", 1))
		if roll < cumulative:
			current_modifier = m
			break
	EventBus.modifier_activated.emit(current_modifier)

# Roule un drop depuis un pool d'entrées.
# Chaque entrée : { item_id, chance, qty_min?, qty_max? }
# source_name : affiché dans loot_dropped (nom ennemi ou "Biome").
func _drop_pool(pool: Array, source_name: String) -> void:
	if pool.is_empty():
		return
	var has_forge := int(GameData.village.get("maitrise_actuelle", 0)) >= 1
	var drops: Array = []
	for entry in pool:
		if randf() >= minf(float(entry.get("chance", 0.0)), 1.0):
			continue
		var item_id: String = entry.get("item_id", "")
		if item_id == "":
			continue
		if not has_forge and GameData.get_entity(item_id).get("entity_type", "") == Enums.EntityType.INGREDIENT:
			continue
		var qty_min: int = int(entry.get("qty_min", 1))
		var qty_max: int = int(entry.get("qty_max", qty_min))
		var qty:     int = randi_range(qty_min, qty_max)
		GameData.add_resource(item_id, qty)
		var res := GameData.get_entity(item_id)
		drops.append({
			"item_id": item_id,
			"name":    Translations.entity_name(res, item_id),
			"qty":     qty
		})
	if not drops.is_empty():
		_stats.loot_total += drops.size()
		for d in drops:
			var did: String = d.get("item_id", "")
			_stats.loot_detail[did] = _stats.loot_detail.get(did, 0) + int(d.get("qty", 1))
		EventBus.loot_dropped.emit(drops, source_name)

# Drop le loot spécifique à l'ennemi vaincu (loot_table de l'ennemi).
func _drop_loot(enemy: Dictionary) -> void:
	_drop_pool(enemy.get("loot_table", []), enemy.get("name", "?"))

# Drop un ingrédient standard depuis une créature évolutive (50% de chance).
# Bloqué tant que la Forge n'est pas débloquée (Village T1).
func _drop_ingredient_from_creature(enemy: Dictionary) -> void:
	if int(GameData.village.get("maitrise_actuelle", 0)) < 1:
		return
	var creature := GameData.get_entity(enemy.get("id", ""))
	if creature.is_empty() or creature.get("est_unique", false):
		return
	var pool := creature.get("ingredients_drop_ids", []) as Array
	if pool.is_empty() or randf() >= Balance.CREATURE_INGREDIENT_DROP_CHANCE:
		return
	var ingredient_id: String = pool[randi() % pool.size()]
	var ingr := GameData.get_entity(ingredient_id)
	if ingr.is_empty():
		return
	GameData.add_resource(ingredient_id, 1)
	_stats.loot_detail[ingredient_id] = _stats.loot_detail.get(ingredient_id, 0) + 1
	_stats.loot_total += 1
	EventBus.loot_dropped.emit(
		[{"item_id": ingredient_id, "name": Translations.entity_name(ingr, ingredient_id), "qty": 1}],
		enemy.get("name", "?")
	)

# Drop des ingrédients depuis ingredients_drop du biome (via _drop_pool).
# Disponible uniquement si Village Tier ≥ 1 (appelé depuis _resolve_victory).
# Les entrées du biome utilisent la clé "id" : on les convertit au format
# attendu par _drop_pool ("item_id") pour mutualiser le tirage.
func _drop_biome_ingredients() -> void:
	var biome := GameData.get_entity(current_biome_id)
	var pool: Array = []
	for ingr in biome.get("ingredients_drop", []) as Array:
		var d := ingr as Dictionary
		pool.append({
			"item_id": d.get("id", ""),
			"chance":  d.get("chance", 0.0),
			"qty_min": d.get("qty_min", 1),
			"qty_max": d.get("qty_max", d.get("qty_min", 1)),
		})
	_drop_pool(pool, "Biome")

# ═══════════════════════════════════════════════════════════
#  Distribution pondérée des créatures (par zone)
# ═══════════════════════════════════════════════════════════

# Reconstruit available_creatures selon la zone courante.
# Surface              : créature Surface uniquement.
# Profondeur et Abysse : Surface + Profondeur, pondérées par écart de palier.
#   - Paliers égaux → 50/50.
#   - Chaque palier d'écart ajoute Balance.POOL_WEIGHT_DIFF_BONUS à la créature la moins avancée.
func _build_available_creatures(biome_id: String) -> void:
	available_creatures = []
	var biome      := GameData.get_entity(biome_id)
	var surface    := biome.get("creature_surface",    {}) as Dictionary
	var profondeur := biome.get("creature_profondeur", {}) as Dictionary

	if zone_courante == Enums.Zone.SURFACE:
		_pool_add(surface, Balance.POOL_WEIGHT_SURFACE_ONLY)
		return

	# Profondeur et Abysse : pondération dynamique par écart de tier entre les deux créatures.
	# On lit la maîtrise réelle depuis GameData.entities (source de vérité à jour),
	# pas depuis le dict imbriqué dans le biome (copie figée au chargement).
	var tier_s := int(GameData.get_entity(surface.get("id",    "")).get("maitrise_actuelle", 0))
	var tier_p := int(GameData.get_entity(profondeur.get("id", "")).get("maitrise_actuelle", 0))
	var diff   := tier_s - tier_p  # positif = Surface plus haute → Profondeur favorisée
	var w_s := maxf(Balance.POOL_WEIGHT_BASE - float(diff) * Balance.POOL_WEIGHT_DIFF_BONUS, 5.0)
	var w_p := maxf(Balance.POOL_WEIGHT_BASE + float(diff) * Balance.POOL_WEIGHT_DIFF_BONUS, 5.0)
	_pool_add(surface,    w_s)
	_pool_add(profondeur, w_p)

# Convertit un dict créature (.tres) en fiche de combat pour CombatPlayer.
# Les stats sont lues au palier de Maîtrise courant de la créature, en
# descendant au palier inférieur le plus proche si absent (GameData.stats_at_tier).
func _combat_sheet(creature: Dictionary) -> Dictionary:
	var tier := int(creature.get("maitrise_actuelle", 0))
	var s    := GameData.stats_at_tier(creature, tier)
	return {
		"id":         creature.get("id", ""),
		"name":       Translations.entity_name(creature, ""),
		"tier":       tier,
		"atk":        s.get("atk",       10),
		"def":        s.get("def",        0),
		"hp":         s.get("hp",         50),
		"vit":        s.get("vit",        20),
		"xp_reward":  s.get("xp_reward",  10),
		"loot_table": creature.get("loot_table", []),
	}

# Ajoute une créature au pool du cycle avec son poids de tirage.
func _pool_add(creature: Dictionary, weight: float) -> void:
	if creature.is_empty():
		return
	available_creatures.append({
		"data":   _combat_sheet(creature),
		"weight": weight,
	})

# Tirage pondéré parmi les créatures disponibles ce cycle.
func _weighted_random_creature() -> Dictionary:
	if available_creatures.is_empty():
		return {}

	var total_weight := 0.0
	for c in available_creatures:
		total_weight += float(c.get("weight", 1.0))

	var roll       := randf() * total_weight
	var cumulative := 0.0
	for c in available_creatures:
		cumulative += float(c.get("weight", 1.0))
		if roll < cumulative:
			return c.get("data", {})

	return available_creatures[0].get("data", {})

# Clôt le cycle et émet adventure_cycle_ended avec toutes les statistiques.
func _end_adventure(victory: bool) -> void:
	is_running = false
	_encounter_timer.stop()
	PassiveSystem.decrement_cooldowns()
	GameData.player["active_biome_id"] = ""
	var summary := _build_summary(victory)
	CycleData.last_cycle_summary = summary
	EventBus.adventure_cycle_ended.emit(summary)

# Sérialise les stats du cycle en Dictionary pour CycleData / CycleSummaryScreen.
func _build_summary(victory: bool, interrupted: bool = false) -> Dictionary:
	return {
		"victory":              victory,
		"interrupted":          interrupted,
		"biome_id":             current_biome_id,
		"hero_id":              "hero",
		"modifier":             current_modifier,
		"xp_total":             _stats.xp_total,
		"xp_hero":              _stats.xp_hero,
		"xp_biome":             _stats.xp_biome,
		"xp_passives_total":    _stats.xp_passives_total,
		"xp_passives_detail":   _stats.xp_passives_detail,
		"xp_entities_detail":   _stats.xp_entities_detail,
		"loot_total":           _stats.loot_total,
		"loot_detail":          _stats.loot_detail.duplicate(),
		"xp_equip_detail":      _stats.xp_equip_detail.duplicate(),
		"combats_won":          _stats.combats_won,
		"events":               _stats.events,
		"events_total":         _stats.events_total,
		"positive_events":      _stats.positive_events,
		"traps_triggered":      _stats.traps_triggered,
		"new_discoveries":      _stats.new_discoveries.duplicate(),
		"unique_beaten":        _stats.unique_beaten,
	}

# ═══════════════════════════════════════════════════════════
#  Créature Unique d'Abysse
# ═══════════════════════════════════════════════════════════

# Déclenche le combat contre la créature Unique. Appelé par l'UI (bouton joueur).
func start_unique_combat() -> void:
	if not is_running or combat_unique_en_cours:
		return
	var biome := GameData.get_entity(current_biome_id)
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return
	combat_unique_en_cours = true
	_encounter_timer.stop()
	var unique_dict := _combat_sheet(unique)
	GameData.record_encounter(
		unique_dict["id"], unique_dict["name"], "Créature", current_biome_id, 0.0
	)
	_is_first_combat = false
	CombatPlayer.start_combat(unique_dict, current_hp, get_modifier_bonuses(), {
		"ambush":         false,
		"poison":         BiomeMechanics.is_mechanic_active("poison"),
		"endurcissement": BiomeMechanics.is_mechanic_active("endurcissement"),
	})

# Résout la victoire contre la créature Unique : flags, ingrédient, passif, signal.
func _resolve_unique_victory(enemy: Dictionary) -> void:
	var biome := GameData.get_entity(current_biome_id)
	biome["creature_unique_vaincue"] = true
	_stats.unique_beaten = true

	# Ingrédient unique → 1 exemplaire dans player.resources
	var ingr_id: String = (biome.get("ingredient_unique", {}) as Dictionary).get("id", "")
	if ingr_id != "" and int(GameData.player["resources"].get(ingr_id, 0)) == 0:
		GameData.add_resource(ingr_id, 1)

	# Passif unique → est_debloque = true
	var passif_id: String = (biome.get("creature_unique", {}) as Dictionary).get("passif_debloque_id", "")
	if passif_id != "":
		var passif := GameData.get_entity(passif_id)
		if not passif.is_empty():
			passif["est_debloque"] = true

	# XP de Maîtrise (distribution standard, base de combat) + loot
	_distribute_mastery_xp(enemy.get("id", ""), Balance.XP_BASE_COMBAT)
	GameData.record_encounter(enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, Balance.XP_BASE_COMBAT)
	_drop_loot(enemy)

	_stats.combats_won += 1

	EventBus.creature_unique_vaincue.emit(current_biome_id, ingr_id, passif_id)

	_apply_regen("hero")
	_tick_bleed()
	if is_running:
		_schedule_next_encounter(Balance.TRANSITION)

# ═══════════════════════════════════════════════════════════
#  Zones
# ═══════════════════════════════════════════════════════════

# Zone maximale débloquée selon la Maîtrise (maitrise_actuelle) du biome.
# Commun/Peu Commun → Surface ; Rare/Épique → Profondeur ; Légendaire/Unique → Abysse.
func _get_max_zone(biome_id: String) -> Enums.Zone:
	var tier: int = GameData.get_entity(biome_id).get("maitrise_actuelle", 0)
	return Balance.max_unlocked_zone(tier) as Enums.Zone
