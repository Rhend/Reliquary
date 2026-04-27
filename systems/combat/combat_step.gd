class_name CombatStep extends Resource

@export var attacker:        String = "hero"  # "hero" | "enemy"
@export var damage:          int    = 0
@export var target_hp_after: int    = 0
@export var is_killing_blow: bool   = false
