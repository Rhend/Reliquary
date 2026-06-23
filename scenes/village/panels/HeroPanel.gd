# ============================================================
# HeroPanel — Contenu du panneau glissant « Héros » du Village.
#
# Construit dans host.rp_content : nom + palier, barre XP, statistiques
# (base + bonus), bouton d'évolution, et cartes de passifs dépliables
# (standard + uniques débloqués). Module sans état (fonctions statiques) ;
# host = nœud Village (accès rp_content, make_evolve_btn).
# ============================================================
class_name HeroPanel

const EQUIP_SLOTS: Array = [
	["arme",   "⚔",  "equipment_arme",   "Arme"  ],
	["anneau", "💍",  "equipment_anneau", "Anneau"],
	["armure", "🛡",  "equipment_armure", "Armure"],
]

# Biome où chaque slot livre son équipement (B7 — placeholder informatif).
# Arme → Montagne · Armure → Marécage · Anneau → Forêt.
const SLOT_BIOME: Dictionary = {
	"arme":   "biome_montagne",
	"armure": "biome_marecage",
	"anneau": "biome_foret",
}

# Point d'entrée : peuple host.rp_content avec la fiche du héros actif.
static func build(host: Village) -> void:
	var c        := GameData.get_entity("hero")
	var tier     := c.get("maitrise_actuelle", 0) as int
	var hero_max := GameData.get_max_tier_for_type(c.get("entity_type", Enums.EntityType.HERO) as String)
	var xp     := c.get("xp_maitrise_actuelle",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xpmax  := float(GameData.xp_thresholds[ni])
	var can_ev := tier < hero_max and xp >= xpmax
	var tcolor := UIColors.tier_color(tier)

	# ── Route du quartier Héros (tout en haut du panneau) ─────
	# Reconstruire la route fait apparaître le chemin vers le quartier de gestion.
	BuildingPanel.build_route_section(host, "hero")

	# ── Bonhomme d'équipement : 6 slots anatomiques ───────────
	# Tout en haut, avant la barre d'XP et les Statistiques.
	host.rp_content.add_child(HeroDoll.new())

	# ── Carte d'identité + XP (DA commune — UIHelpers.entity_xp_card) ──
	# Palier max → xp_max = 0 → la carte affiche « RANG MAX ».
	var hero_xp_max := xpmax
	if tier >= hero_max:
		hero_xp_max = 0.0
	var id_card := UIHelpers.entity_xp_card(
			Translations.entity_name(c), tier, xp, hero_xp_max,
			"", c.get("entity_type", Enums.EntityType.HERO) as String)
	host.rp_content.add_child(id_card["card"] as Control)

	# ── STATISTIQUES ──────────────────────────────────────────
	var stats_sec := UIHelpers.collapsible_section(Translations.T("hero.section.stats"), tcolor, true, host.panel_ui_state())
	host.rp_content.add_child(stats_sec["wrapper"])
	var stats_body := stats_sec["body"] as VBoxContainer

	var eq  := GameData.get_equipment_bonuses()
	var eff := GameData.get_effective_stats("hero")
	var pas := PassiveSystem.get_combat_bonuses()

	var atk_base  := int(eff.get("atk", 0))
	var atk_bonus := int(eq.get("atk", 0)) + int(pas.get("atk_bonus", 0))
	var def_base  := int(eff.get("def", 0))
	var def_bonus := int(eq.get("def", 0)) + int(pas.get("def_bonus", 0))
	var hp_base   := int(eff.get("hp", 0))
	var hp_bonus  := int(eq.get("hp", 0)) + int(pas.get("hp_bonus", 0))
	# VIT effective via StatStacker (même point d'application que le combat).
	var vit_base  := int(eff.get("vit", 20))
	var vit_bonus := int(round(StatStacker.final_stat(float(vit_base),
			[float(eq.get("attack_speed_pct", 0.0)) / 100.0], "vit") - float(vit_base)))

	# Crit du héros : chance de base (.tres) + bonus Village/Forge (même point
	# d'application qu'au combat, cf. combat_player v_crit_pct).
	var crit_base  := float(c.get("crit_chance", Balance.CRIT_CHANCE))
	var crit_bonus := VillageBuildings.get_bonus(VillageBuildings.CH_CRIT_PCT) \
			+ ForgeSystem.get_stat_bonus("crit_pct")
	var crit_total := maxf(crit_base + crit_bonus, 0.0)
	var crit_mult  := float(c.get("crit_multiplier", Balance.CRIT_MULTIPLIER))

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_body.add_child(stats_row)

	for row: Array in [
		["atk", Translations.T("hero.stat.atk"), atk_base + atk_bonus, atk_base, atk_bonus, UIColors.STAT_ATK],
		["def", Translations.T("hero.stat.def"), def_base + def_bonus, def_base, def_bonus, UIColors.STAT_DEF],
		["hp",  Translations.T("hero.stat.hp"),  hp_base  + hp_bonus,  hp_base,  hp_bonus,  UIColors.STAT_HP ],
		["vit", Translations.T("hero.stat.vit"), vit_base + vit_bonus, vit_base, vit_bonus, UIColors.FILTER_ON],
	]:
		var grp := HBoxContainer.new()
		grp.add_theme_constant_override("separation", 4)
		stats_row.add_child(grp)
		var kl := Label.new()
		kl.text = str(row[1]) + " :"
		kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		grp.add_child(kl)
		grp.add_child(UIHelpers.label(str(row[2]), 14, row[5]))
		grp.add_child(UIHelpers.label("(%d + %d)" % [row[3], row[4]], 10, UIColors.TEXT_MUTED))
		# Tooltip d'impact concret par stat (C6).
		var tt := _stat_tooltip_body(str(row[0]), int(row[2]), crit_mult)
		if tt != "":
			_attach_stat_tooltip(grp, str(row[1]), tt, row[5] as Color)

	# CRIT : stat en % (B4a) + tooltip d'impact sur le DPS moyen.
	var crit_grp := HBoxContainer.new()
	crit_grp.add_theme_constant_override("separation", 4)
	stats_row.add_child(crit_grp)
	var crit_kl := Label.new()
	crit_kl.text = Translations.T("hero.stat.crit") + " :"
	crit_kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	crit_grp.add_child(crit_kl)
	crit_grp.add_child(UIHelpers.label("%d%%" % int(round(crit_total * 100.0)), 14, UIColors.TIER_EPIQUE))
	# DPS moyen ×(1 + chance × (mult − 1)) → bonus moyen en %.
	var crit_dps := int(round(crit_total * (crit_mult - 1.0) * 100.0))
	_attach_stat_tooltip(crit_grp, Translations.T("hero.stat.crit"),
			Translations.T("hero.stat.crit_tt") % [int(round(crit_total * 100.0)), "%.1f" % crit_mult, crit_dps],
			UIColors.TIER_EPIQUE)

	if tier < hero_max:
		if can_ev:
			stats_body.add_child(host.make_evolve_btn(
				"hero", Translations.entity_name(c, "hero"),
				c.get("entity_type", Enums.EntityType.CREATURE) as String, tier))
	else:
		var ml := UIHelpers.label(Translations.T("tier.max_level"), 11, UIColors.FILTER_ON)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_body.add_child(ml)

	# ── ÉQUIPEMENT (B7) ───────────────────────────────────────
	# Les 3 slots sont TOUJOURS affichés. Tant que l'équipement n'est pas livré
	# (est_debloque faux), un PLACEHOLDER indique dans quel biome aller le chercher.
	var equip_sec := UIHelpers.collapsible_section(Translations.T("hero.section.equip"), tcolor, true, host.panel_ui_state())
	host.rp_content.add_child(equip_sec["wrapper"])
	var equip_body := equip_sec["body"] as VBoxContainer
	for entry in EQUIP_SLOTS:
		var slot_key:  String = entry[0]
		var slot_icon: String = entry[1]
		var equip_id:  String = entry[2]
		var slot_name: String = Translations.equip_slot_name(slot_key)
		var equip := GameData.get_entity(equip_id)
		if not equip.is_empty() and equip.get("est_debloque", false):
			equip_body.add_child(_equip_slot_card(host, slot_key, slot_icon,
					slot_name, equip_id, equip, tcolor))
		else:
			equip_body.add_child(_equip_placeholder_card(slot_icon, slot_name,
					SLOT_BIOME.get(slot_key, "") as String))

	# ── PASSIFS ───────────────────────────────────────────────
	# Même règle que l'Équipement : la section n'apparaît qu'avec son
	# premier passif débloqué.
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
		if e.get("entity_type", "") != Enums.EntityType.PASSIF_UNIQUE:
			continue
		if not (e.get("est_debloque", false) as bool):
			continue
		cards.append(_passive_card(host, _normalize_unique_passive(eid, e), tcolor))

	if not cards.is_empty():
		var passif_sec := UIHelpers.collapsible_section(Translations.T("hero.section.passives"), tcolor, true, host.panel_ui_state())
		host.rp_content.add_child(passif_sec["wrapper"])
		var passif_body := passif_sec["body"] as VBoxContainer
		for card in cards:
			passif_body.add_child(card)

	# ── INGRÉDIENTS (masqué si Village < T1) ─────────────────
	if (GameData.village.get("maitrise_actuelle", 0) as int) >= 1:
		_build_ingredients(host, tcolor)

# ═══ Inventaire d'ingrédients ═══════════════════════════════
# L'inventaire complet vit ICI (la Forge ne montre que les recettes).
# Affichage compact : chips groupées par biome dans un HFlowContainer
# (retour à la ligne automatique → 3-4 ingrédients par ligne au lieu
# d'une ligne chacun). Quantité en vert, uniques marqués ✦ or, détail
# (provenance + lore) dans le tooltip.
static func _build_ingredients(host: Village, tcolor: Color) -> void:
	# Groupage par biome source (seulement les ingrédients possédés).
	# Section ABSENTE tant que l'inventaire est vide (règle générale :
	# pas de coquille vide, l'apparition signale le premier drop).
	var by_biome: Dictionary = {}
	for eid in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != Enums.EntityType.INGREDIENT:
			continue
		var qty := int(GameData.player["resources"].get(eid, 0))
		if qty <= 0:
			continue
		var src := e.get("biome_source_id", "") as String
		if not by_biome.has(src):
			by_biome[src] = []
		(by_biome[src] as Array).append({"e": e, "qty": qty})
	if by_biome.is_empty():
		return

	var ingr_sec := UIHelpers.collapsible_section(Translations.T("hero.section.ingredients"), tcolor, true, host.panel_ui_state())
	ingr_sec["wrapper"].name = "IngredientsSection"
	host.rp_content.add_child(ingr_sec["wrapper"])
	var body := ingr_sec["body"] as VBoxContainer
	body.add_theme_constant_override("separation", 4)

	# Biomes connus d'abord (ordre canonique), inconnus ensuite.
	const BIOME_ORDER := ["biome_montagne", "biome_foret", "biome_marecage"]
	var ordered: Array = []
	for b in BIOME_ORDER:
		if by_biome.has(b):
			ordered.append(b)
	for b in by_biome:
		if b not in ordered:
			ordered.append(b)

	for src: String in ordered:
		var biome_e := GameData.get_entity(src)
		var bname   := Translations.entity_name(biome_e, src) if not biome_e.is_empty() else src
		var btier   := int(biome_e.get("maitrise_actuelle", 0)) if not biome_e.is_empty() else 0
		var bc      := UIColors.tier_color(btier)
		body.add_child(_biome_header(bname, bc))

		# Uniques en dernier, puis alphabétique : balayage régulier.
		var items := by_biome[src] as Array
		items.sort_custom(func(a, b):
			var ua := a["e"].get("est_unique", false) as bool
			var ub := b["e"].get("est_unique", false) as bool
			if ua != ub: return int(ua) < int(ub)
			return Translations.entity_name(a["e"], "") < Translations.entity_name(b["e"], "")
		)

		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(flow)
		for item in items:
			flow.add_child(_ingredient_chip(item["e"] as Dictionary,
					int(item["qty"]), bname, bc))

# Fine ligne « ── NOM DU BIOME ─────── » aux couleurs du tier du biome.
static func _biome_header(bname: String, bc: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var line1 := ColorRect.new()
	line1.custom_minimum_size = Vector2(14, 1)
	line1.color               = Color(bc, 0.55)
	line1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(line1)
	hb.add_child(UIHelpers.label(bname.to_upper(), 10, Color(bc, 0.85)))
	var line2 := ColorRect.new()
	line2.custom_minimum_size   = Vector2(0, 1)
	line2.color                 = Color(bc, 0.30)
	line2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	hb.add_child(line2)
	return hb

# Chip « Nom ×N » : pilule compacte aux couleurs du biome.
static func _ingredient_chip(e: Dictionary, qty: int, bname: String, bc: Color) -> Control:
	var is_unique := e.get("est_unique", false) as bool
	var nom       := Translations.entity_name(e)

	var chip := PanelContainer.new()
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.TIER_LEGENDAIRE if is_unique else bc,
					0.08, 0.35, 1, 9))

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   8)
	m.add_theme_constant_override("margin_right",  8)
	m.add_theme_constant_override("margin_top",    3)
	m.add_theme_constant_override("margin_bottom", 3)
	chip.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	m.add_child(row)

	if is_unique:
		row.add_child(UIHelpers.label("✦", 10, UIColors.TIER_LEGENDAIRE))

	row.add_child(UIHelpers.label(nom, 11,
			UIColors.TIER_LEGENDAIRE if is_unique else UIColors.TEXT_HEADER))
	row.add_child(UIHelpers.label("×%d" % qty, 12, UIColors.FILTER_ON))

	UIHelpers.add_hover_feedback(chip)
	var tt := Translations.T("forge.ingr.tt_stock") % [bname, qty]
	if is_unique:
		tt += "\n✦ " + Translations.T("forge.ingr.unique")
	UIHelpers.register_tooltip(chip, nom, tt,
			UIColors.TIER_LEGENDAIRE if is_unique else bc,
			Translations.entity_lore(e))
	return chip


# Convertit un passif unique vers la forme attendue par _passive_card
# (champs name localisé / maitrise_actuelle / xp_maitrise_actuelle).
static func _normalize_unique_passive(eid: String, e: Dictionary) -> Dictionary:
	return {
		"id":           eid,
		"name":         Translations.entity_name(e, eid),
		"maitrise_actuelle": int(e.get("maitrise_actuelle", 0)),
		"xp_maitrise_actuelle":   float(e.get("xp_maitrise_actuelle", 0.0)),
		"tier_effects": e.get("tier_effects", []),
		"entity_type":  Enums.EntityType.PASSIF_UNIQUE,
	}

# Retourne une carte dépliable pour un passif : en-tête (nom | palier | XP),
# corps avec effet courant + cascade des paliers à débloquer.
static func _passive_card(host: Village, pdata: Dictionary, _tcolor: Color) -> Control:
	var rarity   := pdata.get("maitrise_actuelle", 0) as int
	var pass_max := GameData.get_max_tier_for_type(pdata.get("entity_type", Enums.EntityType.PASSIVE) as String)
	var has_evos := rarity < pass_max
	var xp_cur   := pdata.get("xp_maitrise_actuelle", 0.0) as float
	var name_txt := Translations.entity_name(pdata, pdata.get("id", "?") as String)

	# Seuil du palier suivant (0 si plus d'évolution → carte « RANG MAX »).
	var xp_max := 0.0
	if has_evos and rarity + 1 < GameData.xp_thresholds.size():
		xp_max = float(GameData.xp_thresholds[rarity + 1])

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale via le template commun (nom | palier | XP) ──
	var built := UIHelpers.entity_xp_card(name_txt, rarity, xp_cur, xp_max,
			"", pdata.get("entity_type", Enums.EntityType.PASSIVE) as String)
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
		wrapper.add_child(host.make_evolve_btn(pid_ev,
				Translations.entity_name(pdata, pid_ev),
				pdata.get("entity_type", Enums.EntityType.PASSIVE) as String, rarity))

	# ── Corps déplié (toggle) : effet courant + cascade à débloquer ──
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.visible = false
	wrapper.add_child(body)

	# Description de l'effet au palier actuel
	for effect in _tier_effects(pdata, rarity):
		var desc := Translations.effect_desc(effect)
		if desc.is_empty():
			continue
		var eff_lbl := UIHelpers.label(desc, 10, UIColors.TEXT_MUTED)
		eff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(eff_lbl)

	# Cascade des paliers non encore atteints
	if has_evos:
		var unlock_hdr := UIHelpers.label(Translations.T("hero.passive.unlock_hdr"), 9, UIColors.TEXT_MUTED)
		unlock_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(unlock_hdr)

		for t in range(rarity + 1, pass_max + 1):
			body.add_child(_evo_row(t, rarity, pdata))

	# Toggle uniquement si le corps a du contenu à révéler
	if body.get_child_count() > 0:
		arrow.text = "  ▶"
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UIHelpers.add_hover_feedback(panel)
		# Tooltip passif.
		var eff_list := pdata.get("effets_par_palier", pdata.get("effet_par_palier", {})) as Dictionary
		var cur_eff  := str(eff_list.get(str(rarity), "")) as String
		var tt_body  := Translations.T("hero.passive.tt_mastery") % GameData.get_tier_name(rarity)
		if cur_eff != "":
			tt_body += Translations.T("hero.passive.tt_effect") % cur_eff
		UIHelpers.register_tooltip(panel, name_txt, tt_body, UIColors.tier_color(rarity),
				Translations.entity_lore(pdata))
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
	var is_max  : bool  = t >= GameData.get_max_tier_for_type(pdata.get("entity_type", Enums.EntityType.PASSIVE) as String)
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

	var name_lbl := UIHelpers.label("→  " + tn, 11, tc)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_lbl)

	var xp_lbl := UIHelpers.label(
			Translations.T("tier.max_rank") if is_max else "%s / %s XP" % [UIHelpers.xp_fmt(int(xp_cur)), UIHelpers.xp_fmt(xp_need)],
			9, tc if is_max else UIColors.TEXT_MUTED)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(xp_lbl)

	# Effets du palier
	for effect in _tier_effects(pdata, t):
		var desc := Translations.effect_desc(effect)
		if desc.is_empty(): continue
		var eff_lbl := UIHelpers.label(desc, 9, tc.darkened(0.2))
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(eff_lbl)

	return margin

# Corps du tooltip d'impact d'une stat (C6 — HP/VIT/ATK/DEF), "" si aucun.
static func _stat_tooltip_body(key: String, total: int, crit_mult: float) -> String:
	match key:
		"atk":
			# Fourchette de dégâts par coup : normal (ATK) → critique (ATK × mult).
			return Translations.T("hero.stat.atk_tt") % [total, int(round(float(total) * crit_mult))]
		"def":
			# % de dégâts absorbés (courbe verrouillée, fonction pure réutilisée).
			return Translations.T("hero.stat.def_tt") % int(round(Balance.def_reduction(float(total)) * 100.0))
		"hp":
			return Translations.T("hero.stat.hp_tt")
		"vit":
			# Cadence d'attaque : frappes/s = vit / VIT_PER_APS.
			return Translations.T("hero.stat.vit_tt") % ("%.1f" % (float(total) / Balance.VIT_PER_APS))
	return ""

# Branche un tooltip d'impact sur un groupe de stat : les labels enfants laissent
# passer le survol (IGNORE) pour que le conteneur reçoive mouse_entered/exited.
static func _attach_stat_tooltip(grp: Control, title: String, body: String, color: Color) -> void:
	grp.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in grp.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIHelpers.register_tooltip(grp, title, body, color)

# Placeholder d'un slot dont l'équipement n'est pas encore livré (B7) : carte
# grisée avec icône + slot + « À débloquer », tooltip indiquant le biome source.
static func _equip_placeholder_card(slot_icon: String, slot_name: String, biome_id: String) -> Control:
	var card := PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.03, 0.18, 1, 6))
	var m := UIHelpers.margin_of(8)
	card.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	m.add_child(row)

	var icon := Label.new()
	icon.text = slot_icon
	icon.modulate = Color(1, 1, 1, 0.45)
	icon.add_theme_font_size_override("font_size", 16)
	row.add_child(icon)

	var sl := UIHelpers.label(slot_name, 12, UIColors.TEXT_MUTED)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)

	row.add_child(UIHelpers.label("🔒 " + Translations.T("hero.equip.placeholder"), 11, UIColors.TEXT_MUTED))

	var biome := GameData.get_entity(biome_id)
	var bname := Translations.entity_name(biome, biome_id) if not biome.is_empty() else biome_id
	var bc := UIColors.tier_color(int(biome.get("maitrise_actuelle", 0))) if not biome.is_empty() else UIColors.TEXT_MUTED
	UIHelpers.add_hover_feedback(card)
	UIHelpers.register_tooltip(card, slot_name,
			Translations.T("hero.equip.placeholder_tt") % bname, bc)
	return card

# Carte d'équipement — DA commune entity_xp_card (même pattern que passifs/biomes).
static func _equip_slot_card(_host: Village, _slot_key: String, slot_icon: String,
		slot_name: String, equip_id: String, equip: Dictionary, _tcolor: Color) -> Control:
	var etier    := int(equip.get("maitrise_actuelle", 0))
	var enom     := Translations.entity_name(equip, equip_id)
	var ec       := UIColors.tier_color(etier)
	var at_max   := etier >= GameData.get_max_tier_for_type(Enums.EntityType.EQUIPMENT)
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
	if int(stats_at.get("atk", 0)) != 0:              stat_parts.append(Translations.T("hero.stat.atk") + " +%d" % int(stats_at["atk"]))
	if int(stats_at.get("def", 0)) != 0:              stat_parts.append(Translations.T("hero.stat.def") + " +%d" % int(stats_at["def"]))
	if int(stats_at.get("hp", 0)) != 0:               stat_parts.append(Translations.T("hero.stat.hp") + " +%d" % int(stats_at["hp"]))
	if int(stats_at.get("attack_speed_pct", 0)) != 0: stat_parts.append("VIT +%d%%" % int(stats_at["attack_speed_pct"]))

	# ── Carte XP unifiée (DA commune) ─────────────────────────
	# Les stats sont injectées à l'intérieur de la carte, sous le header,
	# en reparentant le header dans un VBox pour y ajouter une 2e ligne.
	var built  := UIHelpers.entity_xp_card(enom, etier, xp_cur, xp_max, slot_icon, Enums.EntityType.EQUIPMENT)
	var xpcard := built["card"] as XPCard
	var hdr    := built["header"] as HBoxContainer
	wrapper.add_child(xpcard)

	# Étiquette de slot ajoutée à droite du header
	hdr.add_child(UIHelpers.label(slot_name, 10, UIColors.TEXT_MUTED))

	# Injecter les stats dans la carte : reparenter le header dans un VBox
	if stat_parts.size() > 0:
		var mg  := hdr.get_parent()  # MarginContainer de entity_xp_card
		var vb  := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		hdr.reparent(vb)
		vb.add_child(UIHelpers.label("  ".join(stat_parts), 11, UIColors.TEXT_MUTED))
		mg.add_child(vb)

	# ── Indicateur forge (visible uniquement si barre pleine) ──
	if not at_max and MasterySystem.can_evolve(equip_id):
		wrapper.add_child(_forge_ready_panel(equip_id, etier, ec))

	# Tooltip JRPG
	var tt := Translations.T("hero.equip.tt_slot") % [slot_name, GameData.get_tier_name(etier)]
	if stat_parts.size() > 0:
		tt += "\n" + "  ".join(stat_parts)
	UIHelpers.register_tooltip(xpcard, enom, tt, ec, Translations.entity_lore(equip))

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

	if int(GameData.village.get("maitrise_actuelle", 0)) < 1:
		var lbl := UIHelpers.label(Translations.T("hero.forge_required"), 12, UIColors.TEXT_MUTED)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lbl)
	else:
		var recipe := GameData.get_forge_recipe(equip_id, etier + 1)
		if recipe.is_empty():
			return body
		vb.add_child(UIHelpers.label(Translations.T("hero.forge_ready"), 11, UIColors.LOG_VICTORY))
		for req in recipe:
			var ingr_id  := req.get("ingredient_id", "") as String
			var needed   := int(req.get("quantite", 1))
			var ingr     := GameData.get_entity(ingr_id)
			var have     := int(GameData.player["resources"].get(ingr_id, 0))
			var ingr_nom := Translations.entity_name(ingr, ingr_id)
			var ok       := have >= needed
			var ic       := UIColors.INGREDIENT_OK if ok else UIColors.INGREDIENT_MISSING
			var row      := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			vb.add_child(row)
			var il := UIHelpers.label("  %s" % ingr_nom, 11, ic)
			il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(il)
			row.add_child(UIHelpers.label("%d / %d" % [have, needed], 11, ic))

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
