# ============================================================
# AdventureSystem.gd — Boucle principale d'aventure.
#
# Fonctionnement général :
#   1. start_adventure() initialise l'état et tire un modificateur.
#   2. _schedule_next_event() démarre un timer de 2 s.
#   3. À l'expiration, _process_event() tire le type d'événement
#      (combat / positif / piège) selon la table du biome.
#   4. Les événements de combat délèguent à CombatSystem et
#      attendent le signal combat_ended avant de continuer.
#   5. Après chaque événement, le héro régénère REGEN_PCT de
#      ses PV max (modifiable par le modificateur de cycle).
#
# Modificateurs de cycle :
#   Tirés aléatoirement au lancement, ils durent tout le cycle.
#   Exemples : XP ×1.5, régénération 30 %, pièges ignorés.
#
# Combo :
#   Incrémenté si le héro perd ≤ COMBO_HP_THRESHOLD % de ses PV
#   pendant un combat, remis à zéro sinon.
# ============================================================
extends Node

# ─── Constantes ─────────────────────────────────────────────

# Délai (secondes) entre la fin d'un événement et le déclenchement du suivant.
const BETWEEN_EVENTS_DELAY: float = 2.0

# Régénération par défaut entre les événements (% des PV max).
const DEFAULT_REGEN_PCT: float = 0.15

# Seuil de perte de PV en-dessous duquel le combo s'incrémente.
# Si le héro perd ≤ 25 % de ses PV max dans un combat, c'est un "combat propre".
const COMBO_HP_THRESHOLD: float = 0.25

# ─── Modificateurs de cycle disponibles ─────────────────────
# Chaque dict peut porter : xp_mult, regen_pct, atk_mult, def_mult, ignore_traps.
# Les clés absentes utilisent leurs valeurs par défaut dans les fonctions.
const CYCLE_MODIFIERS: Array = [
	{
		"id":       "none",
		"name":     "—",
		"desc":     "",
		"xp_mult":  1.0
		# Aucune propriété spéciale — cycle standard
	},
	{
		"id":       "bonus_xp",
		"name":     "Cycle Chanceux",
		"desc":     "XP ×1.5 ce cycle",
		"xp_mult":  1.5
		# Idéal pour grinder de l'XP rapidement
	},
	{
		"id":       "resilient",
		"name":     "Endurance",
		"desc":     "Régénère 30 % entre combats",
		"xp_mult":  0.8,
		"regen_pct": 0.30
		# PV diminuent plus lentement — utile pour les biomes piégés
	},
	{
		"id":          "ghost",
		"name":        "Fantôme",
		"desc":        "Pièges ignorés, XP ×0.7",
		"xp_mult":     0.7,
		"ignore_traps": true
		# Traverse les pièges sans dégâts — bon pour le Marécage
	},
]

# ─── État runtime ────────────────────────────────────────────

var is_running:       bool       = false
var current_biome_id: String     = ""
var current_hp:       float      = 0.0
var current_modifier: Dictionary = {}   # Modificateur actif ce cycle

var _event_timer:    Timer
var _combo_count:    int   = 0      # Combats "propres" consécutifs
var _combat_start_hp: float = 0.0   # HP du héro avant le combat en cours

func _ready() -> void:
	_event_timer          = Timer.new()
	_event_timer.one_shot = true
	_event_timer.timeout.connect(_on_event_timer)
	add_child(_event_timer)
	EventBus.combat_ended.connect(_on_combat_ended)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

func start_adventure(biome_id: String) -> void:
	var biome       = GameData.get_entity(biome_id)
	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	if biome.is_empty() or creature.is_empty():
		push_error("AdventureSystem: biome ou créature manquant pour démarrer")
		return

	# Initialisation des HP de départ (stats effectives + bonus équipement)
	var equip_hp    = GameData.get_equipment_bonuses().get("hp", 0.0)
	var eff_stats   = GameData.get_effective_stats(creature_id)
	current_hp      = float(eff_stats.get("hp", 100)) + equip_hp

	current_biome_id = biome_id
	is_running       = true
	_combo_count     = 0
	_pick_modifier()   # Tire le modificateur de cycle

	GameData.player["active_biome_id"] = biome_id
	EventBus.adventure_started.emit(biome_id)
	_schedule_next_event()

func stop_adventure() -> void:
	if not is_running:
		return
	is_running = false
	_event_timer.stop()
	if CombatSystem.is_fighting:
		CombatSystem.stop_combat()
	EventBus.adventure_stopped.emit()

# Exposé pour CombatSystem : modificateurs d'ATK/DEF du cycle actif.
func get_modifier_bonuses() -> Dictionary:
	return {
		"atk_mult": float(current_modifier.get("atk_mult", 1.0)),
		"def_mult": float(current_modifier.get("def_mult", 1.0))
	}

# ═══════════════════════════════════════════════════════════
#  Boucle d'événements
# ═══════════════════════════════════════════════════════════

func _on_event_timer() -> void:
	if is_running:
		_process_event()

func _process_event() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var event_type  = _roll_event_type()
	var event_data  = {
		"type":       event_type,
		"biome_id":   current_biome_id,
		"creature_id": creature_id
	}

	match event_type:
		"combat":   _handle_combat_event(creature_id, event_data)
		"positive": _handle_positive_event(creature_id, event_data)
		"trap":     _handle_trap_event(creature_id, event_data)

# ─── Gestionnaire : Combat ───────────────────────────────────

func _handle_combat_event(creature_id: String, event_data: Dictionary) -> void:
	var biome   = GameData.get_entity(current_biome_id)
	var enemies = biome.get("base_stats", {}).get("enemies", [])

	if enemies.is_empty():
		_schedule_next_event()
		return

	var enemy           = enemies[randi() % enemies.size()].duplicate()
	event_data["enemy"] = enemy
	_combat_start_hp    = current_hp   # Mémorise les HP avant le combat pour le combo

	# Première rencontre — pas d'XP, juste un marquage dans le Hall
	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, 0.0
	)
	EventBus.adventure_event_resolved.emit(event_data)

	# Délègue le combat visuel à CombatSystem ;
	# le prochain événement ne se lance qu'après réception de combat_ended
	CombatSystem.start_combat(creature_id, enemy, current_hp)

# ─── Gestionnaire : Événement positif ───────────────────────

func _handle_positive_event(creature_id: String, event_data: Dictionary) -> void:
	var biome  = GameData.get_entity(current_biome_id)
	var events = biome.get("base_stats", {}).get("positive_events", [])

	if not events.is_empty():
		var evt              = events[randi() % events.size()]
		event_data["effect"] = evt
		GameData.record_encounter(
			evt.get("id", ""), evt.get("name", "?"), "Événement", current_biome_id, 5.0
		)

	EventBus.adventure_event_resolved.emit(event_data)
	_apply_regen(creature_id)
	_schedule_next_event()

# ─── Gestionnaire : Piège ────────────────────────────────────

func _handle_trap_event(creature_id: String, event_data: Dictionary) -> void:
	var biome = GameData.get_entity(current_biome_id)
	var traps = biome.get("base_stats", {}).get("traps", [])

	if traps.is_empty():
		EventBus.adventure_event_resolved.emit(event_data)
		_schedule_next_event()
		return

	var trap           = traps[randi() % traps.size()]
	event_data["trap"] = trap

	if current_modifier.get("ignore_traps", false):
		# Modificateur Fantôme : le piège est ignoré, enregistré mais sans dégâts
		event_data["ignored"] = true
		GameData.record_encounter(
			trap.get("id", ""), trap.get("name", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(event_data)
		_apply_regen(creature_id)
		_schedule_next_event()
	else:
		current_hp -= float(trap.get("damage", 10))
		GameData.record_encounter(
			trap.get("id", ""), trap.get("name", "?"), "Piège", current_biome_id, 5.0
		)
		EventBus.adventure_event_resolved.emit(event_data)
		if current_hp <= 0.0:
			_end_adventure(false)
		else:
			_apply_regen(creature_id)
			_schedule_next_event()

# ═══════════════════════════════════════════════════════════
#  Résultat de combat
# ═══════════════════════════════════════════════════════════

func _on_combat_ended(result: Dictionary) -> void:
	if not is_running:
		return

	current_hp = result.get("remaining_creature_hp", 0.0)

	if result.get("victory", false):
		_resolve_victory(result.get("enemy", {}))
	else:
		_end_adventure(false)

func _resolve_victory(enemy: Dictionary) -> void:
	var xp_base  = float(enemy.get("xp_reward", 10))
	var gen_tier = int(enemy.get("tier", 0))
	var xp_mult  = float(current_modifier.get("xp_mult", 1.0))

	# Distribution d'XP aux passifs actifs et au biome (XP biome = 40 % de l'XP gagnée)
	MasterySystem.add_xp_to_all_active(xp_base * xp_mult, gen_tier)
	MasterySystem.add_xp_to_entity(current_biome_id, xp_base * xp_mult * 0.4, gen_tier)

	# Mise à jour du Hall des Évolutions avec l'XP de base (hors multiplicateur de cycle)
	GameData.record_encounter(
		enemy.get("id", ""), enemy.get("name", "?"), "Créature", current_biome_id, xp_base
	)

	# Drop de loot selon la loot_table de l'ennemi
	_drop_loot(enemy)

	# Suivi du combo : combat "propre" si le héro a perdu ≤ COMBO_HP_THRESHOLD de ses PV
	var max_hp      = _get_max_hp()
	var hp_lost_pct = (_combat_start_hp - current_hp) / max_hp if max_hp > 0.0 else 1.0
	if hp_lost_pct <= COMBO_HP_THRESHOLD:
		_combo_count += 1
	else:
		_combo_count = 0
	EventBus.combo_changed.emit(_combo_count)

	_apply_regen(GameData.player.get("active_creature_id", ""))
	_schedule_next_event()

# ═══════════════════════════════════════════════════════════
#  Utilitaires internes
# ═══════════════════════════════════════════════════════════

# Régénère un pourcentage des PV max après chaque événement.
# Le pourcentage est celui du modificateur actif (défaut 15 %).
func _apply_regen(_creature_id: String) -> void:
	var regen_pct = float(current_modifier.get("regen_pct", DEFAULT_REGEN_PCT))
	var max_hp    = _get_max_hp()
	current_hp    = minf(current_hp + max_hp * regen_pct, max_hp)

# PV maximum du héro = stats effectives + bonus équipements.
func _get_max_hp() -> float:
	var creature_id = GameData.player.get("active_creature_id", "")
	var equip_hp    = GameData.get_equipment_bonuses().get("hp", 0.0)
	return float(GameData.get_effective_stats(creature_id).get("hp", 100)) + equip_hp

func _schedule_next_event() -> void:
	if not is_running:
		return
	_event_timer.wait_time = BETWEEN_EVENTS_DELAY
	_event_timer.start()

# Tire le type d'événement en tenant compte de la chance du joueur.
# La chance (luck) transfère un peu de probabilité de piège vers les événements positifs.
func _roll_event_type() -> String:
	var biome       = GameData.get_entity(current_biome_id)
	var event_table = biome.get("base_stats", {}).get("event_table", {
		"combat": 0.70, "positive": 0.15, "trap": 0.15
	})

	# Chaque point de luck transfère 1 % de chance de piège vers les événements positifs
	var luck        = float(GameData.player.get("luck", 0))
	var trap_base   = float(event_table.get("trap", 0.15))
	var luck_shift  = minf(luck * 0.01, trap_base)   # Ne peut pas dépasser le % de piège

	var combat_chance   = float(event_table.get("combat",   0.70))
	var positive_chance = float(event_table.get("positive", 0.15)) + luck_shift

	var roll = randf()
	if roll < combat_chance:
		return "combat"
	elif roll < combat_chance + positive_chance:
		return "positive"
	else:
		return "trap"

# Tire un modificateur de cycle aléatoirement selon les probabilités configurées.
func _pick_modifier() -> void:
	var roll = randf()
	if roll < 0.05:
		current_modifier = CYCLE_MODIFIERS[3]   # Fantôme      — 5 %
	elif roll < 0.15:
		current_modifier = CYCLE_MODIFIERS[2]   # Endurance    — 10 %
	elif roll < 0.30:
		current_modifier = CYCLE_MODIFIERS[1]   # Cycle Chanceux — 15 %
	else:
		current_modifier = CYCLE_MODIFIERS[0]   # Normal       — 70 %
	EventBus.modifier_activated.emit(current_modifier)

# Fait les rolls de loot pour chaque entrée de la loot_table de l'ennemi.
# Le bonus de luck augmente légèrement la chance de chaque drop.
func _drop_loot(enemy: Dictionary) -> void:
	var loot_table = enemy.get("loot_table", [])
	if loot_table.is_empty():
		return

	var drops:      Array = []
	var luck_bonus: float = float(GameData.player.get("luck", 0)) * 0.01

	for entry in loot_table:
		var roll_threshold = float(entry.get("chance", 0.0)) + luck_bonus
		if randf() < roll_threshold:
			var item_id = entry.get("item_id", "")
			if item_id == "":
				continue
			GameData.add_resource(item_id, 1)
			var res = GameData.get_entity(item_id)
			drops.append({
				"item_id": item_id,
				"name":    res.get("name", item_id),
				"qty":     1
			})

	if not drops.is_empty():
		EventBus.loot_dropped.emit(drops, enemy.get("name", "?"))

func _end_adventure(victory: bool) -> void:
	is_running = false
	_event_timer.stop()
	EventBus.adventure_cycle_ended.emit({
		"victory":     victory,
		"biome_id":    current_biome_id,
		"creature_id": GameData.player.get("active_creature_id", "")
	})
