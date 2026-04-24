extends Control

# --- Héro (gauche) ---
var _c_hp_bar:    ProgressBar
var _c_hp_label:  Label
var _c_hp_style:  StyleBoxFlat
var _c_hp_tween:  Tween
var _c_atk_flash: Label
var _combo_label: Label

# --- Ennemi (droite) ---
var _e_name_label:  Label
var _e_stats_label: Label
var _e_hp_bar:      ProgressBar
var _e_hp_label:    Label
var _e_hp_style:    StyleBoxFlat
var _e_hp_tween:    Tween
var _e_atk_flash:   Label

# --- Partagé ---
var _event_label:    Label
var _modifier_label: Label
var _log_vbox:       VBoxContainer

# --- État interne ---
var _enemy_max_hp:        float  = 0.0
var _current_enemy_name:  String = "Ennemi"

# ─────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_turn.connect(_on_combat_turn)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.modifier_activated.connect(_on_modifier_activated)
	EventBus.combo_changed.connect(_on_combo_changed)
	# Affiche le modificateur déjà actif si l'aventure était déjà lancée
	if not AdventureSystem.current_modifier.is_empty():
		_on_modifier_activated(AdventureSystem.current_modifier)

# ─────────────────────────────────────────
#  Construction UI
# ─────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.11, 0.09)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var biome  = GameData.get_entity(GameData.player.get("active_biome_id", ""))
	var title  = Label.new()
	title.text = biome.get("name", "Biome").to_upper()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_modifier_label = Label.new()
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.add_theme_font_size_override("font_size", 13)
	_modifier_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.1))
	_modifier_label.visible = false
	root.add_child(_modifier_label)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	_build_creature_card(row)
	_build_enemy_card(row)

	_build_event_banner(root)
	_build_event_log(root)

	var exit_btn = Button.new()
	exit_btn.text = "◀  Quitter le cycle"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	root.add_child(exit_btn)

# --- Carte héro (gauche) ---

func _build_creature_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	_h1(vbox, creature.get("name", "Héro").to_upper())
	vbox.add_child(HSeparator.new())

	_c_hp_label      = Label.new()
	var equip_bonuses = GameData.get_equipment_bonuses()
	var eff_stats     = GameData.get_effective_stats(creature_id)
	var max_hp        = float(eff_stats.get("hp", 100)) + equip_bonuses.get("hp", 0.0)
	var initial_hp    = AdventureSystem.current_hp if AdventureSystem.is_running else max_hp
	_c_hp_label.text  = "PV : %.0f / %.0f" % [initial_hp, max_hp]
	vbox.add_child(_c_hp_label)

	_c_hp_style = _make_fill_style(_hp_color(initial_hp / max_hp if max_hp > 0 else 1.0))
	_c_hp_bar   = _make_bar(_c_hp_style, max_hp, initial_hp)
	vbox.add_child(_c_hp_bar)

	var stats_lbl = Label.new()
	stats_lbl.text = "ATK %d  DEF %d  PV %d" % [
		int(eff_stats.get("atk", 0)) + int(equip_bonuses.get("atk", 0)),
		eff_stats.get("def", 0),
		int(max_hp)
	]
	stats_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(stats_lbl)

	var parts: Array = []
	for slot in ["weapon", "shield", "boots"]:
		var item = GameData.get_entity(GameData.player.get("equipped", {}).get(slot, ""))
		if not item.is_empty():
			parts.append(item.get("name", ""))
	var equip_line = Label.new()
	equip_line.text = "  ".join(parts) if not parts.is_empty() else "Aucun équipement"
	equip_line.add_theme_font_size_override("font_size", 11)
	equip_line.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	equip_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(equip_line)

	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 14)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.0))
	_combo_label.visible = false
	vbox.add_child(_combo_label)

	vbox.add_child(_spacer())

	_c_atk_flash = _flash_label("⚔  ATTAQUE !", Color(1.0, 0.92, 0.05))
	vbox.add_child(_c_atk_flash)

# --- Carte ennemi (droite) ---

func _build_enemy_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	_e_name_label      = Label.new()
	_e_name_label.text = "EN ATTENTE..."
	_e_name_label.add_theme_font_size_override("font_size", 18)
	_e_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_name_label)

	vbox.add_child(HSeparator.new())

	_e_hp_label      = Label.new()
	_e_hp_label.text = "PV : —"
	vbox.add_child(_e_hp_label)

	_e_hp_style = _make_fill_style(Color(0.85, 0.2, 0.2))
	_e_hp_bar   = _make_bar(_e_hp_style, 100.0, 0.0)
	vbox.add_child(_e_hp_bar)

	_e_stats_label      = Label.new()
	_e_stats_label.text = ""
	_e_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_stats_label)

	vbox.add_child(_spacer())

	_e_atk_flash = _flash_label("💥  RIPOSTE !", Color(1.0, 0.2, 0.05))
	vbox.add_child(_e_atk_flash)

# --- Bandeau événement ---

func _build_event_banner(parent: Node) -> void:
	var card = PanelContainer.new()
	parent.add_child(card)

	var m = _pad(card, 12)
	_event_label = Label.new()
	_event_label.text = "En attente du premier événement..."
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_child(_event_label)

# --- Journal d'événements (8 lignes max) ---

func _build_event_log(parent: Node) -> void:
	var panel = PanelContainer.new()
	parent.add_child(panel)

	var m = _pad(panel, 8)
	var vbox_outer = VBoxContainer.new()
	vbox_outer.add_theme_constant_override("separation", 4)
	m.add_child(vbox_outer)

	var header = Label.new()
	header.text = "JOURNAL"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox_outer.add_child(header)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 96)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox_outer.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_log_vbox)

# ─────────────────────────────────────────
#  Handlers signaux
# ─────────────────────────────────────────

func _on_combat_started(_creature_id: String, enemy: Dictionary, creature_hp: float, enemy_hp: float) -> void:
	_current_enemy_name = enemy.get("name", "Ennemi")
	_enemy_max_hp       = enemy_hp

	_e_name_label.text  = _current_enemy_name.to_upper()
	_e_stats_label.text = "ATK %d   DEF %d" % [enemy.get("atk", 0), enemy.get("def", 0)]
	_e_hp_style.bg_color = _enemy_hp_color(1.0)
	_e_hp_bar.max_value  = _enemy_max_hp
	_e_hp_bar.value      = _enemy_max_hp
	_e_hp_label.text     = "PV : %.0f / %.0f" % [_enemy_max_hp, _enemy_max_hp]

	_set_creature_hp(creature_hp)
	_event_label.text = "⚔  Combat contre %s !" % _current_enemy_name
	_add_log_entry("⚔  Combat: %s  (PV %d)" % [_current_enemy_name, int(enemy_hp)], Color(0.95, 0.58, 0.12))

func _on_combat_turn(attacker: String, damage: float, creature_hp: float, enemy_hp: float) -> void:
	_set_creature_hp(creature_hp)
	_set_enemy_hp(enemy_hp)

	var c_name = GameData.get_entity(GameData.player.get("active_creature_id","")).get("name", "Héro")
	if attacker == "creature":
		_event_label.text = "⚔ %s inflige %.0f dégâts à %s  —  PV ennemi : %.0f" % [
			c_name, damage, _current_enemy_name, maxf(enemy_hp, 0.0)
		]
		_flash(_c_atk_flash)
	else:
		_event_label.text = "💥 %s riposte : %.0f dégâts à %s  —  PV restants : %.0f" % [
			_current_enemy_name, damage, c_name, maxf(creature_hp, 0.0)
		]
		_flash(_e_atk_flash)

func _on_combat_ended(result: Dictionary) -> void:
	var enemy_name = result.get("enemy", {}).get("name", "l'ennemi")
	if result.get("victory", false):
		_event_label.text = "Victoire contre %s ! Prochain événement dans 2 s..." % enemy_name
		_add_log_entry("  Victoire vs %s" % enemy_name, Color(0.2, 0.85, 0.35))
	else:
		_event_label.text = "Défaite contre %s..." % enemy_name
		_add_log_entry("  Défaite vs %s" % enemy_name, Color(0.88, 0.18, 0.12))
	_set_creature_hp(result.get("remaining_creature_hp", 0.0))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"positive":
			var effect = event_data.get("effect", {})
			_event_label.text = effect.get("name", "Événement positif")
			_add_log_entry("  " + effect.get("name", "Événement positif"), Color(0.4, 0.9, 0.55))
			_clear_enemy_display()
		"trap":
			var trap    = event_data.get("trap", {})
			var ignored = event_data.get("ignored", false)
			if ignored:
				_event_label.text = "Piège ignoré : %s  (Fantôme)" % trap.get("name","?")
				_add_log_entry("  Piège ignoré: %s" % trap.get("name","?"), Color(0.5, 0.5, 0.9))
			else:
				_event_label.text = "Piège : %s  (−%.0f PV)" % [trap.get("name","?"), trap.get("damage",0.0)]
				_add_log_entry("  Piège: %s  −%.0f PV" % [trap.get("name","?"), trap.get("damage",0.0)], Color(0.88, 0.22, 0.22))
			_clear_enemy_display()
			_set_creature_hp(AdventureSystem.current_hp)

func _on_cycle_ended(result: Dictionary) -> void:
	if not result.get("victory", true):
		_event_label.text = "💀 Cycle terminé — retour au village dans 2 s..."
		await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

func _on_loot_dropped(drops: Array, enemy_name: String) -> void:
	var parts: Array = []
	for d in drops:
		parts.append("%s ×%d" % [d.get("name", "?"), d.get("qty", 1)])
	_add_log_entry("  Butin [%s] : %s" % [enemy_name, ", ".join(PackedStringArray(parts))], Color(1.0, 0.85, 0.15))

func _on_modifier_activated(modifier: Dictionary) -> void:
	var m_name = modifier.get("name", "—")
	var m_desc = modifier.get("desc", "")
	if m_name == "—" or m_name == "":
		_modifier_label.visible = false
	else:
		_modifier_label.text = "  %s  —  %s  " % [m_name, m_desc]
		_modifier_label.visible = true

func _on_combo_changed(count: int) -> void:
	if count > 1:
		_combo_label.text = "COMBO  ×%d" % count
		_combo_label.visible = true
	else:
		_combo_label.visible = false

func _add_log_entry(text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_vbox.add_child(lbl)
	while _log_vbox.get_child_count() > 8:
		_log_vbox.get_child(0).queue_free()

func _on_exit_pressed() -> void:
	AdventureSystem.stop_adventure()
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

# ─────────────────────────────────────────
#  Helpers affichage HP (tween + couleur)
# ─────────────────────────────────────────

func _set_creature_hp(hp: float) -> void:
	var val = maxf(hp, 0.0)
	_c_hp_label.text = "PV : %.0f / %.0f" % [val, _c_hp_bar.max_value]
	if _c_hp_tween:
		_c_hp_tween.kill()
	_c_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_c_hp_tween.tween_property(_c_hp_bar, "value", val, 0.28)
	var pct = val / _c_hp_bar.max_value if _c_hp_bar.max_value > 0 else 1.0
	_c_hp_style.bg_color = _hp_color(pct)

func _set_enemy_hp(hp: float) -> void:
	var val = maxf(hp, 0.0)
	_e_hp_label.text = "PV : %.0f / %.0f" % [val, _enemy_max_hp]
	if _e_hp_tween:
		_e_hp_tween.kill()
	_e_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_e_hp_tween.tween_property(_e_hp_bar, "value", val, 0.28)
	var pct = val / _enemy_max_hp if _enemy_max_hp > 0 else 1.0
	_e_hp_style.bg_color = _enemy_hp_color(pct)

func _hp_color(pct: float) -> Color:
	if pct > 0.6:
		return Color(0.18, 0.82, 0.32)   # vert
	elif pct > 0.3:
		return Color(0.9,  0.74, 0.08)   # jaune
	else:
		return Color(0.88, 0.18, 0.12)   # rouge

func _enemy_hp_color(pct: float) -> Color:
	if pct > 0.6:
		return Color(0.88, 0.18, 0.12)   # rouge — dangereux
	elif pct > 0.3:
		return Color(0.9,  0.52, 0.08)   # orange — affaibli
	else:
		return Color(0.88, 0.82, 0.08)   # jaune — presque vaincu

func _clear_enemy_display() -> void:
	_e_name_label.text  = "—"
	_e_stats_label.text = ""
	_e_hp_label.text    = "PV : —"
	_e_hp_bar.value     = 0.0

# ─────────────────────────────────────────
#  Flash FX
# ─────────────────────────────────────────

func _flash(lbl: Label) -> void:
	var tween = create_tween()
	tween.tween_property(lbl, "modulate:a", 1.0, 0.04)
	tween.tween_interval(0.30)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.45)

# ─────────────────────────────────────────
#  Utilitaires constructeurs
# ─────────────────────────────────────────

func _make_fill_style(color: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left  = 4
	return s

func _make_bar(fill_style: StyleBoxFlat, max_val: float, val: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.min_value        = 0.0
	bar.max_value        = max_val
	bar.value            = val
	bar.show_percentage  = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.add_theme_stylebox_override("fill", fill_style)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.10, 0.15)
	bg.corner_radius_top_left     = 4
	bg.corner_radius_top_right    = 4
	bg.corner_radius_bottom_right = 4
	bg.corner_radius_bottom_left  = 4
	bar.add_theme_stylebox_override("background", bg)
	return bar

func _pad(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

func _h1(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

func _spacer() -> Control:
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

func _flash_label(text: String, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text     = text
	lbl.modulate = Color(color.r, color.g, color.b, 0.0)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl
