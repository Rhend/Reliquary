# ============================================================
# GameSettings — Paramètres joueur persistants.
#
# Sauvegardés dans un fichier séparé (settings.json) pour
# survivre aux effacements de sauvegarde de progression.
# ============================================================
extends Node

const SETTINGS_PATH = "user://settings.json"

# Multiplicateur de durée par step de combat.
# 1.0 = vitesse normale, 0.5 = x2, 0.25 = x4.
var combat_speed: float = 1.0
var fullscreen: bool = false

func _ready() -> void:
	_load()
	_apply_fullscreen()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		set_fullscreen(not fullscreen)

func set_combat_speed(multiplier: float) -> void:
	combat_speed = multiplier
	_save()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()
	_save()

func _apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
			if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _save() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"combat_speed": combat_speed, "fullscreen": fullscreen}, "\t"))
	file.close()

func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.get_data()
		combat_speed = float(data.get("combat_speed", 1.0))
		fullscreen = bool(data.get("fullscreen", false))
	file.close()
