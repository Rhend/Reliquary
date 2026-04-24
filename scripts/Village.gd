extends Control

# --- refs UI mis à jour dynamiquement ---
var _evolve_btn: Button
var _xp_bar: ProgressBar
var _xp_label: Label
var _tier_label: Label

func _ready() -> void:
	# Sélectionne automatiquement la première créature disponible
	for entity_id in GameData.entities:
		if GameData.entities[entity_id].get("entity_type") == "creature":
			GameData.player["active_creature_id"] = entity_id
			break

	_build_ui()

	EventBus.entity_ready_to_evolve.connect(_on_ready_to_evolve)
	EventBus.entity_evolved.connect(_on_entity_evolved)

# ─────────────────────────────────────────
#  Construction de l'interface
# ─────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.09, 0.16)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 24)
	margin.add_child(root_vbox)

	# Titre
	var title = Label.new()
	title.text = "VILLAGE"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# Ligne de cartes
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(row)

	_build_adventure_card(row)
	_build_creature_card(row)

# --- Carte "Partir en aventure" ---

func _build_adventure_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 280)
	parent.add_child(card)

	var m = _margin_container(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	m.add_child(vbox)

	_section_title(vbox, "PARTIR EN AVENTURE")

	var sep = HSeparator.new()
	vbox.add_child(sep)

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

# --- Carte créature ---

func _build_creature_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 280)
	parent.add_child(card)

	var m = _margin_container(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	_section_title(vbox, creature.get("name", "Aucune créature").to_upper())

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var tier = creature.get("current_tier", 0)
	_tier_label = Label.new()
	_tier_label.text = "Palier : " + GameData.get_tier_name(tier)
	vbox.add_child(_tier_label)

	# Barre XP
	var xp     = creature.get("current_xp", 0.0)
	var next_i = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max = float(GameData.xp_thresholds[next_i])

	_xp_label = Label.new()
	_xp_label.text = "XP : %.0f / %.0f" % [xp, xp_max]
	vbox.add_child(_xp_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = xp_max
	_xp_bar.value     = xp
	vbox.add_child(_xp_bar)

	# Stats
	var stats     = creature.get("base_stats", {})
	var stats_lbl = Label.new()
	stats_lbl.text = "ATK %d  |  DEF %d  |  PV %d" % [
		stats.get("atk", 0), stats.get("def", 0), stats.get("hp", 0)
	]
	vbox.add_child(stats_lbl)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Bouton évolution (désactivé par défaut)
	_evolve_btn = Button.new()
	_evolve_btn.text = "★  Évoluer"
	_evolve_btn.disabled = true
	_evolve_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evolve_btn.pressed.connect(_on_evolve_pressed)
	vbox.add_child(_evolve_btn)

	# Activer si déjà évoluable au chargement
	_check_evolve_btn()

# ─────────────────────────────────────────
#  Logique
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

func _on_evolve_pressed() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	if MasterySystem.evolve_entity(creature_id):
		_refresh_creature_display()
	_evolve_btn.disabled = true

func _check_evolve_btn() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var entity      = GameData.get_entity(creature_id)
	if entity.is_empty() or _evolve_btn == null:
		return
	var tier    = entity.get("current_tier", 0)
	var next_i  = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max  = float(GameData.xp_thresholds[next_i])
	_evolve_btn.disabled = entity.get("current_xp", 0.0) < xp_max or tier >= GameData.MAX_TIER

func _refresh_creature_display() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var entity      = GameData.get_entity(creature_id)
	if entity.is_empty():
		return
	var tier   = entity.get("current_tier", 0)
	var xp     = entity.get("current_xp",   0.0)
	var next_i = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max = float(GameData.xp_thresholds[next_i])
	_tier_label.text  = "Palier : " + GameData.get_tier_name(tier)
	_xp_label.text    = "XP : %.0f / %.0f" % [xp, xp_max]
	_xp_bar.max_value = xp_max
	_xp_bar.value     = xp

func _on_ready_to_evolve(entity_id: String) -> void:
	if entity_id == GameData.player.get("active_creature_id", ""):
		if _evolve_btn:
			_evolve_btn.disabled = false

func _on_entity_evolved(_entity_id: String, _new_tier: int) -> void:
	_refresh_creature_display()

# ─────────────────────────────────────────
#  Utilitaires UI
# ─────────────────────────────────────────

func _margin_container(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

func _section_title(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
