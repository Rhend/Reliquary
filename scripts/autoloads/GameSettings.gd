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
var combat_speed:   float = 1.0
var fullscreen:     bool  = false
var volume_music:   float = 1.0   # 0.0–1.0
var volume_sfx:     float = 1.0   # 0.0–1.0

func _ready() -> void:
	_ensure_audio_buses()
	_load()
	_apply_fullscreen()
	_apply_volume_music(volume_music)
	_apply_volume_sfx(volume_sfx)

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

func set_volume_music(value: float) -> void:
	volume_music = clampf(value, 0.0, 1.0)
	_apply_volume_music(volume_music)
	_save()

func set_volume_sfx(value: float) -> void:
	volume_sfx = clampf(value, 0.0, 1.0)
	_apply_volume_sfx(volume_sfx)
	_save()

func _apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
			if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _apply_volume_music(v: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0 else -80.0)

func _apply_volume_sfx(v: float) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0 else -80.0)

func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

func _save() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"combat_speed":  combat_speed,
		"fullscreen":    fullscreen,
		"volume_music":  volume_music,
		"volume_sfx":    volume_sfx,
	}, "\t"))
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
		combat_speed  = float(data.get("combat_speed",  1.0))
		fullscreen    = bool(data.get("fullscreen",     false))
		volume_music  = float(data.get("volume_music",  1.0))
		volume_sfx    = float(data.get("volume_sfx",    1.0))
	file.close()
