extends Node

# --- Maîtrise ---
signal xp_gained(entity_id: String, amount: float)
signal entity_ready_to_evolve(entity_id: String)
signal entity_evolved(entity_id: String, new_tier: int)
signal bestiary_updated(enc_id: String)

# --- Passifs ---
signal passive_unlocked(entity_id: String, passive_id: String)
signal passives_refreshed()

# --- Aventure ---
signal adventure_started(biome_id: String)
signal adventure_event_resolved(event_data: Dictionary)
signal adventure_cycle_ended(result: Dictionary)
signal adventure_stopped()

# --- Combat tour par tour ---
signal combat_started(creature_id: String, enemy: Dictionary, creature_hp: float, enemy_hp: float)
signal combat_turn(attacker: String, damage: float, creature_hp: float, enemy_hp: float)
signal combat_ended(result: Dictionary)

# --- Sauvegarde ---
signal save_completed()
signal load_completed()
