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
@warning_ignore("unused_signal")
signal xp_gained(entity_id: String, amount: float)

# Émis quand une entité a suffisamment d'XP pour monter de tier.
# Note : l'évolution elle-même est toujours déclenchée manuellement.
@warning_ignore("unused_signal")
signal entity_ready_to_evolve(entity_id: String)

# Émis après une évolution réussie, avec le nouveau tier.
@warning_ignore("unused_signal")
signal entity_evolved(entity_id: String, new_tier: int)

# Émis quand une entrée du Hall des Évolutions est créée ou mise à jour.
@warning_ignore("unused_signal")
signal bestiary_updated(enc_id: String)

# ── Ressources & Forge ──────────────────────────────────────

# Émis par AdventureSystem après un drop de butin.
# drops : Array de { item_id, name, qty }
@warning_ignore("unused_signal")
signal loot_dropped(drops: Array, enemy_name: String)

# Émis par GameData après tout changement d'inventaire (drop, craft, consommation).
@warning_ignore("unused_signal")
signal resources_changed()

# ── Modificateurs de cycle & Combo ─────────────────────────

# Émis par AdventureSystem au lancement d'une aventure avec le modificateur tiré.
@warning_ignore("unused_signal")
signal modifier_activated(modifier: Dictionary)

# Émis après chaque victoire de combat avec le compteur de combo courant.
# count = 0 si le combo a été cassé.
@warning_ignore("unused_signal")
signal combo_changed(count: int)

# Émis quand un événement positif de soin restaure des PV.
# amount = PV effectivement restaurés, new_hp = PV après soin.
@warning_ignore("unused_signal")
signal heal_applied(amount: float, new_hp: float)

# Émis quand un événement positif de chance booste la luck du cycle.
@warning_ignore("unused_signal")
signal luck_boosted(cycle_luck: int)

# ── Passifs ─────────────────────────────────────────────────

# Émis quand un passif est débloqué sur une entité (palier de tier atteint).
@warning_ignore("unused_signal")
signal passive_unlocked(entity_id: String, passive_id: String)

# Émis par PassiveSystem après un recalcul complet des effets actifs.
@warning_ignore("unused_signal")
signal passives_refreshed()

# ── Mécaniques de biome ─────────────────────────────────────

# Émis par BiomeMechanics.initialize_for_biome() quand une mécanique forte se déclenche.
# mechanic = "ambush" | "poison" | "pirate_luck"
@warning_ignore("unused_signal")
signal biome_mechanic_activated(mechanic: String)

# ── Aventure ────────────────────────────────────────────────

@warning_ignore("unused_signal")
signal adventure_started(biome_id: String)
# Émis par AdventureSystem à chaque changement de zone pendant une expédition.
@warning_ignore("unused_signal")
signal zone_changee(nouvelle_zone: int)
# Émis après la victoire contre une créature Unique d'Abysse.
@warning_ignore("unused_signal")
signal creature_unique_vaincue(biome_id: String, ingredient_id: String, passif_id: String)
# event_data : { type, biome_id, creature_id, [enemy / effect / trap], [ignored] }
@warning_ignore("unused_signal")
signal adventure_event_resolved(event_data: Dictionary)
# result     : { victory, biome_id, creature_id }
@warning_ignore("unused_signal")
signal adventure_cycle_ended(result: Dictionary)
@warning_ignore("unused_signal")
signal adventure_stopped()

# ── Combat tour par tour ────────────────────────────────────

# combat_started : HP initiaux des deux combattants.
@warning_ignore("unused_signal")
signal combat_started(creature_id: String, enemy: Dictionary,
		creature_hp: float, enemy_hp: float)

# combat_turn    : attacker = "creature" | "enemy", damage, HP actuels.
@warning_ignore("unused_signal")
signal combat_turn(attacker: String, damage: float,
		creature_hp: float, enemy_hp: float)

# combat_ended   : { victory, remaining_creature_hp, enemy }
@warning_ignore("unused_signal")
signal combat_ended(result: Dictionary)

# ── Équipement ──────────────────────────────────────────────

# Émis quand un item est équipé ou déséquipé.
@warning_ignore("unused_signal")
signal equipment_changed()

# ── État joueur ─────────────────────────────────────────────

# Émis quand une donnée joueur change hors des circuits habituels.
@warning_ignore("unused_signal")
signal player_state_changed()

# ── Sauvegarde ──────────────────────────────────────────────

@warning_ignore("unused_signal")
signal save_completed()
@warning_ignore("unused_signal")
signal load_completed()
