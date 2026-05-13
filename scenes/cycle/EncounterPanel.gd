# ============================================================
# EncounterPanel — Panel de rencontre unifié (SPEC 3).
#
# Affiche un seul événement à la fois selon son type :
#   • "combat"   → cartes Héro / Ennemi avec glow + halo + shake
#   • "trap"     → nom, description, indicateur visuel
#   • "positive" → nom, description, indicateur visuel
#
# FX de combat (SPEC 2) :
#   Liseret permanent violet (Héro) / rouge (Ennemi).
#   À chaque step_started :
#     - Attaquant : glow (liseret saturé + épaisseur ×2) + halo diffus
#     - Receveur  : shake (translation X) + pop de dégâts
#   Tous les tweens sont proportionnels à step_duration.
# ============================================================
extends Control

# ─── Cartes de combat ───────────────────────────────────────

var _c_card:       PanelContainer
var _e_card:       PanelContainer
var _c_border:     StyleBoxFlat
var _e_border:     StyleBoxFlat
var _c_halo:       ColorRect
var _e_halo:       ColorRect

# ─── HP ─────────────────────────────────────────────────────

var _c_hp_bar:     ProgressBar
var _c_hp_label:   Label
var _c_hp_style:   StyleBoxFlat
var _c_hp_tween:   Tween

var _e_name_label: Label
var _e_hp_bar:     ProgressBar
var _e_hp_label:   Label
var _e_hp_style:   StyleBoxFlat
var _e_hp_tween:   Tween

# ─── Overlay FX ─────────────────────────────────────────────

var _fx_overlay:   Control

# ─── Conteneurs de vue ──────────────────────────────────────

var _combat_view:  Control
var _event_view:   Control
var _event_title:  Label
var _event_body:   Label
var _event_badge:  Label

# ─── Stato ─────────────────────────────────────────────────

var _enemy_max_hp: float  = 0.0
var _hero_max_hp:  float  = 100.0

# ═══════════════════════════════════════════════════════════
#  Construction
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_build()
	CombatPlayer.step_started.connect(_on_step_started)
	CombatPlayer.combat_finished.connect(_on_combat_finished)
	EventBus.combat_started.connect(_on_combat_started)

func _build() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Vue combat (cartes H/E côte à côte)
	_combat_view = HBoxContainer.new()
	(_combat_view as HBoxContainer).add_theme_constant_override("separation", 14)
	_combat_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_combat_view)

	_build_hero_card(_combat_view)
	_build_enemy_card(_combat_view)

	# Vue événement / piège
	_event_view = PanelContainer.new()
	_event_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_event_view.visible = false
	add_child(_event_view)

	var ev_m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		ev_m.add_theme_constant_override(side, 20)
	_event_view.add_child(ev_m)

	var ev_vbox = VBoxContainer.new()
	ev_vbox.add_theme_constant_override("separation", 10)
	ev_m.add_child(ev_vbox)

	_event_badge = Label.new()
	_event_badge.add_theme_font_size_override("font_size", 11)
	ev_vbox.add_child(_event_badge)

	_event_title = Label.new()
	_event_title.add_theme_font_size_override("font_size", 20)
	ev_vbox.add_child(_event_title)

	_event_body = Label.new()
	_event_body.add_theme_font_size_override("font_size", 13)
	_event_body.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_event_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev_vbox.add_child(_event_body)

	# Overlay FX (par-dessus tout)
	_fx_overlay = Control.new()
	_fx_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_overlay)

# ── Carte Héro ──────────────────────────────────────────────

func _build_hero_card(parent: Node) -> void:
	_c_card = PanelContainer.new()
	_c_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_c_card.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_c_border = _bordered_style(CombatColors.HERO_BORDER_COLOR, CombatColors.BORDER_IDLE)
	_c_card.add_theme_stylebox_override("panel", _c_border)
	parent.add_child(_c_card)

	_c_halo = _halo_rect(CombatColors.HERO_HALO_COLOR)
	_c_card.add_child(_c_halo)

	var m    = _pad(_c_card, 14)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var passives = PassiveSystem.get_combat_bonuses()
	var equip    = GameData.get_equipment_bonuses()
	var cid      = GameData.player.get("active_creature_id", "") as String
	var stats    = GameData.get_effective_stats(cid)
	_hero_max_hp = float(stats.get("hp", 0)) + passives.get("hp_bonus", 0.0) + equip.get("hp", 0.0)
	var cur_hp   = AdventureSystem.current_hp if AdventureSystem.is_running else _hero_max_hp

	var name_lbl = Label.new()
	name_lbl.text = "HÉRO"
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	vbox.add_child(HSeparator.new())

	_c_hp_label = Label.new()
	_c_hp_label.text = "PV %.0f / %.0f" % [cur_hp, _hero_max_hp]
	vbox.add_child(_c_hp_label)

	_c_hp_style = _fill_style(UIColors.hero_hp(cur_hp / _hero_max_hp if _hero_max_hp > 0 else 1.0))
	_c_hp_bar   = _make_bar(_c_hp_style, _hero_max_hp, cur_hp)
	vbox.add_child(_c_hp_bar)

	var stats_lbl = Label.new()
	var h_atk = int(float(stats.get("atk", 0)) + passives.get("atk_bonus", 0.0) + equip.get("atk", 0.0))
	var h_def = int(float(stats.get("def", 0)) + passives.get("def_bonus", 0.0) + equip.get("def", 0.0))
	stats_lbl.text = "ATK %d   DEF %d" % [h_atk, h_def]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(stats_lbl)

# ── Carte Ennemi ────────────────────────────────────────────

func _build_enemy_card(parent: Node) -> void:
	_e_card = PanelContainer.new()
	_e_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_e_card.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_e_border = _bordered_style(CombatColors.ENEMY_BORDER_COLOR, CombatColors.BORDER_IDLE)
	_e_card.add_theme_stylebox_override("panel", _e_border)
	parent.add_child(_e_card)

	_e_halo = _halo_rect(CombatColors.ENEMY_HALO_COLOR)
	_e_card.add_child(_e_halo)

	var m    = _pad(_e_card, 14)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	_e_name_label = Label.new()
	_e_name_label.text = "EN ATTENTE..."
	_e_name_label.add_theme_font_size_override("font_size", 14)
	_e_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_name_label)
	vbox.add_child(HSeparator.new())

	_e_hp_label = Label.new()
	_e_hp_label.text = "PV — / —"
	vbox.add_child(_e_hp_label)

	_e_hp_style = _fill_style(UIColors.ENEMY_HIGH)
	_e_hp_bar   = _make_bar(_e_hp_style, 100.0, 0.0)
	vbox.add_child(_e_hp_bar)

# ═══════════════════════════════════════════════════════════
#  Interface publique — appelée par Biome.gd
# ═══════════════════════════════════════════════════════════

func display_combat() -> void:
	_combat_view.visible = true
	_event_view.visible  = false

func display_trap(trap: Dictionary) -> void:
	_combat_view.visible = false
	_event_view.visible  = true
	_event_badge.text = "▲ PIÈGE"
	_event_badge.add_theme_color_override("font_color", UIColors.LOG_TRAP)
	_event_title.text = trap.get("name", "Piège")
	_event_title.add_theme_color_override("font_color", UIColors.LOG_TRAP)
	var dmg = int(trap.get("damage", 0))
	_event_body.text = "Vous perdez %d PV." % dmg

func display_trap_ignored(trap: Dictionary) -> void:
	_combat_view.visible = false
	_event_view.visible  = true
	_event_badge.text = "◌ PIÈGE IGNORÉ (Fantôme)"
	_event_badge.add_theme_color_override("font_color", UIColors.LOG_IGNORED)
	_event_title.text = trap.get("name", "Piège")
	_event_title.add_theme_color_override("font_color", UIColors.LOG_IGNORED)
	_event_body.text = "Le piège n'a aucun effet."

func display_positive(evt: Dictionary) -> void:
	_combat_view.visible = false
	_event_view.visible  = true
	_event_badge.text = "✦ BONUS"
	_event_badge.add_theme_color_override("font_color", UIColors.LOG_EVENT)
	_event_title.text = evt.get("name", "Événement")
	_event_title.add_theme_color_override("font_color", UIColors.LOG_EVENT)
	_event_body.text = _describe_effect(evt)

# ═══════════════════════════════════════════════════════════
#  Handlers de signaux
# ═══════════════════════════════════════════════════════════

func _on_combat_started(_creature_id: String, enemy: Dictionary,
		creature_hp: float, enemy_hp: float) -> void:
	display_combat()
	_enemy_max_hp        = enemy_hp
	_e_name_label.text   = enemy.get("name", "Ennemi").to_upper()
	_e_hp_bar.max_value  = enemy_hp
	_e_hp_bar.value      = enemy_hp
	_e_hp_label.text     = "PV %.0f / %.0f" % [enemy_hp, enemy_hp]
	_e_hp_style.bg_color = UIColors.enemy_hp(1.0)
	_set_hero_hp(creature_hp)

func _on_step_started(step: CombatStep) -> void:
	var step_dur := CombatPlayer.BASE_STEP_DURATION * GameSettings.combat_speed

	if step.attacker == "hero":
		# Éteint le glow ennemi du step précédent avant d'allumer le héro
		_reset_card_fx(_e_card, _e_border, _e_halo, CombatColors.ENEMY_BORDER_COLOR)
		_glow_card(_c_card, _c_border, _c_halo,
			CombatColors.HERO_GLOW_COLOR, CombatColors.HERO_HALO_COLOR, step_dur)
		_shake_card(_e_card, step_dur)
		_spawn_damage_pop(_e_hp_bar, "-%d" % step.damage, step.is_killing_blow, step_dur)
		_set_enemy_hp(float(step.target_hp_after))
	else:
		# Éteint le glow héro du step précédent avant d'allumer l'ennemi
		_reset_card_fx(_c_card, _c_border, _c_halo, CombatColors.HERO_BORDER_COLOR)
		_glow_card(_e_card, _e_border, _e_halo,
			CombatColors.ENEMY_GLOW_COLOR, CombatColors.ENEMY_HALO_COLOR, step_dur)
		_shake_card(_c_card, step_dur)
		_spawn_damage_pop(_c_hp_bar, "-%d" % step.damage, step.is_killing_blow, step_dur)
		_set_hero_hp(float(step.target_hp_after))

func _on_combat_finished(_winner: String) -> void:
	_reset_card_fx(_c_card, _c_border, _c_halo, CombatColors.HERO_BORDER_COLOR)
	_reset_card_fx(_e_card, _e_border, _e_halo, CombatColors.ENEMY_BORDER_COLOR)

# ═══════════════════════════════════════════════════════════
#  FX — Glow + Halo
# ═══════════════════════════════════════════════════════════

func _glow_card(card: Control, border: StyleBoxFlat, halo: ColorRect,
		glow_color: Color, halo_color: Color, step_dur: float) -> void:
	var t := 0.1  # apparition rapide

	# Liseret glow
	var tw_b = create_tween()
	tw_b.tween_property(border, "border_color", glow_color, t)
	tw_b.tween_property(border, "border_width_left",   CombatColors.BORDER_GLOW, t)
	tw_b.tween_property(border, "border_width_right",  CombatColors.BORDER_GLOW, t)
	tw_b.tween_property(border, "border_width_top",    CombatColors.BORDER_GLOW, t)
	tw_b.tween_property(border, "border_width_bottom", CombatColors.BORDER_GLOW, t)

	# Halo
	halo.color   = Color(halo_color.r, halo_color.g, halo_color.b, 0.0)
	halo.visible = true
	var tw_h = create_tween()
	tw_h.tween_property(halo, "color:a", halo_color.a, t)

func _reset_card_fx(card: Control, border: StyleBoxFlat, halo: ColorRect,
		idle_color: Color) -> void:
	var t := 0.1
	var tw_b = create_tween()
	tw_b.tween_property(border, "border_color", idle_color, t)
	tw_b.tween_property(border, "border_width_left",   CombatColors.BORDER_IDLE, t)
	tw_b.tween_property(border, "border_width_right",  CombatColors.BORDER_IDLE, t)
	tw_b.tween_property(border, "border_width_top",    CombatColors.BORDER_IDLE, t)
	tw_b.tween_property(border, "border_width_bottom", CombatColors.BORDER_IDLE, t)
	var tw_h = create_tween()
	tw_h.tween_property(halo, "color:a", 0.0, t)
	tw_h.tween_callback(func(): halo.visible = false)

# ═══════════════════════════════════════════════════════════
#  FX — Shake receveur
# ═══════════════════════════════════════════════════════════

func _shake_card(card: Control, step_dur: float) -> void:
	var amp     := 7.0
	var dur     := minf(0.15, step_dur * 0.4)
	var origin  := card.position
	var tw = create_tween()
	tw.tween_property(card, "position", origin + Vector2(amp, 2.0), dur * 0.15)
	tw.tween_property(card, "position", origin + Vector2(-amp, -1.0), dur * 0.20)
	tw.tween_property(card, "position", origin + Vector2(amp * 0.5, 1.0), dur * 0.20)
	tw.tween_property(card, "position", origin + Vector2(-amp * 0.3, 0.0), dur * 0.20)
	tw.tween_property(card, "position", origin, dur * 0.25).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════════════════════
#  FX — Pop de dégâts
# ═══════════════════════════════════════════════════════════

func _spawn_damage_pop(anchor: ProgressBar, text: String,
		killing_blow: bool, step_dur: float) -> void:
	var rect  = anchor.get_global_rect()
	var start = Vector2(rect.get_center().x - 20.0, rect.position.y - 10.0)

	var lbl = Label.new()
	lbl.text          = text
	lbl.position      = start
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 24 if killing_blow else 20)
	lbl.add_theme_color_override("font_color",
		Color("#FF1010") if killing_blow else Color("#FF3B3B"))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fx_overlay.add_child(lbl)

	var rise  := minf(0.6, step_dur * 0.75)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", start.y - 30.0, rise) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate:a", 0.0, rise) \
		.set_ease(Tween.EASE_IN).set_delay(rise * 0.3)
	tw.chain().tween_callback(lbl.queue_free)

# ═══════════════════════════════════════════════════════════
#  HP bars
# ═══════════════════════════════════════════════════════════

func _set_hero_hp(hp: float) -> void:
	var val  := maxf(hp, 0.0)
	var down := val < _c_hp_bar.value
	_c_hp_label.text = "PV %.0f / %.0f" % [val, _c_hp_bar.max_value]
	if _c_hp_tween: _c_hp_tween.kill()
	_c_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_c_hp_tween.tween_property(_c_hp_bar, "value", val, 0.22)
	var pct := val / _c_hp_bar.max_value if _c_hp_bar.max_value > 0.0 else 1.0
	if down:
		_c_hp_style.bg_color = Color.WHITE
		create_tween().tween_property(_c_hp_style, "bg_color", UIColors.hero_hp(pct), 0.18)
	else:
		_c_hp_style.bg_color = UIColors.hero_hp(pct)

func _set_enemy_hp(hp: float) -> void:
	var val  := maxf(hp, 0.0)
	var down := val < _e_hp_bar.value
	_e_hp_label.text = "PV %.0f / %.0f" % [val, _enemy_max_hp]
	if _e_hp_tween: _e_hp_tween.kill()
	_e_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_e_hp_tween.tween_property(_e_hp_bar, "value", val, 0.22)
	var pct := val / _enemy_max_hp if _enemy_max_hp > 0.0 else 1.0
	if down:
		_e_hp_style.bg_color = Color.WHITE
		create_tween().tween_property(_e_hp_style, "bg_color", UIColors.enemy_hp(pct), 0.18)
	else:
		_e_hp_style.bg_color = UIColors.enemy_hp(pct)

# ═══════════════════════════════════════════════════════════
#  Utilitaires constructeurs
# ═══════════════════════════════════════════════════════════

func _bordered_style(border_color: Color, width: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color           = UIColors.BG_CARD
	s.border_color       = border_color
	s.border_width_left  = width
	s.border_width_right = width
	s.border_width_top   = width
	s.border_width_bottom = width
	s.set_corner_radius_all(6)
	return s

func _halo_rect(halo_color: Color) -> ColorRect:
	var r = ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.color   = Color(halo_color.r, halo_color.g, halo_color.b, 0.0)
	r.visible = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rendu additif pour l'effet de lueur diffuse
	r.material = CanvasItemMaterial.new()
	(r.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return r

func _fill_style(color: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	return s

func _make_bar(fill: StyleBoxFlat, max_val: float, val: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max_val
	bar.value     = val
	bar.show_percentage     = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.add_theme_stylebox_override("fill", fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = UIColors.BG_BAR
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	return bar

func _pad(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

func _describe_effect(evt: Dictionary) -> String:
	var effect = evt.get("effect", "")
	var value  = evt.get("value",  0)
	match effect:
		"heal": return "+%d PV restaurés." % int(value)
		"luck": return "+%d Luck pour ce cycle." % int(value)
		_:      return evt.get("description", "Effet inconnu.")
