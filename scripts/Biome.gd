# ============================================================
# Biome.gd — Scène de cycle d'aventure.
#
# Mise en page :
#   [Header : nom du biome + XP biome]
#   [Modificateur de cycle + Luck]
#   [EncounterPanel : combat | piège | événement]
#   [Contrôle de vitesse x1/x2/x4]
#   [Journal (8 dernières lignes)]
#   [Bouton Quitter]
# ============================================================
extends Control

# ─── Références UI ──────────────────────────────────────────

var _encounter_panel: Control         # instance d'EncounterPanel
var _modifier_label:  Label
var _luck_label:      Label
var _biome_xp_label:  Label
var _log_vbox:        VBoxContainer
var _scroll_log:      ScrollContainer
var _speed_buttons:   Dictionary = {} # speed_value → Button
var _fade_rect:       ColorRect

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_build_ui()

	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.modifier_activated.connect(_on_modifier_activated)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.luck_boosted.connect(_on_luck_boosted)
	EventBus.xp_gained.connect(_on_xp_gained)
	CombatPlayer.combat_finished.connect(_on_combat_finished_visual)

	if not AdventureSystem.current_modifier.is_empty():
		_on_modifier_activated(AdventureSystem.current_modifier)

# ═══════════════════════════════════════════════════════════
#  Construction de l'interface
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.10, 0.08)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_header(root)
	_build_modifier_row(root)
	_build_encounter_panel(root)
	_build_speed_control(root)
	_build_event_log(root)

	var exit_btn = Button.new()
	exit_btn.text = "Quitter le cycle"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	root.add_child(exit_btn)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.40)

# ─── Header ─────────────────────────────────────────────────

func _build_header(parent: Node) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	var biome = GameData.get_entity(GameData.player.get("active_biome_id", ""))
	var title = Label.new()
	title.text = biome.get("name", "Biome").to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	var xp_panel = PanelContainer.new()
	xp_panel.custom_minimum_size = Vector2(190, 0)
	hbox.add_child(xp_panel)
	var xp_m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		xp_m.add_theme_constant_override(side, 6)
	xp_panel.add_child(xp_m)
	_biome_xp_label = Label.new()
	_biome_xp_label.add_theme_font_size_override("font_size", 11)
	_biome_xp_label.add_theme_color_override("font_color", UIColors.TYPE_BIOME)
	xp_m.add_child(_biome_xp_label)
	_update_biome_xp_label()

# ─── Modificateur + Luck ────────────────────────────────────

func _build_modifier_row(parent: Node) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	_modifier_label = Label.new()
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.add_theme_font_size_override("font_size", 13)
	_modifier_label.add_theme_color_override("font_color", UIColors.MODIFIER_ACTIVE)
	_modifier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modifier_label.visible = false
	row.add_child(_modifier_label)

	_luck_label = Label.new()
	_luck_label.visible = false
	_luck_label.add_theme_font_size_override("font_size", 12)
	_luck_label.add_theme_color_override("font_color", UIColors.LOG_LOOT)
	row.add_child(_luck_label)

# ─── EncounterPanel ─────────────────────────────────────────

func _build_encounter_panel(parent: Node) -> void:
	var panel_script = load("res://scenes/cycle/EncounterPanel.gd")
	_encounter_panel = Control.new()
	_encounter_panel.set_script(panel_script)
	_encounter_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_encounter_panel.custom_minimum_size = Vector2(0, 180)
	parent.add_child(_encounter_panel)

# ─── Contrôle de vitesse ────────────────────────────────────

func _build_speed_control(parent: Node) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Vitesse :"
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(lbl)

	for speed in [1.0, 0.5, 0.25]:
		var label = "x1" if speed == 1.0 else ("x2" if speed == 0.5 else "x4")
		var btn   = Button.new()
		btn.text  = label
		btn.toggle_mode   = true
		btn.button_pressed = (GameSettings.combat_speed == speed)
		btn.pressed.connect(_on_speed_pressed.bind(speed))
		hbox.add_child(btn)
		_speed_buttons[speed] = btn

# ─── Journal ─────────────────────────────────────────────────

func _build_event_log(parent: Node) -> void:
	var panel = PanelContainer.new()
	parent.add_child(panel)
	var m     = _pad(panel, 8)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	m.add_child(outer)

	var header = Label.new()
	header.text = "JOURNAL"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	outer.add_child(header)

	_scroll_log = ScrollContainer.new()
	_scroll_log.custom_minimum_size    = Vector2(0, 80)
	_scroll_log.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll_log)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_scroll_log.add_child(_log_vbox)

# ═══════════════════════════════════════════════════════════
#  Handlers de signaux
# ═══════════════════════════════════════════════════════════

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"positive":
			var effect = event_data.get("effect", {})
			_encounter_panel.display_positive(effect)
			_add_log_entry("✦ " + effect.get("name", "Événement"), UIColors.LOG_EVENT)
		"trap":
			var trap    = event_data.get("trap", {})
			var ignored = event_data.get("ignored", false)
			if ignored:
				_encounter_panel.display_trap_ignored(trap)
				_add_log_entry("◌ Piège ignoré : %s" % trap.get("name","?"), UIColors.LOG_IGNORED)
			else:
				_encounter_panel.display_trap(trap)
				_add_log_entry("▲ %s  −%.0f PV" % [trap.get("name","?"), trap.get("damage",0.0)],
					UIColors.LOG_TRAP)
		# "combat" : EncounterPanel est géré par ses propres connexions (combat_started)

func _on_cycle_ended(result: Dictionary) -> void:
	_add_log_entry(
		"— Cycle : %s" % ("Victoire !" if result.get("victory", false) else "Défaite"),
		UIColors.LOG_VICTORY if result.get("victory", false) else UIColors.LOG_DEFEAT
	)
	_show_cycle_summary(result)

func _on_loot_dropped(drops: Array, enemy_name: String) -> void:
	var parts: Array = []
	for d in drops:
		parts.append("%s ×%d" % [d.get("name", "?"), d.get("qty", 1)])
	_add_log_entry("★ [%s] %s" % [enemy_name, ", ".join(PackedStringArray(parts))],
		UIColors.LOG_LOOT)

func _on_modifier_activated(modifier: Dictionary) -> void:
	var m_name = modifier.get("name", "—")
	if m_name == "—" or m_name == "":
		_modifier_label.visible = false
		return
	_modifier_label.text    = "%s  —  %s" % [m_name, modifier.get("desc", "")]
	_modifier_label.visible = true
	_modifier_label.modulate.a = 0.0
	create_tween().set_ease(Tween.EASE_OUT) \
		.tween_property(_modifier_label, "modulate:a", 1.0, 0.50)

func _on_combo_changed(count: int) -> void:
	if count > 1:
		_add_log_entry("COMBO x%d (+%d%% ATK)" % [count, (count - 1) * 5], UIColors.COMBO_COLOR)

func _on_heal_applied(amount: float, _new_hp: float) -> void:
	_add_log_entry("+%.0f PV (soin)" % amount, UIColors.HEAL_COLOR)

func _on_luck_boosted(cycle_luck: int) -> void:
	_luck_label.text    = "✦ Luck +%d" % cycle_luck
	_luck_label.visible = true
	_luck_label.modulate = UIColors.LOG_LOOT * 1.5
	create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD) \
		.tween_property(_luck_label, "modulate", Color.WHITE, 0.6)

func _on_xp_gained(entity_id: String, _amount: float) -> void:
	if entity_id == GameData.player.get("active_biome_id", ""):
		_update_biome_xp_label()

func _on_combat_finished_visual(winner: String) -> void:
	if winner == "hero":
		_add_log_entry("✓ Victoire !", UIColors.LOG_VICTORY)
	else:
		_add_log_entry("✗ Défaite...", UIColors.LOG_DEFEAT)

func _on_speed_pressed(speed: float) -> void:
	GameSettings.set_combat_speed(speed)
	for s in _speed_buttons:
		_speed_buttons[s].button_pressed = (s == speed)

func _on_exit_pressed() -> void:
	AdventureSystem.stop_adventure()
	_fade_to("res://scenes/village/village.tscn")

# ═══════════════════════════════════════════════════════════
#  XP du biome
# ═══════════════════════════════════════════════════════════

func _update_biome_xp_label() -> void:
	if _biome_xp_label == null:
		return
	var biome_id = GameData.player.get("active_biome_id", "")
	var biome    = GameData.get_entity(biome_id)
	if biome.is_empty():
		return
	var tier      = biome.get("current_tier", 0)
	var xp        = biome.get("current_xp",   0.0)
	var next_idx  = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max    = float(GameData.xp_thresholds[next_idx])
	_biome_xp_label.text = "%s  XP %.0f/%.0f" % [GameData.get_tier_name(tier), xp, xp_max]

# ═══════════════════════════════════════════════════════════
#  Résumé de cycle
# ═══════════════════════════════════════════════════════════

func _show_cycle_summary(result: Dictionary) -> void:
	var victory     = result.get("victory", false)
	var biome       = GameData.get_entity(result.get("biome_id", ""))
	var modifier    = result.get("modifier", {})
	var xp_total    = result.get("xp_total",    0.0)
	var loot_total  = result.get("loot_total",  0)
	var combo_max   = result.get("combo_max",   0)
	var combats_won = result.get("combats_won", 0)
	var cycle_luck  = result.get("cycle_luck",  0)

	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var bg_rect = ColorRect.new()
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_rect.color = Color(0.0, 0.0, 0.0, 0.80)
	overlay.add_child(bg_rect)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 28)
	panel.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	m.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "VICTOIRE !" if victory else "DÉFAITE..."
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color",
		UIColors.VICTORY_GLOW if victory else UIColors.LOG_DEFEAT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var ctx_lbl = Label.new()
	ctx_lbl.text = "%s  •  %s" % [biome.get("name", "?"), modifier.get("name", "—")]
	ctx_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctx_lbl.add_theme_font_size_override("font_size", 13)
	ctx_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(ctx_lbl)
	vbox.add_child(HSeparator.new())

	for stat in [
		["XP gagnée",       "%.0f" % xp_total,   UIColors.FILTER_ON],
		["Combats gagnés",  "%d"   % combats_won, UIColors.LOG_VICTORY],
		["Meilleur combo",  "x%d"  % combo_max,   UIColors.COMBO_COLOR],
		["Objets ramassés", "%d"   % loot_total,  UIColors.LOG_LOOT],
	]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)
		var k = Label.new()
		k.text = stat[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		k.add_theme_font_size_override("font_size", 13)
		row.add_child(k)
		var v = Label.new()
		v.text = stat[1]
		v.add_theme_color_override("font_color", stat[2])
		v.add_theme_font_size_override("font_size", 14)
		row.add_child(v)

	if cycle_luck > 0:
		var row = HBoxContainer.new()
		vbox.add_child(row)
		var k = Label.new(); k.text = "Luck accumulée"
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		k.add_theme_font_size_override("font_size", 13)
		row.add_child(k)
		var v = Label.new(); v.text = "+%d" % cycle_luck
		v.add_theme_color_override("font_color", UIColors.LOG_LOOT)
		v.add_theme_font_size_override("font_size", 14)
		row.add_child(v)

	vbox.add_child(HSeparator.new())

	var btn = Button.new()
	btn.text = "Retour au Village"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn)

	var countdown_lbl = Label.new()
	countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_lbl.add_theme_font_size_override("font_size", 11)
	countdown_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(countdown_lbl)

	overlay.modulate.a = 0.0
	create_tween().set_ease(Tween.EASE_OUT) \
		.tween_property(overlay, "modulate:a", 1.0, 0.40)

	btn.pressed.connect(func():
		if is_instance_valid(overlay): overlay.queue_free()
		_fade_to("res://scenes/village/village.tscn")
	)
	_run_summary_countdown(overlay, countdown_lbl)

func _run_summary_countdown(overlay: Control, lbl: Label) -> void:
	var secs := 6
	while secs > 0 and is_instance_valid(overlay) and is_instance_valid(lbl):
		lbl.text = "Retour automatique dans %d s..." % secs
		await get_tree().create_timer(1.0).timeout
		secs -= 1
	if is_instance_valid(overlay):
		overlay.queue_free()
		_fade_to("res://scenes/village/village.tscn")

# ═══════════════════════════════════════════════════════════
#  Journal
# ═══════════════════════════════════════════════════════════

func _add_log_entry(text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_vbox.add_child(lbl)
	while _log_vbox.get_child_count() > 8:
		var old = _log_vbox.get_child(0)
		_log_vbox.remove_child(old)
		old.queue_free()
	if _scroll_log != null:
		_scroll_log.call_deferred("set", "scroll_vertical", 999999)

# ═══════════════════════════════════════════════════════════
#  Fondu de scène
# ═══════════════════════════════════════════════════════════

func _fade_to(scene_path: String) -> void:
	_fade_rect.color.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.30)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ═══════════════════════════════════════════════════════════
#  Utilitaire
# ═══════════════════════════════════════════════════════════

func _pad(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m
