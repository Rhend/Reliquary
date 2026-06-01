# ============================================================
# HeroPanel — Contenu du panneau glissant « Héro » du Village.
#
# Construit dans host._rp_content : nom + palier, barre XP, statistiques
# (base + bonus), bouton d'évolution, et cartes de passifs dépliables
# (standard + uniques débloqués). Module sans état (fonctions statiques) ;
# host = nœud Village (accès _rp_content, _make_evolve_btn).
# ============================================================
class_name HeroPanel

# Point d'entrée : peuple host._rp_content avec la fiche du héro actif.
static func build(host: Village) -> void:
	var cid    := GameData.player.get("active_creature_id", "") as String
	var c      := GameData.get_entity(cid)
	var tier   := c.get("maitrise_actuelle", 0) as int
	var xp     := c.get("xp_maitrise_actuelle",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xpmax  := float(GameData.xp_thresholds[ni])
	var can_ev := tier < GameData.MAX_TIER and xp >= xpmax
	var tcolor := UIColors.tier_color(tier)

	# Nom + tier
	var lname := Label.new()
	lname.text = "%s  —  %s" % [c.get("nom_affichage_fr", c.get("name", "Héro")), GameData.get_tier_name(tier)]
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 16)
	lname.add_theme_color_override("font_color", tcolor)
	host._rp_content.add_child(lname)

	# ── Barre XP (même DA que les autres panneaux : XPCard à fond rempli animé) ──
	if tier < GameData.MAX_TIER:
		var frac := clampf(xp / xpmax, 0.0, 1.0) if xpmax > 0.0 else 0.0
		var xp_color := UIColors.FILTER_ON if can_ev else UIColors.STAT_HP
		var xp_card := UIHelpers.xp_panel(xp_color, frac)
		xp_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host._rp_content.add_child(xp_card)

		var xpm := UIHelpers.margin_of(6)
		xp_card.add_child(xpm)
		var xl := Label.new()
		xl.text = "XP  %.0f / %.0f" % [xp, xpmax]
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.add_theme_font_size_override("font_size", 11)
		xl.add_theme_color_override("font_color", Color.WHITE)
		xpm.add_child(xl)

	# ── Sous-section STATISTIQUES ─────────────────────────────
	host._rp_content.add_child(UIHelpers.section_header("◆  STATISTIQUES", tcolor))

	var eq  := GameData.get_equipment_bonuses()
	var eff := GameData.get_effective_stats(cid)
	var pas := PassiveSystem.get_combat_bonuses()

	var atk_base  := int(eff.get("atk", 0))
	var atk_bonus := int(eq.get("atk", 0)) + int(pas.get("atk_bonus", 0))
	var def_base  := int(eff.get("def", 0))
	var def_bonus := int(pas.get("def_bonus", 0))
	var hp_base   := int(eff.get("hp", 0))
	var hp_bonus  := int(eq.get("hp", 0)) + int(pas.get("hp_bonus", 0))

	# Les trois stats sur une seule ligne horizontale, espacées pour lisibilité.
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._rp_content.add_child(stats_row)

	for row: Array in [
		["ATK", atk_base + atk_bonus, atk_base, atk_bonus, UIColors.STAT_ATK],
		["DEF", def_base + def_bonus, def_base, def_bonus, UIColors.STAT_DEF],
		["PV",  hp_base  + hp_bonus,  hp_base,  hp_bonus,  UIColors.STAT_HP ],
	]:
		var grp := HBoxContainer.new()
		grp.add_theme_constant_override("separation", 4)
		stats_row.add_child(grp)
		var kl := Label.new()
		kl.text = str(row[0]) + " :"
		kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		grp.add_child(kl)
		var vl := Label.new()
		vl.text = str(row[1])
		vl.add_theme_font_size_override("font_size", 14)
		vl.add_theme_color_override("font_color", row[4])
		grp.add_child(vl)
		var detail := Label.new()
		detail.text = "(%d + %d)" % [row[2], row[3]]
		detail.add_theme_font_size_override("font_size", 10)
		detail.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		grp.add_child(detail)

	if tier < GameData.MAX_TIER:
		if can_ev:
			host._rp_content.add_child(host._make_evolve_btn(
				cid, c.get("nom_affichage_fr", c.get("name", cid)) as String,
				c.get("entity_type", "creature") as String, tier))
	else:
		var ml := Label.new()
		ml.text = "▲ NIVEAU MAXIMUM"
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 11)
		ml.add_theme_color_override("font_color", UIColors.FILTER_ON)
		host._rp_content.add_child(ml)

	# ── Sous-section PASSIFS (standard + uniques débloqués, même carte) ──
	host._rp_content.add_child(UIHelpers.section_header("◆  PASSIFS", tcolor))

	# Seuls les passifs débloqués apparaissent — aucune carte verrouillée.
	var cards: Array[Control] = []
	var seen: Array           = []
	for pid in (c.get("unlocked_passives", []) as Array) + (GameData.player.get("active_passives", []) as Array):
		if pid in seen:
			continue
		seen.append(pid)
		var pdata := GameData.get_entity(pid)
		if not pdata.is_empty():
			cards.append(_passive_card(host, pdata, tcolor))

	for eid in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != "passif_unique":
			continue
		if not (e.get("est_debloque", false) as bool):
			continue
		cards.append(_passive_card(host, _normalize_unique_passive(eid, e), tcolor))

	if cards.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "Aucun passif débloqué"
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		host._rp_content.add_child(none_lbl)
	else:
		for card in cards:
			host._rp_content.add_child(card)

	# ── Sous-section INGRÉDIENTS (placeholder, masquée si Village < T2) ──
	var ingredients_section := VBoxContainer.new()
	ingredients_section.name = "IngredientsSection"
	ingredients_section.add_theme_constant_override("separation", 5)
	ingredients_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ingredients_section.visible = (GameData.village.get("tier_actuel", 0) as int) >= 1
	ingredients_section.add_child(UIHelpers.section_header("◆  INGRÉDIENTS", tcolor))
	host._rp_content.add_child(ingredients_section)


# Convertit un passif unique vers la forme attendue par _passive_card
# (champs nom_affichage_fr / maitrise_actuelle / xp_maitrise_actuelle).
static func _normalize_unique_passive(eid: String, e: Dictionary) -> Dictionary:
	return {
		"id":           eid,
		"name":         e.get("nom_affichage_fr", eid),
		"maitrise_actuelle": int(e.get("maitrise_actuelle", 0)),
		"xp_maitrise_actuelle":   float(e.get("xp_maitrise_actuelle", 0.0)),
		"tier_effects": e.get("tier_effects", []),
		"entity_type":  "passif_unique",
	}

# Retourne une carte dépliable pour un passif : en-tête (nom | palier | XP),
# corps avec effet courant + cascade des paliers à débloquer.
static func _passive_card(host: Village, pdata: Dictionary, _tcolor: Color) -> Control:
	var rarity   := pdata.get("maitrise_actuelle", 0) as int
	var rcolor   := UIColors.tier_color(rarity)
	var rname    := GameData.get_tier_name(rarity)
	var has_evos := rarity < GameData.MASTERY_TIERS.size() - 1

	# Calcul de la progression XP vers le palier suivant
	var xp_cur  : float = pdata.get("xp_maitrise_actuelle", 0.0) as float
	var xp_need : int   = 0
	var xp_fill := 0.0
	if has_evos and rarity + 1 < GameData.xp_thresholds.size():
		xp_need = int(GameData.xp_thresholds[rarity + 1])
		if xp_need > 0:
			xp_fill = clampf(xp_cur / float(xp_need), 0.0, 1.0)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale avec barre XP en fond ──────────────
	var panel := UIHelpers.xp_panel(rcolor, xp_fill)
	wrapper.add_child(panel)

	var m := UIHelpers.margin_of(6)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	m.add_child(vb)

	# ── En-tête (toujours visible) : nom | palier | flèche | XP ──
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = pdata.get("name", pdata.get("id", "?")) as String
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(name_lbl)

	var badge := Label.new()
	badge.text = rname
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", rcolor)
	header.add_child(badge)

	var arrow := Label.new()
	arrow.add_theme_font_size_override("font_size", 9)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	header.add_child(arrow)

	var xp_lbl := Label.new()
	if rarity >= GameData.MAX_TIER:
		xp_lbl.text = "RANG MAX"
		xp_lbl.add_theme_color_override("font_color", rcolor)
	else:
		xp_lbl.text = "%s / %s XP" % [UIHelpers.xp_fmt(int(xp_cur)), UIHelpers.xp_fmt(xp_need)]
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(xp_lbl)

	# Bouton évoluer (action manuelle, si éligible)
	var pid_ev := pdata.get("id", "") as String
	if MasterySystem.can_evolve(pid_ev):
		wrapper.add_child(host._make_evolve_btn(pid_ev,
				pdata.get("name", pid_ev) as String,
				pdata.get("entity_type", "passive") as String, rarity))

	# ── Corps déplié (toggle) : effet courant + cascade à débloquer ──
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.visible = false
	wrapper.add_child(body)

	# Description de l'effet au palier actuel
	for effect in _tier_effects(pdata, rarity):
		var desc := effect.get("description", "") as String
		if desc.is_empty():
			continue
		var eff_lbl := Label.new()
		eff_lbl.text = desc
		eff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_lbl.add_theme_font_size_override("font_size", 10)
		eff_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(eff_lbl)

	# Cascade des paliers non encore atteints
	if has_evos:
		var unlock_hdr := Label.new()
		unlock_hdr.text = "— À DÉBLOQUER —"
		unlock_hdr.add_theme_font_size_override("font_size", 9)
		unlock_hdr.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		unlock_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(unlock_hdr)

		for t in range(rarity + 1, GameData.MASTERY_TIERS.size()):
			body.add_child(_evo_row(t, rarity, pdata))

	# Toggle uniquement si le corps a du contenu à révéler
	if body.get_child_count() > 0:
		arrow.text = "  ▶"
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UIHelpers.add_hover_feedback(panel)
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				body.visible = not body.visible
				arrow.text = "  ▼" if body.visible else "  ▶"
		)

	return wrapper

static func _evo_row(t: int, base_rarity: int, pdata: Dictionary) -> Control:
	var tc      := UIColors.tier_color(t)
	var tn      := GameData.get_tier_name(t)
	var indent  := (t - base_rarity) * 14
	var xp_cur  : float = pdata.get("xp_maitrise_actuelle", 0.0) as float
	var is_max  : bool  = t >= GameData.MAX_TIER
	var xp_need : int   = 0
	if not is_max and t + 1 < GameData.xp_thresholds.size():
		xp_need = int(GameData.xp_thresholds[t + 1])
	var xp_fill := 0.0
	if xp_need > 0:
		xp_fill = clampf(xp_cur / float(xp_need), 0.0, 1.0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", indent)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := UIHelpers.xp_panel(tc, xp_fill, 0.06, 0.38, 1, 3)
	margin.add_child(panel)

	var pm := UIHelpers.margin_of(4)
	panel.add_child(pm)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm.add_child(vb)

	# Ligne rareté + XP X/Y
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)

	var name_lbl := Label.new()
	name_lbl.text = "→  " + tn
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", tc)
	hb.add_child(name_lbl)

	var xp_lbl := Label.new()
	xp_lbl.text = "RANG MAX" if is_max else "%s / %s XP" % [UIHelpers.xp_fmt(int(xp_cur)), UIHelpers.xp_fmt(xp_need)]
	xp_lbl.add_theme_font_size_override("font_size", 9)
	xp_lbl.add_theme_color_override("font_color", tc if is_max else UIColors.TEXT_MUTED)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(xp_lbl)

	# Effets du palier
	for effect in _tier_effects(pdata, t):
		var desc := effect.get("description", "") as String
		if desc.is_empty(): continue
		var eff_lbl := Label.new()
		eff_lbl.text = desc
		eff_lbl.add_theme_font_size_override("font_size", 9)
		eff_lbl.add_theme_color_override("font_color", tc.darkened(0.2))
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(eff_lbl)

	return margin

# Retourne la liste d'effets pour le palier t, ou les effets de base si absent.
static func _tier_effects(pdata: Dictionary, t: int) -> Array:
	var te_list: Array = pdata.get("tier_effects", [])
	if t < te_list.size():
		var effs: Array = te_list[t].get("effects", [])
		if not effs.is_empty(): return effs
	if not te_list.is_empty():
		return te_list[0].get("effects", [])
	return []
