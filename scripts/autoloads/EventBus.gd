# ============================================================
# EventBus.gd — Bus de signaux central (pattern Observer).
#
# Tous les systèmes communiquent exclusivement via ce nœud :
# un émetteur appelle  EventBus.signal_name.emit(...)
# un récepteur appelle EventBus.signal_name.connect(callback)
#
# Avantage : aucun système ne référence directement un autre,
# ce qui rend l'ajout ou la suppression de systèmes trivial.
# ============================================================
extends Node

# ── Maîtrise & Évolution ────────────────────────────────────

# Émis par MasterySystem chaque fois qu'une entité gagne de l'XP.
signal xp_gained(entity_id: String, amount: float)

# Émis quand une entité a suffisamment d'XP pour monter de tier.
# Note : l'évolution elle-même est toujours déclenchée manuellement.
signal entity_ready_to_evolve(entity_id: String)

# Émis après une évolution réussie, avec le nouveau tier.
signal entity_evolved(entity_id: String, new_tier: int)

# Émis quand une entrée du Hall des Évolutions est créée ou mise à jour.
signal bestiary_updated(enc_id: String)

# ── Ressources & Forge ──────────────────────────────────────

# Émis par AdventureSystem après un drop de butin.
# drops : Array de { item_id, name, qty }
signal loot_dropped(drops: Array, enemy_name: String)

# Émis par GameData après tout changement d'inventaire (drop, craft, consommation).
signal resources_changed()

# ── Modificateurs de cycle & Combo ─────────────────────────

# Émis par AdventureSystem au lancement d'une aventure avec le modificateur tiré.
signal modifier_activated(modifier: Dictionary)

# Émis après chaque victoire de combat avec le compteur de combo courant.
# count = 0 si le combo a été cassé.
signal combo_changed(count: int)

# Émis quand un événement positif de soin restaure des PV.
# amount = PV effectivement restaurés, new_hp = PV après soin.
signal heal_applied(amount: float, new_hp: float)

# Émis quand un événement positif de chance booste la luck du cycle.
signal luck_boosted(cycle_luck: int)

# ── Passifs ─────────────────────────────────────────────────

# Émis quand un passif est débloqué sur une entité (palier de tier atteint).
signal passive_unlocked(entity_id: String, passive_id: String)

# Émis par PassiveSystem après un recalcul complet des effets actifs.
signal passives_refreshed()

# ── Aventure ────────────────────────────────────────────────

signal adventure_started(biome_id: String)
# event_data : { type, biome_id, creature_id, [enemy / effect / trap], [ignored] }
signal adventure_event_resolved(event_data: Dictionary)
# result     : { victory, biome_id, creature_id }
signal adventure_cycle_ended(result: Dictionary)
signal adventure_stopped()

# ── Combat tour par tour ────────────────────────────────────

# combat_started : HP initiaux des deux combattants.
signal combat_started(creature_id: String, enemy: Dictionary,
		creature_hp: float, enemy_hp: float)

# combat_turn    : attacker = "creature" | "enemy", damage, HP actuels.
signal combat_turn(attacker: String, damage: float,
		creature_hp: float, enemy_hp: float)

# combat_ended   : { victory, remaining_creature_hp, enemy }
signal combat_ended(result: Dictionary)

# ── État joueur ─────────────────────────────────────────────

# Émis quand une donnée joueur change hors des circuits habituels
# (ex. changement de créature active dans le Village).
signal player_state_changed()

# ── Sauvegarde ──────────────────────────────────────────────

signal save_completed()
signal load_completed()
