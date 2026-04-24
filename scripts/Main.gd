extends Node2D


func _ready() -> void:
	print("IdleEvolution - Démarrage")
	SaveManager.load_save()
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

