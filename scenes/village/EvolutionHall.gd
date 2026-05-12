# ============================================================
# EvolutionHall — Hall des Évolutions.
#
# Liste toutes les entités soumises à la Maîtrise.
# Découvertes : affichées avec barre XP + bouton Évoluer.
# Non découvertes : silhouette "???" numérotée par type.
# ============================================================
extends Control

const SECTION_LABELS := {
	"creature":  "CRÉATURES",
	"biome":     "BIOMES",
	"passive":   "PASSIFS",
	"equipment": "ÉQUIPEMENTS",
	"trap":      "PIÈGES",
	"event":     "ÉVÉNEMENTS",
}

var _scroll_vbox: VBoxContainer

func _ready() -> void:
	_build_ui()
	EventBus.entity_evolved.connect(_on_entity_evolved)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── Header ───────────────────────────────────────────────
	var header = _header_bar()
	root.add_child(header)

	# ── Scroll ───────────────────────────────────────────────
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	scroll.add_child(margin)

	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.add_theme_constant_override("separation", 20)
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll_vbox)

	_populate()

func _header_bar() -> Control:
	var bar = PanelContainer.new()
	var m   = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 14)
	bar.add_child(m)
	var hbox = HBoxContainer.new()
	m.add_child(hbox)

	var back = Button.new()
	back.text = "← Village"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/village/village.tscn"))
	hbox.add_child(back)

	var title = Label.new()
	title.text = "HALL DES ÉVOLUTIONS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIColors.FILTER_ON)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	# spacer pour équilibrer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(spacer)
	return bar

func _populate() -> void:
	for child in _scroll_vbox.get_children():
		_scroll_vbox.remove_child(child)
		child.queue_free()

	for entity_type in SECTION_LABELS:
		var entities = MasteryRegistry.get_entities_by_type(entity_type)
		if entities.is_empty():
			continue
		_add_section(entity_type, entities)

func _add_section(entity_type: String, entities: Array) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	_scroll_vbox.add_child(section)

	# Titre de section
	var lbl = Label.new()
	lbl.text = SECTION_LABELS.get(entity_type, entity_type.to_upper())
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	section.add_child(lbl)
	section.add_child(HSeparator.new())

	var discovered  := 0
	for e in entities:
		if MasteryRegistry.is_discovered(e.get("id", "")):
			discovered += 1
			_add_entity_row(section, e)
		else:
			_add_unknown_slot(section, entity_type)

	# Compteur de découverte
	var count_lbl = Label.new()
	count_lbl.text = "%d / %d découvert(s)" % [discovered, entities.size()]
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	section.add_child(count_lbl)

func _add_entity_row(parent: Node, entity: Dictionary) -> void:
	var entity_id: String = entity.get("id", "")
	var display   := MasteryRegistry.get_mastery_display(entity_id)
	if display.is_empty():
		return

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	card.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	m.add_child(hbox)

	# Nom + tier
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)

	var name_lbl = Label.new()
	name_lbl.text = display["name"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	left.add_child(name_lbl)

	var tier_lbl = Label.new()
	tier_lbl.text = display["tier_name"]
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
	left.add_child(tier_lbl)

	# Barre XP + seuil
	var right = VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(right)

	if not display["at_max"]:
		var bar = ProgressBar.new()
		bar.min_value       = 0.0
		bar.max_value       = display["xp_max"]
		bar.value           = display["xp"]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = UIColors.FILTER_ON
		fill_style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill_style)
		var bg_style = StyleBoxFlat.new()
		bg_style.bg_color = UIColors.BG_BAR
		bg_style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg_style)
		right.add_child(bar)

		var xp_lbl = Label.new()
		xp_lbl.text = "%.0f / %.0f XP" % [display["xp"], display["xp_max"]]
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		right.add_child(xp_lbl)

		if display["can_evolve"]:
			var btn = Button.new()
			btn.text = "ÉVOLUER ▲"
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_color_override("font_color", UIColors.FILTER_ON)
			btn.pressed.connect(func(): _on_evolve_pressed(entity_id))
			right.add_child(btn)
	else:
		var max_lbl = Label.new()
		max_lbl.text = "Maîtrise maximale"
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		right.add_child(max_lbl)

func _add_unknown_slot(parent: Node, entity_type: String) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	card.add_child(m)

	var lbl = Label.new()
	lbl.text = "??? — Non découvert"
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 12)
	m.add_child(lbl)

func _on_evolve_pressed(entity_id: String) -> void:
	if MasterySystem.evolve_entity(entity_id):
		_populate()

func _on_entity_evolved(_id: String, _tier: int) -> void:
	_populate()
