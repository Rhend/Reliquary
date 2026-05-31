# ============================================================
# AdventureSystem.gd — Boucle principale d'aventure.
#
# Fonctionnement général :
#   1. start_adventure() initialise l'état et tire un modificateur.
#   2. _schedule_next_encounter() démarre un timer (1 s pour le
#      premier, 2.5 s après un combat, 1 s après piège ou bénédiction).
#   3. À l'expiration, _process_encounter() tire le type de rencontre
#      (créature / bénédiction / piège) selon la table du biome.
#   4. Les rencontres de type créature délèguent à CombatPlayer et
#      attendent le signal combat_ended avant de continuer.
#   5. Après chaque rencontre, le héro régénère REGEN_PCT de
#      ses PV max (modifiable par le modificateur de cycle).
#
# Modificateurs de cycle :
#   Tirés aléatoirement au lancement, ils durent tout le cycle.
#   Exemples : XP ×1.5, régénération 30 %, pièges ignorés.
#
# Combo :
#   Incrémenté si le héro perd ≤ COMBO_HP_THRESHOLD % de ses PV.
#   Le combo donne un bonus d'ATK multiplicatif au combat suivant
#   (+5 % par niveau de combo au-dessus de 1).
#
# Luck de cycle :
#   Accumulée temporairement via les bénédictions de type "luck".
#   Elle s'ajoute à la luck permanente du joueur pour les rolls du cycle
#   et est réinitialisée à chaque nouvelle aventure.
# ============================================================
extends Node

# ─── Constantes de cadence ──────────────────────────────────
# (Timings de boucle uniquement. Tout l'équilibrage chiffré — XP,
#  combo, régén, zones, modificateurs de cycle — est dans Balance.gd.)

const FIRST_ENCOUNTER_DELAY: float = 1.0  # délai avant la toute première rencontre du cycle
const COMBAT_POST_DELAY:     float = 2.5  # pause après la fin d'un combat
const INSTANT_EVENT_DELAY:   float = 1.0  # pause après piège ou bénédiction

# ─── État runtime ────────────────────────────────────────────

var is_running:               bool       = false  # vrai pendant qu'une aventure est en cours
var current_biome_id:         String     = ""     # id du biome actuellement exploré
var current_hp:               float      = 0.0    # PV courants du héro
var current_modifier:         Dictionary = {}     # modificateur de cycle actif
var zone_courante:            Enums.Zone = Enums.Zone.SURFACE
var _nb_evenements_zone:      int        = 0      # événements résolus dans la zone courante
var combat_unique_en_cours:   bool       = false  # vrai pendant le combat contre la créature Unique

var _encounter_timer:         Timer              # timer qui cadence les rencontres
var _first_encounter_pending: bool  = false      # vrai uniquement pour la toute première rencontre du cycle
var _is_first_combat:         bool  = true       # vrai jusqu'au premier combat du cycle (embuscade)
var _combo_count:             int   = 0          # combo courant (remis à 0 si trop de dégâts reçus)
var _combat_start_hp:         float = 0.0        # PV du héro au début du combat (pour calcul combo)

# Créatures disponibles ce cycle avec leurs poids pondérés.
# Rempli une fois par cycle via _build_available_creatures().
# Format : [ { "data": {enemy_dict}, "weight": float }, … ]
var available_creatures: Array = []

# ─── Statistiques du cycle en cours ─────────────────────────

var _cycle_luck:               int        = 0    # Luck temporaire accumulée par les bénédictions de type "luck"
var _cycle_xp:                 float      = 0.0  # XP totale gagnée par le héro ce cycle
var _cycle_loot:               int        = 0    # Nombre total d'objets droppés
var _cycle_combo_max:          int        = 0    # Meilleur combo atteint
var _cycle_combats_won:        int        = 0    # Combats remportés
var _cycle_events:             int        = 0    # Rencontres totales (hors créatures)
var _cycle_events_total:       int        = 0
var _cycle_positive_events:    int        = 0
var _cycle_traps_triggered:    int        = 0
var _cycle_xp_hero:            float      = 0.0
var _cycle_xp_biome:           float      = 0.0
var _cycle_xp_passives_total:  float      = 0.0
var _cycle_xp_passives_detail: Dictionary = {}
# XP par entité rencontrée ce cycle (créatures, pièges, bénédictions).
var _cycle_xp_entities_detail: Dictionary = {}

func _ready() -> void:
	_encounter_timer          = Timer.new()
	_encounter_timer.one_shot = true
	_encounter_timer.timeout.connect(_on_encounter_timer)
	add_child(_encounter_timer)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.xp_gained.connect(_on_xp_gained_tracking)

# Accumule l'XP héro/biome/passifs/entités pour le résumé de cycle.
# Appelé par EventBus.xp_gained à chaque attribution MasterySystem.
func _on_xp_gained_tracking(entity_id: String, amount: float) -> void:
	if not is_running:
		return
	var entity := GameData.get_entity(entity_id)
	match entity.get("entity_type", ""):
		"hero":
			_cycle_xp_hero += amount
		"biome":
			_cycle_xp_biome += amount
		"passive":
			_cycle_xp_passives_total               += amount
			_cycle_xp_passives_detail[entity_id]    = \
				_cycle_xp_passives_detail.get(entity_id, 0.0) + amount
		"creature", "trap", "benediction":
			_cycle_xp_entities_detail[entity_id]    = \
				_cycle_xp_entities_detail.get(entity_id, 0.0) + amount

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Lance une nouvelle aventure dans le biome donné. Réinitialise tous les stats du cycle.
func start_adventure(biome_id: String) -> void:
	var biome   = GameData.get_entity(biome_id)
	var hero_id = GameData.player.get("active_creature_id", "")
	var hero    = GameData.get_entity(hero_id)

	if biome.is_empty() or hero.is_empty():
		push_error("AdventureSystem: biome ou héro manquant pour démarrer")
		return

	current_biome_id = biome_id
	is_running       = true
	current_hp       = get_max_hp()

	_combo_count             = 0
	_first_encounter_pending = true
	_is_first_combat         = true
	zone_courante            = Enums.Zone.SURFACE
	_nb_evenements_zone      = 0
	combat_unique_en_cours   = false

	BiomeMechanics.initialize_for_biome(biome_id)
	_build_available_creatures(biome_id)

	# Réinitialise les statistiques du cycle
	_cycle_luck               = 0
	_cycle_xp                 = 0.0
	_cycle_loot               = 0
	_cycle_combo_max          = 0
	_cycle_combats_won        = 0
	_cycle_events             = 0
	_cycle_events_total       = 0
	_cycle_positive_events    = 0
	_cycle_traps_triggered    = 0
	_cycle_xp_hero            = 0.0
	_cycle_xp_biome           = 0.0
	_cycle_xp_passives_total  = 0.0
	_cycle_xp_passives_detail = {}
	_cycle_xp_entities_detail = {}

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
	_cycle_combo_max  = maxi(_cycle_combo_max,  _combo_count)
	PassiveSystem.decrement_cooldowns()
	CycleData.last_cycle_summary = _build_summary(false, true)
	EventBus.adventure_stopped.emit()

# Bonus ATK/DEF du modificateur de cycle + bonus de combo.
# Le combo donne +COMBO_ATK_BONUS_PCT par niveau au-dessus de 1.
func get_modifier_bonuses() -> Dictionary:
	var combo_mult = 1.0 + maxf(0.0, float(_combo_count - 1)) * Balance.COMBO_ATK_BONUS_PCT
	return {
		"atk_mult": float(current_modifier.get("atk_mult", 1.0)) * combo_mult,
		"def_mult": float(current_modifier.get("def_mult", 1.0))
	}

# Luck effective = luck permanente du joueur + luck temporaire du cycle.
func _get_effective_luck() -> int:
	return int(GameData.player.get("luck", 0)) + _cycle_luck

# ═══════════════════════════════════════════════════════════
#  Boucle de rencontres
# ═══════════════════════════════════════════════════════════

func _on_encounter_timer() -> void:
	if is_running:
		_process_encounter()

# Tire le type de rencontre et délègue au handler correspondant.
func _process_encounter() -> void:
	var hero_id      = GameData.player.get("active_creature_id", "")
	var enc_type     = _roll_encounter_type()
	var enc_data     = {
		"type":    enc_type,
		"biome_id": current_biome_id,
		"hero_id":  hero_id
	}

	_cycle_events_total += 1

	match enc_type:
		"creature":    _handle_creature_encounter(hero_id, enc_data)
		"benediction": _handle_benediction_encounter(hero_id, enc_data)
		"trap":        _handle_trap_encounter(hero_id, enc_data)

# ─── Rencontre Créature ───────────────────────────────────────

# Tire un ennemi aléatoire dans le pool du biome et lance le combat.
func _handle_creature_encounter(_hero_id: String, enc_data: Dictionary) -> void:
	var enemy := _weighted_random_creature()
	if enemy.is_empty():
		_schedule_next_encounter()
		return
	enemy              = enemy.duplicate()
	enc_data["enemy"]  = enemy
	_combat_start_hp   = current_hp

	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, 0.0
	)
	EventBus.adventure_event_resolved.emit(enc_data)

	var combat_options := {
		"ambush": _is_first_combat and BiomeMechanics.is_ambush_active(),
		"poison": BiomeMechanics.is_mechanic_active("poison"),
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
			bene.get("id", ""), bene.get("nom_affichage_fr", "?"), "Bénédiction", current_biome_id, 5.0
		)
		_apply_benediction_effect(bene)
		_cycle_events          += 1
		_cycle_positive_events += 1

	EventBus.adventure_event_resolved.emit(enc_data)
	_check_zone_transition()
	_apply_regen(hero_id)
	_schedule_next_encounter()

# Multiplicateur d'intensité des pièges et bénédictions selon la zone.
func _get_zone_intensity() -> float:
	match zone_courante:
		Enums.Zone.PROFONDEUR: return Balance.ZONE_INTENSITY_PROFONDEUR
		Enums.Zone.ABYSSE:     return Balance.ZONE_INTENSITY_ABYSSE
		_:                     return Balance.ZONE_INTENSITY_SURFACE

# Applique l'effet d'une bénédiction (soin ou bonus de luck), modulé par la zone.
func _apply_benediction_effect(bene: Dictionary) -> void:
	var effect_type  = bene.get("effet", "")
	var effect_value = float(bene.get("valeur", 0.0)) * _get_zone_intensity()

	match effect_type:
		"heal":
			var max_hp = get_max_hp()
			var healed = minf(effect_value, max_hp - current_hp)
			current_hp = minf(current_hp + effect_value, max_hp)
			EventBus.heal_applied.emit(healed, current_hp)

		"luck":
			_cycle_luck += int(effect_value)
			EventBus.luck_boosted.emit(_cycle_luck)

# Distribue l'XP de Maîtrise d'un événement résolu à TOUTES les entités actives :
# l'entité rencontrée, le héro, le biome, le village et les passifs actifs.
# Pour chacune : XP = base × modificateur d'écart × coefficient de type (cf. MasterySystem).
# event_id   = id de l'entité rencontrée (créature / piège / bénédiction).
# event_base = XP de base du type d'événement (avant modificateur de cycle).
func _distribute_mastery_xp(event_id: String, event_base: float) -> void:
	if event_id == "":
		return
	var base       := event_base * float(current_modifier.get("xp_mult", 1.0))
	var event_tier := int(GameData.get_entity(event_id).get("maitrise_actuelle", 0))

	MasterySystem.add_xp_to_entity(event_id, base, event_tier)                                       # entité rencontrée
	MasterySystem.add_xp_to_entity(GameData.player.get("active_creature_id", ""), base, event_tier)  # héro
	MasterySystem.add_xp_to_entity(current_biome_id, base, event_tier)                               # biome
	MasterySystem.add_xp_to_all_active(base, event_tier)                                             # passifs actifs
	GameData.add_village_mastery_xp(base, event_tier)                                                # village

	_cycle_xp += base

# ─── Rencontre Piège ──────────────────────────────────────────

# Tire un piège aléatoire et applique ses dégâts (sauf si modificateur "Fantôme").
func _handle_trap_encounter(hero_id: String, enc_data: Dictionary) -> void:
	var biome = GameData.get_entity(current_biome_id)
	var traps = biome.get("pieges", [])

	if traps.is_empty():
		EventBus.adventure_event_resolved.emit(enc_data)
		_schedule_next_encounter()
		return

	var trap           = traps[randi() % traps.size()]
	enc_data["trap"]   = trap
	_distribute_mastery_xp(trap.get("id", ""), Balance.XP_BASE_TRAP)

	if current_modifier.get("ignore_traps", false):
		enc_data["ignored"] = true
		GameData.record_encounter(
			trap.get("id", ""), trap.get("nom_affichage_fr", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(enc_data)
		_check_zone_transition()
		_apply_regen(hero_id)
		_schedule_next_encounter()
	else:
		_cycle_events          += 1
		_cycle_traps_triggered += 1
		current_hp = maxf(current_hp - float(trap.get("degats", 10)) * _get_zone_intensity(), 0.0)
		GameData.record_encounter(
			trap.get("id", ""), trap.get("nom_affichage_fr", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(enc_data)
		if current_hp <= 0.0:
			_end_adventure(false)
		else:
			_check_zone_transition()
			_apply_regen(hero_id)
			_schedule_next_encounter()

# ═══════════════════════════════════════════════════════════
#  Résultat de combat
# ═══════════════════════════════════════════════════════════

# Reçoit le résultat de combat et continue l'aventure ou l'arrête.
func _on_combat_ended(result: Dictionary) -> void:
	if not is_running:
		return

	current_hp = result.get("remaining_creature_hp", 0.0)

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
	var hero_id = GameData.player.get("active_creature_id", "")

	# XP de Maîtrise distribuée à toutes les entités actives (base de combat)
	_distribute_mastery_xp(enemy.get("id", ""), Balance.XP_BASE_COMBAT)

	# Hall des Évolutions
	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, Balance.XP_BASE_COMBAT
	)

	# Loot ennemi
	_drop_loot(enemy)
	_drop_ingredient_from_creature(enemy)

	# Ingrédients biome (uniquement si Village Tier ≥ 2)
	if GameData.get_entity("hero").get("maitrise_actuelle", 0) >= 2:
		_drop_ingredients()

	# Combo
	var max_hp      = get_max_hp()
	var hp_lost_pct = (_combat_start_hp - current_hp) / max_hp if max_hp > 0.0 else 1.0
	if hp_lost_pct <= Balance.COMBO_HP_THRESHOLD:
		_combo_count += 1
	else:
		_combo_count = 0
	EventBus.combo_changed.emit(_combo_count)

	# Statistiques du cycle
	_cycle_combats_won += 1
	_cycle_combo_max    = maxi(_cycle_combo_max, _combo_count)

	_check_zone_transition()
	_apply_regen(hero_id)
	_schedule_next_encounter(COMBAT_POST_DELAY)

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

# Calcule les PV max effectifs du héro (stats de base + équipement + passifs).
func get_max_hp() -> float:
	var hero_id  = GameData.player.get("active_creature_id", "")
	var equip_hp = GameData.get_equipment_bonuses().get("hp", 0.0)
	var hp_bonus = PassiveSystem.get_combat_bonuses().get("hp_bonus", 0.0)
	return float(GameData.get_effective_stats(hero_id).get("hp", 100)) + equip_hp + hp_bonus

# Programme la prochaine rencontre.
# Utilise FIRST_ENCOUNTER_DELAY pour la toute première, sinon le délai fourni.
func _schedule_next_encounter(delay: float = INSTANT_EVENT_DELAY) -> void:
	if not is_running:
		return
	var actual_delay := FIRST_ENCOUNTER_DELAY if _first_encounter_pending else delay
	_first_encounter_pending   = false
	_encounter_timer.wait_time = actual_delay
	_encounter_timer.start()

# Tire le type de rencontre selon la zone courante et les probabilités du biome.
func _roll_encounter_type() -> String:
	# Abysse : pas de combat — 50 % bénédictions / 50 % pièges
	if zone_courante == Enums.Zone.ABYSSE:
		return "benediction" if randf() < Balance.ABYSS_BENEDICTION_CHANCE else "trap"

	# Surface et Profondeur : distribution standard du biome
	var biome      = GameData.get_entity(current_biome_id)
	var base_table = biome.get("event_table", {
		"creature": 0.70, "benediction": 0.15, "trap": 0.15
	})

	# Bonne Étoile : déplace -5 % de créatures vers les événements positifs
	var event_table = BiomeMechanics.modify_event_probabilities(base_table)

	var luck        = float(_get_effective_luck())
	var trap_base   = float(event_table.get("trap", 0.15))
	var luck_shift  = minf(luck * Balance.LUCK_EVENT_SHIFT_PER_POINT, trap_base)

	var creature_chance    = float(event_table.get("creature",    0.70))
	var benediction_chance = float(event_table.get("benediction", 0.15)) + luck_shift

	var roll = randf()
	if roll < creature_chance:
		return "creature"
	elif roll < creature_chance + benediction_chance:
		return "benediction"
	else:
		return "trap"

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

# Roule un drop depuis un pool d'entrées avec bonus de luck.
# Chaque entrée : { item_id, chance, name, qty_min?, qty_max? }
# source_name : affiché dans loot_dropped (nom ennemi ou "Biome").
func _drop_pool(pool: Array, source_name: String) -> void:
	if pool.is_empty():
		return
	var drops:      Array = []
	var luck_bonus: float = float(_get_effective_luck()) * Balance.LUCK_DROP_BONUS_PER_POINT
	for entry in pool:
		var roll_threshold := minf(float(entry.get("chance", 0.0)) + luck_bonus, 1.0)
		if randf() >= roll_threshold:
			continue
		var item_id: String = entry.get("item_id", "")
		if item_id == "":
			continue
		var qty_min: int = int(entry.get("qty_min", 1))
		var qty_max: int = int(entry.get("qty_max", qty_min))
		var qty:     int = randi_range(qty_min, qty_max)
		GameData.add_resource(item_id, qty)
		var res := GameData.get_entity(item_id)
		drops.append({
			"item_id": item_id,
			"name":    res.get("nom_affichage_fr", res.get("name", item_id)),
			"qty":     qty
		})
	if not drops.is_empty():
		_cycle_loot += drops.size()
		EventBus.loot_dropped.emit(drops, source_name)

# Drop le loot spécifique à l'ennemi vaincu (loot_table de l'ennemi).
func _drop_loot(enemy: Dictionary) -> void:
	_drop_pool(enemy.get("loot_table", []), enemy.get("name", "?"))

# Drop un ingrédient standard depuis une créature évolutive (50% de chance).
func _drop_ingredient_from_creature(enemy: Dictionary) -> void:
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
	ingr["quantite_en_stock"] = int(ingr.get("quantite_en_stock", 0)) + 1
	EventBus.loot_dropped.emit(
		[{"item_id": ingredient_id, "name": ingr.get("nom_affichage_fr", ingredient_id), "qty": 1}],
		enemy.get("name", "?")
	)

# Drop des ingrédients depuis ingredients_drop du biome.
# Disponible uniquement si Village Tier ≥ 2 (appelé depuis _resolve_victory).
func _drop_ingredients() -> void:
	var biome       := GameData.get_entity(current_biome_id)
	var ingredients := biome.get("ingredients_drop", []) as Array
	if ingredients.is_empty():
		return
	var drops:      Array = []
	var luck_bonus: float = float(_get_effective_luck()) * Balance.LUCK_DROP_BONUS_PER_POINT
	for ingr in ingredients:
		var ingr_dict := ingr as Dictionary
		var roll_threshold := minf(float(ingr_dict.get("chance", 0.0)) + luck_bonus, 1.0)
		if randf() >= roll_threshold:
			continue
		var item_id: String = ingr_dict.get("id", "")
		if item_id == "":
			continue
		var qty_min: int = int(ingr_dict.get("qty_min", 1))
		var qty_max: int = int(ingr_dict.get("qty_max", qty_min))
		var qty:     int = randi_range(qty_min, qty_max)
		GameData.add_resource(item_id, qty)
		drops.append({"item_id": item_id, "name": ingr_dict.get("nom_affichage_fr", item_id), "qty": qty})
	if not drops.is_empty():
		_cycle_loot += drops.size()
		EventBus.loot_dropped.emit(drops, "Biome")

# ═══════════════════════════════════════════════════════════
#  Distribution pondérée des créatures (par zone)
# ═══════════════════════════════════════════════════════════

# Reconstruit available_creatures selon la zone courante.
# Surface    : créature Surface uniquement (la Profondeur n'apparaît pas tant
#              qu'elle n'est pas débloquée — on n'y descend que si la zone l'est)
# Profondeur : créature Profondeur (70 %) + créature Surface (30 %, taux moindre)
# Abysse     : aucune créature évolutive (Phase 4 gère l'Unique)
func _build_available_creatures(biome_id: String) -> void:
	available_creatures = []
	if zone_courante == Enums.Zone.ABYSSE:
		return

	var biome      := GameData.get_entity(biome_id)
	var surface    := biome.get("creature_surface",    {}) as Dictionary
	var profondeur := biome.get("creature_profondeur", {}) as Dictionary

	match zone_courante:
		Enums.Zone.SURFACE:
			_pool_add(surface,    Balance.POOL_WEIGHT_SURFACE)
		Enums.Zone.PROFONDEUR:
			_pool_add(surface,    Balance.POOL_WEIGHT_DEEP_SURFACE)
			_pool_add(profondeur, Balance.POOL_WEIGHT_DEEP_DEEP)

# Convertit un dict créature en entrée de combat et l'ajoute au pool avec son poids.
func _pool_add(creature: Dictionary, weight: float) -> void:
	if creature.is_empty():
		return
	var s := (creature.get("stats_par_palier", {}) as Dictionary).get(0, {}) as Dictionary
	available_creatures.append({
		"data": {
			"id":         creature.get("id", ""),
			"name":       creature.get("nom_affichage_fr", ""),
			"tier":       0,
			"atk":        s.get("atk",       10),
			"def":        s.get("def",        0),
			"hp":         s.get("hp",         50),
			"vit":        s.get("vit",        20),
			"xp_reward":  s.get("xp_reward",  10),
			"loot_table": creature.get("loot_table", []),
		},
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
	_cycle_combo_max  = maxi(_cycle_combo_max,  _combo_count)
	PassiveSystem.decrement_cooldowns()
	var summary := _build_summary(victory)
	CycleData.last_cycle_summary = summary
	EventBus.adventure_cycle_ended.emit(summary)

func _build_summary(victory: bool, interrupted: bool = false) -> Dictionary:
	return {
		"victory":              victory,
		"interrupted":          interrupted,
		"biome_id":             current_biome_id,
		"creature_id":          GameData.player.get("active_creature_id", ""),
		"modifier":             current_modifier,
		"xp_total":             _cycle_xp,
		"xp_hero":              _cycle_xp_hero,
		"xp_biome":             _cycle_xp_biome,
		"xp_passives_total":    _cycle_xp_passives_total,
		"xp_passives_detail":   _cycle_xp_passives_detail,
		"xp_entities_detail":   _cycle_xp_entities_detail,
		"loot_total":           _cycle_loot,
		"combo_max":            _cycle_combo_max,
		"combats_won":          _cycle_combats_won,
		"events":               _cycle_events,
		"events_total":         _cycle_events_total,
		"positive_events":      _cycle_positive_events,
		"traps_triggered":      _cycle_traps_triggered,
		"cycle_luck":           _cycle_luck,
	}

# ═══════════════════════════════════════════════════════════
#  Créature Unique d'Abysse
# ═══════════════════════════════════════════════════════════

# Déclenche le combat contre la créature Unique. Appelé par l'UI (bouton joueur).
func start_unique_combat() -> void:
	if not is_running or combat_unique_en_cours:
		return
	var biome := GameData.get_entity(current_biome_id)
	if biome.get("creature_unique_vaincue", false):
		return
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return
	combat_unique_en_cours = true
	_encounter_timer.stop()
	var s := (unique.get("stats_par_palier", {}) as Dictionary).get(0, {}) as Dictionary
	var unique_dict := {
		"id":         unique.get("id", ""),
		"name":       unique.get("nom_affichage_fr", ""),
		"tier":       2,
		"atk":        s.get("atk",       50),
		"def":        s.get("def",        0),
		"hp":         s.get("hp",        150),
		"vit":        s.get("vit",        15),
		"xp_reward":  s.get("xp_reward", 200),
		"loot_table": unique.get("loot_table", []),
	}
	GameData.record_encounter(
		unique_dict["id"], unique_dict["name"], "Créature", current_biome_id, 0.0
	)
	_combat_start_hp = current_hp
	_is_first_combat = false
	CombatPlayer.start_combat(unique_dict, current_hp, get_modifier_bonuses(), {
		"ambush": false,
		"poison": BiomeMechanics.is_mechanic_active("poison"),
	})

# Résout la victoire contre la créature Unique : flags, ingrédient, passif, signal.
func _resolve_unique_victory(enemy: Dictionary) -> void:
	var biome := GameData.get_entity(current_biome_id)
	biome["creature_unique_vaincue"] = true

	# Ingrédient unique → quantite_en_stock = 1
	var ingr_id: String = (biome.get("ingredient_unique", {}) as Dictionary).get("id", "")
	if ingr_id != "":
		var ingr := GameData.get_entity(ingr_id)
		if not ingr.is_empty():
			ingr["quantite_en_stock"] = 1

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

	_cycle_combats_won += 1

	EventBus.creature_unique_vaincue.emit(current_biome_id, ingr_id, passif_id)

	var hero_id: String = GameData.player.get("active_creature_id", "")
	_apply_regen(hero_id)
	_schedule_next_encounter(COMBAT_POST_DELAY)

# ═══════════════════════════════════════════════════════════
#  Zones
# ═══════════════════════════════════════════════════════════

# Zone maximale débloquée selon la Maîtrise (maitrise_actuelle) du biome.
# Commun/Peu Commun → Surface ; Rare/Épique → Profondeur ; Légendaire/Unique → Abysse.
func _get_max_zone(biome_id: String) -> Enums.Zone:
	var tier: int = GameData.get_entity(biome_id).get("maitrise_actuelle", 0)
	if tier >= Balance.ZONE_UNLOCK_TIER_ABYSSE:
		return Enums.Zone.ABYSSE
	elif tier >= Balance.ZONE_UNLOCK_TIER_PROFONDEUR:
		return Enums.Zone.PROFONDEUR
	else:
		return Enums.Zone.SURFACE

# Appelée après chaque événement résolu. Si le seuil est atteint et la zone suivante
# est débloquée, transition et émission du signal zone_changee.
func _check_zone_transition() -> void:
	_nb_evenements_zone += 1
	if _nb_evenements_zone < Balance.ZONE_TRANSITION_THRESHOLD:
		return
	var next_zone: int = int(zone_courante) + 1
	if next_zone > int(Enums.Zone.ABYSSE):
		return
	if next_zone > int(_get_max_zone(current_biome_id)):
		return
	zone_courante       = next_zone as Enums.Zone
	_nb_evenements_zone = 0
	_build_available_creatures(current_biome_id)
	EventBus.zone_changee.emit(int(zone_courante))
