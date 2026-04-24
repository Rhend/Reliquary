extends Control

var _bestiary_vbox:   VBoxContainer
var _hall_filter:     String = "Tout"
var _filter_buttons:  Dictionary = {}
var _resources_vbox:  VBoxContainer
var _forge_vbox:      VBoxContainer

const FILTER_TO_TYPE: Dictionary = {
	"Créatures":  "Créature",
	"Pièges":     "Piège",
	"Événements": "Événement"
}

func _ready() -> void:
	for entity_id in GameData.entities:
		if GameData.entities[entity_id].get("entity_type") == "creature":
			GameData.player["active_creature_id"] = entity_id
			break
	_build_ui()

# ─────────────────────────────────────────
#  Construction de l'interface
# ─────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.09, 0.16)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	scroll.add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 24)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	var title = Label.new()
	title.text = "VILLAGE"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(row)

	_build_adventure_card(row)
	_build_hero_card(row)
	_build_equipment_card(row)
	_build_hall_section(root_vbox)
	_build_resources_section(root_vbox)
	_build_forge_section(root_vbox)

# --- Carte "Partir en aventure" ---

func _build_adventure_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 220)
	parent.add_child(card)

	var m    = _margin_container(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	m.add_child(vbox)

	_section_title(vbox, "PARTIR EN AVENTURE")
	vbox.add_child(HSeparator.new())

	var biome_lbl = Label.new()
	biome_lbl.text = "Choisir un biome :"
	vbox.add_child(biome_lbl)

	var biome_selector = OptionButton.new()
	biome_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") == "biome":
			biome_selector.add_item(e.get("name", entity_id))
			biome_selector.set_item_metadata(biome_selector.item_count - 1, entity_id)
	vbox.add_child(biome_selector)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var start_btn = Button.new()
	start_btn.text = "▶   Lancer l'aventure"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(func(): _start_adventure(biome_selector))
	vbox.add_child(start_btn)

# --- Carte héro (stats uniquement, pas d'évolution propre) ---

func _build_hero_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	parent.add_child(card)

	var m    = _margin_container(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	_section_title(vbox, creature.get("name", "Héro").to_upper())
	vbox.add_child(HSeparator.new())

	var equip = GameData.get_equipment_bonuses()
	var eff   = GameData.get_effective_stats(creature_id)

	var rows = [
		["ATK", int(eff.get("atk", 0)) + int(equip.get("atk", 0)), Color(1.0, 0.55, 0.2)],
		["DEF", eff.get("def", 0),                                  Color(0.3, 0.7,  1.0)],
		["PV",  int(eff.get("hp", 0)) + int(equip.get("hp", 0)),   Color(0.2, 0.85, 0.35)]
	]
	for row_data in rows:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(hbox)
		var key_lbl = Label.new()
		key_lbl.text = str(row_data[0]) + " :"
		key_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		hbox.add_child(key_lbl)
		var val_lbl = Label.new()
		val_lbl.text = str(row_data[1])
		val_lbl.add_theme_color_override("font_color", row_data[2])
		val_lbl.add_theme_font_size_override("font_size", 14)
		hbox.add_child(val_lbl)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

# --- Carte équipement ---

func _build_equipment_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	parent.add_child(card)

	var m    = _margin_container(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	_section_title(vbox, "ÉQUIPEMENT")
	vbox.add_child(HSeparator.new())

	var icons = {"weapon": "⚔", "shield": "🛡", "boots": "👢"}
	for slot in ["weapon", "shield", "boots"]:
		var item_id = GameData.player.get("equipped", {}).get(slot, "")
		var item    = GameData.get_entity(item_id)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		var icon_lbl = Label.new()
		icon_lbl.text = icons.get(slot, "?")
		row.add_child(icon_lbl)

		var name_lbl = Label.new()
		name_lbl.text = item.get("name", "(vide)") if not item.is_empty() else "(vide)"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		if not item.is_empty():
			var bonuses = item.get("base_stats", {}).get("bonuses", {})
			var parts: Array = []
			for key in bonuses:
				match key:
					"atk":              parts.append("+%d ATK" % int(bonuses[key]))
					"hp":               parts.append("+%d PV"  % int(bonuses[key]))
					"attack_speed_pct": parts.append("+%d%% vit." % int(bonuses[key]))
			var bonus_lbl = Label.new()
			bonus_lbl.text = "  ".join(parts)
			bonus_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
			bonus_lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(bonus_lbl)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

# ─────────────────────────────────────────
#  Hall des Évolutions
# ─────────────────────────────────────────

func _build_hall_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_section_title(section, "HALL DES ÉVOLUTIONS")
	section.add_child(HSeparator.new())
	_build_filter_buttons(section)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)

	_bestiary_vbox = VBoxContainer.new()
	_bestiary_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(_bestiary_vbox)

	_refresh_bestiary()

func _build_filter_buttons(parent: Node) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	for f in ["Tout", "Créatures", "Pièges", "Événements", "Biomes"]:
		var btn = Button.new()
		btn.text = f
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.flat = true
		_filter_buttons[f] = btn
		btn.pressed.connect(func(): _on_filter_pressed(f))
		row.add_child(btn)

	_update_filter_buttons()

func _on_filter_pressed(filter: String) -> void:
	_hall_filter = filter
	_update_filter_buttons()
	_refresh_bestiary()

func _update_filter_buttons() -> void:
	for f in _filter_buttons:
		var btn: Button = _filter_buttons[f]
		if f == _hall_filter:
			btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.2))
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")

func _refresh_bestiary() -> void:
	if _bestiary_vbox == null:
		return
	for child in _bestiary_vbox.get_children():
		child.queue_free()

	if _hall_filter == "Biomes":
		_populate_biomes()
		return

	var hall: Dictionary = GameData.player.get("bestiary", {})

	var by_biome: Dictionary = {}
	for enc_id in hall:
		var entry    = hall[enc_id]
		var enc_type = entry.get("type", "Créature")
		if _hall_filter != "Tout":
			var required = FILTER_TO_TYPE.get(_hall_filter, "")
			if enc_type != required:
				continue
		var biome_name = entry.get("biome_name", "Inconnu")
		if not by_biome.has(biome_name):
			by_biome[biome_name] = []
		by_biome[biome_name].append(entry)

	if by_biome.is_empty():
		var lbl = Label.new()
		lbl.text = "Aucune rencontre enregistrée pour ce filtre." if not hall.is_empty() \
				   else "Aucune rencontre enregistrée pour le moment..."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_bestiary_vbox.add_child(lbl)
		return

	for biome_name in by_biome:
		_add_group_header(biome_name)
		for entry in by_biome[biome_name]:
			_add_entry_row(entry)
		_bestiary_vbox.add_child(HSeparator.new())

func _populate_biomes() -> void:
	_add_group_header("BIOMES EXPLORÉS")
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") != "biome":
			continue
		_add_entry_row({
			"name":  e.get("name", "?"),
			"type":  "Biome",
			"tier":  e.get("current_tier", 0),
			"xp":    e.get("current_xp",   0.0),
			"count": 0
		})

func _add_group_header(biome_name: String) -> void:
	var lbl = Label.new()
	lbl.text = "▸  " + biome_name.to_upper()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_bestiary_vbox.add_child(lbl)

	var header = _hall_row()
	_bestiary_vbox.add_child(header)
	for col in ["Nom", "Type", "Maîtrise", "XP"]:
		var h = Label.new()
		h.text = col
		h.add_theme_font_size_override("font_size", 11)
		h.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(h)

func _add_entry_row(entry: Dictionary) -> void:
	var tier: int    = entry.get("tier",  0)
	var xp: float    = entry.get("xp",    0.0)
	var count: int   = entry.get("count", entry.get("kills", 0))
	var enc_type     = entry.get("type",  "Créature")
	var next_i: int  = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max: float = float(GameData.xp_thresholds[next_i])
	var bar_color     = _type_color(enc_type)

	var row = _hall_row()
	_bestiary_vbox.add_child(row)

	var name_lbl = Label.new()
	name_lbl.text = entry.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)

	var type_lbl = Label.new()
	type_lbl.text = enc_type
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.add_theme_color_override("font_color", bar_color)
	row.add_child(type_lbl)

	var tier_lbl = Label.new()
	tier_lbl.text = GameData.get_tier_name(tier)
	tier_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(tier_lbl)

	var xp_col = VBoxContainer.new()
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar = _make_colored_bar(bar_color, 14)
	bar.min_value = 0.0
	bar.max_value = xp_max
	bar.value     = xp
	xp_col.add_child(bar)

	var count_text = "  (%d×)" % count if count > 0 else ""
	var xp_lbl = Label.new()
	xp_lbl.text = "%.0f / %.0f%s" % [xp, xp_max, count_text]
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	xp_col.add_child(xp_lbl)

	row.add_child(xp_col)

func _type_color(enc_type: String) -> Color:
	match enc_type:
		"Créature":  return Color(0.95, 0.58, 0.12)
		"Piège":     return Color(0.88, 0.22, 0.22)
		"Événement": return Color(0.20, 0.80, 0.42)
		"Biome":     return Color(0.22, 0.72, 0.90)
		_:           return Color.WHITE

func _make_colored_bar(color: Color, min_h: int) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, min_h)
	bar.show_percentage = false
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left     = 3
	fill.corner_radius_top_right    = 3
	fill.corner_radius_bottom_right = 3
	fill.corner_radius_bottom_left  = 3
	bar.add_theme_stylebox_override("fill", fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.10, 0.15)
	bg.corner_radius_top_left     = 3
	bg.corner_radius_top_right    = 3
	bg.corner_radius_bottom_right = 3
	bg.corner_radius_bottom_left  = 3
	bar.add_theme_stylebox_override("background", bg)
	return bar

func _hall_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

# ─────────────────────────────────────────
#  Inventaire ressources
# ─────────────────────────────────────────

func _build_resources_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_section_title(section, "INVENTAIRE")
	section.add_child(HSeparator.new())

	_resources_vbox = VBoxContainer.new()
	_resources_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resources_vbox.add_theme_constant_override("separation", 4)
	section.add_child(_resources_vbox)

	_refresh_resources()

func _refresh_resources() -> void:
	if _resources_vbox == null:
		return
	for child in _resources_vbox.get_children():
		child.queue_free()

	var resources: Dictionary = GameData.player.get("resources", {})
	if resources.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune ressource pour l'instant..."
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_resources_vbox.add_child(empty_lbl)
		return

	var row_wrap = HFlowContainer.new()
	row_wrap.add_theme_constant_override("h_separation", 16)
	row_wrap.add_theme_constant_override("v_separation", 6)
	_resources_vbox.add_child(row_wrap)

	for item_id in resources:
		var qty = int(resources[item_id])
		if qty <= 0:
			continue
		var res  = GameData.get_entity(item_id)
		var name = res.get("name", item_id)

		var chip = PanelContainer.new()
		row_wrap.add_child(chip)

		var m    = MarginContainer.new()
		for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
			m.add_theme_constant_override(side, 6)
		chip.add_child(m)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		m.add_child(hbox)

		var name_lbl = Label.new()
		name_lbl.text = name
		name_lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(name_lbl)

		var qty_lbl = Label.new()
		qty_lbl.text = "×%d" % qty
		qty_lbl.add_theme_font_size_override("font_size", 12)
		qty_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		hbox.add_child(qty_lbl)

# ─────────────────────────────────────────
#  Forge
# ─────────────────────────────────────────

func _build_forge_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_section_title(section, "FORGE")
	section.add_child(HSeparator.new())

	_forge_vbox = VBoxContainer.new()
	_forge_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_vbox.add_theme_constant_override("separation", 10)
	section.add_child(_forge_vbox)

	_refresh_forge()

func _refresh_forge() -> void:
	if _forge_vbox == null:
		return
	for child in _forge_vbox.get_children():
		child.queue_free()

	var recipes = GameData.get_forge_recipes()
	if recipes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune recette disponible."
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_forge_vbox.add_child(empty_lbl)
		return

	for recipe in recipes:
		_add_recipe_card(recipe)

func _add_recipe_card(recipe: Dictionary) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_vbox.add_child(card)

	var m    = _margin_container(card, 12)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	m.add_child(vbox)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_lbl = Label.new()
	name_lbl.text = recipe.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var slot_lbl = Label.new()
	slot_lbl.text = "[%s]" % recipe.get("result_slot", "?")
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	header.add_child(slot_lbl)

	var ing_row = HBoxContainer.new()
	ing_row.add_theme_constant_override("separation", 12)
	vbox.add_child(ing_row)

	var resources: Dictionary = GameData.player.get("resources", {})
	var can_craft = GameData.can_craft(recipe)

	for ing in recipe.get("ingredients", []):
		var item_id  = ing.get("item_id", "")
		var needed   = int(ing.get("qty", 0))
		var have     = int(resources.get(item_id, 0))
		var res_ent  = GameData.get_entity(item_id)
		var res_name = res_ent.get("name", item_id)

		var ing_lbl = Label.new()
		ing_lbl.add_theme_font_size_override("font_size", 11)
		ing_lbl.text = "%s %d/%d" % [res_name, have, needed]
		ing_lbl.add_theme_color_override("font_color",
			Color(0.35, 0.85, 0.35) if have >= needed else Color(0.85, 0.35, 0.35))
		ing_row.add_child(ing_lbl)

	var forge_btn = Button.new()
	forge_btn.text = "Forger"
	forge_btn.disabled = not can_craft
	forge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_btn.pressed.connect(func(): _on_forge_pressed(recipe))
	vbox.add_child(forge_btn)

func _on_forge_pressed(recipe: Dictionary) -> void:
	if GameData.craft(recipe):
		_refresh_resources()
		_refresh_forge()

# ─────────────────────────────────────────
#  Logique aventure
# ─────────────────────────────────────────

func _start_adventure(biome_selector: OptionButton) -> void:
	if biome_selector.item_count == 0:
		return
	var biome_id    = biome_selector.get_item_metadata(biome_selector.selected)
	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id == "":
		return
	AdventureSystem.start_adventure(biome_id)
	get_tree().change_scene_to_file("res://scenes/Biome.tscn")

# ─────────────────────────────────────────
#  Utilitaires UI
# ─────────────────────────────────────────

func _margin_container(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

func _section_title(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
