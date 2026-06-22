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

	var sec := UIHelpers.collapsible_section(icon + "  " + nom.to_upper(), ec, true,
			host.panel_ui_state(), equip_id)
	host.rp_content.add_child(sec["wrapper"])
	var body := sec["body"] as VBoxContainer
	body.add_theme_constant_override("separation", 6)

	# Carte XP / palier
	var built := UIHelpers.entity_xp_card(nom, tier, xp_cur,
			0.0 if at_max else xp_nxt, icon, Enums.EntityType.EQUIPMENT)
	(built["card"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(built["card"])

	# Points de Forge
	var pts := ForgeSystem.points(equip_id)
	var pts_lbl := Label.new()
	pts_lbl.text = Translations.T("forge.points") % pts
	pts_lbl.add_theme_font_size_override("font_size", 12)
	pts_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
	body.add_child(pts_lbl)

	# Bouton d'évolution (rituel) si prêt
	if not at_max and ForgeSystem.can_evolve_equipment(equip_id):
		var nc  := UIColors.tier_color(tier + 1)
		var ebtn := UIHelpers.evolve_button("▲  " + Translations.T("forge.evolve_btn"), nc, 12)
		ebtn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ebtn.custom_minimum_size = Vector2(220.0, 28.0)
		ebtn.pressed.connect(func() -> void:
			var nt := ForgeSystem.evolve_equipment(equip_id)
			if nt >= 0:
				host.launch_evolution_ritual(Enums.EntityType.EQUIPMENT, equip_id, nom, nt - 1, nt)
		)
		body.add_child(ebtn)
	elif at_max:
		var maxl := Label.new()
		maxl.text = Translations.T("forge.equip.max_rank")
		maxl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		maxl.add_theme_font_size_override("font_size", 11)
		maxl.add_theme_color_override("font_color", UIColors.TIER_LEGENDAIRE)
		body.add_child(maxl)

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
		tree_btn.tooltip_text = Translations.T("forge.tree_locked")
	else:
		tree_btn.pressed.connect(func() -> void:
			var overlay := ForgeTreeOverlay.new()
			overlay.equipment_id = equip_id
			host.add_child(overlay)
		)
	body.add_child(tree_btn)

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
	var title_lbl := Label.new()
	title_lbl.text = Translations.T("forge.locked.title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	vb.add_child(title_lbl)
	var hint := Label.new()
	hint.text = Translations.T("forge.locked.hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
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
	var lbl := Label.new()
	lbl.text = Translations.T("forge.equip.locked") \
			% [Translations.entity_name(equip, equip_id), biome_name, tier_name]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	m.add_child(lbl)
	return card
