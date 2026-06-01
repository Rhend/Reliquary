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

	var cid    := GameData.player.get("active_creature_id", "") as String
	var hero   := GameData.get_entity(cid)
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
	title_lbl.text                  = "CYCLE TERMINÉ  —  %s" % biome_name.to_upper()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_hb.add_child(title_lbl)

	# Tag de fin de cycle — style uniforme, seul le texte change.
	var tag_text := "Défaite"
	if data.get("interrupted", false):
		tag_text = "Interruption"
	elif data.get("victory", false):
		tag_text = "Victoire"
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
	btn.text = "🏠  RETOUR AU VILLAGE"
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

	var sh := UIHelpers.section_header("◆  DÉCOUVERTES", tcolor)
	vb.add_child(sh)
	_fade_register(sh)

	# Grille 2 colonnes : items de découverte répartis sur deux colonnes.
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 24)
	rows.add_theme_constant_override("v_separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(rows)

	_discovery_row(rows, "Créatures rencontrées", MasteryRegistry.count_discovered(creatures), creatures.size())
	_discovery_row(rows, "Pièges identifiés",     MasteryRegistry.count_discovered(traps),     traps.size())
	_discovery_row(rows, "Bénédictions trouvées",  MasteryRegistry.count_discovered(benes),     benes.size())

	# Fragment de Mémoire du biome
	var frag_done := false
	for fid in GameData.entities:
		var f := GameData.entities[fid] as Dictionary
		if f.get("entity_type", "") == "fragment" and f.get("biome_source_id", "") == biome_id:
			frag_done = f.get("est_collecte", false)
			break
	_discovery_check(rows, "Fragment de Mémoire", frag_done)
	_discovery_check(rows, "Créature Unique", biome.get("creature_unique_vaincue", false) as bool)

# ── Section 2 : Répartition XP ─────────────────────────────
func _section_xp(vb: VBoxContainer, data: Dictionary,
		biome_name: String, tcolor: Color) -> void:
	var sh := UIHelpers.section_header("◆  RÉPARTITION XP", tcolor)
	vb.add_child(sh)
	_fade_register(sh)

	# XP total du cycle en tête de section (déplacé du footer).
	var total_lbl := Label.new()
	total_lbl.text = "XP total — %d" % int(data.get("xp_total", 0.0))
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
	vb.add_child(total_lbl)
	_fade_register(total_lbl)

	var cid := data.get("creature_id", "") as String
	_xp_entity(vb, "⚔", "Héro", GameData.get_entity(cid), data.get("xp_hero", 0.0) as float)
	_xp_entity(vb, "🌿", biome_name, GameData.get_entity(data.get("biome_id", "") as String),
			data.get("xp_biome", 0.0) as float)

	# Entités rencontrées ce cycle : créatures, pièges, bénédictions.
	# (l'icône indique le type ; la couleur de la carte vient du palier de l'entité)
	var entities_xp := data.get("xp_entities_detail", {}) as Dictionary
	for ent_id: String in entities_xp:
		var e := GameData.get_entity(ent_id)
		var e_name := e.get("nom_affichage_fr", e.get("name", ent_id)) as String
		var icon := "🐾"
		match e.get("entity_type", ""):
			"trap":        icon = "▲"
			"benediction": icon = "✦"
		_xp_entity(vb, icon, e_name, e, entities_xp[ent_id] as float)

	var detail := data.get("xp_passives_detail", {}) as Dictionary
	for passive_id: String in detail:
		var p := GameData.get_entity(passive_id)
		var p_name := p.get("nom_affichage_fr", p.get("name", passive_id)) as String
		_xp_entity(vb, "⚡", p_name, p, detail[passive_id] as float)

# Ajoute une ligne XP pour une entité ayant reçu de l'XP ce cycle (sinon ignorée).
# La couleur de la carte = couleur du palier (tier) courant de l'entité.
# xp_avant = XP au début du cycle, xp_apres = XP à la fin, xp_max = seuil du palier courant.
func _xp_entity(vb: VBoxContainer, icon: String, label: String, entity: Dictionary,
		gained: float) -> void:
	if gained <= 0.0 or entity.is_empty():
		return
	var tier         := entity.get("maitrise_actuelle", 0) as int
	var entity_color := UIColors.tier_color(tier)
	var xp_max    := _next_tier_threshold(entity)
	var xp_apres  := entity.get("xp_maitrise_actuelle", 0.0) as float
	var xp_avant  := maxf(xp_apres - gained, 0.0)
	var tier_name := GameData.get_tier_name(tier)
	var avant_frac := clampf(xp_avant / xp_max, 0.0, 1.0) if xp_max > 0.0 else 0.0
	var apres_frac := clampf(xp_apres / xp_max, 0.0, 1.0) if xp_max > 0.0 else 1.0

	var card := _xp_card(icon, label, entity_color, xp_apres, xp_max, tier_name)
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
	var sh := UIHelpers.section_header("◆  ÉVOLUTIONS DISPONIBLES", UIColors.FILTER_ON)
	vb.add_child(sh)
	_fade_register(sh)

	var found := false
	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") == "equipment":
			continue   # l'équipement évolue via la Forge, pas le rituel
		if MasterySystem.can_evolve(eid):
			found = true
			_evolution_card(vb, eid, e)

	if not found:
		var lbl := Label.new()
		lbl.text = "Aucune évolution disponible"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(lbl)
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
	btn.text = "ÉVOLUER ▲"
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

# Carte XP au style des cartes de biome : XPCard au fond rempli (couleur entité
# jusqu'au niveau d'XP, à 35 % via le composant), animée avant→après.
# Toutes les infos sont DANS la carte :
#   En-tête   : icône + nom | palier | "+X XP" vert (animé)
#   Sous-ligne: "XP cur / max"
# Retourne { container, card, xp_label } pour l'animation.
func _xp_card(icon: String, label: String, entity_color: Color,
		xp_apres: float, xp_max: float, tier_name: String) -> Dictionary:
	var card := UIHelpers.xp_panel(entity_color, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m := UIHelpers.margin_of(8)
	card.add_child(m)
	var vbx := VBoxContainer.new()
	vbx.add_theme_constant_override("separation", 4)
	m.add_child(vbx)

	# ── En-tête : icône + nom | palier | +X XP (vert) ────────
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbx.add_child(hdr)

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", entity_color)
	hdr.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	hdr.add_child(name_lbl)

	var palier_lbl := Label.new()
	palier_lbl.text = tier_name
	palier_lbl.add_theme_font_size_override("font_size", 11)
	palier_lbl.add_theme_color_override("font_color", entity_color)
	hdr.add_child(palier_lbl)

	var gain_lbl := Label.new()
	gain_lbl.text = "+0 XP"
	gain_lbl.add_theme_font_size_override("font_size", 12)
	gain_lbl.add_theme_color_override("font_color", UIColors.LOG_VICTORY)
	hdr.add_child(gain_lbl)

	# ── Sous-ligne : XP cur / max (dans la carte) ────────────
	var xp_lbl := Label.new()
	xp_lbl.text = "XP  %d / %d" % [int(xp_apres), int(xp_max)]
	xp_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	xp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbx.add_child(xp_lbl)

	return {"container": card, "card": card, "xp_label": gain_lbl}

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

func _go_to_village() -> void:
	get_tree().change_scene_to_file("res://scenes/village/village.tscn")
