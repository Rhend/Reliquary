# ============================================================
# Village.gd — Scène principale du Village.
#
# Sections inline :
#   • Partir en expédition — sélection du biome + CTA mis en avant
#   • Héro                 — stats + XP + évolution
#   • Équipement           — 4 slots
#   • Passifs actifs
#   • Inventaire
#
# Écrans secondaires (overlay plein écran) :
#   • Hall des Évolutions  — EvolutionHall.gd
#   • Forge                — Forge.gd
# ============================================================
extends Control

# ─── Références UI dynamiques ───────────────────────────────

var _resources_vbox:  VBoxContainer
var _passives_vbox:   VBoxContainer
var _hero_vbox:       VBoxContainer
var _fade_rect:       ColorRect

# ─── Badges de notification d'évolution ─────────────────────

var _hero_evo_badge: Label       # "▲ Évolution disponible" dans l'en-tête Héro
var _hall_btn:       Button      # Bouton d'accès au Hall (badge si évolution dispo)
var _evolvable_set:  Dictionary = {}  # entity_id → true, entités prêtes à évoluer

const SLOT_ICONS: Dictionary = {"weapon":"Arme","shield":"Bouclier","boots":"Bottes","armor":"Armure"}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	SaveManager.load_save()

	_build_ui()
	_scan_evolvable_entities()   # Badges dès l'entrée si des entités peuvent évoluer

	# Rafraîchissements dynamiques via EventBus
	# Note : pas de connexion loot_dropped → _refresh_resources car resources_changed
	# est émis par add_resource() et couvre tous les cas sans double-rebuild.
	EventBus.resources_changed.connect(_refresh_resources)
	EventBus.entity_evolved.connect(_on_entity_evolved)
	EventBus.passive_unlocked.connect(func(_eid, _pid): _refresh_passives())
	EventBus.xp_gained.connect(_on_xp_gained_village)
	EventBus.entity_ready_to_evolve.connect(_on_entity_ready_to_evolve)

# ═══════════════════════════════════════════════════════════
#  Construction de l'interface (appelée une seule fois)
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	# Fond sombre de la scène
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	# ScrollContainer global pour les petits écrans
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

	# Section aventure — pleine largeur, mise en avant
	_build_adventure_section(root_vbox)

	# Cartes héro + équipement
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(row)

	_build_hero_card(row)
	_build_equipment_card(row)

	# Accès aux écrans secondaires + sections basses
	_build_hall_button(root_vbox)
	_build_forge_button(root_vbox)
	_build_passives_section(root_vbox)
	_build_resources_section(root_vbox)

	# Overlay de fondu — doit être le DERNIER enfant pour se rendre par-dessus tout
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	# Fondu d'entrée : noir → transparent
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.40)

# ─── Section "Partir en expédition" — pleine largeur ────────

func _build_adventure_section(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _margin(card, 20)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	m.add_child(vbox)

	# Titre avec accent coloré
	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	vbox.add_child(title_row)

	var accent = ColorRect.new()
	accent.color = UIColors.TYPE_EVENT_POS
	accent.custom_minimum_size = Vector2(4, 22)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(accent)

	var title_lbl = Label.new()
	title_lbl.text = "PARTIR EN EXPÉDITION"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	title_row.add_child(title_lbl)

	vbox.add_child(HSeparator.new())

	# Ligne : sélecteur de biome + aperçu
	var selector_row = HBoxContainer.new()
	selector_row.add_theme_constant_override("separation", 16)
	vbox.add_child(selector_row)

	var biome_selector = OptionButton.new()
	biome_selector.custom_minimum_size = Vector2(200, 0)
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") == "biome":
			biome_selector.add_item(e.get("name", entity_id))
			biome_selector.set_item_metadata(biome_selector.item_count - 1, entity_id)
	selector_row.add_child(biome_selector)

	var biome_preview = Label.new()
	biome_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_preview.add_theme_font_size_override("font_size", 12)
	biome_preview.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	biome_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selector_row.add_child(biome_preview)

	var _refresh_preview = func():
		if biome_selector.item_count == 0:
			return
		var bid    = biome_selector.get_item_metadata(biome_selector.selected)
		var bdata  = GameData.get_entity(bid)
		var bstats = bdata.get("base_stats", {})
		var tier   = bdata.get("current_tier", 0)
		var tier_name = GameData.get_tier_name(tier)
		var n_enemies = bstats.get("enemies", []).size()
		var n_events  = bstats.get("positive_events", []).size()
		var n_traps   = bstats.get("traps", []).size()
		biome_preview.text = "%s  ·  %d ennemis · %d événements · %d pièges" % [
			tier_name, n_enemies, n_events, n_traps
		]

	_refresh_preview.call()
	biome_selector.item_selected.connect(func(_i): _refresh_preview.call())

	# Bouton CTA mis en avant
	var start_btn = Button.new()
	start_btn.text = "▶  LANCER L'EXPÉDITION"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.add_theme_color_override("font_color", UIColors.BG_DARK)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = UIColors.TYPE_EVENT_POS
	for corner in ["corner_radius_top_left","corner_radius_top_right",
			"corner_radius_bottom_right","corner_radius_bottom_left"]:
		btn_style.set(corner, 6)
	start_btn.add_theme_stylebox_override("normal",  btn_style)
	start_btn.add_theme_stylebox_override("hover",   btn_style)
	start_btn.add_theme_stylebox_override("pressed", btn_style)
	start_btn.pressed.connect(func(): _start_adventure(biome_selector))
	vbox.add_child(start_btn)

# ─── Carte Héro (sélecteur + stats + XP + évolution) ─────────

func _build_hero_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 0)
	parent.add_child(card)

	var m    = _margin(card, 18)
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 8)
	m.add_child(card_vbox)

	_hero_evo_badge = _title_label(card_vbox, "HÉRO", UIColors.STAT_HP)
	card_vbox.add_child(HSeparator.new())

	_hero_vbox = VBoxContainer.new()
	_hero_vbox.add_theme_constant_override("separation", 8)
	card_vbox.add_child(_hero_vbox)

	_fill_hero_card()

func _fill_hero_card() -> void:
	for child in _hero_vbox.get_children():
		child.queue_free()

	var hero_name_lbl = Label.new()
	hero_name_lbl.text = GameData.get_entity("hero").get("name", "Héro")
	hero_name_lbl.add_theme_font_size_override("font_size", 14)
	hero_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_vbox.add_child(hero_name_lbl)
	_hero_vbox.add_child(HSeparator.new())

	# ── Stats ────────────────────────────────────────────────
	var creature_id = GameData.player.get("active_creature_id", "")
	var equip       = GameData.get_equipment_bonuses()
	var eff         = GameData.get_effective_stats(creature_id)
	var passives    = PassiveSystem.get_combat_bonuses()

	var stat_rows = [
		["ATK", int(eff.get("atk",0)) + int(equip.get("atk",0)) + int(passives.get("atk_bonus",0)), UIColors.STAT_ATK],
		["DEF", int(eff.get("def",0)) + int(passives.get("def_bonus",0)),                            UIColors.STAT_DEF],
		["PV",  int(eff.get("hp", 0)) + int(equip.get("hp", 0)) + int(passives.get("hp_bonus", 0)), UIColors.STAT_HP ],
	]
	for row_data in stat_rows:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		_hero_vbox.add_child(hbox)

		var key_lbl = Label.new()
		key_lbl.text = str(row_data[0]) + " :"
		key_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hbox.add_child(key_lbl)

		var val_lbl = Label.new()
		val_lbl.text = str(row_data[1])
		val_lbl.add_theme_color_override("font_color", row_data[2])
		val_lbl.add_theme_font_size_override("font_size", 14)
		hbox.add_child(val_lbl)

	# ── Progression XP ───────────────────────────────────────
	_hero_vbox.add_child(HSeparator.new())

	var creature    = GameData.get_entity(creature_id)
	var tier        = creature.get("current_tier",  0)
	var xp          = creature.get("current_xp",   0.0)
	var next_idx    = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max      = float(GameData.xp_thresholds[next_idx])
	var can_evolve  = tier < GameData.MAX_TIER and xp >= xp_max

	var tier_lbl = Label.new()
	tier_lbl.text = GameData.get_tier_name(tier)
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color",
		UIColors.FILTER_ON if tier > 0 else UIColors.TEXT_MUTED)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_vbox.add_child(tier_lbl)

	if tier < GameData.MAX_TIER:
		var bar_fill = StyleBoxFlat.new()
		bar_fill.bg_color = UIColors.FILTER_ON if can_evolve else UIColors.STAT_HP
		for corner in ["corner_radius_top_left","corner_radius_top_right",
				"corner_radius_bottom_right","corner_radius_bottom_left"]:
			bar_fill.set(corner, 3)

		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = UIColors.BG_BAR
		for corner in ["corner_radius_top_left","corner_radius_top_right",
				"corner_radius_bottom_right","corner_radius_bottom_left"]:
			bar_bg.set(corner, 3)

		var xp_bar = ProgressBar.new()
		xp_bar.min_value       = 0.0
		xp_bar.max_value       = xp_max
		xp_bar.value           = minf(xp, xp_max)
		xp_bar.show_percentage = true
		xp_bar.custom_minimum_size = Vector2(0, 16)
		xp_bar.add_theme_stylebox_override("fill", bar_fill)
		xp_bar.add_theme_stylebox_override("background", bar_bg)
		xp_bar.add_theme_color_override("font_color", Color.WHITE)
		xp_bar.add_theme_font_size_override("font_size", 10)
		_hero_vbox.add_child(xp_bar)

		var xp_lbl = Label.new()
		xp_lbl.text = "XP  %.0f / %.0f" % [xp, xp_max]
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color",
			UIColors.FILTER_ON if can_evolve else UIColors.TEXT_MUTED)
		xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hero_vbox.add_child(xp_lbl)

		if can_evolve:
			var evolve_btn = Button.new()
			evolve_btn.text = "ÉVOLUER ▲"
			evolve_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			evolve_btn.add_theme_color_override("font_color", UIColors.FILTER_ON)
			evolve_btn.pressed.connect(func():
				if MasterySystem.evolve_entity(creature_id):
					_fill_hero_card()
					_refresh_passives()
			)
			_hero_vbox.add_child(evolve_btn)
	else:
		var max_lbl = Label.new()
		max_lbl.text = "Maîtrise maximale"
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hero_vbox.add_child(max_lbl)

	_hero_vbox.add_child(_spacer())

# ─── Carte Équipement (4 slots) ──────────────────────────────

func _build_equipment_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	parent.add_child(card)

	var m    = _margin(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	_title_label(vbox, "ÉQUIPEMENT", UIColors.STAT_DEF)
	vbox.add_child(HSeparator.new())

	for slot in ["weapon", "shield", "boots", "armor"]:
		var item_id = GameData.player.get("equipped", {}).get(slot, "")
		var item    = GameData.get_entity(item_id)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		# Slot label (type d'équipement)
		var slot_lbl = Label.new()
		slot_lbl.text = SLOT_ICONS.get(slot, "?")
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		slot_lbl.custom_minimum_size = Vector2(58, 0)
		row.add_child(slot_lbl)

		# Nom de l'objet équipé
		var name_lbl = Label.new()
		name_lbl.text = item.get("name", "(vide)") if not item.is_empty() else "(vide)"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if item.is_empty():
			name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(name_lbl)

		# Résumé des bonus de l'objet
		if not item.is_empty():
			var bonuses = item.get("base_stats", {}).get("bonuses", {})
			var parts: Array = []
			for key in bonuses:
				match key:
					"atk":              parts.append("+%d ATK" % int(bonuses[key]))
					"hp":               parts.append("+%d PV"  % int(bonuses[key]))
					"attack_speed_pct": parts.append("+%d%% vit." % int(bonuses[key]))
			if not parts.is_empty():
				var bonus_lbl = Label.new()
				bonus_lbl.text = "  ".join(PackedStringArray(parts))
				bonus_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
				bonus_lbl.add_theme_font_size_override("font_size", 11)
				row.add_child(bonus_lbl)

	vbox.add_child(_spacer())

# ═══════════════════════════════════════════════════════════
#  Hall des Évolutions (bouton d'accès)
# ═══════════════════════════════════════════════════════════

func _on_entity_evolved(entity_id: String, _new_tier: int) -> void:
	_evolvable_set.erase(entity_id)
	_update_evo_badges()
	_refresh_passives()
	if entity_id == GameData.player.get("active_creature_id", ""):
		_fill_hero_card()

func _on_xp_gained_village(entity_id: String, _amount: float) -> void:
	if entity_id == GameData.player.get("active_creature_id", ""):
		_fill_hero_card()

# Reçoit le signal émis par MasterySystem dès qu'une entité franchit le seuil.
# Peuple _evolvable_set au chargement de la scène (entités déjà au seuil).
func _scan_evolvable_entities() -> void:
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") not in ["hero", "biome"]:
			continue
		var tier = e.get("current_tier", 0)
		if tier >= GameData.MAX_TIER:
			continue
		if e.get("current_xp", 0.0) >= float(GameData.xp_thresholds[tier + 1]):
			_evolvable_set[entity_id] = true
	_update_evo_badges()

func _on_entity_ready_to_evolve(entity_id: String) -> void:
	_evolvable_set[entity_id] = true
	_update_evo_badges()

func _update_evo_badges() -> void:
	var hero_ready  := false
	var hall_ready  := false
	for eid in _evolvable_set:
		var e_type = GameData.get_entity(eid).get("entity_type", "")
		if e_type == "hero":  hero_ready = true
		elif e_type == "biome": hall_ready = true

	if _hero_evo_badge != null:
		_hero_evo_badge.visible = hero_ready
	if _hall_btn != null:
		_hall_btn.text = ("⚔ HALL DES ÉVOLUTIONS  ▲" if hall_ready
				else "⚔ HALL DES ÉVOLUTIONS")

func _build_hall_button(parent: Node) -> void:
	_hall_btn = Button.new()
	_hall_btn.text = "⚔ HALL DES ÉVOLUTIONS"
	_hall_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hall_btn.pressed.connect(_open_hall)
	parent.add_child(_hall_btn)

func _open_hall() -> void:
	var hall = load("res://scripts/village/EvolutionHall.gd").new()
	add_child(hall)

# ═══════════════════════════════════════════════════════════
#  Inventaire
# ═══════════════════════════════════════════════════════════

func _build_resources_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "INVENTAIRE", UIColors.RESOURCE_QTY)
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

	# Trie les ressources à quantité positive par nom
	var sorted_ids: Array = []
	for item_id in resources:
		if int(resources[item_id]) > 0:
			sorted_ids.append(item_id)
	sorted_ids.sort_custom(func(a, b):
		return GameData.get_entity(a).get("name", a) < GameData.get_entity(b).get("name", b)
	)

	if sorted_ids.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune ressource pour le moment..."
		empty_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_resources_vbox.add_child(empty_lbl)
		return

	# HFlowContainer pour un affichage en grille fluide
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 6)
	_resources_vbox.add_child(flow)

	for item_id in sorted_ids:
		var qty = int(resources[item_id])
		var res      = GameData.get_entity(item_id)
		var res_name = res.get("name", item_id)

		# Chip : nom + quantité sur fond de carte
		var chip = PanelContainer.new()
		flow.add_child(chip)

		var m = MarginContainer.new()
		for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
			m.add_theme_constant_override(side, 6)
		chip.add_child(m)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		m.add_child(hbox)

		var name_lbl = Label.new()
		name_lbl.text = res_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(name_lbl)

		var qty_lbl = Label.new()
		qty_lbl.text = "×%d" % qty
		qty_lbl.add_theme_font_size_override("font_size", 12)
		qty_lbl.add_theme_color_override("font_color", UIColors.RESOURCE_QTY)
		hbox.add_child(qty_lbl)

func _build_forge_button(parent: Node) -> void:
	var btn = Button.new()
	btn.text = "🔨 FORGE"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_open_forge)
	parent.add_child(btn)

func _open_forge() -> void:
	var forge = load("res://scripts/village/Forge.gd").new()
	add_child(forge)

# ═══════════════════════════════════════════════════════════
#  Passifs actifs
# ═══════════════════════════════════════════════════════════

func _build_passives_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "PASSIFS ACTIFS", UIColors.TEXT_BONUS)
	section.add_child(HSeparator.new())

	_passives_vbox = VBoxContainer.new()
	_passives_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_passives_vbox.add_theme_constant_override("separation", 6)
	section.add_child(_passives_vbox)

	_refresh_passives()

func _refresh_passives() -> void:
	if _passives_vbox == null:
		return
	for child in _passives_vbox.get_children():
		child.queue_free()

	# Collecte tous les passifs actifs (débloqués sur des entités)
	var active: Array = []
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		for passive_id in e.get("unlocked_passives", []):
			if passive_id not in active:
				active.append(passive_id)
	for passive_id in GameData.player.get("active_passives", []):
		if passive_id not in active:
			active.append(passive_id)

	if active.is_empty():
		var lbl = Label.new()
		lbl.text = "Aucun passif actif — faites évoluer vos biomes !"
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 12)
		_passives_vbox.add_child(lbl)
		return

	var bonuses = PassiveSystem.get_combat_bonuses()

	for passive_id in active:
		var p = GameData.get_entity(passive_id)
		if p.is_empty():
			continue

		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_passives_vbox.add_child(card)

		var m    = _margin(card, 10)
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		m.add_child(hbox)

		# Nom + effets
		var left = VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(left)

		var name_lbl = Label.new()
		name_lbl.text = p.get("name", passive_id)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
		left.add_child(name_lbl)

		for effect in p.get("base_stats", {}).get("effects", []):
			var eff_lbl = Label.new()
			eff_lbl.text = effect.get("description", "")
			eff_lbl.add_theme_font_size_override("font_size", 11)
			eff_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
			left.add_child(eff_lbl)

	# Résumé des bonus totaux
	var parts: Array = []
	if bonuses.get("atk_bonus", 0.0) > 0.0:
		parts.append("+%.0f ATK" % bonuses["atk_bonus"])
	if bonuses.get("def_bonus", 0.0) > 0.0:
		parts.append("+%.0f DEF" % bonuses["def_bonus"])
	if bonuses.get("hp_bonus", 0.0) > 0.0:
		parts.append("+%.0f PV" % bonuses["hp_bonus"])

	if not parts.is_empty():
		var total_lbl = Label.new()
		total_lbl.text = "Bonus total : " + "   ".join(PackedStringArray(parts))
		total_lbl.add_theme_font_size_override("font_size", 12)
		total_lbl.add_theme_color_override("font_color", UIColors.STAT_ATK)
		total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_passives_vbox.add_child(total_lbl)

# ═══════════════════════════════════════════════════════════
#  Logique aventure
# ═══════════════════════════════════════════════════════════

func _start_adventure(biome_selector: OptionButton) -> void:
	if biome_selector.item_count == 0:
		return
	var biome_id    = biome_selector.get_item_metadata(biome_selector.selected)
	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id == "":
		return
	AdventureSystem.start_adventure(biome_id)
	_fade_to("res://scenes/Biome.tscn")

# Fondu vers noir puis changement de scène.
func _fade_to(scene_path: String) -> void:
	_fade_rect.color.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.30)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ═══════════════════════════════════════════════════════════
#  Utilitaires constructeurs UI
# ═══════════════════════════════════════════════════════════

# Crée un MarginContainer avec marges uniformes et l'ajoute à parent.
func _margin(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

# Titre de section : barre d'accent colorée à gauche + texte + badge caché.
# Retourne le Label de badge afin que l'appelant puisse l'afficher / masquer.
func _title_label(parent: Node, text: String, accent: Color = UIColors.TEXT_HEADER) -> Label:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)

	var bar = ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(bar)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	hbox.add_child(lbl)

	# Badge d'évolution — caché par défaut, affiché via _update_evo_badges()
	var badge = Label.new()
	badge.text = " ▲ ÉVOLUTION"
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", UIColors.FILTER_ON)
	badge.visible = false
	hbox.add_child(badge)
	return badge

# Spacer vertical pour pousser le contenu vers le haut.
func _spacer() -> Control:
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

