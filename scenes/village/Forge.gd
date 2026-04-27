# ============================================================
# Forge — Le Forgeron : inventaire, équipement et crafting.
#
# Flux :
#   Crafter → ajoute en equipment_inventory
#   Équiper  → déplace de l'inventaire vers le slot équipé
#   Retirer  → déplace du slot équipé vers l'inventaire
# ============================================================
extends Control

const SLOTS       := ["weapon", "armor", "accessory"]
const SLOT_LABELS := {"weapon": "Armes", "armor": "Armures", "accessory": "Accessoires"}

var _active_slot: String        = "weapon"
var _content:     VBoxContainer
var _tab_buttons: Dictionary    = {}

func _ready() -> void:
	_build_ui()
	EventBus.resources_changed.connect(_refresh)
	EventBus.equipment_changed.connect(_refresh)

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

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)

	_refresh()

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
		btn.toggle_mode    = true
		btn.button_pressed = (slot == _active_slot)
		btn.pressed.connect(_on_tab.bind(slot))
		hbox.add_child(btn)
		_tab_buttons[slot] = btn

	return bar

func _on_tab(slot: String) -> void:
	_active_slot = slot
	for s in _tab_buttons:
		_tab_buttons[s].button_pressed = (s == slot)
	_refresh()

# ═══════════════════════════════════════════════════════════
#  Rafraîchissement du contenu
# ═══════════════════════════════════════════════════════════

func _refresh(_a = null) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	_section_equipped()
	_section_inventory()
	_section_recipes()

# ── Slot équipé ──────────────────────────────────────────────

func _section_equipped() -> void:
	var equipped_id = GameData.player["equipped"].get(_active_slot, "")
	_add_section_header("ÉQUIPÉ")

	if equipped_id == "":
		var lbl = Label.new()
		lbl.text = "— Aucun équipement —"
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 12)
		_content.add_child(lbl)
	else:
		_content.add_child(_build_item_card(equipped_id, true))

	_content.add_child(_spacer())

# ── Inventaire ───────────────────────────────────────────────

func _section_inventory() -> void:
	var items = _inventory_for_slot(_active_slot)
	if items.is_empty():
		return

	_add_section_header("EN INVENTAIRE")
	for item_id in items:
		_content.add_child(_build_item_card(item_id, false))
	_content.add_child(_spacer())

# ── Recettes ────────────────────────────────────────────────

func _section_recipes() -> void:
	var recipes = RecipeRegistry.get_by_slot(_active_slot)
	if recipes.is_empty():
		return

	_add_section_header("À FORGER")
	for recipe in recipes:
		_content.add_child(_build_recipe_card(recipe))

# ═══════════════════════════════════════════════════════════
#  Constructeurs de cartes
# ═══════════════════════════════════════════════════════════

func _build_item_card(item_id: String, is_equipped: bool) -> Control:
	var item   = GameData.get_entity(item_id)
	var card   = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = UIColors.BG_CARD
	style.set_corner_radius_all(4)
	if is_equipped:
		style.border_color       = UIColors.STAT_ATK
		style.border_width_left  = 2
		style.border_width_right = 2
		style.border_width_top   = 2
		style.border_width_bottom = 2
	card.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	card.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	m.add_child(hbox)

	# Infos
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_lbl = Label.new()
	name_lbl.text = item.get("name", item_id)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color",
		UIColors.STAT_ATK if is_equipped else UIColors.TEXT_HEADER)
	info.add_child(name_lbl)

	var bonuses: Dictionary = item.get("base_stats", {}).get("bonuses", {})
	var bonus_parts: Array  = []
	if bonuses.get("atk", 0.0) > 0: bonus_parts.append("+%d ATK" % int(bonuses["atk"]))
	if bonuses.get("def", 0.0) > 0: bonus_parts.append("+%d DEF" % int(bonuses["def"]))
	if bonuses.get("hp",  0.0) > 0: bonus_parts.append("+%d PV"  % int(bonuses["hp"]))
	if bonuses.get("attack_speed_pct", 0.0) > 0:
		bonus_parts.append("+%d%% Vitesse" % int(bonuses["attack_speed_pct"]))
	if not bonus_parts.is_empty():
		var bonus_lbl = Label.new()
		bonus_lbl.text = "  ".join(PackedStringArray(bonus_parts))
		bonus_lbl.add_theme_font_size_override("font_size", 11)
		bonus_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
		info.add_child(bonus_lbl)

	# Bouton action
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(90, 0)
	if is_equipped:
		btn.text = "Retirer"
		btn.pressed.connect(func(): GameData.unequip_item(_active_slot))
	else:
		btn.text = "Équiper"
		btn.add_theme_color_override("font_color", UIColors.INGREDIENT_OK)
		btn.pressed.connect(func(): GameData.equip_item(item_id))
	hbox.add_child(btn)

	return card

func _build_recipe_card(recipe: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	card.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	m.add_child(hbox)

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

	var craftable = RecipeRegistry.can_craft(recipe)
	var btn = Button.new()
	btn.text     = "Crafter"
	btn.disabled = not craftable
	btn.custom_minimum_size = Vector2(90, 0)
	if craftable:
		btn.add_theme_color_override("font_color", UIColors.INGREDIENT_OK)
	btn.pressed.connect(func():
		if RecipeRegistry.craft(recipe):
			_refresh()
	)
	hbox.add_child(btn)

	return card

# ═══════════════════════════════════════════════════════════
#  Utilitaires
# ═══════════════════════════════════════════════════════════

func _inventory_for_slot(slot: String) -> Array:
	var result: Array = []
	for item_id in GameData.player.get("equipment_inventory", []):
		var item = GameData.get_entity(item_id)
		if item.get("base_stats", {}).get("slot", "") == slot:
			result.append(item_id)
	return result

func _add_section_header(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_content.add_child(lbl)

func _spacer() -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c
