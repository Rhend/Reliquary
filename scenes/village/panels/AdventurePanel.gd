# ============================================================
# AdventurePanel — Contenu du panneau glissant « Expéditions » du Village.
#
# Construit dans host.rp_content : bouton de départ + accordéon des biomes
# découverts (catégories créatures / pièges / bénédictions / ingrédients,
# filtrées par zone débloquée). Module sans état (fonctions statiques) ;
# host = nœud Village (accès rp_content, adv_selected_biome_id,
# make_evolve_btn, start_selected_expedition).
# ============================================================
class_name AdventurePanel

# Point d'entrée : peuple host.rp_content avec le panneau Expéditions.
static func build(host: Village) -> void:
	var tier   := host.village_tier()
	var tcolor := UIColors.tier_color(tier)

	# Invalide la sélection si l'entité n'existe plus (pas d'auto-select)
	if not host.adv_selected_biome_id.is_empty() and GameData.get_entity(host.adv_selected_biome_id).is_empty():
		host.adv_selected_biome_id = ""

	# ── Expédition en cours ───────────────────────────────────
	if AdventureSystem.is_running:
		var running_biome := GameData.get_entity(AdventureSystem.current_biome_id)
		var rname := Translations.entity_name(running_biome, "?")
		var zone_str   := Translations.zone_name(int(AdventureSystem.zone_courante))
		var info := PanelContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_stylebox_override("panel", UIHelpers.card_style(tcolor, 0.10, 0.60, 2, 6))
		var m := UIHelpers.margin_of(10)
		info.add_child(m)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		m.add_child(vb)
		var lbl1 := Label.new()
		lbl1.text = "⚔  " + Translations.T("adv.running.expedition")
		lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl1.add_theme_font_size_override("font_size", 14)
		lbl1.add_theme_color_override("font_color", tcolor)
		vb.add_child(lbl1)
		var lbl2 := Label.new()
		lbl2.text = "%s  —  %s" % [rname, zone_str]
		lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl2.add_theme_font_size_override("font_size", 11)
		lbl2.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(lbl2)
		host.rp_content.add_child(info)
		# Pas de bouton de départ quand une expédition tourne déjà
		host.rp_content.add_child(HSeparator.new())

	# ── Slot supérieur : placeholder OU bouton ────────────────
	var no_biome_selected := host.adv_selected_biome_id.is_empty()

	# Encadré neutre (aucun biome choisi) — masqué si expédition en cours
	var placeholder := PanelContainer.new()
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.custom_minimum_size   = Vector2(0, 52)
	placeholder.visible = no_biome_selected and not AdventureSystem.is_running
	placeholder.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.06, 0.25, 1, 6))
	var ph_lbl := Label.new()
	ph_lbl.text = Translations.T("adv.biome_placeholder")
	ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ph_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ph_lbl.add_theme_font_size_override("font_size", 13)
	ph_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	placeholder.add_child(ph_lbl)
	host.rp_content.add_child(placeholder)

	# Bouton actif (biome sélectionné) — masqué si expédition en cours.
	# Volontairement plus imposant que les cartes alentour (hauteur, fond
	# saturé, liseré épais, pulsation) : c'est l'action principale du panneau,
	# elle ne doit pas se noyer dans la liste des biomes.
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 64)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", tcolor.lightened(0.35))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 5)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	btn.visible = not no_biome_selected and not AdventureSystem.is_running
	if not no_biome_selected:
		var bname: String = Translations.entity_name(
				GameData.get_entity(host.adv_selected_biome_id), host.adv_selected_biome_id).to_upper()
		btn.text = Translations.T("adv.start_btn_named") % bname
	else:
		btn.text = Translations.T("adv.start_btn")
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.30, 1.0, 3, 8))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.48, 1.0, 3, 8))
	btn.pressed.connect(host.start_selected_expedition)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(btn)
	# Pulsation continue pour attirer l'œil (même procédé que le bouton Forger).
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	var pulse := btn.create_tween()
	pulse.set_loops()
	pulse.tween_property(btn, "scale", Vector2(1.02, 1.02), 0.7) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(btn, "scale", Vector2.ONE, 0.7) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	host.rp_content.add_child(btn)

	# ── Séparateur ────────────────────────────────────────────
	host.rp_content.add_child(HSeparator.new())

	# ── Liste des biomes (accordéon) ──────────────────────────
	var biomes_sec  := UIHelpers.collapsible_section(Translations.T("adv.section.biomes"), tcolor, true, host.panel_ui_state())
	host.rp_content.add_child(biomes_sec["wrapper"])
	var biomes_body := biomes_sec["body"] as VBoxContainer

	# Références partagées entre les closures pour l'accordéon
	var contents:     Dictionary = {}   # biome_id → VBoxContainer (détail)
	var arrows:       Dictionary = {}   # biome_id → Label (▶ / ▼)
	var biome_names:  Dictionary = {}   # biome_id → nom affiché (pour le bouton)
	var glows:        Dictionary = {}   # biome_id → SelectionGlow (liseré or)

	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != Enums.EntityType.BIOME:
			continue
		if not e.get("est_decouvert", false):
			continue
		var bid := eid
		biome_names[bid] = Translations.entity_name(e, bid).to_upper()

		var result  := _adv_biome_card(host, bid, e)
		var wrapper := result["wrapper"] as Control
		var panel   := result["panel"]   as Control
		var section := result["section"] as VBoxContainer
		var arrow   := result["arrow"]   as Label
		var glow    := result["glow"]    as SelectionGlow
		contents[bid] = section
		arrows[bid]   = arrow
		glows[bid]    = glow

		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton \
					and ev.button_index == MOUSE_BUTTON_LEFT \
					and ev.pressed):
				return
			var bname := biome_names.get(bid, bid) as String
			if bid == host.adv_selected_biome_id:
				section.visible = not section.visible
				arrow.text = "  ▼" if section.visible else "  ▶"
				glow.visible = section.visible
				if section.visible:
					# Ré-sélection : bouton actif.
					btn.text = Translations.T("adv.start_btn_named") % bname
					btn.visible = true
					placeholder.visible = false
				else:
					# Désélection : plus de biome choisi → bouton masqué, placeholder affiché.
					host.adv_selected_biome_id = ""
					btn.visible = false
					placeholder.visible = true
			else:
				if host.adv_selected_biome_id in contents \
						and is_instance_valid(contents[host.adv_selected_biome_id]):
					contents[host.adv_selected_biome_id].visible = false
					arrows[host.adv_selected_biome_id].text = "  ▶"
					(glows[host.adv_selected_biome_id] as SelectionGlow).visible = false
				host.adv_selected_biome_id = bid
				section.visible = true
				arrow.text = "  ▼"
				glow.visible = true
				btn.text = Translations.T("adv.start_btn_named") % bname
				placeholder.visible = false
				btn.visible = true
		)
		biomes_body.add_child(wrapper)

# Construit la carte accordéon d'un biome avec ses catégories (créatures, pièges, etc.).
# Retourne { wrapper, panel, section, arrow } pour que build() connecte le gui_input.
static func _adv_biome_card(host: Village, biome_id: String, biome: Dictionary) -> Dictionary:
	var btier := biome.get("maitrise_actuelle", 0) as int
	var bdisp := MasteryRegistry.get_mastery_display(biome_id)
	var pools := MasteryRegistry.get_biome_entity_pools(biome_id)

	# Pools filtrés par zone débloquée — partagés entre le compteur de
	# découverte et les lignes d'entités (un seul point de vérité).
	var creatures_p := _filter_pool_by_zone(pools["creatures"], btier)
	var traps_p     := _filter_pool_by_zone(pools["traps"], btier)
	var bless_p     := _filter_pool_by_zone(pools["benedictions"], btier)

	# XP courante / seuil pour la carte (0 si palier max → « RANG MAX »).
	var xp_cur := 0.0
	var xp_max := 0.0
	if not bdisp.is_empty() and not bdisp.get("at_max", false):
		xp_cur = float(bdisp.get("xp", 0.0))
		xp_max = float(bdisp.get("xp_max", 0.0))

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale via le template commun (nom | palier+XP CENTRÉ |
	# extras à droite — cf. UIHelpers.entity_xp_card) ──
	var built := UIHelpers.entity_xp_card(
			Translations.entity_name(biome, biome_id).to_upper(), btier, xp_cur, xp_max,
			"", Enums.EntityType.BIOME)
	var panel := built["card"] as XPCard
	var header := built["header"] as HBoxContainer
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(panel)
	wrapper.add_child(panel)

	# Surcouche de sélection : liseré or + luciole (AdventurePanel.build
	# la rend visible quand ce biome est le biome sélectionné).
	var glow := SelectionGlow.new()
	glow.visible = (host.adv_selected_biome_id == biome_id)
	panel.add_child(glow)

	# Tooltip du biome.
	var btooltip_body := _tooltip_zone_line(btier)
	var mech_id := biome.get("mecanique_forte_id", "") as String
	if mech_id != "":
		btooltip_body += "\n" + Translations.T("adv.mechanic_label") % _mech_name(mech_id)
	var ms := _next_biome_milestone(biome_id, biome)
	if not ms.is_empty():
		btooltip_body += "\n" + _milestone_text(ms)
	UIHelpers.register_tooltip(panel,
			Translations.entity_name(biome, biome_id),
			btooltip_body, UIColors.tier_color(btier),
			Translations.entity_lore(biome))

	# Compteur d'entités du biome, POOLS COMPLETS (toutes zones, boss
	# unique inclus) : le joueur voit qu'il reste des choses à découvrir
	# même derrière les zones verrouillées. Vert quand tout est trouvé.
	var full_pool: Array = (pools["creatures"] as Array) \
			+ (pools["traps"] as Array) + (pools["benedictions"] as Array)
	var disc_total := full_pool.size()
	var disc_found := MasteryRegistry.count_discovered(full_pool)
	var count_lbl := Label.new()
	count_lbl.text = Translations.T("adv.entities_count") % [disc_found, disc_total]
	count_lbl.add_theme_font_size_override("font_size", 10)
	count_lbl.add_theme_color_override("font_color",
			UIColors.LOG_VICTORY if disc_found >= disc_total else UIColors.TEXT_MUTED)
	header.add_child(count_lbl)

	# Flèche d'accordéon, à droite de l'en-tête du template.
	var arrow := Label.new()
	# Sélection ⇔ accordéon déplié : à la (re)construction, le biome déjà
	# sélectionné repart déplié (même invariant que le toggle au clic).
	var is_selected := host.adv_selected_biome_id == biome_id
	arrow.text = "  ▼" if is_selected else "  ▶"
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	header.add_child(arrow)

	# ── Section catégories (repliée par défaut, sauf biome sélectionné) ──
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = is_selected
	if MasterySystem.can_evolve(biome_id):
		wrapper.add_child(host.make_evolve_btn(biome_id,
				Translations.entity_name(biome, biome_id), Enums.EntityType.BIOME, btier))
	wrapper.add_child(section)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 12)
	indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(indent)

	var cat_vb := VBoxContainer.new()
	cat_vb.add_theme_constant_override("separation", 3)
	indent.add_child(cat_vb)

	# Prochain jalon de progression du biome (pill toujours visible dans l'accordéon).
	_adv_next_milestone_row(cat_vb, biome_id, biome)

	# Mécanique forte du biome (pill toujours visible dans l'accordéon).
	_adv_mechanic_row(cat_vb, biome)

	# Liste plate : la catégorie devient un préfixe coloré du nom de l'entité
	# (« Créature · Loup des cimes ») — gain de place et de clics par rapport
	# aux anciens sous-accordéons. Filtrage par zone débloquée inchangé.
	_adv_entity_rows(host, cat_vb, creatures_p,
			UIColors.TYPE_CREATURE, XPCard.Motif.PAWS, btier, Translations.T("adv.cat.creature"))
	_adv_entity_rows(host, cat_vb, traps_p,
			UIColors.TYPE_TRAP, XPCard.Motif.LIGHTNING, btier, Translations.T("adv.cat.trap"))
	_adv_entity_rows(host, cat_vb, bless_p,
			UIColors.TYPE_BENEDICTION, XPCard.Motif.CROSSES, btier, Translations.T("adv.cat.blessing"))
	_adv_resource_rows(cat_vb, biome)

	return {"wrapper": wrapper, "panel": panel, "section": section, "arrow": arrow, "glow": glow}

# Remplit parent avec une carte par entité DÉCOUVERTE du pool, même format
# pour tous les types. Les entités non découvertes n'apparaissent PAS (leur
# existence n'est trahie que par le compteur « Entités x/y » du header) :
# chaque nouvelle ligne est une récompense de découverte.
# `motif` = motif de particules de la barre d'XP (commun à toute la catégorie).
# `cat_label` = préfixe de catégorie affiché en couleur devant le nom.
static func _adv_entity_rows(host: Village, parent: VBoxContainer, pool: Array, color: Color, _motif: int = XPCard.Motif.BUBBLES, btier: int = 0, cat_label: String = "") -> void:
	for entry: Dictionary in pool:
		var entry_id := entry.get("id", "") as String
		if not MasteryRegistry.is_discovered(entry_id):
			continue

		var entity      := GameData.get_entity(entry_id)
		var bentry      := GameData.player.get("bestiary", {}).get(entry_id, {}) as Dictionary
		var is_equip: bool = entity.get("entity_type", "") == Enums.EntityType.EQUIPMENT
		var entity_tier := 0
		var entity_xp   := 0.0
		var at_max      := false
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

		# Nom AU PALIER COURANT (noms par palier) : seule l'entité vivante porte
		# les noms_par_palier_* ; le pool statique ne sert que de repli. Corrige
		# le « Loup des Cimes » figé alors que la créature est montée en rareté.
		var name_src := entity if not entity.is_empty() else entry
		var disp_name := Translations.entity_name_at(name_src, entity_tier)

		var ec      := UIColors.tier_color(entity_tier)
		var xp_need := 0
		if not at_max and not is_equip and entity_tier + 1 < GameData.xp_thresholds.size():
			xp_need = int(GameData.xp_thresholds[entity_tier + 1])

		# Carte XP UNIFIÉE — exactement la même DA que les biomes (palier + XP
		# CENTRÉS, fond rempli, motif choisi par type). Remplace l'ancien layout
		# maison où rareté et XP étaient alignés à droite.
		var xp_max_card := float(xp_need) if (not at_max and not is_equip and xp_need > 0) else 0.0
		var built  := UIHelpers.entity_xp_card(disp_name, entity_tier, entity_xp,
				xp_max_card, "", entity.get("entity_type", "") as String)
		var panel  := built["card"] as XPCard
		var header := built["header"] as HBoxContainer
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(panel)

		# Préfixe de catégorie (« Créature »…) en couleur, greffé à droite de
		# l'en-tête pour ne pas déséquilibrer le bloc central.
		if cat_label != "":
			var cat_lbl := Label.new()
			cat_lbl.text = cat_label
			cat_lbl.add_theme_font_size_override("font_size", 10)
			cat_lbl.add_theme_color_override("font_color",
					Color(color.r, color.g, color.b, 0.85))
			header.add_child(cat_lbl)

		# Tooltip de l'entité.
		UIHelpers.register_tooltip(panel, disp_name,
				_tooltip_entity_body(entry, entity, btier), ec,
				Translations.entity_lore(entity))

		if MasterySystem.can_evolve(entry_id):
			parent.add_child(host.make_evolve_btn(
					entry_id, disp_name,
					entity.get("entity_type", Enums.EntityType.CREATURE) as String,
					entity_tier))

# Lignes plates des ingrédients de biome — préfixe « Ingrédient · », nom
# (couleur tier), plage de quantité et chance de drop. Absentes tant que
# village_tier < 1 (Forge non débloquée) ; un ingrédient JAMAIS obtenu
# n'apparaît pas (même règle de révélation que les entités — la clé existe
# dans player.resources dès le premier drop, même retombé à 0 après forge).
static func _adv_resource_rows(parent: VBoxContainer, biome: Dictionary) -> void:
	# Les 2 ressources PROPRES du biome (Chantier 3) : la fréquente (taux fixe) et
	# la rare (taux croissant selon le palier de la créature tuée → une fourchette).
	# N'apparaissent qu'une fois OBTENUES (récompense de découverte, comme les
	# entités). Taux toujours lus dans Balance.DROP_* — jamais en dur ici.
	var rare_lo := roundi(Balance.rare_drop_rate(0) * 100.0)
	var rare_hi := roundi(Balance.rare_drop_rate(Balance.DROP_RARE_RATE_BY_TIER.size() - 1) * 100.0)
	var entries := [
		{"id": str(biome.get("ressource_frequente_id", "")),
			"rate": "%d%%" % roundi(Balance.DROP_FREQUENT_RATE * 100.0), "tier": 0},
		{"id": str(biome.get("ressource_rare_id", "")),
			"rate": "%d–%d%%" % [rare_lo, rare_hi], "tier": 2},
	]
	var nc := UIColors.CARD_NEUTRAL
	for entry: Dictionary in entries:
		var res_id: String = entry["id"]
		# Ressource non définie pour ce biome, ou pas encore obtenue → pas de ligne.
		if res_id == "" or not GameData.player["resources"].has(res_id):
			continue
		var res := GameData.get_entity(res_id)
		var ec := UIColors.tier_color(int(entry["tier"]))

		# Même gabarit visuel que les cartes d'entités (panneau fin + marge).
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.04, 0.30, 1, 3))
		parent.add_child(panel)

		var pm := UIHelpers.margin_of(4)
		panel.add_child(pm)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		pm.add_child(row)

		var cat_lbl := Label.new()
		cat_lbl.text = Translations.T("adv.cat.resource") + " · "
		cat_lbl.add_theme_font_size_override("font_size", 11)
		cat_lbl.add_theme_color_override("font_color", Color(nc.r, nc.g, nc.b, 0.85))
		row.add_child(cat_lbl)

		var icon := str(res.get("icon", ""))
		var name_lbl := Label.new()
		name_lbl.text = (icon + " " if icon != "" else "") + Translations.entity_name(res, res_id)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", ec)
		row.add_child(name_lbl)

		var rate_lbl := Label.new()
		rate_lbl.text = entry["rate"]
		rate_lbl.add_theme_font_size_override("font_size", 10)
		rate_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(rate_lbl)

# Affiche la mécanique forte du biome : pill colorée (active) ou verrouillée (tier < Rare).
# Rien si le biome n'a pas de mécanique définie.
static func _adv_mechanic_row(parent: VBoxContainer, biome: Dictionary) -> void:
	const MECH_COLORS: Dictionary = {
		"ambush":         Color(0.90, 0.35, 0.35),
		"poison":         Color(0.40, 0.80, 0.30),
		"endurcissement": Color(0.80, 0.55, 0.25),
	}
	var mech_id := biome.get("mecanique_forte_id", "") as String
	if mech_id == "" or not MECH_COLORS.has(mech_id):
		return

	var mname   := Translations.mech_name(mech_id)
	var mdesc   := Translations.mech_desc(mech_id)
	var mcolor  := MECH_COLORS[mech_id] as Color
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
			else (Translations.T("adv.mechanic_locked") % mname)
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", 11)
	text_lbl.add_theme_color_override("font_color", pill_color)
	hb.add_child(text_lbl)

	var mtooltip := mdesc if active else Translations.T("adv.mechanic_tt_locked")
	UIHelpers.register_tooltip(pill, Translations.T("adv.mechanic_tt_title") % mname, mtooltip, pill_color)

# ─── Prochain jalon de progression ────────────────────────────

# Premier palier futur du biome qui débloque quelque chose de notable.
# Retourne { "tier": int, "parts": PackedStringArray } ou {} si plus rien
# à venir (rang max, ou tout déjà obtenu). Les règles viennent de Balance /
# GameData — jamais dupliquées en littéraux ici.
static func _next_biome_milestone(biome_id: String, biome: Dictionary) -> Dictionary:
	var btier    := int(biome.get("maitrise_actuelle", 0))
	var max_tier := GameData.get_max_tier_for_type(Enums.EntityType.BIOME)
	for t in range(btier + 1, max_tier + 1):
		var parts := PackedStringArray()
		if t == Balance.EQUIPMENT_UNLOCK_BIOME_TIER:
			parts.append(Translations.T("adv.next.equipment"))
		if t in Balance.FRAGMENT_RELEASE_TIERS \
				and GameData.uncollected_fragment_for(biome_id) != "":
			parts.append(Translations.T("adv.next.fragment"))
		var mech_id := biome.get("mecanique_forte_id", "") as String
		if t == BiomeMechanics.UNLOCK_TIER and mech_id != "":
			parts.append(Translations.T("adv.next.mechanic") % Translations.mech_name(mech_id))
		if Balance.max_unlocked_zone(t) > Balance.max_unlocked_zone(t - 1):
			parts.append(Translations.T("adv.next.zone") % Translations.zone_name(Balance.max_unlocked_zone(t)))
		var secondary_id := biome.get("biome_secondaire_id", "") as String
		if t == Balance.SECONDARY_BIOME_REVEAL_TIER and secondary_id != "" \
				and not GameData.get_entity(secondary_id).get("est_decouvert", false):
			parts.append(Translations.T("adv.next.secondary"))
		if not parts.is_empty():
			return {"tier": t, "parts": parts}
	return {}

# Texte d'un jalon : « Prochain palier — Rare : libère un Fragment · … ».
static func _milestone_text(ms: Dictionary) -> String:
	var title := Translations.T("adv.next.title") % GameData.get_tier_name(int(ms["tier"]))
	return "%s : %s" % [title, " · ".join(ms["parts"] as PackedStringArray)]

# Pill « Prochain palier » : annonce ce que le prochain jalon du biome
# débloque (Fragment, mécanique, zone, équipement, biome secondaire).
static func _adv_next_milestone_row(parent: VBoxContainer, biome_id: String, biome: Dictionary) -> void:
	var ms := _next_biome_milestone(biome_id, biome)
	if ms.is_empty():
		return
	var tcolor := UIColors.tier_color(int(ms["tier"]))

	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill.add_theme_stylebox_override("panel", UIHelpers.card_style(tcolor, 0.06, 0.45, 1, 3))
	parent.add_child(pill)

	var m := UIHelpers.margin_of(5)
	pill.add_child(m)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	m.add_child(hb)

	# Icône « ! » dans un cercle : signale un déblocage à venir, plus
	# parlant qu'un simple triangle.
	var icon := PanelContainer.new()
	var ist  := StyleBoxFlat.new()
	ist.bg_color     = Color(tcolor, 0.14)
	ist.border_color = tcolor
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(8)   # rond pour une taille de 16 px
	icon.add_theme_stylebox_override("panel", ist)
	icon.custom_minimum_size  = Vector2(16, 16)
	icon.size_flags_vertical  = Control.SIZE_SHRINK_BEGIN
	var bang := Label.new()
	bang.text = "!"
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bang.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bang.add_theme_font_size_override("font_size", 10)
	bang.add_theme_color_override("font_color", tcolor)
	icon.add_child(bang)
	hb.add_child(icon)

	var text_lbl := Label.new()
	text_lbl.text = _milestone_text(ms)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", 11)
	text_lbl.add_theme_color_override("font_color", tcolor)
	hb.add_child(text_lbl)

	UIHelpers.register_tooltip(pill,
			Translations.T("adv.next.title") % GameData.get_tier_name(int(ms["tier"])),
			Translations.T("adv.next.tt"), tcolor)

# ─── Helpers tooltip ──────────────────────────────────────────

static func _mech_name(mech_id: String) -> String:
	return Translations.mech_name(mech_id)

# Ligne "Zone max : Surface / Profondeur / Abysse" selon le tier du biome.
static func _tooltip_zone_line(btier: int) -> String:
	var zone_max := Balance.max_unlocked_zone(btier)
	return Translations.T("adv.zone_max") % Translations.zone_name(zone_max)

# Corps de tooltip pour une entité (créature, piège, bénédiction, ingrédient).
static func _tooltip_entity_body(entry: Dictionary, entity: Dictionary, btier: int = 0) -> String:
	var etype    := entity.get("entity_type", "") as String
	var tier     := int(entity.get("maitrise_actuelle", 0))
	var _zone_max := Balance.max_unlocked_zone(btier)
	match etype:
		Enums.EntityType.CREATURE:
			var z    := int(entry.get("zone_associee", 0))
			return Translations.T("adv.creature.tt") % [Translations.zone_name(z), GameData.get_tier_name(tier)]
		Enums.EntityType.TRAP:
			return Translations.T("adv.trap.dmg_zones") + Translations.T("adv.trap.mastery_note")
		Enums.EntityType.BENEDICTION:
			return Translations.T("adv.bless.desc")
		Enums.EntityType.INGREDIENT:
			var biome_id := entity.get("biome_source_id", "") as String
			var biome_e  := GameData.get_entity(biome_id)
			var bname    := Translations.entity_name(biome_e, biome_id)
			var qty      := int(GameData.player["resources"].get(entity.get("id", ""), 0))
			return Translations.T("adv.ingr.tooltip") % [bname, qty]
		_:
			return Translations.T("hero.passive.tt_mastery") % GameData.get_tier_name(tier)

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
