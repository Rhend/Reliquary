# ============================================================
# Forge — Le Forgeron : crafting par catégorie d'équipement.
# ============================================================
extends Control

const SLOTS := ["weapon", "armor", "accessory"]
const SLOT_LABELS := {"weapon": "Armes", "armor": "Armures", "accessory": "Accessoires"}

var _active_slot:  String        = "weapon"
var _recipe_vbox:  VBoxContainer
var _tab_buttons:  Dictionary    = {}  # slot → Button

func _ready() -> void:
	_build_ui()
	EventBus.resources_changed.connect(_refresh_recipes)

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
	root.add_child(_tab_bar())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	scroll.add_child(margin)

	_recipe_vbox = VBoxContainer.new()
	_recipe_vbox.add_theme_constant_override("separation", 12)
	_recipe_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_recipe_vbox)

	_refresh_recipes()

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
	title.text = "LE FORGERON"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIColors.STAT_ATK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(spacer)
	return bar

func _tab_bar() -> Control:
	var bar  = PanelContainer.new()
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	bar.add_child(hbox)

	for slot in SLOTS:
		var btn = Button.new()
		btn.text = SLOT_LABELS[slot]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (slot == _active_slot)
		btn.pressed.connect(_on_tab_pressed.bind(slot))
		hbox.add_child(btn)
		_tab_buttons[slot] = btn

	return bar

func _on_tab_pressed(slot: String) -> void:
	_active_slot = slot
	for s in _tab_buttons:
		_tab_buttons[s].button_pressed = (s == slot)
	_refresh_recipes()

func _refresh_recipes(_a = null, _b = null) -> void:
	for child in _recipe_vbox.get_children():
		_recipe_vbox.remove_child(child)
		child.queue_free()

	var recipes = RecipeRegistry.get_by_slot(_active_slot)
	if recipes.is_empty():
		var lbl = Label.new()
		lbl.text = "Aucune recette disponible."
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_recipe_vbox.add_child(lbl)
		return

	for recipe in recipes:
		_recipe_vbox.add_child(_build_recipe_card(recipe))

func _build_recipe_card(recipe: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 12)
	card.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	m.add_child(hbox)

	# ── Info (nom + ingrédients) ─────────────────────────────
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_lbl = Label.new()
	name_lbl.text = RecipeRegistry.get_result_name(recipe)
	name_lbl.add_theme_font_size_override("font_size", 14)
	info.add_child(name_lbl)

	for ing in RecipeRegistry.get_ingredient_summary(recipe):
		var ing_lbl = Label.new()
		var color   = UIColors.INGREDIENT_OK if ing["ok"] else UIColors.INGREDIENT_MISSING
		ing_lbl.text = "  %s : %d / %d" % [ing["name"], ing["have"], ing["needed"]]
		ing_lbl.add_theme_color_override("font_color", color)
		ing_lbl.add_theme_font_size_override("font_size", 11)
		info.add_child(ing_lbl)

	# ── Bouton Crafter ───────────────────────────────────────
	var craftable = RecipeRegistry.can_craft(recipe)
	var btn = Button.new()
	btn.text = "Crafter"
	btn.disabled = not craftable
	btn.custom_minimum_size = Vector2(90, 0)
	if craftable:
		btn.add_theme_color_override("font_color", UIColors.INGREDIENT_OK)
	btn.pressed.connect(func():
		if RecipeRegistry.craft(recipe):
			_refresh_recipes()
	)
	hbox.add_child(btn)

	return card
