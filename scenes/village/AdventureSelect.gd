# ============================================================
# AdventureSelect — Sélection de biome avant aventure.
#
# Gauche : liste des biomes disponibles.
# Droite : contenu du biome sélectionné (créatures, pièges,
#           événements, équipements) avec état de découverte.
# ============================================================
extends Control

var _selected_biome_id: String = ""
var _content_vbox:      VBoxContainer
var _biome_btns:        Dictionary = {}  # biome_id → Button

func _ready() -> void:
	_build_ui()

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

	root.add_child(_header_bar())

	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	body.add_child(_build_biome_list())
	body.add_child(_build_content_panel())

	# Sélectionne le premier biome par défaut
	var first_biome := _first_biome_id()
	if first_biome != "":
		_select_biome(first_biome)

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
	title.text = "CHOISIR UNE AVENTURE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIColors.TYPE_EVENT_POS)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(spacer)
	return bar

func _build_biome_list() -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 12)
	panel.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "BIOMES"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	vbox.add_child(lbl)
	vbox.add_child(HSeparator.new())

	for eid in GameData.entities:
		var e = GameData.entities[eid]
		if e.get("entity_type", "") != "biome":
			continue
		var btn = Button.new()
		btn.text = e.get("name", eid)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_biome.bind(eid))
		vbox.add_child(btn)
		_biome_btns[eid] = btn

	return panel

func _build_content_panel() -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var outer = MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		outer.add_theme_constant_override(side, 16)
	panel.add_child(outer)

	var vbox_outer = VBoxContainer.new()
	vbox_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_outer.add_theme_constant_override("separation", 12)
	outer.add_child(vbox_outer)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox_outer.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(_content_vbox)

	return panel

func _select_biome(biome_id: String) -> void:
	_selected_biome_id = biome_id
	for bid in _biome_btns:
		_biome_btns[bid].add_theme_color_override(
			"font_color",
			UIColors.TYPE_EVENT_POS if bid == biome_id else UIColors.TEXT_HEADER
		)
	_refresh_content()

func _refresh_content() -> void:
	for child in _content_vbox.get_children():
		_content_vbox.remove_child(child)
		child.queue_free()

	if _selected_biome_id == "":
		return

	var biome  = GameData.get_entity(_selected_biome_id)
	var pools  = MasteryRegistry.get_biome_entity_pools(_selected_biome_id)
	var bstats = biome.get("base_stats", {})

	# ── Titre biome + mastery ─────────────────────────────────
	var bdisp = MasteryRegistry.get_mastery_display(_selected_biome_id)
	var title = Label.new()
	title.text = biome.get("name", _selected_biome_id).to_upper()
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIColors.TYPE_BIOME)
	_content_vbox.add_child(title)

	if not bdisp.is_empty() and not bdisp["at_max"]:
		var xp_lbl = Label.new()
		xp_lbl.text = "%s  •  XP %.0f / %.0f" % [
			bdisp["tier_name"], bdisp["xp"], bdisp["xp_max"]
		]
		xp_lbl.add_theme_font_size_override("font_size", 11)
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_content_vbox.add_child(xp_lbl)

	_content_vbox.add_child(HSeparator.new())

	# ── Sections de contenu ───────────────────────────────────
	_add_pool_section("Créatures",           pools["creatures"],  UIColors.TYPE_CREATURE)
	_add_pool_section("Pièges",              pools["traps"],      UIColors.TYPE_TRAP)
	_add_pool_section("Événements positifs", pools["events"],     UIColors.TYPE_EVENT_POS)
	_add_pool_section("Équipements",         pools["equipment"],  UIColors.STAT_ATK)

	# ── Bouton Partir ─────────────────────────────────────────
	var btn = Button.new()
	btn.text = "Partir à l'aventure ▶"
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", UIColors.TYPE_EVENT_POS)
	btn.pressed.connect(_on_start_adventure)
	_content_vbox.add_child(btn)

func _add_pool_section(label: String, pool: Array, color: Color) -> void:
	if pool.is_empty():
		return

	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	_content_vbox.add_child(section)

	var header = Label.new()
	header.text = label.to_upper()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", color)
	section.add_child(header)

	var total      := pool.size()
	var discovered := MasteryRegistry.count_discovered(pool)

	for i in range(total):
		var entry     = pool[i]
		var entry_id  = entry.get("id", "")
		var is_known  = MasteryRegistry.is_discovered(entry_id)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		section.add_child(row)

		if is_known:
			var disp = MasteryRegistry.get_mastery_display(entry_id)
			var name_lbl = Label.new()
			name_lbl.text = entry.get("name", "?")
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_color_override("font_color", color)
			name_lbl.add_theme_font_size_override("font_size", 12)
			row.add_child(name_lbl)

			if not disp.is_empty():
				var tier_lbl = Label.new()
				tier_lbl.text = disp["tier_name"]
				tier_lbl.add_theme_font_size_override("font_size", 11)
				tier_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
				row.add_child(tier_lbl)

				if not disp["at_max"]:
					var bar = ProgressBar.new()
					bar.min_value       = 0.0
					bar.max_value       = disp["xp_max"]
					bar.value           = disp["xp"]
					bar.show_percentage = false
					bar.custom_minimum_size = Vector2(100, 10)
					var fill = StyleBoxFlat.new()
					fill.bg_color = color
					fill.set_corner_radius_all(2)
					bar.add_theme_stylebox_override("fill", fill)
					var bg = StyleBoxFlat.new()
					bg.bg_color = UIColors.BG_BAR
					bg.set_corner_radius_all(2)
					bar.add_theme_stylebox_override("background", bg)
					row.add_child(bar)
		else:
			var slot_lbl = Label.new()
			slot_lbl.text = "??? — Slot %d / %d" % [i + 1, total]
			slot_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
			slot_lbl.add_theme_font_size_override("font_size", 12)
			row.add_child(slot_lbl)

func _on_start_adventure() -> void:
	if _selected_biome_id == "":
		return
	GameData.player["active_biome_id"] = _selected_biome_id
	AdventureSystem.start_adventure(_selected_biome_id)
	get_tree().change_scene_to_file("res://scenes/Biome.tscn")

func _first_biome_id() -> String:
	for eid in GameData.entities:
		if GameData.entities[eid].get("entity_type", "") == "biome":
			return eid
	return ""
