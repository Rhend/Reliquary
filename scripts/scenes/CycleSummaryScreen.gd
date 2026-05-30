# ============================================================
# CycleSummaryScreen.gd — Écran de résumé de fin de cycle.
#
# Animation en 3 phases séquentielles :
#   Phase 1 — Fade-in staggeré (top → bottom) de tous les éléments
#   Phase 2 — Compteurs stat (0 → N, accélération EASE_IN, un par un)
#   Phase 3 — Remplissage barres XP (0 → N, EASE_OUT, une par une)
# ============================================================
extends Control

var _fade_nodes: Array = []   # Controls à révéler en phase 1
var _stat_anims: Array = []   # {label, target, prefix, suffix}
var _xp_anims:   Array = []   # {bar, xp_label, target, max_val}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	_run_animation_sequence()

# ═══════════════════════════════════════════════════════════
#  Construction UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var data := CycleData.last_cycle_summary
	if data.is_empty():
		_go_to_village()
		return

	var cid    := GameData.player.get("active_creature_id", "") as String
	var hero   := GameData.get_entity(cid)
	var tier   := hero.get("current_tier", 0) as int
	var tcolor := UIColors.tier_color(tier)

	var biome      := GameData.get_entity(data.get("biome_id", "") as String)
	var biome_name := biome.get("nom_affichage_fr", "Biome Inconnu") as String

	# ── Fond BG_DARK ────────────────────────────────────────
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	# ── Marges extérieures ──────────────────────────────────
	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer_margin.add_theme_constant_override(side, 16)
	add_child(outer_margin)

	# ── Panel principal ─────────────────────────────────────
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.04, 0.05, 0.09, 0.97)
	ps.border_color = Color(tcolor.r, tcolor.g, tcolor.b, 0.80)
	ps.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", ps)
	outer_margin.add_child(panel)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# ── Barre titre ─────────────────────────────────────────
	var tb_color := tcolor.darkened(0.55)
	tb_color.a   = 0.85
	var title_bar := PanelContainer.new()
	title_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = tb_color
	tb_style.set_border_width_all(0)
	title_bar.add_theme_stylebox_override("panel", tb_style)
	col.add_child(title_bar)
	_fade_register(title_bar)

	var title_m := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		title_m.add_theme_constant_override(side, 14)
	for side in ["margin_top", "margin_bottom"]:
		title_m.add_theme_constant_override(side, 8)
	title_bar.add_child(title_m)

	var title_hb := HBoxContainer.new()
	title_m.add_child(title_hb)

	var title_lbl := Label.new()
	title_lbl.text                  = "CYCLE TERMINÉ  —  %s" % biome_name.to_upper()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_hb.add_child(title_lbl)


	# ── Séparateur ──────────────────────────────────────────
	var sep_color := tcolor; sep_color.a = 0.55
	var sep_line  := ColorRect.new()
	sep_line.color                 = sep_color
	sep_line.custom_minimum_size   = Vector2(0, 1)
	sep_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sep_line)
	_fade_register(sep_line)

	# ── Zone de contenu scrollable ───────────────────────────
	var content_m := MarginContainer.new()
	content_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_m.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		content_m.add_theme_constant_override(side, 16)
	col.add_child(content_m)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_m.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	scroll.add_child(vb)

	_fill_content(vb, data, biome_name, tcolor)

	# ── Bouton retour ────────────────────────────────────────
	var btn_m := MarginContainer.new()
	btn_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m.add_theme_constant_override("margin_left",   16)
	btn_m.add_theme_constant_override("margin_right",  16)
	btn_m.add_theme_constant_override("margin_top",    8)
	btn_m.add_theme_constant_override("margin_bottom", 12)
	col.add_child(btn_m)

	var btn := Button.new()
	btn.text = "🏠  RETOUR AU VILLAGE"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", tcolor)

	var s_n := StyleBoxFlat.new()
	s_n.bg_color = Color(tcolor.r, tcolor.g, tcolor.b, 0.14)
	s_n.border_color = tcolor
	s_n.set_border_width_all(2)
	s_n.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s_n)

	var s_h := s_n.duplicate() as StyleBoxFlat
	s_h.bg_color = Color(tcolor.r, tcolor.g, tcolor.b, 0.30)
	btn.add_theme_stylebox_override("hover", s_h)

	btn.pressed.connect(_go_to_village)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(btn)
	btn_m.add_child(btn)
	_fade_register(btn_m)

# ═══════════════════════════════════════════════════════════
#  Contenu
# ═══════════════════════════════════════════════════════════

func _fill_content(vb: VBoxContainer, data: Dictionary,
		biome_name: String, tcolor: Color) -> void:

	# ── ◆ STATISTIQUES ───────────────────────────────────────
	var sh1 := UIHelpers.section_header("◆  STATISTIQUES", tcolor)
	vb.add_child(sh1)
	_fade_register(sh1)

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	_fade_register(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)

	var events_total  := data.get("events_total",    0) as int
	var combats_won   := data.get("combats_won",     0) as int
	var positive_evts := data.get("positive_events", 0) as int
	var traps         := data.get("traps_triggered", 0) as int
	var combo_max     := data.get("combo_max",       0) as int
	var loot          := data.get("loot_total",      0) as int
	var luck          := data.get("cycle_luck",       0) as int

	# Colonne gauche
	var lbl_ev  := _stat_row_into(left,  "Événements",    UIColors.TEXT_HEADER)
	var lbl_cbt := _stat_row_into(left,  "Combats gagnés",
		UIColors.LOG_VICTORY if combats_won > 0 else UIColors.TEXT_MUTED)
	var lbl_pos := _stat_row_into(left,  "Évén. positifs",
		UIColors.HEAL_COLOR  if positive_evts > 0 else UIColors.TEXT_MUTED)

	# Colonne droite
	var lbl_trap   := _stat_row_into(right, "Pièges",
		UIColors.LOG_TRAP    if traps > 0      else UIColors.TEXT_MUTED)
	var lbl_combo  := _stat_row_into(right, "Meilleur combo",
		UIColors.COMBO_COLOR if combo_max > 1  else UIColors.TEXT_MUTED)
	var lbl_loot   := _stat_row_into(right, "Objets", UIColors.LOG_LOOT)

	lbl_combo.text = "x0"

	_stat_anims.append({"label": lbl_ev,    "target": events_total,  "prefix": "",  "suffix": ""})
	_stat_anims.append({"label": lbl_cbt,   "target": combats_won,   "prefix": "",  "suffix": ""})
	_stat_anims.append({"label": lbl_pos,   "target": positive_evts, "prefix": "",  "suffix": ""})
	_stat_anims.append({"label": lbl_trap,  "target": traps,         "prefix": "",  "suffix": ""})
	_stat_anims.append({"label": lbl_combo, "target": combo_max,     "prefix": "x", "suffix": ""})
	_stat_anims.append({"label": lbl_loot,  "target": loot,          "prefix": "",  "suffix": ""})

	if luck > 0:
		var lbl_luck := _stat_row_into(right, "Luck", UIColors.FILTER_ON)
		lbl_luck.text = "+0"
		_stat_anims.append({"label": lbl_luck, "target": luck, "prefix": "+", "suffix": ""})

	# ── ◆ RÉPARTITION XP ─────────────────────────────────────
	var sh2 := UIHelpers.section_header("◆  RÉPARTITION XP", tcolor)
	vb.add_child(sh2)
	_fade_register(sh2)

	var xp_hero  := data.get("xp_hero",  0.0) as float
	var xp_biome := data.get("xp_biome", 0.0) as float
	var detail   := data.get("xp_passives_detail", {}) as Dictionary

	# Héro — barre vs seuil du prochain tier héro
	var cid         := data.get("creature_id", "") as String
	var hero_thresh := _next_tier_threshold(GameData.get_entity(cid))
	var hero_card   := _xp_card("⚔", "Héro", hero_thresh, UIColors.STAT_ATK, tcolor)
	vb.add_child(hero_card["container"])
	_fade_register(hero_card["container"])
	_xp_anims.append({"bar": hero_card["bar"], "xp_label": hero_card["xp_label"],
		"target": xp_hero, "max_val": hero_thresh})

	# Biome — barre vs seuil du prochain tier biome
	var biome_entity := GameData.get_entity(data.get("biome_id", "") as String)
	var biome_thresh := _next_tier_threshold(biome_entity)
	var biome_card   := _xp_card("🌿", biome_name, biome_thresh, UIColors.TYPE_BIOME, tcolor)
	vb.add_child(biome_card["container"])
	_fade_register(biome_card["container"])
	_xp_anims.append({"bar": biome_card["bar"], "xp_label": biome_card["xp_label"],
		"target": xp_biome, "max_val": biome_thresh})

	# Passifs — une carte par passif vs son propre seuil de tier-up
	for passive_id: String in detail:
		var p_entity := GameData.get_entity(passive_id)
		var p_name   := p_entity.get("nom_affichage_fr", p_entity.get("name", passive_id)) as String
		var p_xp     := detail[passive_id] as float
		var p_thresh := _next_tier_threshold(p_entity)
		var p_card   := _xp_card("⚡", p_name, p_thresh, UIColors.COMBO_COLOR, tcolor)
		vb.add_child(p_card["container"])
		_fade_register(p_card["container"])
		_xp_anims.append({"bar": p_card["bar"], "xp_label": p_card["xp_label"],
			"target": p_xp, "max_val": p_thresh})

	# ── ◆ ÉVOLUTION DISPONIBLE ───────────────────────────────
	var ready_names: Array = []
	for eid: String in GameData.entities:
		var e: Dictionary = GameData.entities[eid]
		if e.get("entity_type", "") not in ["hero", "biome"]:
			continue
		var e_tier := e.get("current_tier", 0) as int
		if e_tier >= GameData.MAX_TIER:
			continue
		if e.get("current_xp", 0.0) >= float(GameData.xp_thresholds[e_tier + 1]):
			ready_names.append(e.get("nom_affichage_fr", e.get("name", eid)))

	if not ready_names.is_empty():
		var sh3 := UIHelpers.section_header("◆  ÉVOLUTION DISPONIBLE", UIColors.FILTER_ON)
		vb.add_child(sh3)
		_fade_register(sh3)

		var evo_lbl := Label.new()
		evo_lbl.text = "▲  " + ", ".join(PackedStringArray(ready_names))
		evo_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		evo_lbl.add_theme_font_size_override("font_size", 13)
		evo_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(evo_lbl)
		_fade_register(evo_lbl)

# ═══════════════════════════════════════════════════════════
#  Animations
# ═══════════════════════════════════════════════════════════

# Enregistre un nœud pour la phase 1 (invisible dès maintenant).
func _fade_register(node: Control) -> void:
	node.modulate.a = 0.0
	_fade_nodes.append(node)

func _run_animation_sequence() -> void:
	await get_tree().create_timer(0.25).timeout

	# ── Phase 1 : fade-in staggeré ───────────────────────────
	var tw1 := create_tween().set_parallel(true)
	var d   := 0.0
	for node: Control in _fade_nodes:
		tw1.tween_property(node, "modulate:a", 1.0, 0.20) \
			.set_delay(d).set_ease(Tween.EASE_OUT)
		d += 0.05
	await tw1.finished

	# ── Phase 2 : compteurs stats (séquentiels) ──────────────
	for stat: Dictionary in _stat_anims:
		await _count_stat(stat)

	# ── Phase 3 : remplissage barres XP (séquentiels) ────────
	for xp: Dictionary in _xp_anims:
		await _fill_xp_bar(xp)

# Compte un label de 0 → target avec accélération (EASE_IN QUAD).
func _count_stat(stat: Dictionary) -> void:
	var label : Label  = stat["label"]
	var target: int    = stat["target"]
	var prefix: String = stat["prefix"]
	var suffix: String = stat["suffix"]

	if target <= 0:
		label.text = prefix + "0" + suffix
		return

	# Durée proportionnelle à la valeur, bornée entre 0.3 s et 0.9 s.
	var duration := clampf(0.3 + float(target) * 0.008, 0.3, 0.9)

	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		label.text = prefix + str(int(v)) + suffix
	, 0.0, float(target), duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw.finished

# Remplit une barre XP et son label de 0 → target (EASE_OUT CUBIC).
func _fill_xp_bar(xp: Dictionary) -> void:
	var bar     : XPCard = xp["bar"]
	var xp_lbl  : Label  = xp["xp_label"]
	var target  : float  = xp["target"]
	var max_val : float  = xp["max_val"]

	bar.xp_fill = 0.0
	xp_lbl.text = "+0 XP"

	if target <= 0.0:
		return

	var frac_target := clampf(target / max_val, 0.0, 1.0) if max_val > 0.0 else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(bar, "xp_fill", frac_target, 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void:
		xp_lbl.text = "+%.0f XP" % v
	, 0.0, target, 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

func _go_to_village() -> void:
	get_tree().change_scene_to_file("res://scenes/village/village.tscn")

# ═══════════════════════════════════════════════════════════
#  Helpers UI
# ═══════════════════════════════════════════════════════════

# Retourne le seuil XP du prochain tier de l'entité.
# Si l'entité est au tier max, retourne le dernier seuil (barre pleine = déjà max).
func _next_tier_threshold(entity: Dictionary) -> float:
	var entity_tier := entity.get("current_tier", 0) as int
	var next_idx    := entity_tier + 1
	if entity_tier >= GameData.MAX_TIER or next_idx >= GameData.xp_thresholds.size():
		return float(GameData.xp_thresholds.back())
	return float(GameData.xp_thresholds[next_idx])

# Crée une ligne clé:valeur dans un VBoxContainer. Retourne le Label valeur.
# La valeur s'affiche "0" au départ ; le compteur l'animera ensuite.
func _stat_row_into(parent: VBoxContainer, key: String, val_color: Color) -> Label:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)

	var kl := Label.new()
	kl.text                  = key + " :"
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hb.add_child(kl)

	var vl := Label.new()
	vl.text = "0"
	vl.add_theme_font_size_override("font_size", 14)
	vl.add_theme_color_override("font_color", val_color)
	hb.add_child(vl)

	return vl

# Card XP — barre vide + "+0 XP" au départ. Retourne container/bar/xp_label.
func _xp_card(icon: String, label: String, xp_max: float,
		icon_color: Color, card_color: Color) -> Dictionary:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(card_color.r, card_color.g, card_color.b, 0.07)
	style.border_color = Color(card_color.r, card_color.g, card_color.b, 0.60)
	style.set_border_width_all(1)
	for prop: String in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 4)
	panel.add_theme_stylebox_override("panel", style)
	wrapper.add_child(panel)

	var m := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(s, 6)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", icon_color)
	hb.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text                  = label
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(name_lbl)

	var xp_lbl := Label.new()
	xp_lbl.text = "+0 XP"
	xp_lbl.add_theme_font_size_override("font_size", 12)
	xp_lbl.add_theme_color_override("font_color", icon_color)
	hb.add_child(xp_lbl)

	# Barre XP universelle (XPCard + bulles). Animée via xp_fill dans _fill_xp_bar.
	var bar := UIHelpers.xp_bar(0.0, xp_max, icon_color, 12, false)
	vb.add_child(bar)

	return {"container": wrapper, "bar": bar, "xp_label": xp_lbl}

