# ============================================================
# Village — Hub principal : 3 boutons vers les sous-scènes.
# ============================================================
extends Control

func _ready() -> void:
	SaveManager.load_save()
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.custom_minimum_size = Vector2(320, 0)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "ARTEFACT : PUPPET TALE"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_add_hub_button(vbox, "⚔  Partir en Aventure",   UIColors.TYPE_EVENT_POS,
		"res://scenes/village/adventure_select.tscn")
	_add_hub_button(vbox, "▲  Hall des Évolutions",   UIColors.FILTER_ON,
		"res://scenes/village/evolution_hall.tscn")
	_add_hub_button(vbox, "🔨  Le Forgeron",           UIColors.STAT_ATK,
		"res://scenes/village/forge.tscn")

func _add_hub_button(parent: Node, label: String, color: Color, scene: String) -> void:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", color)
	btn.pressed.connect(func(): get_tree().change_scene_to_file(scene))
	parent.add_child(btn)
