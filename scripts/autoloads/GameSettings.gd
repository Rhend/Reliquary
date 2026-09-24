# ============================================================
# GameSettings — Paramètres joueur persistants.
#
# Sauvegardés dans un fichier séparé (settings.json) pour
# survivre aux effacements de sauvegarde de progression.
# ============================================================
extends Node

const SETTINGS_PATH = "user://settings.json"

signal language_changed(lang: String)

# Multiplicateur de durée par step de combat.
# 1.0 = vitesse normale, 0.5 = x2, 0.25 = x4.
var combat_speed:   float  = 1.0
var fullscreen:     bool   = true   # défaut aligné sur window/size/mode=3
var volume_music:   float  = 1.0   # 0.0–1.0
var volume_sfx:     float  = 1.0   # 0.0–1.0
var language:       String = "fr"  # "fr" ou "en"
# Message d'accueil (WelcomeOverlay) : tant que false, il s'affiche à chaque
# démarrage. Coché « ne plus voir » → passe à true et ne réapparaît plus.
var welcome_dismissed: bool = false

func _ready() -> void:
	# Les bus Music/SFX sont créés par AudioManager (autoload antérieur) ; ici on
	# ne fait qu'appliquer les volumes persistés.
	_load()
	_apply_fullscreen()
	_apply_volume_music(volume_music)
	_apply_volume_sfx(volume_sfx)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		set_fullscreen(not fullscreen)

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

func set_welcome_dismissed(value: bool) -> void:
	welcome_dismissed = value
	_save()

func set_language(lang: String) -> void:
	if language == lang:
		return
	language = lang
	_save()
	language_changed.emit(lang)

func _apply_fullscreen() -> void:
	# FULLSCREEN (bordure retirée, résolution native du moniteur INCHANGÉE) et
	# non EXCLUSIVE_FULLSCREEN (24/09/2026, retour Rhend : « rendu pixelisé »)
	# — l'exclusif change le MODE VIDÉO réel pour la résolution du projet
	# (1280×720) et laisse le GPU/moniteur ré-agrandir l'image lui-même, un
	# scaler matériel bien moins soigné que l'étirement natif de Godot
	# (window/stretch/mode=canvas_items rend directement à la résolution du
	# bureau). Avec FULLSCREEN, le signal reste toujours à la résolution
	# native du moniteur, quelle qu'elle soit — c'est Godot qui agrandit le
	# canevas 1280×720, pas l'écran.
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN \
			if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _apply_volume_music(v: float) -> void:
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, v)

func _apply_volume_sfx(v: float) -> void:
	AudioManager.set_bus_volume(AudioManager.SFX_BUS, v)

func _save() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"combat_speed":  combat_speed,
		"fullscreen":    fullscreen,
		"volume_music":  volume_music,
		"volume_sfx":    volume_sfx,
		"language":      language,
		"welcome_dismissed": welcome_dismissed,
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
		fullscreen    = bool(data.get("fullscreen",     true))
		volume_music  = float(data.get("volume_music",  1.0))
		volume_sfx    = float(data.get("volume_sfx",    1.0))
		language      = str(data.get("language",        "fr"))
		welcome_dismissed = bool(data.get("welcome_dismissed", false))
	file.close()
