class_name Creature
extends Entity

func get_atk() -> float:
	return get_stat("atk")

func get_def() -> float:
	return get_stat("def")

func get_max_hp() -> float:
	return get_stat("hp")

# Retourne les PV après régénération de 20% PV max
func apply_regen(current_hp: float) -> float:
	return min(current_hp + get_max_hp() * 0.2, get_max_hp())
