# ============================================================
# AdventurePanel — Contenu du panneau glissant « Expéditions » du Village.
#
# Construit dans host._rp_content : bouton de départ + accordéon des biomes
# découverts (catégories créatures / pièges / bénédictions / ingrédients,
# filtrées par zone débloquée). Module sans état (fonctions statiques) ;
# host = nœud Village (accès _rp_content, _adv_selected_biome_id,
# _make_evolve_btn, _on_start_selected_expedition).
# ============================================================
class_name AdventurePanel

# Point d'entrée : peuple host._rp_content avec le panneau Expéditions.
static func build(host: Village) -> void:
	var tier   := host._maitrise_actuelle()
	var tcolor := UIColors.tier_color(tier)

	# Invalide la sélection si l'entité n'existe plus (pas d'auto-select)
	if not host._adv_selected_biome_id.is_empty() and GameData.get_entity(host._adv_selected_biome_id).is_empty():
		host._adv_selected_biome_id = ""

	# ── Slot supérieur : placeholder OU bouton ────────────────
	var no_biome_selected := host._adv_selected_biome_id.is_empty()

	# Encadré neutre (aucun biome choisi)
	var placeholder := PanelContainer.new()
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.custom_minimum_size   = Vector2(0, 52)
	placeholder.visible = no_biome_selected
	placeholder.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.06, 0.25, 1, 6))
	var ph_lbl := Label.new()
	ph_lbl.text = "Choisir un biome pour partir en expédition"
	ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ph_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ph_lbl.add_theme_font_size_override("font_size", 13)
	ph_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	placeholder.add_child(ph_lbl)
	host._rp_content.add_child(placeholder)

	# Bouton actif (biome sélectionné)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", tcolor)
	btn.visible = not no_biome_selected
	if not no_biome_selected:
		var bname: String = str(GameData.get_entity(host._adv_selected_biome_id).get("nom_affichage_fr", host._adv_selected_biome_id)).to_upper()
		btn.text = "⚔   PARTIR EN EXPÉDITION — " + bname
	else:
		btn.text = "⚔   PARTIR EN EXPÉDITION"
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	btn.pressed.connect(host._on_start_selected_expedition)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(btn)
	host._rp_content.add_child(btn)

	# ── Séparateur ────────────────────────────────────────────
	host._rp_content.add_child(HSeparator.new())

	# ── Liste des biomes (accordéon) ──────────────────────────
	host._rp_content.add_child(UIHelpers.section_header("◆  BIOMES DISPONIBLES", tcolor))

	# Références partagées entre les closures pour l'accordéon
	var contents:     Dictionary = {}   # biome_id → VBoxContainer (détail)
	var arrows:       Dictionary = {}   # biome_id → Label (▶ / ▼)
	var biome_names:  Dictionary = {}   # biome_id → nom affiché (pour le bouton)

	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != "biome":
			continue
		if not e.get("est_decouvert", false):
			continue
		var bid := eid
		biome_names[bid] = e.get("nom_affichage_fr", bid).to_upper()

		var result  := _adv_biome_card(host, bid, e)
		var wrapper := result["wrapper"] as Control
		var panel   := result["panel"]   as Control
		var section := result["section"] as VBoxContainer
		var arrow   := result["arrow"]   as Label
		contents[bid] = section
		arrows[bid]   = arrow

		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton \
					and ev.button_index == MOUSE_BUTTON_LEFT \
					and ev.pressed):
				return
			var bname := biome_names.get(bid, bid) as String
			if bid == host._adv_selected_biome_id:
				section.visible = not section.visible
				arrow.text = "  ▼" if section.visible else "  ▶"
				if section.visible:
					# Ré-sélection : bouton actif.
					btn.text = "⚔   PARTIR EN EXPÉDITION — " + bname
					btn.visible = true
					placeholder.visible = false
				else:
					# Désélection : plus de biome choisi → bouton masqué, placeholder affiché.
					host._adv_selected_biome_id = ""
					btn.visible = false
					placeholder.visible = true
			else:
				if host._adv_selected_biome_id in contents \
						and is_instance_valid(contents[host._adv_selected_biome_id]):
					contents[host._adv_selected_biome_id].visible = false
					arrows[host._adv_selected_biome_id].text = "  ▶"
				host._adv_selected_biome_id = bid
				section.visible = true
				arrow.text = "  ▼"
				btn.text = "⚔   PARTIR EN EXPÉDITION — " + bname
				placeholder.visible = false
				btn.visible = true
		)
		host._rp_content.add_child(wrapper)

# Construit la carte accordéon d'un biome avec ses catégories (créatures, pièges, etc.).
# Retourne { wrapper, panel, section, arrow } pour que build() connecte le gui_input.
static func _adv_biome_card(host: Village, biome_id: String, biome: Dictionary) -> Dictionary:
	var btier := biome.get("maitrise_actuelle", 0) as int
	var bdisp := MasteryRegistry.get_mastery_display(biome_id)
	var pools := MasteryRegistry.get_biome_entity_pools(biome_id)

	# XP courante / seuil pour la carte (0 si palier max → « RANG MAX »).
	var xp_cur := 0.0
	var xp_max := 0.0
	if not bdisp.is_empty() and not bdisp.get("at_max", false):
		xp_cur = float(bdisp.get("xp", 0.0))
		xp_max = float(bdisp.get("xp_max", 0.0))

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale via le template commun (nom | palier | XP) ──
	var built := UIHelpers.entity_xp_card(
			(biome.get("nom_affichage_fr", biome_id) as String).to_upper(), btier, xp_cur, xp_max,
			"", "biome")
	var panel := built["card"] as XPCard
	var header := built["header"] as HBoxContainer
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(panel)
	wrapper.add_child(panel)

	# Tooltip du biome.
	var btooltip_body := _tooltip_zone_line(btier)
	var mech_id := biome.get("mecanique_forte_id", "") as String
	if mech_id != "":
		btooltip_body += "\nMécanique : " + _mech_name(mech_id)
	UIHelpers.register_tooltip(panel,
			biome.get("nom_affichage_fr", biome_id) as String,
			btooltip_body, UIColors.tier_color(btier))

	# Flèche d'accordéon, à droite de l'en-tête du template.
	var arrow := Label.new()
	arrow.text = "  ▶"
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	header.add_child(arrow)

	# ── Section catégories (repliée par défaut) ───────────────
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	if MasterySystem.can_evolve(biome_id):
		wrapper.add_child(host._make_evolve_btn(biome_id,
				biome.get("nom_affichage_fr", biome_id) as String, "biome", btier))
	wrapper.add_child(section)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 12)
	indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(indent)

	var cat_vb := VBoxContainer.new()
	cat_vb.add_theme_constant_override("separation", 3)
	indent.add_child(cat_vb)

	# Mécanique forte du biome (pill toujours visible dans l'accordéon).
	_adv_mechanic_row(cat_vb, biome)

	# Filtrage par zone débloquée : seuls les éléments des zones actives comptent et s'affichent.
	# Chaque catégorie porte son propre motif de barre d'XP (cf. XPCard.Motif).
	_adv_category_card(host, cat_vb, "CRÉATURES",    _filter_pool_by_zone(pools["creatures"], btier),    UIColors.TYPE_CREATURE,    XPCard.Motif.PAWS)
	_adv_category_card(host, cat_vb, "PIÈGES",       _filter_pool_by_zone(pools["traps"], btier),        UIColors.TYPE_TRAP,        XPCard.Motif.LIGHTNING)
	_adv_category_card(host, cat_vb, "BÉNÉDICTIONS", _filter_pool_by_zone(pools["benedictions"], btier), UIColors.TYPE_BENEDICTION, XPCard.Motif.CROSSES)
	_adv_ingredient_section(cat_vb, pools["ingredients"])

	return {"wrapper": wrapper, "panel": panel, "section": section, "arrow": arrow}

# Carte catégorie cliquable (Créatures / Pièges / Bénédictions) avec compteur de découverte.
# Panneau cliquable + liste d'entités repliée en dessous. `motif` = motif de barre d'XP.
static func _adv_category_card(host: Village, parent: VBoxContainer, label: String, pool: Array, color: Color, motif: int = XPCard.Motif.BUBBLES) -> void:
	if pool.is_empty():
		return
	var body := _accordion(parent, label, "%d / %d" % [MasteryRegistry.count_discovered(pool), pool.size()])
	_adv_entity_rows(host, body, pool, color, motif)

# Construit un « accordéon » repliable : panneau neutre cliquable
# [label | (compteur) | ▶] + section repliée dessous. Retourne le VBox interne
# (vide) à remplir par l'appelant. count_text == "" → pas de compteur affiché.
static func _accordion(parent: VBoxContainer, label: String, count_text: String) -> VBoxContainer:
	var nc := UIColors.CARD_NEUTRAL

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(panel)
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.06, 0.38, 1, 3))
	wrap.add_child(panel)

	var m := UIHelpers.margin_of(6)
	panel.add_child(m)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	m.add_child(hdr)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", nc)
	hdr.add_child(lbl)

	if count_text != "":
		var count_lbl := Label.new()
		count_lbl.text = count_text
		count_lbl.add_theme_font_size_override("font_size", 10)
		count_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hdr.add_child(count_lbl)

	var arrow := Label.new()
	arrow.text = "  ▶"
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hdr.add_child(arrow)

	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	section.visible = false
	wrap.add_child(section)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 10)
	indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(indent)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	indent.add_child(body)

	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			section.visible = not section.visible
			arrow.text = "  ▼" if section.visible else "  ▶"
	)
	return body

# Remplit parent avec une carte par entité du pool, même format pour tous les types.
# Entité non découverte → nom "?", palier Commun, XP 0 / seuil (placeholder homogène).
# `motif` = motif de particules de la barre d'XP (commun à toute la catégorie).
static func _adv_entity_rows(host: Village, parent: VBoxContainer, pool: Array, _color: Color, motif: int = XPCard.Motif.BUBBLES) -> void:
	for entry: Dictionary in pool:
		var entry_id := entry.get("id", "") as String
		var is_known := MasteryRegistry.is_discovered(entry_id)

		# Valeurs d'affichage — placeholder Commun si non découvert.
		var disp_name   := "?"
		var entity_tier := 0
		var entity_xp   := 0.0
		var at_max      := false
		var is_equip    := false
		var entity: Dictionary = {}

		if is_known:
			entity = GameData.get_entity(entry_id)
			var bentry := GameData.player.get("bestiary", {}).get(entry_id, {}) as Dictionary
			is_equip   = entity.get("entity_type", "") == "equipment"
			disp_name  = entry.get("nom_affichage_fr", entry.get("name", "?"))
			if not entity.is_empty() and not is_equip:
				entity_tier = entity.get("maitrise_actuelle", 0)
				entity_xp   = entity.get("xp_maitrise_actuelle",   0.0)
				at_max      = entity_tier >= GameData.get_max_tier_for_type(entity.get("entity_type", ""))
			elif not bentry.is_empty():
				entity_tier = bentry.get("tier", entry.get("tier", 0))
				entity_xp   = bentry.get("xp",   0.0)
				at_max      = entity_tier >= GameData.get_max_tier_for_type(entity.get("entity_type", ""))
			else:
				entity_tier = entry.get("tier", 0)

		var ec      := UIColors.tier_color(entity_tier)
		var xp_need := 0
		var xp_fill := 0.0
		if not at_max and not is_equip and entity_tier + 1 < GameData.xp_thresholds.size():
			xp_need = int(GameData.xp_thresholds[entity_tier + 1])
			if xp_need > 0:
				xp_fill = clampf(entity_xp / float(xp_need), 0.0, 1.0)

		var panel := UIHelpers.xp_panel(ec, xp_fill, 0.06, 0.38, 1, 3, motif)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(panel)

		# Tooltip de l'entité.
		if is_known:
			var tt_title := disp_name
			var tt_body  := _tooltip_entity_body(entry, entity)
			UIHelpers.register_tooltip(panel, tt_title, tt_body, ec)

		var pm := UIHelpers.margin_of(4)
		panel.add_child(pm)

		var hb := HBoxContainer.new()
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pm.add_child(hb)

		var name_lbl := Label.new()
		name_lbl.text = disp_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if is_known else UIColors.TEXT_MUTED)
		hb.add_child(name_lbl)

		var tbadge := Label.new()
		tbadge.text = GameData.get_tier_name(entity_tier)
		tbadge.add_theme_font_size_override("font_size", 10)
		tbadge.add_theme_color_override("font_color", ec)
		hb.add_child(tbadge)

		if not is_equip:
			var xp_text := "RANG MAX" if at_max \
					else "%s / %s XP" % [UIHelpers.xp_fmt(int(entity_xp)), UIHelpers.xp_fmt(xp_need)]
			var xp_lbl := Label.new()
			xp_lbl.text = xp_text
			xp_lbl.add_theme_font_size_override("font_size", 9)
			xp_lbl.add_theme_color_override("font_color", ec if at_max else UIColors.TEXT_MUTED)
			xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hb.add_child(xp_lbl)

		if is_known and MasterySystem.can_evolve(entry_id):
			parent.add_child(host._make_evolve_btn(
					entry_id, disp_name,
					entity.get("entity_type", "creature") as String,
					entity_tier))

# Carte catégorie dédiée aux ingrédients de biome.
# Absente tant que village_tier < 1 (Forge non débloquée).
# Débloquée : liste nom (couleur tier), plage de quantité et chance de drop par item.
static func _adv_ingredient_section(parent: VBoxContainer, pool: Array) -> void:
	if pool.is_empty():
		return
	# Section absente (pas grisée) tant que la Forge n'est pas débloquée (Village Tier 1).
	if (GameData.village.get("tier_actuel", 0) as int) < 1:
		return
	var body := _accordion(parent, "INGRÉDIENTS", "")
	for entry: Dictionary in pool:
		var ec := UIColors.tier_color(int(entry.get("tier", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		body.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = entry.get("name", "?")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", ec)
		row.add_child(name_lbl)

		var qty_min := int(entry.get("qty_min", 1))
		var qty_max := int(entry.get("qty_max", 1))
		var qty_lbl := Label.new()
		qty_lbl.text = ("×%d–%d" % [qty_min, qty_max]) if qty_min != qty_max else ("×%d" % qty_min)
		qty_lbl.add_theme_font_size_override("font_size", 10)
		qty_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(qty_lbl)

		var chance_lbl := Label.new()
		chance_lbl.text = "%d%%" % int(float(entry.get("chance", 0.0)) * 100.0)
		chance_lbl.add_theme_font_size_override("font_size", 10)
		chance_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(chance_lbl)

# Affiche la mécanique forte du biome : pill colorée (active) ou verrouillée (tier < Rare).
# Rien si le biome n'a pas de mécanique définie.
static func _adv_mechanic_row(parent: VBoxContainer, biome: Dictionary) -> void:
	const MECHS: Dictionary = {
		"ambush":       ["Embuscade",      "La créature attaque en premier.",                    Color(0.90, 0.35, 0.35)],
		"poison":       ["Empoisonnement", "Chaque frappe du héros empoisonne l'ennemi (3 max).", Color(0.40, 0.80, 0.30)],
		"bonne_etoile": ["Bonne Étoile",   "-5 % de combats, +5 % de bénédictions.",             Color(1.00, 0.85, 0.30)],
	}
	var mech_id := biome.get("mecanique_forte_id", "") as String
	if mech_id == "" or not MECHS.has(mech_id):
		return

	var info    := MECHS[mech_id] as Array
	var mname   := info[0] as String
	var mdesc   := info[1] as String
	var mcolor  := info[2] as Color
	var btier   := int(biome.get("maitrise_actuelle", 0))
	var active  := btier >= BiomeMechanics.UNLOCK_TIER

	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pill_color := mcolor if active else UIColors.TEXT_MUTED
	pill.add_theme_stylebox_override("panel",
			UIHelpers.card_style(pill_color, 0.08, 0.50, 1, 3))
	parent.add_child(pill)

	var m := UIHelpers.margin_of(5)
	pill.add_child(m)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	m.add_child(hb)

	var icon_lbl := Label.new()
	icon_lbl.text = "⚡" if active else "🔒"
	icon_lbl.add_theme_font_size_override("font_size", 11)
	hb.add_child(icon_lbl)

	var text_lbl := Label.new()
	text_lbl.text = ("%s  —  %s" % [mname, mdesc]) if active \
			else ("%s  —  Débloquée à Rare" % mname)
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", 11)
	text_lbl.add_theme_color_override("font_color", pill_color)
	hb.add_child(text_lbl)

	var mtooltip := mdesc if active else "Atteins Rare pour débloquer cette mécanique."
	UIHelpers.register_tooltip(pill, "Mécanique — %s" % mname, mtooltip, pill_color)

# ─── Helpers tooltip ──────────────────────────────────────────

static func _mech_name(mech_id: String) -> String:
	const N: Dictionary = {"ambush": "Embuscade", "poison": "Empoisonnement", "bonne_etoile": "Bonne Étoile"}
	return N.get(mech_id, mech_id)

# Ligne "Zone max : Surface / Profondeur / Abysse" selon le tier du biome.
static func _tooltip_zone_line(btier: int) -> String:
	var zone_max := Balance.max_unlocked_zone(btier)
	const ZONES := ["Surface", "Profondeur", "Abysse"]
	return "Zone max : %s" % ZONES[clampi(zone_max, 0, 2)]

# Corps de tooltip pour une entité (créature, piège, bénédiction, ingrédient).
static func _tooltip_entity_body(entry: Dictionary, entity: Dictionary) -> String:
	var etype := entity.get("entity_type", "") as String
	var tier  := int(entity.get("maitrise_actuelle", 0))
	match etype:
		"creature":
			const ZONE_NAMES := ["Surface", "Profondeur", "Abysse"]
			var z    := int(entry.get("zone_associee", 0))
			var zname := ZONE_NAMES[clampi(z, 0, 2)]
			return "Zone : %s\nMaîtrise : %s" % [zname, GameData.get_tier_name(tier)]
		"trap":
			return "Dégâts : 8 % PV (Surface)  ·  15 % (Profondeur)  ·  30 % (Abysse)\nMaîtrise réduit les dégâts subis."
		"benediction":
			return "Bonus XP et soins selon la zone.\nMaîtrise augmente l'effet reçu."
		"ingredient":
			var biome_id := entity.get("biome_source_id", "") as String
			var biome_e  := GameData.get_entity(biome_id)
			var bname    := biome_e.get("nom_affichage_fr", biome_id) as String
			var qty      := int(entity.get("quantite_en_stock", 0))
			return "Biome : %s\nEn stock : %d" % [bname, qty]
		_:
			return "Maîtrise : %s" % GameData.get_tier_name(tier)

# Garde uniquement les entrées dont la zone est débloquée pour ce tier de biome.
# Les entrées sans champ de zone (pièges, bénédictions — transversaux) sont conservées.
static func _filter_pool_by_zone(pool: Array, tier: int) -> Array:
	var max_zone := Balance.max_unlocked_zone(tier)
	var out: Array = []
	for entry: Dictionary in pool:
		if entry.has("zone_associee") and int(entry["zone_associee"]) > max_zone:
			continue
		out.append(entry)
	return out
