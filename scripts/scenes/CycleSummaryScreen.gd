# ============================================================
# CycleSummaryScreen.gd — Écran de résultat d'expédition.
#
# Affiché après victoire, défaite ou interruption volontaire.
# Trois sections :
#   1. Découvertes — état de complétion du biome (zones débloquées)
#   2. Répartition XP — total + une barre universelle par entité
#   3. Évolutions disponibles — cartes avec bouton (déclenchement manuel)
#
# Traitement visuel uniforme quel que soit le résultat ; seul le tag change.
# La logique XP / évolution n'est pas modifiée ici.
# ============================================================
extends Control

var _fade_nodes: Array = []   # Controls révélés en phase 1
var _xp_anims:   Array = []   # {card, xp_label, gained, before_frac, after_frac}

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

	var hero   := GameData.get_entity("hero")
	var tcolor := UIColors.tier_color(hero.get("maitrise_actuelle", 0) as int)

	var biome      := GameData.get_entity(data.get("biome_id", "") as String)
	var biome_name := biome.get("nom_affichage_fr", "Biome Inconnu") as String

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer_margin.add_theme_constant_override(side, 16)
	add_child(outer_margin)

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

	# ── Barre titre + tag de résultat ───────────────────────
	var tb_color := tcolor.darkened(0.55); tb_color.a = 0.85
	var title_bar := PanelContainer.new()
	title_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = tb_color
	title_bar.add_theme_stylebox_override("panel", tb_style)
	col.add_child(title_bar)
	_fade_register(title_bar)

	var title_m := MarginContainer.new()
	title_m.add_theme_constant_override("margin_left", 14)
	title_m.add_theme_constant_override("margin_right", 14)
	title_m.add_theme_constant_override("margin_top", 8)
	title_m.add_theme_constant_override("margin_bottom", 8)
	title_bar.add_child(title_m)

	var title_hb := HBoxContainer.new()
	title_hb.add_theme_constant_override("separation", 10)
	title_m.add_child(title_hb)

	var title_lbl := Label.new()
	title_lbl.text                  = Translations.T("cycle.title") % biome_name.to_upper()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_hb.add_child(title_lbl)

	# Tag de fin de cycle — style uniforme, seul le texte change.
	var tag_text := Translations.T("cycle.defeat")
	if data.get("interrupted", false):
		tag_text = Translations.T("cycle.interrupted")
	elif data.get("victory", false):
		tag_text = Translations.T("cycle.victory")
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UIHelpers.card_style(tcolor, 0.22, 0.80, 1, 10))
	var tag_lbl := Label.new()
	tag_lbl.text = tag_text
	tag_lbl.add_theme_font_size_override("font_size", 13)
	tag_lbl.add_theme_color_override("font_color", Color.WHITE)
	tag.add_child(tag_lbl)
	title_hb.add_child(tag)

	# ── Séparateur ──────────────────────────────────────────
	var sep_color := tcolor; sep_color.a = 0.55
	var sep_line := ColorRect.new()
	sep_line.color                 = sep_color
	sep_line.custom_minimum_size   = Vector2(0, 1)
	sep_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sep_line)
	_fade_register(sep_line)

	# ── Contenu scrollable ──────────────────────────────────
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

	_fill_content(vb, data, biome, biome_name, tcolor)

	# ── Footer : Retour au village uniquement ────────────────
	var btn_m := MarginContainer.new()
	btn_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m.add_theme_constant_override("margin_left", 16)
	btn_m.add_theme_constant_override("margin_right", 16)
	btn_m.add_theme_constant_override("margin_top", 8)
	btn_m.add_theme_constant_override("margin_bottom", 12)
	col.add_child(btn_m)

	var btn := Button.new()
	btn.text = Translations.T("cycle.back_village")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", tcolor)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	btn.pressed.connect(_go_to_village)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(btn)
	btn_m.add_child(btn)
	_fade_register(btn_m)

# ═══════════════════════════════════════════════════════════
#  Contenu
# ═══════════════════════════════════════════════════════════

func _fill_content(vb: VBoxContainer, data: Dictionary,
		biome: Dictionary, biome_name: String, tcolor: Color) -> void:
	_section_discoveries(vb, data, biome, tcolor)
	_section_loot(vb, data, tcolor)
	_section_xp(vb, data, biome_name, tcolor)
	_section_evolutions(vb)

# ── Section 1 : Découvertes (état du biome) ────────────────
func _section_discoveries(vb: VBoxContainer, data: Dictionary,
		biome: Dictionary, tcolor: Color) -> void:
	var biome_id := data.get("biome_id", "") as String
	var btier    := biome.get("maitrise_actuelle", 0) as int
	var pools    := MasteryRegistry.get_biome_entity_pools(biome_id)

	var creatures := _filter_zone(pools["creatures"],    btier)
	var traps     := _filter_zone(pools["traps"],        btier)
	var benes     := _filter_zone(pools["benedictions"], btier)

	var sec := UIHelpers.collapsible_section(Translations.T("cycle.section.discoveries"), tcolor)
	vb.add_child(sec["wrapper"])
	_fade_register(sec["wrapper"])
	var body_dec := sec["body"] as VBoxContainer

	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 24)
	rows.add_theme_constant_override("v_separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_dec.add_child(rows)

	_discovery_row(rows, Translations.T("cycle.encounters"), MasteryRegistry.count_discovered(creatures), creatures.size())
	_discovery_row(rows, Translations.T("cycle.traps"),     MasteryRegistry.count_discovered(traps),     traps.size())
	_discovery_row(rows, Translations.T("cycle.blessings"), MasteryRegistry.count_discovered(benes),     benes.size())

	# Fragment de Mémoire du biome
	var frag_done := false
	for fid in GameData.entities:
		var f := GameData.entities[fid] as Dictionary
		if f.get("entity_type", "") == "fragment" and f.get("biome_source_id", "") == biome_id:
			frag_done = f.get("est_collecte", false)
			break
	_discovery_check(rows, Translations.T("cycle.discovery.fragment"), frag_done)
	_discovery_check(rows, Translations.T("cycle.discovery.unique"), biome.get("creature_unique_vaincue", false) as bool)

# ── Section 2 : Ressources collectées ──────────────────────────
func _section_loot(vb: VBoxContainer, data: Dictionary, tcolor: Color) -> void:
	var loot_detail := data.get("loot_detail", {}) as Dictionary
	if loot_detail.is_empty():
		return
	var sec := UIHelpers.collapsible_section(Translations.T("cycle.section.resources"), tcolor)
	vb.add_child(sec["wrapper"])
	_fade_register(sec["wrapper"])
	var body_loot := sec["body"] as VBoxContainer

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_loot.add_child(grid)

	for item_id: String in loot_detail:
		var qty      := int(loot_detail[item_id])
		var item     := GameData.get_entity(item_id)
		var nom      := (item.get("nom_affichage_fr", item.get("name", item_id))) as String
		var is_unique := item.get("est_unique", false) as bool
		var ic       := UIColors.TIER_LEGENDAIRE if is_unique else UIColors.FILTER_ON
		var row      := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		grid.add_child(row)
		var nl := Label.new()
		nl.text = ("✦ %s" % nom) if is_unique else nom
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", ic)
		row.add_child(nl)
		var ql := Label.new()
		ql.text = "+%d" % qty
		ql.add_theme_font_size_override("font_size", 12)
		ql.add_theme_color_override("font_color", ic)
		row.add_child(ql)

# ── Section 3 : Répartition XP ─────────────────────────────
func _section_xp(vb: VBoxContainer, data: Dictionary,
		biome_name: String, tcolor: Color) -> void:
	var sec_xp := UIHelpers.collapsible_section(Translations.T("cycle.section.xp"), tcolor)
	vb.add_child(sec_xp["wrapper"])
	_fade_register(sec_xp["wrapper"])
	var body_xp := sec_xp["body"] as VBoxContainer

	var total_lbl := Label.new()
	total_lbl.text = Translations.T("cycle.xp_total") % int(data.get("xp_total", 0.0))
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
	body_xp.add_child(total_lbl)
	_fade_register(total_lbl)

	var cid := data.get("creature_id", "") as String
	_xp_entity(body_xp, "⚔", Translations.T("cycle.hero_label"), GameData.get_entity(cid), data.get("xp_hero", 0.0) as float)
	_xp_entity(body_xp, "🌿", biome_name, GameData.get_entity(data.get("biome_id", "") as String),
			data.get("xp_biome", 0.0) as float)

	var entities_xp := data.get("xp_entities_detail", {}) as Dictionary
	for ent_id: String in entities_xp:
		var e := GameData.get_entity(ent_id)
		var e_name := e.get("nom_affichage_fr", e.get("name", ent_id)) as String
		var icon := "🐾"
		match e.get("entity_type", ""):
			"trap":        icon = "▲"
			"benediction": icon = "✦"
		_xp_entity(body_xp, icon, e_name, e, entities_xp[ent_id] as float)

	var detail := data.get("xp_passives_detail", {}) as Dictionary
	for passive_id: String in detail:
		var p := GameData.get_entity(passive_id)
		var p_name := p.get("nom_affichage_fr", p.get("name", passive_id)) as String
		_xp_entity(body_xp, "⚡", p_name, p, detail[passive_id] as float)

	var equip_detail := data.get("xp_equip_detail", {}) as Dictionary
	for equip_id: String in equip_detail:
		var eq := GameData.get_entity(equip_id)
		var eq_name := eq.get("nom_affichage_fr", equip_id) as String
		_xp_entity(body_xp, "🔨", eq_name, eq, equip_detail[equip_id] as float)

# Ajoute une ligne XP pour une entité ayant reçu de l'XP ce cycle (sinon ignorée).
# La couleur de la carte = couleur du palier (tier) courant de l'entité.
# xp_avant = XP au début du cycle, xp_apres = XP à la fin, xp_max = seuil du palier courant.
func _xp_entity(vb: VBoxContainer, icon: String, label: String, entity: Dictionary,
		gained: float) -> void:
	if gained <= 0.0 or entity.is_empty():
		return
	var tier      := entity.get("maitrise_actuelle", 0) as int
	var xp_max    := _next_tier_threshold(entity)
	var xp_apres  := entity.get("xp_maitrise_actuelle", 0.0) as float
	var xp_avant  := maxf(xp_apres - gained, 0.0)
	var avant_frac := clampf(xp_avant / xp_max, 0.0, 1.0) if xp_max > 0.0 else 0.0
	var apres_frac := clampf(xp_apres / xp_max, 0.0, 1.0) if xp_max > 0.0 else 1.0

	var card := _xp_card(icon, label, tier, xp_apres, xp_max, entity.get("entity_type", "") as String)
	vb.add_child(card["container"])
	_fade_register(card["container"])
	_xp_anims.append({
		"card":        card["card"],
		"xp_label":    card["xp_label"],
		"gained":      gained,
		"before_frac": avant_frac,
		"after_frac":  apres_frac,
	})

# ── Section 3 : Évolutions disponibles ─────────────────────
func _section_evolutions(vb: VBoxContainer) -> void:
	var sec_ev := UIHelpers.collapsible_section(Translations.T("cycle.section.evolutions"), UIColors.FILTER_ON)
	vb.add_child(sec_ev["wrapper"])
	_fade_register(sec_ev["wrapper"])
	var body_ev := sec_ev["body"] as VBoxContainer

	var found := false
	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") == "equipment":
			continue
		if MasterySystem.can_evolve(eid):
			found = true
			_evolution_card(body_ev, eid, e)

	if not found:
		var lbl := Label.new()
		lbl.text = Translations.T("cycle.no_evolution")
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		body_ev.add_child(lbl)
		_fade_register(lbl)

func _evolution_card(vb: VBoxContainer, entity_id: String, entity: Dictionary) -> void:
	var tier := entity.get("maitrise_actuelle", 0) as int
	var nc   := UIColors.tier_color(tier + 1)
	var nom  := entity.get("nom_affichage_fr", entity.get("name", entity_id)) as String

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.10, 0.60, 1, 4))
	vb.add_child(panel)
	_fade_register(panel)

	var m := UIHelpers.margin_of(8)
	panel.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = nom
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = "%s  →  %s" % [GameData.get_tier_name(tier), GameData.get_tier_name(tier + 1)]
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", nc)
	info.add_child(tier_lbl)

	var btn := Button.new()
	btn.text = Translations.T("btn.evolve")
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", nc)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(nc, 0.15, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(nc, 0.30, 1.0, 1, 4))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var etype := entity.get("entity_type", "creature") as String
	btn.pressed.connect(_launch_evolution.bind(entity_id, nom, etype, tier))
	hb.add_child(btn)

# Déclenche l'évolution (manuel) puis le rituel — réutilise le flux existant.
func _launch_evolution(entity_id: String, entity_name: String,
		entity_type: String, from_tier: int) -> void:
	if not MasterySystem.evolve_entity(entity_id):
		return
	SaveManager.save()
	GameData.pending_evolution = {
		"entity_type": entity_type,
		"entity_id":   entity_id,
		"entity_name": entity_name,
		"from_tier":   from_tier,
		"to_tier":     from_tier + 1,
	}
	get_tree().change_scene_to_file("res://scenes/village/EvolutionRitual.tscn")

# ═══════════════════════════════════════════════════════════
#  Animations
# ═══════════════════════════════════════════════════════════

func _fade_register(node: Control) -> void:
	node.modulate.a = 0.0
	_fade_nodes.append(node)

func _run_animation_sequence() -> void:
	await get_tree().create_timer(0.25).timeout

	# Phase 1 — fade-in staggeré
	var tw1 := create_tween().set_parallel(true)
	var d := 0.0
	for node: Control in _fade_nodes:
		tw1.tween_property(node, "modulate:a", 1.0, 0.20).set_delay(d).set_ease(Tween.EASE_OUT)
		d += 0.05
	await tw1.finished

	# Phase 2 — remplissage des barres XP (avant → après), une par une
	for xp: Dictionary in _xp_anims:
		await _fill_xp_bar(xp)

# Anime une carte : le remplissage du fond va de xp_avant vers xp_apres,
# pendant que "+X XP" compte de 0 au gain du cycle.
func _fill_xp_bar(xp: Dictionary) -> void:
	var card   : XPCard = xp["card"]
	var xp_lbl : Label  = xp["xp_label"]
	var gained : float  = xp["gained"]
	var before : float  = xp["before_frac"]
	var after  : float  = xp["after_frac"]

	card.xp_fill = before
	xp_lbl.text = "+0 XP"

	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "xp_fill", after, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void:
		xp_lbl.text = "+%.0f XP" % v
	, 0.0, gained, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

# Garde les entrées dont la zone est débloquée (sans zone = transversal, conservé).
func _filter_zone(pool: Array, tier: int) -> Array:
	var mz := Balance.max_unlocked_zone(tier)
	var out: Array = []
	for entry: Dictionary in pool:
		if entry.has("zone_associee") and int(entry["zone_associee"]) > mz:
			continue
		out.append(entry)
	return out

# Ligne "label : n / total" — vert si complet.
func _discovery_row(parent: Container, label: String, n: int, total: int) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(hb)
	_fade_register(hb)

	var kl := Label.new()
	kl.text = label + " :"
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hb.add_child(kl)

	var vl := Label.new()
	vl.text = "%d / %d" % [n, total]
	vl.add_theme_font_size_override("font_size", 14)
	vl.add_theme_color_override("font_color",
			UIColors.LOG_VICTORY if (total > 0 and n >= total) else UIColors.TEXT_HEADER)
	hb.add_child(vl)

# Ligne "label : ✔/—" — ✔ vert si fait, neutre sinon.
func _discovery_check(parent: Container, label: String, done: bool) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(hb)
	_fade_register(hb)

	var kl := Label.new()
	kl.text = label + " :"
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hb.add_child(kl)

	var vl := Label.new()
	vl.text = "✔" if done else "—"
	vl.add_theme_font_size_override("font_size", 14)
	vl.add_theme_color_override("font_color", UIColors.LOG_VICTORY if done else UIColors.TEXT_MUTED)
	hb.add_child(vl)

# Seuil XP du prochain tier de l'entité (dernier seuil si au max).
func _next_tier_threshold(entity: Dictionary) -> float:
	var tier := entity.get("maitrise_actuelle", 0) as int
	var next_idx := tier + 1
	if tier >= GameData.get_max_tier_for_type(entity.get("entity_type", "")) or next_idx >= GameData.xp_thresholds.size():
		return float(GameData.xp_thresholds.back())
	return float(GameData.xp_thresholds[next_idx])

# Carte XP du récap : carte d'entité commune (UIHelpers.entity_xp_card —
# même DA que les panneaux du Village : fond rempli, « icône | nom | palier |
# XP à droite ») + un gain « +X XP » vert greffé à droite de l'en-tête, animé
# (compteur 0→gain) en parallèle du remplissage du fond.
# Retourne { container, card, xp_label } pour l'animation (_fill_xp_bar).
func _xp_card(icon: String, label: String, tier: int,
		xp_apres: float, xp_max: float, entity_type: String = "") -> Dictionary:
	var built := UIHelpers.entity_xp_card(label, tier, xp_apres, xp_max, icon, entity_type)
	var card := built["card"] as XPCard
	var header := built["header"] as HBoxContainer

	var gain_lbl := Label.new()
	gain_lbl.text = "+0 XP"
	gain_lbl.add_theme_font_size_override("font_size", 12)
	gain_lbl.add_theme_color_override("font_color", UIColors.LOG_VICTORY)
	header.add_child(gain_lbl)

	return {"container": card, "card": card, "xp_label": gain_lbl}

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

func _go_to_village() -> void:
	UIHelpers.fade_to_scene(self, "res://scenes/village/village.tscn")
