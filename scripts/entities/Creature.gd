class_name Creature
extends Entity

func get_atk() -> float:
	return get_stat("atk")

func get_def() -> float:
	return get_stat("def")

func get_max_hp() -> float:
	return get_stat("hp")
