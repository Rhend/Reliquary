# ============================================================
# ForgePanel — Panneau Forge polish.
#
# Layout :
#   ◆ INGRÉDIENTS   — inventaire groupé par biome, mini-cartes avec hover
#   ◆ [BIOME]       — XPCard équipement + stats + recette + bouton forgé
#
# Conventions visuelles :
#   • Couleur = biome tier (évolue au fil de la progression)
#   • VERT  = ingrédient disponible / forge possible
#   • ROUGE = manque d'ingrédients
#   • GRIS  = en attente d'XP / verrouillé
# ============================================================
class_name ForgePanel

# Mapping biome → équipement → label section (ordre d'affichage).
const BIOME_EQUIP: Array = [
	["biome_montagne", "equipment_arme",   "⛰  MONTAGNE"],
	["biome_foret",    "equipment_anneau", "🌿  FORÊT SOMBRE"],
	["biome_marecage", "equipment_armure", "💧  MARÉCAGE PUTRIDE"],
]

const SLOT_NAMES: Array = ["Arme", "Anneau", "Armure", "Ceinture", "Bouclier", "Talisman"]

# ═══════════════════════════════════════════════════════════
#  Entrée
# ═══════════════════════════════════════════════════════════

static func build(host: Village) -> void:
	if GameData.village.get("tier_actuel", 0) < 1:
		_build_locked(host)
		return

	var hero_tier := int(host._active_creature().get("maitrise_actuelle", 0))
	var tcolor    := UIColors.tier_color(hero_tier)

	_build_ingredients(host, tcolor)

	for entry in BIOME_EQUIP:
		_build_biome_section(host, entry[0] as String, entry[1] as String, entry[2] as String)

# ═══════════════════════════════════════════════════════════
#  État verrouillé
# ═══════════════════════════════════════════════════════════

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
	icon_lbl.text                  = "🔨"
	icon_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 36)
	vb.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text                 = "LE FORGERON"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	vb.add_child(title_lbl)

	vb.add_child(_hsep(UIColors.TEXT_MUTED, 0.22))

	var quote := Label.new()
	quote.text               = "« Je ne peux pas encore vous aider. »"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	quote.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(quote)

	var hint := Label.new()
	hint.text                = "Libérez un Fragment de Mémoire\npour faire évoluer le Village."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hint.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	host._rp_content.add_child(card)

# ═══════════════════════════════════════════════════════════
#  Section ingrédients
# ═══════════════════════════════════════════════════════════

static func _build_ingredients(host: Village, tcolor: Color) -> void:
	var sec  := UIHelpers.collapsible_section("◆  INGRÉDIENTS", tcolor)
	host._rp_content.add_child(sec["wrapper"])
	var body := sec["body"] as VBoxContainer
	body.add_theme_constant_override("separation", 2)

	# Ordre d'affichage des biomes
	var biome_order: Array = []
	for entry in BIOME_EQUIP:
		biome_order.append(entry[0] as String)

	# Collecte + tri
	var ingr_list: Array = []
	for eid in GameData.entities:
		var e: Dictionary = GameData.entities[eid]
		if e.get("entity_type", "") == "ingredient":
			ingr_list.append({"id": eid, "e": e})

	ingr_list.sort_custom(func(a, b):
		var ia := biome_order.find(a["e"].get("biome_source_id", ""))
		var ib := biome_order.find(b["e"].get("biome_source_id", ""))
		if ia != ib: return ia < ib
		return int(a["e"].get("est_unique", false)) < int(b["e"].get("est_unique", false))
	)

	var last_biome := ""
	var any_ingr   := false

	for item in ingr_list:
		var eid  := item["id"] as String
		var e    := item["e"] as Dictionary
		var qty  := int(GameData.player["resources"].get(eid, 0))
		var src  := e.get("biome_source_id", "") as String

		# ── Séparateur de biome ────────────────────────────
		if src != last_biome:
			last_biome = src
			if any_ingr:
				body.add_child(_small_spacer(4))
			body.add_child(_biome_header(src))

		body.add_child(_ingredient_card(eid, e, qty))
		any_ingr = true

	if not any_ingr:
		var none_lbl := UIHelpers.none_label(11)
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(none_lbl)

# En-tête de groupe biome : ligne colorée + nom
static func _biome_header(biome_src: String) -> Control:
	var biome  := GameData.get_entity(biome_src)
	var bname  := biome.get("nom_affichage_fr", biome_src) as String if not biome.is_empty() else biome_src
	var btier  := int(biome.get("maitrise_actuelle", 0)) if not biome.is_empty() else 0
	var bc     := UIColors.tier_color(btier)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)

	var line1 := ColorRect.new()
	line1.custom_minimum_size = Vector2(16, 1)
	line1.color               = Color(bc.r, bc.g, bc.b, 0.55)
	line1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(line1)

	var lbl := Label.new()
	lbl.text = bname.to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(bc.r, bc.g, bc.b, 0.85))
	hb.add_child(lbl)

	var line2 := ColorRect.new()
	line2.custom_minimum_size   = Vector2(0, 1)
	line2.color                 = Color(bc.r, bc.g, bc.b, 0.35)
	line2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	hb.add_child(line2)

	return hb

# Mini-carte d'un ingrédient avec hover feedback + tooltip
static func _ingredient_card(eid: String, e: Dictionary, qty: int) -> Control:
	var is_unique := e.get("est_unique", false) as bool
	var nom       := e.get("nom_affichage_fr", eid) as String
	var biome_src := e.get("biome_source_id", "") as String
	var biome_e   := GameData.get_entity(biome_src)
	var btier     := int(biome_e.get("maitrise_actuelle", 0)) if not biome_e.is_empty() else 0
	var bc        := UIColors.tier_color(btier)
	var has_stock := qty > 0
	var txt_color := UIColors.FILTER_ON if is_unique and has_stock \
			else (UIColors.TEXT_HEADER if has_stock else UIColors.TEXT_MUTED)

	var card := PanelContainer.new()
	card.size_flags_horizontal       = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape  = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(bc if has_stock else UIColors.TEXT_MUTED,
					0.05 if has_stock else 0.03,
					0.22 if has_stock else 0.12, 1, 4))

	var m := UIHelpers.margin_of(6)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	m.add_child(row)

	# Icône unique
	if is_unique:
		var star := Label.new()
		star.text = "✦"
		star.add_theme_font_size_override("font_size", 11)
		star.add_theme_color_override("font_color",
				UIColors.TIER_LEGENDAIRE if has_stock else UIColors.TEXT_MUTED)
		row.add_child(star)

	var name_lbl := Label.new()
	name_lbl.text                    = nom
	name_lbl.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", txt_color)
	row.add_child(name_lbl)

	# Badge quantité
	var qty_lbl := Label.new()
	qty_lbl.text = "×%d" % qty if has_stock else "×0"
	qty_lbl.add_theme_font_size_override("font_size", 12)
	qty_lbl.add_theme_color_override("font_color",
			UIColors.FILTER_ON if has_stock else UIColors.TEXT_MUTED)
	row.add_child(qty_lbl)

	# Hover feedback
	UIHelpers.add_hover_feedback(card)

	# Tooltip
	var biome_name := biome_e.get("nom_affichage_fr", biome_src) as String if not biome_e.is_empty() else biome_src
	var tt_body    := "Biome : %s\nEn stock : %d" % [biome_name, qty]
	if is_unique:
		tt_body += "\n✦ Ingrédient unique — une seule obtention possible."
	UIHelpers.register_tooltip(card, nom, tt_body,
			bc if has_stock else UIColors.TEXT_MUTED,
			e.get("lore_fr", "") as String)

	return card

# ═══════════════════════════════════════════════════════════
#  Section équipement par biome
# ═══════════════════════════════════════════════════════════

static func _build_biome_section(host: Village, biome_id: String,
		equip_id: String, section_label: String) -> void:
	var biome := GameData.get_entity(biome_id)
	if biome.is_empty() or not biome.get("est_decouvert", false):
		return
	var equip := GameData.get_entity(equip_id)
	if equip.is_empty():
		return

	var biome_tier  := int(biome.get("maitrise_actuelle", 0))
	var biome_color := UIColors.tier_color(biome_tier)

	# Badge "DISPONIBLE" dans le titre si forge possible
	var can_f    := GameData.can_forge(equip_id)
	var xp_full  := GameData.equipment_xp_full(equip_id)
	var at_max   := int(equip.get("maitrise_actuelle", 0)) >= GameData.get_max_tier_for_type("equipment")
	var title    := section_label
	if can_f:
		title += "   ⚡"

	var sec  := UIHelpers.collapsible_section(title, biome_color, true)
	host._rp_content.add_child(sec["wrapper"])
	var body := sec["body"] as VBoxContainer
	body.add_theme_constant_override("separation", 6)

	body.add_child(_equip_card(host, equip_id, equip, biome_color, can_f, xp_full, at_max))

static func _equip_card(host: Village, equip_id: String, equip: Dictionary,
		_tcolor: Color, can_forge_it: bool, xp_full: bool, at_max: bool) -> Control:

	# ── Verrouillé (biome non découvert) ──────────────────
	if not equip.get("est_debloque", false):
		return _locked_equip_card(equip, equip_id)

	var equip_tier  := int(equip.get("maitrise_actuelle", 0))
	var nom         := equip.get("nom_affichage_fr", equip_id) as String
	var slot_idx    := int(equip.get("slot", 0))
	var slot_name: String = SLOT_NAMES[slot_idx] if slot_idx < SLOT_NAMES.size() else ""
	var ec          := UIColors.tier_color(equip_tier)
	var next_tier   := equip_tier + 1
	var recipe      := GameData.get_forge_recipe(equip_id, next_tier)
	var xp_cur      := float(equip.get("xp_maitrise_actuelle", 0.0))
	var xp_nxt      := GameData.palier_suivant_cost("equipment", equip_tier)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── XPCard ─────────────────────────────────────────────
	var icon_slot := _slot_icon(slot_idx)
	var built     := UIHelpers.entity_xp_card(nom, equip_tier, xp_cur,
			xp_nxt if not at_max else 0.0, icon_slot, "equipment")
	var xpcard    := built["card"] as Control
	xpcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(xpcard)

	# Badge slot dans le header
	if slot_name != "":
		var hdr    := built["header"] as HBoxContainer
		var sl_lbl := Label.new()
		sl_lbl.text = slot_name
		sl_lbl.add_theme_font_size_override("font_size", 10)
		sl_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hdr.add_child(sl_lbl)

	# Tooltip de la carte XP
	var stats_cur  := _stats_at(equip, equip_tier)
	var tt_body    := "Slot : %s  ·  Rang : %s" % [slot_name, GameData.get_tier_name(equip_tier)]
	if not stats_cur.is_empty():
		tt_body += "\n" + _stats_line(stats_cur)
	if not at_max:
		var stats_nxt := _stats_at(equip, next_tier)
		if not stats_nxt.is_empty():
			tt_body += "\n→ %s : %s" % [GameData.get_tier_name(next_tier), _stats_line(stats_nxt)]
	UIHelpers.register_tooltip(xpcard, nom, tt_body, ec, equip.get("lore_fr", "") as String)

	# ── Stats actuelles ────────────────────────────────────
	if not stats_cur.is_empty():
		outer.add_child(_stats_display(stats_cur, ec, false))

	# ── Rang max ───────────────────────────────────────────
	if at_max:
		var max_row := HBoxContainer.new()
		max_row.add_theme_constant_override("separation", 6)
		var max_lbl := Label.new()
		max_lbl.text = "▲  RANG MAXIMUM"
		max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		max_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.TIER_LEGENDAIRE)
		max_row.add_child(max_lbl)
		outer.add_child(max_row)
		return outer

	# ── Recette manquante ──────────────────────────────────
	if recipe.is_empty():
		var nr := Label.new()
		nr.text = "Recette non définie"
		nr.add_theme_font_size_override("font_size", 11)
		nr.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		nr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(nr)
		return outer

	# ── Séparateur vers palier suivant ──────────────────────
	outer.add_child(_small_spacer(2))
	var next_color  := UIColors.tier_color(next_tier)
	var next_header := HBoxContainer.new()
	next_header.add_theme_constant_override("separation", 6)
	var arrow_lbl   := Label.new()
	arrow_lbl.text  = "→"
	arrow_lbl.add_theme_font_size_override("font_size", 11)
	arrow_lbl.add_theme_color_override("font_color", next_color)
	next_header.add_child(arrow_lbl)
	var target_lbl  := Label.new()
	target_lbl.text = GameData.get_tier_name(next_tier)
	target_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_lbl.add_theme_font_size_override("font_size", 11)
	target_lbl.add_theme_color_override("font_color", next_color)
	next_header.add_child(target_lbl)
	outer.add_child(next_header)

	# Aperçu stats palier suivant (delta)
	var stats_nxt := _stats_at(equip, next_tier)
	if not stats_nxt.is_empty():
		outer.add_child(_stats_display(stats_nxt, next_color, true))

	# ── Ingrédients requis ─────────────────────────────────
	outer.add_child(_small_spacer(2))
	outer.add_child(_recipe_block(recipe))

	# ── Statut XP ─────────────────────────────────────────
	if not xp_full:
		var xp_status := Label.new()
		var pct        := int(clampf(xp_cur / maxf(xp_nxt, 1.0), 0.0, 1.0) * 100.0)
		xp_status.text = "⧖  XP — %d %%  (continuez l'aventure)" % pct
		xp_status.add_theme_font_size_override("font_size", 11)
		xp_status.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		xp_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(xp_status)

	# ── Bouton Forger ──────────────────────────────────────
	outer.add_child(_small_spacer(2))
	outer.add_child(_forge_btn(host, equip_id, next_tier, next_color, can_forge_it))

	return outer

# Carte d'équipement verrouillé (biome non découvert)
static func _locked_equip_card(equip: Dictionary, equip_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 4))
	var m  := UIHelpers.margin_of(10)
	card.add_child(m)
	var lbl := Label.new()
	lbl.text = "🔒  %s  —  Biome non découvert" % equip.get("nom_affichage_fr", equip_id)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	m.add_child(lbl)
	return card

# ── Bloc recette ─────────────────────────────────────────────
static func _recipe_block(recipe: Array) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	for req in recipe:
		var ingr_id  := req.get("ingredient_id", "") as String
		var needed   := int(req.get("quantite", 1))
		var ingr     := GameData.get_entity(ingr_id)
		var have     := int(GameData.player["resources"].get(ingr_id, 0))
		var nom      := ingr.get("nom_affichage_fr", ingr_id) as String
		var ok       := have >= needed
		var ic       := UIColors.INGREDIENT_OK if ok else UIColors.INGREDIENT_MISSING

		var card := PanelContainer.new()
		card.size_flags_horizontal      = Control.SIZE_EXPAND_FILL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_theme_stylebox_override("panel",
				UIHelpers.card_style(ic, 0.05 if ok else 0.06, 0.20, 1, 3))

		var m := UIHelpers.margin_of(5)
		card.add_child(m)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		m.add_child(row)

		# Check / Cross
		var check := Label.new()
		check.text = "✓" if ok else "✗"
		check.add_theme_font_size_override("font_size", 12)
		check.add_theme_color_override("font_color", ic)
		row.add_child(check)

		var nl := Label.new()
		nl.text                  = nom
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", ic)
		row.add_child(nl)

		# Quantité have / needed
		var ql := Label.new()
		ql.text = "%d / %d" % [have, needed]
		ql.add_theme_font_size_override("font_size", 11)
		ql.add_theme_color_override("font_color", ic)
		row.add_child(ql)

		UIHelpers.add_hover_feedback(card)

		var ingr_lore := ingr.get("lore_fr", "") as String
		UIHelpers.register_tooltip(card, nom,
				"En stock : %d\nRequis : %d" % [have, needed], ic, ingr_lore)

		vb.add_child(card)
	return vb

# ── Bouton Forger ─────────────────────────────────────────────
static func _forge_btn(host: Village, equip_id: String, next_tier: int,
		next_color: Color, forgeable: bool) -> Control:
	var btn := Button.new()
	btn.text                  = "🔨  Forger → %s" % GameData.get_tier_name(next_tier)
	btn.disabled              = not forgeable
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bc := next_color if forgeable else UIColors.TEXT_MUTED
	btn.add_theme_color_override("font_color", bc)
	btn.add_theme_stylebox_override("normal",
			UIHelpers.card_style(bc, 0.10 if forgeable else 0.06, 0.80 if forgeable else 0.25, 1, 5))
	btn.add_theme_stylebox_override("hover",
			UIHelpers.card_style(bc, 0.22, 1.0, 2, 5))
	btn.add_theme_stylebox_override("disabled",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 5))

	if forgeable:
		# Pulse scale quand disponible
		btn.pivot_offset = Vector2(190, 18)
		var tw := btn.create_tween()
		tw.set_loops()
		tw.tween_property(btn, "scale", Vector2(1.015, 1.015), 0.6) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		UIHelpers.add_hover_feedback(btn)

		btn.pressed.connect(func() -> void:
			if GameData.forge(equip_id):
				var e   := GameData.get_entity(equip_id)
				var nom := e.get("nom_affichage_fr", equip_id) as String
				var nt  := int(e.get("maitrise_actuelle", 0))
				host._show_banner(
						"🔨  %s → %s" % [nom, GameData.get_tier_name(nt)],
						UIColors.LOG_VICTORY, Color(0.02, 0.12, 0.05, 0.92), 2.0, 0.4)
				host._open_panel("forge")
		)
	else:
		UIHelpers.register_tooltip(btn, "Forge indisponible",
				"Remplissez la barre XP et réunissez les ingrédients.",
				UIColors.TEXT_MUTED)

	return btn

# ═══════════════════════════════════════════════════════════
#  Helpers visuels
# ═══════════════════════════════════════════════════════════

# Ligne séparatrice horizontale colorée
static func _hsep(color: Color, alpha: float = 0.30) -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.color                 = Color(color.r, color.g, color.b, alpha)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sep

# Espacement vertical fixe
static func _small_spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

# Icône de slot selon l'index Enums.SlotEquipement
static func _slot_icon(slot_idx: int) -> String:
	match slot_idx:
		0: return "⚔"    # Arme
		1: return "💍"   # Anneau
		2: return "🛡"   # Armure
		3: return "🪢"   # Ceinture
		4: return "⬡"    # Bouclier
		5: return "✦"    # Talisman
		_: return ""

# Stats d'un équipement au palier t
static func _stats_at(equip: Dictionary, tier: int) -> Dictionary:
	var spp := equip.get("stats_par_palier", {}) as Dictionary
	return spp.get(tier, spp.get(0, {})) as Dictionary

# Affiche une ligne de stats avec icônes et couleurs par stat
static func _stats_display(stats: Dictionary, accent: Color, is_preview: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)

	var entries: Array = [
		["atk",              "⚔", UIColors.STAT_ATK, "+%d ATK"],
		["def",              "🛡", UIColors.STAT_DEF, "+%d DEF"],
		["hp",               "❤", UIColors.STAT_HP,  "+%d PV"],
		["attack_speed_pct", "⚡", UIColors.FILTER_ON, "+%d%% VIT"],
	]

	var has_stat := false
	for e in entries:
		var val := int(stats.get(e[0], 0))
		if val == 0:
			continue
		has_stat = true
		var grp := HBoxContainer.new()
		grp.add_theme_constant_override("separation", 2)
		hb.add_child(grp)

		var icon_l := Label.new()
		icon_l.text = e[1] as String
		icon_l.add_theme_font_size_override("font_size", 11)
		grp.add_child(icon_l)

		var val_l := Label.new()
		val_l.text = (e[3] as String) % val
		val_l.add_theme_font_size_override("font_size", 11)
		val_l.add_theme_color_override("font_color",
				accent if is_preview else (e[2] as Color))
		grp.add_child(val_l)

	if not has_stat:
		return Control.new()

	# Centrer la ligne dans un wrapper
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(hb)
	return center

# Formate les stats en string pour les tooltips
static func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	if int(stats.get("atk", 0)) != 0:              parts.append("ATK +%d" % int(stats["atk"]))
	if int(stats.get("def", 0)) != 0:              parts.append("DEF +%d" % int(stats["def"]))
	if int(stats.get("hp", 0)) != 0:               parts.append("PV +%d" % int(stats["hp"]))
	if int(stats.get("attack_speed_pct", 0)) != 0: parts.append("VIT +%d%%" % int(stats["attack_speed_pct"]))
	return "  ".join(parts)
