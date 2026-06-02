# ============================================================
# TestBackgrounds — Aperçu des fonds animés de biome.
#
# Plein écran : un BiomeBackground + des boutons pour basculer le biome
# (Forêt / Ville) et la zone (Surface / Profondeur / Abysse), afin de juger
# l'ambiance et la descente en hostilité.
#
# Lancer tests/TestBackgrounds.tscn (F6) depuis l'éditeur.
# ============================================================
extends Control

var _bg: BiomeBackground

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_bg = BiomeBackground.new()
	add_child(_bg)   # premier enfant → derrière les boutons

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	panel.position = Vector2(16, 16)
	add_child(panel)

	panel.add_child(_header("BIOME"))
	var biome_row := HBoxContainer.new()
	biome_row.add_theme_constant_override("separation", 6)
	panel.add_child(biome_row)
	biome_row.add_child(_btn("Forêt",    func() -> void: _bg.apply_preset("forest")))
	biome_row.add_child(_btn("Marécage", func() -> void: _bg.apply_preset("marsh")))
	biome_row.add_child(_btn("Montagne", func() -> void: _bg.apply_preset("mountain")))
	biome_row.add_child(_btn("Ville",    func() -> void: _bg.apply_preset("city")))

	panel.add_child(_header("ZONE"))
	var zone_row := HBoxContainer.new()
	zone_row.add_theme_constant_override("separation", 6)
	panel.add_child(zone_row)
	zone_row.add_child(_btn("Surface",    func() -> void: _bg.set_zone(Enums.Zone.SURFACE)))
	zone_row.add_child(_btn("Profondeur", func() -> void: _bg.set_zone(Enums.Zone.PROFONDEUR)))
	zone_row.add_child(_btn("Abysse",     func() -> void: _bg.set_zone(Enums.Zone.ABYSSE)))

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	return l

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b
