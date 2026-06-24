# ============================================================
# ForgePanel — Panneau Forge (Chantier 5).
#
# La Forge gère l'équipement par la MAÎTRISE (XP, sans ingrédient) + un ARBRE de
# nœuds (points de Forge). Ce panneau montre, par équipement débloqué : sa carte
# d'XP/palier, ses points de Forge, le bouton d'évolution (rituel) si prêt, et
# l'accès à l'arbre spatial (ForgeTreeOverlay).
#
# Verrouillé tant que le Village n'est pas Peu Commun (T1) — cf. hub Forge.
# ============================================================
class_name ForgePanel

# Équipements VS (ordre d'affichage) : id → icône de slot.
const EQUIPS: Array = [
	["equipment_arme",   "⚔"],
	["equipment_anneau", "💍"],
	["equipment_armure", "🛡"],
]

static func build(host: Village) -> void:
	if int(GameData.village.get("maitrise_actuelle", 0)) < 1:
		_build_locked(host)
		return
	# Route du quartier Forge (tout en haut) : reconstruire fait apparaître le
	# chemin vers le quartier de gestion (forgeron/armurier/joaillier/couturier).
	BuildingPanel.build_route_section(host, "forge")
	for e in EQUIPS:
		_build_equip_section(host, e[0] as String, e[1] as String)

# ─── Section par équipement ──────────────────────────────────

static func _build_equip_section(host: Village, equip_id: String, icon: String) -> void:
	var equip := GameData.get_entity(equip_id)
	if equip.is_empty():
		return
	if not equip.get("est_debloque", false):
		host.rp_content.add_child(_locked_equip_card(equip, equip_id))
		return

	var tier   := int(equip.get("maitrise_actuelle", 0))
	var ec     := UIColors.tier_color(tier)
	var at_max := tier >= GameData.get_max_tier_for_type(Enums.EntityType.EQUIPMENT)
	var nom    := Translations.entity_name(equip, equip_id)
	var xp_cur := float(equip.get("xp_maitrise_actuelle", 0.0))
	var xp_nxt := ForgeSystem.effective_evolve_cost(equip_id)
	var pts    := ForgeSystem.points(equip_id)
	var can_evolve := not at_max and ForgeSystem.can_evolve_equipment(equip_id)
	var frac := 1.0 if at_max else (clampf(xp_cur / xp_nxt, 0.0, 1.0) if xp_nxt > 0.0 else 0.0)

	# Carte UNIQUE englobant nom + palier + XP + points de Forge + indication
	# d'évolution. Cliquable : évolue l'équipement quand il est prêt (le clic
	# remplace l'ancien bouton ÉVOLUER). Fond rempli par la progression d'XP.
	var card := UIHelpers.xp_panel(ec, frac, 0.08, 0.60, 1, 6, XPCard.motif_for_type(Enums.EntityType.EQUIPMENT))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.rp_content.add_child(card)

	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le clic passe à la carte
	m.add_child(vb)

	# Ligne 1 : icône + nom (gauche) · palier (droite).
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row1)
	var name_lbl := UIHelpers.label(icon + "  " + nom.to_upper(), 14, ec.lerp(Color.WHITE, 0.25))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(name_lbl)
	row1.add_child(UIHelpers.label(GameData.get_tier_name(tier), 11, ec))

	# Ligne 2 (sous le nom) : points de Forge (gauche) · XP / coût ou Rang Max (droite).
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row2)
	var pts_lbl := UIHelpers.label(Translations.T("forge.points") % pts, 11, UIColors.FILTER_ON)
	pts_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pts_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.add_child(pts_lbl)
	if at_max:
		row2.add_child(UIHelpers.label(Translations.T("forge.equip.max_rank"), 10, UIColors.TIER_LEGENDAIRE))
	else:
		row2.add_child(UIHelpers.label("XP  %s / %s" % [UIHelpers.xp_fmt(int(xp_cur)), UIHelpers.xp_fmt(int(xp_nxt))],
				10, UIColors.TEXT_MUTED))

	# Ligne 3 : indication « cliquer pour évoluer » quand l'équipement est prêt.
	if can_evolve:
		var nc := UIColors.tier_color(tier + 1)
		var hint := UIHelpers.label("▲  " + Translations.T("forge.evolve_btn"), 12, nc.lerp(Color.WHITE, 0.20))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hint)

		# Carte cliquable → lance le rituel d'évolution de l'équipement.
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UIHelpers.add_hover_feedback(card)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton \
					and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
				return
			var nt := ForgeSystem.evolve_equipment(equip_id)
			if nt >= 0:
				host.launch_evolution_ritual(Enums.EntityType.EQUIPMENT, equip_id, nom, nt - 1, nt)
		)

	# Accès à l'arbre (spatial) — actif dès l'activation de l'arbre (équip. T1).
	var tree_btn := Button.new()
	tree_btn.text = Translations.T("forge.open_tree")
	tree_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tree_btn.add_theme_font_size_override("font_size", 12)
	tree_btn.add_theme_color_override("font_color", ec.lerp(Color.WHITE, 0.25))
	tree_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(ec, 0.08, 0.45, 1, 5))
	tree_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(ec, 0.20, 0.90, 2, 5))
	if tier < 1:
		tree_btn.disabled = true
		# Tooltip JRPG du jeu (TooltipOverlay) plutôt que l'infobulle native de Godot,
		# qui jure avec la DA. mouse_filter STOP : un Button désactivé n'émet plus de
		# survol, donc le tooltip ne se déclencherait pas sans ça.
		tree_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		UIHelpers.register_tooltip(tree_btn, Translations.T("forge.open_tree"),
				Translations.T("forge.tree_locked"), ec)
	else:
		tree_btn.pressed.connect(func() -> void:
			var overlay := ForgeTreeOverlay.new()
			overlay.equipment_id = equip_id
			host.add_child(overlay)
		)
	host.rp_content.add_child(tree_btn)

# ─── États verrouillés ───────────────────────────────────────

static func _build_locked(host: Village) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 8))
	var m := UIHelpers.margin_of(24)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)
	var icon_lbl := Label.new()
	icon_lbl.text = "🔨"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 36)
	vb.add_child(icon_lbl)
	var title_lbl := UIHelpers.label(Translations.T("forge.locked.title"), 14, UIColors.TEXT_HEADER)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_lbl)
	var hint := UIHelpers.label(Translations.T("forge.locked.hint"), 11, UIColors.TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	host.rp_content.add_child(card)

# Formate des stats d'équipement en string (réutilisé par HeroDoll pour ses tooltips).
static func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	if int(stats.get("atk", 0)) != 0:              parts.append(Translations.T("hero.stat.atk") + " +%d" % int(stats["atk"]))
	if int(stats.get("def", 0)) != 0:              parts.append(Translations.T("hero.stat.def") + " +%d" % int(stats["def"]))
	if int(stats.get("hp", 0)) != 0:               parts.append(Translations.T("hero.stat.hp")  + " +%d" % int(stats["hp"]))
	if int(stats.get("attack_speed_pct", 0)) != 0: parts.append("VIT +%d%%" % int(stats["attack_speed_pct"]))
	return "  ".join(parts)

static func _locked_equip_card(equip: Dictionary, equip_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 4))
	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var biome      := GameData.get_entity(str(equip.get("biome_source_id", "")))
	var biome_name := Translations.entity_name(biome, str(equip.get("biome_source_id", "")))
	var tier_name  := GameData.get_tier_name(Balance.EQUIPMENT_UNLOCK_BIOME_TIER)
	var lbl := UIHelpers.label(Translations.T("forge.equip.locked") \
			% [Translations.entity_name(equip, equip_id), biome_name, tier_name], 12, UIColors.TEXT_MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(lbl)
	return card
