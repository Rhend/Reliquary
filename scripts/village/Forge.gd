# Forge.gd — Écran complet de la Forge.
# Instancié dynamiquement par Village.gd via _open_forge().
extends Control

var _recipes_vbox: VBoxContainer

const SLOT_ICONS: Dictionary = {
	"weapon": "Arme",
	"shield": "Bouclier",
	"boots":  "Bottes",
	"armor":  "Armure"
}

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# En-tête
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var accent = ColorRect.new()
	accent.color = UIColors.STAT_ATK
	accent.custom_minimum_size = Vector2(4, 26)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(accent)

	var title_lbl = Label.new()
	title_lbl.text = "FORGE"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "✕ FERMER"
	close_btn.pressed.connect(queue_free)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Inventaire compact
	vbox.add_child(_build_inventory_row())
	vbox.add_child(HSeparator.new())

	# Recettes
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_recipes_vbox = VBoxContainer.new()
	_recipes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipes_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_recipes_vbox)

	_refresh()

func _build_inventory_row() -> Control:
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 4)

	var resources: Dictionary = GameData.player.get("resources", {})
	var has_any := false
	for item_id in resources:
		var qty = int(resources[item_id])
		if qty <= 0:
			continue
		has_any = true
		var res_name = GameData.get_entity(item_id).get("name", item_id)

		var lbl = Label.new()
		lbl.text = "%s ×%d" % [res_name, qty]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UIColors.RESOURCE_QTY)
		flow.add_child(lbl)

	if not has_any:
		var lbl = Label.new()
		lbl.text = "Aucune ressource"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		flow.add_child(lbl)

	return flow

func _refresh() -> void:
	if _recipes_vbox == null:
		return
	for child in _recipes_vbox.get_children():
		child.queue_free()

	var recipes = GameData.get_forge_recipes()
	if recipes.is_empty():
		var lbl = Label.new()
		lbl.text = "Aucune recette disponible."
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_recipes_vbox.add_child(lbl)
		return

	recipes.sort_custom(func(a, b):
		var ca = 0; for i in a.get("ingredients",[]): ca += int(i.get("qty",0))
		var cb = 0; for i in b.get("ingredients",[]): cb += int(i.get("qty",0))
		return ca < cb
	)

	for recipe in recipes:
		_add_recipe_card(recipe)

func _add_recipe_card(recipe: Dictionary) -> void:
	var slot      = recipe.get("result_slot", "weapon")
	var result_id = recipe.get("result_id", "")
	var equipped  = GameData.player.get("equipped", {}).get(slot, "")
	var is_equipped = (equipped == result_id)

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipes_vbox.add_child(card)

	var m    = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 12)
	card.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	m.add_child(vbox)

	# En-tête : nom + slot + badge
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_lbl = Label.new()
	name_lbl.text = recipe.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var badge_text  = ""
	var badge_color = UIColors.TEXT_MUTED
	if is_equipped:
		badge_text  = "ÉQUIPÉ"
		badge_color = UIColors.INGREDIENT_OK
	else:
		var result_item  = GameData.get_entity(result_id)
		var current_item = GameData.get_entity(equipped)
		if not result_item.is_empty():
			var r_score = 0
			var c_score = 0
			for v in result_item.get("base_stats",{}).get("bonuses",{}).values():
				r_score += int(v)
			for v in current_item.get("base_stats",{}).get("bonuses",{}).values():
				c_score += int(v)
			if r_score > c_score:
				badge_text  = "UPGRADE ▲"
				badge_color = UIColors.FILTER_ON

	var slot_lbl = Label.new()
	slot_lbl.text = "[%s]" % SLOT_ICONS.get(slot, "?")
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.add_theme_color_override("font_color", UIColors.RESULT_SLOT)
	header.add_child(slot_lbl)

	if badge_text != "":
		var badge = Label.new()
		badge.text = badge_text
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", badge_color)
		header.add_child(badge)

	# Ingrédients
	var ing_row = HBoxContainer.new()
	ing_row.add_theme_constant_override("separation", 16)
	vbox.add_child(ing_row)

	var resources: Dictionary = GameData.player.get("resources", {})
	for ing in recipe.get("ingredients", []):
		var item_id  = ing.get("item_id", "")
		var needed   = int(ing.get("qty", 0))
		var have     = int(resources.get(item_id, 0))
		var res_name = GameData.get_entity(item_id).get("name", item_id)

		var ing_lbl = Label.new()
		ing_lbl.text = "%s  %d / %d" % [res_name, have, needed]
		ing_lbl.add_theme_font_size_override("font_size", 12)
		ing_lbl.add_theme_color_override("font_color",
			UIColors.INGREDIENT_OK if have >= needed else UIColors.INGREDIENT_MISSING)
		ing_row.add_child(ing_lbl)

	# Bouton Forger
	var can_craft = GameData.can_craft(recipe)
	var forge_btn = Button.new()
	forge_btn.text     = "Forger" if not is_equipped else "Déjà équipé"
	forge_btn.disabled = not can_craft or is_equipped
	forge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if can_craft and not is_equipped:
		forge_btn.add_theme_color_override("font_color", UIColors.INGREDIENT_OK)
	forge_btn.pressed.connect(func():
		if GameData.craft(recipe):
			_refresh()
	)
	vbox.add_child(forge_btn)
