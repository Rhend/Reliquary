# ============================================================
# HeroPanel — Contenu du panneau glissant « Héros » du Village.
#
# Construit dans host._rp_content : nom + palier, barre XP, statistiques
# (base + bonus), bouton d'évolution, et cartes de passifs dépliables
# (standard + uniques débloqués). Module sans état (fonctions statiques) ;
# host = nœud Village (accès _rp_content, _make_evolve_btn).
# ============================================================
class_name HeroPanel

const EQUIP_SLOTS: Array = [
	["arme",   "⚔",  "equipment_arme",   "Arme"  ],
	["anneau", "💍",  "equipment_anneau", "Anneau"],
	["armure", "🛡",  "equipment_armure", "Armure"],
]

# Point d'entrée : peuple host._rp_content avec la fiche du héros actif.
static func build(host: Village) -> void:
	var cid    := GameData.player.get("active_creature_id", "") as String
	var c      := GameData.get_entity(cid)
	var tier   := c.get("maitrise_actuelle", 0) as int
	var xp     := c.get("xp_maitrise_actuelle",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xpmax  := float(GameData.xp_thresholds[ni])
	var can_ev := tier < GameData.MAX_TIER and xp >= xpmax
	var tcolor := UIColors.tier_color(tier)

	# ── Carte d'identité + XP (DA commune — UIHelpers.entity_xp_card) ──
	# Palier max → xp_max = 0 → la carte affiche « RANG MAX ».
	var hero_xp_max := xpmax
	if tier >= GameData.MAX_TIER:
		hero_xp_max = 0.0
	var id_card := UIHelpers.entity_xp_card(
			c.get("nom_affichage_fr", c.get("name", "Héros")) as String, tier, xp, hero_xp_max,
			"", c.get("entity_type", "hero") as String)
	host._rp_content.add_child(id_card["card"] as Control)

	# ── STATISTIQUES ──────────────────────────────────────────
	var stats_sec := UIHelpers.collapsible_section("◆  STATISTIQUES", tcolor)
	host._rp_content.add_child(stats_sec["wrapper"])
	var stats_body := stats_sec["body"] as VBoxContainer

	var eq  := GameData.get_equipment_bonuses()
	var eff := GameData.get_effective_stats(cid)
	var pas := PassiveSystem.get_combat_bonuses()

	var atk_base  := int(eff.get("atk", 0))
	var atk_bonus := int(eq.get("atk", 0)) + int(pas.get("atk_bonus", 0))
	var def_base  := int(eff.get("def", 0))
	var def_bonus := int(pas.get("def_bonus", 0))
	var hp_base   := int(eff.get("hp", 0))
	var hp_bonus  := int(eq.get("hp", 0)) + int(pas.get("hp_bonus", 0))

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_body.add_child(stats_row)

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
			stats_body.add_child(host._make_evolve_btn(
				cid, c.get("nom_affichage_fr", c.get("name", cid)) as String,
				c.get("entity_type", "creature") as String, tier))
	else:
		var ml := Label.new()
		ml.text = "▲ NIVEAU MAXIMUM"
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 11)
		ml.add_theme_color_override("font_color", UIColors.FILTER_ON)
		stats_body.add_child(ml)

	# ── ÉQUIPEMENT ────────────────────────────────────────────
	var equip_sec := UIHelpers.collapsible_section("◆  ÉQUIPEMENT", tcolor)
	host._rp_content.add_child(equip_sec["wrapper"])
	var equip_body := equip_sec["body"] as VBoxContainer
	for entry in EQUIP_SLOTS:
		var slot_key:  String = entry[0]
		var slot_icon: String = entry[1]
		var equip_id:  String = entry[2]
		var slot_name: String = entry[3]
		var equip := GameData.get_entity(equip_id)
		if equip.is_empty() or not equip.get("est_debloque", false):
			continue
		equip_body.add_child(_equip_slot_card(host, slot_key, slot_icon, slot_name, equip_id, equip, tcolor))

	# ── PASSIFS ───────────────────────────────────────────────
	var passif_sec := UIHelpers.collapsible_section("◆  PASSIFS", tcolor)
	host._rp_content.add_child(passif_sec["wrapper"])
	var passif_body := passif_sec["body"] as VBoxContainer

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
		passif_body.add_child(none_lbl)
	else:
		for card in cards:
			passif_body.add_child(card)

	# ── INGRÉDIENTS (masqué si Village < T1) ─────────────────
	if (GameData.village.get("tier_actuel", 0) as int) >= 1:
		var ingr_sec := UIHelpers.collapsible_section("◆  INGRÉDIENTS", tcolor)
		ingr_sec["wrapper"].name = "IngredientsSection"
		host._rp_content.add_child(ingr_sec["wrapper"])


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
	var has_evos := rarity < GameData.MASTERY_TIERS.size() - 1
	var xp_cur   := pdata.get("xp_maitrise_actuelle", 0.0) as float
	var name_txt := pdata.get("name", pdata.get("id", "?")) as String

	# Seuil du palier suivant (0 si plus d'évolution → carte « RANG MAX »).
	var xp_max := 0.0
	if has_evos and rarity + 1 < GameData.xp_thresholds.size():
		xp_max = float(GameData.xp_thresholds[rarity + 1])

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale via le template commun (nom | palier | XP) ──
	var built := UIHelpers.entity_xp_card(name_txt, rarity, xp_cur, xp_max,
			"", pdata.get("entity_type", "passive") as String)
	var panel := built["card"] as XPCard
	var header := built["header"] as HBoxContainer
	wrapper.add_child(panel)

	# Flèche d'accordéon, ajoutée à droite de l'en-tête du template.
	var arrow := Label.new()
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	header.add_child(arrow)

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
		# Tooltip passif.
		var eff_list := pdata.get("effets_par_palier", pdata.get("effet_par_palier", {})) as Dictionary
		var cur_eff  := str(eff_list.get(str(rarity), "")) as String
		var tt_body  := "Maîtrise : %s" % GameData.get_tier_name(rarity)
		if cur_eff != "":
			tt_body += "\nEffet : %s" % cur_eff
		UIHelpers.register_tooltip(panel, name_txt, tt_body, UIColors.tier_color(rarity))
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

# Carte d'équipement — DA commune entity_xp_card (même pattern que passifs/biomes).
static func _equip_slot_card(_host: Village, _slot_key: String, slot_icon: String,
		slot_name: String, equip_id: String, equip: Dictionary, _tcolor: Color) -> Control:
	var etier    := int(equip.get("maitrise_actuelle", 0))
	var enom     := equip.get("nom_affichage_fr", equip_id) as String
	var ec       := UIColors.tier_color(etier)
	var at_max   := etier >= GameData.get_max_tier_for_type("equipment")
	var xp_cur   := float(equip.get("xp_maitrise_actuelle", 0.0))
	var next_idx := etier + 1
	var xp_max   := float(GameData.xp_thresholds[next_idx]) if not at_max and next_idx < GameData.xp_thresholds.size() else 0.0

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Stats actuelles ───────────────────────────────────────
	var stats_dict := equip.get("stats_par_palier", {}) as Dictionary
	var stats_at   := stats_dict.get(etier, stats_dict.get(0, {})) as Dictionary
	var stat_parts: PackedStringArray = []
	if int(stats_at.get("atk", 0)) != 0:              stat_parts.append("ATK +%d" % int(stats_at["atk"]))
	if int(stats_at.get("def", 0)) != 0:              stat_parts.append("DEF +%d" % int(stats_at["def"]))
	if int(stats_at.get("hp", 0)) != 0:               stat_parts.append("PV +%d" % int(stats_at["hp"]))
	if int(stats_at.get("attack_speed_pct", 0)) != 0: stat_parts.append("VIT +%d%%" % int(stats_at["attack_speed_pct"]))

	# ── Carte XP unifiée (DA commune) ─────────────────────────
	# Les stats sont injectées à l'intérieur de la carte, sous le header,
	# en reparentant le header dans un VBox pour y ajouter une 2e ligne.
	var built  := UIHelpers.entity_xp_card(enom, etier, xp_cur, xp_max, slot_icon, "equipment")
	var xpcard := built["card"] as XPCard
	var hdr    := built["header"] as HBoxContainer
	wrapper.add_child(xpcard)

	# Étiquette de slot ajoutée à droite du header
	var slot_lbl := Label.new()
	slot_lbl.text = slot_name
	slot_lbl.add_theme_font_size_override("font_size", 10)
	slot_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hdr.add_child(slot_lbl)

	# Injecter les stats dans la carte : reparenter le header dans un VBox
	if stat_parts.size() > 0:
		var mg  := hdr.get_parent()  # MarginContainer de entity_xp_card
		var vb  := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		hdr.reparent(vb)
		var stats_lbl := Label.new()
		stats_lbl.text = "  ".join(stat_parts)
		stats_lbl.add_theme_font_size_override("font_size", 11)
		stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(stats_lbl)
		mg.add_child(vb)

	# ── Indicateur forge (visible uniquement si barre pleine) ──
	if not at_max and MasterySystem.can_evolve(equip_id):
		wrapper.add_child(_forge_ready_panel(equip_id, etier, ec))

	# Tooltip JRPG
	var tt := "Slot : %s  ·  Rang : %s" % [slot_name, GameData.get_tier_name(etier)]
	if stat_parts.size() > 0:
		tt += "\n" + "  ".join(stat_parts)
	UIHelpers.register_tooltip(xpcard, enom, tt, ec)

	return wrapper

# Panneau "Forge Requise" ou liste d'ingrédients quand la barre XP est pleine.
static func _forge_ready_panel(equip_id: String, etier: int, ec: Color) -> Control:
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", UIHelpers.card_style(ec, 0.04, 0.30, 1, 3))
	var m := UIHelpers.margin_of(6)
	body.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	m.add_child(vb)

	if int(GameData.village.get("tier_actuel", 0)) < 1:
		var lbl := Label.new()
		lbl.text = "🔨  Forge Requise"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(lbl)
	else:
		var recipe := GameData.get_forge_recipe(equip_id, etier + 1)
		if recipe.is_empty():
			return body
		var hdr_lbl := Label.new()
		hdr_lbl.text = "🔨  Prêt à forger :"
		hdr_lbl.add_theme_font_size_override("font_size", 11)
		hdr_lbl.add_theme_color_override("font_color", UIColors.LOG_VICTORY)
		vb.add_child(hdr_lbl)
		for req in recipe:
			var ingr_id  := req.get("ingredient_id", "") as String
			var needed   := int(req.get("quantite", 1))
			var ingr     := GameData.get_entity(ingr_id)
			var have     := int(ingr.get("quantite_en_stock", 0))
			var ingr_nom := ingr.get("nom_affichage_fr", ingr_id) as String
			var ok       := have >= needed
			var ic       := UIColors.INGREDIENT_OK if ok else UIColors.INGREDIENT_MISSING
			var row      := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			vb.add_child(row)
			var il := Label.new()
			il.text = "  %s" % ingr_nom
			il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			il.add_theme_font_size_override("font_size", 11)
			il.add_theme_color_override("font_color", ic)
			row.add_child(il)
			var ql := Label.new()
			ql.text = "%d / %d" % [have, needed]
			ql.add_theme_font_size_override("font_size", 11)
			ql.add_theme_color_override("font_color", ic)
			row.add_child(ql)

	return body

# Retourne la liste d'effets pour le palier t, ou les effets de base si absent.
static func _tier_effects(pdata: Dictionary, t: int) -> Array:
	var te_list: Array = pdata.get("tier_effects", [])
	if t < te_list.size():
		var effs: Array = te_list[t].get("effects", [])
		if not effs.is_empty(): return effs
	if not te_list.is_empty():
		return te_list[0].get("effects", [])
	return []
