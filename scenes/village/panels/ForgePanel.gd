# ============================================================
# ForgePanel — Panneau Forge polish.
#
# Layout : une section par biome — XPCard équipement + stats + recette
# + bouton forger. L'inventaire d'ingrédients vit dans le panneau HÉROS
# (HeroPanel) ; ici on ne montre que les recettes et leur disponibilité.
#
# Conventions visuelles :
#   • Couleur = biome tier (évolue au fil de la progression)
#   • VERT  = ingrédient disponible / forge possible
#   • ROUGE = manque d'ingrédients
#   • GRIS  = en attente d'XP / verrouillé
# ============================================================
class_name ForgePanel

# Mapping biome → équipement → icône de section (ordre d'affichage).
# Le nom affiché de la section vient des données du biome (Translations.entity_name).
const BIOME_EQUIP: Array = [
	["biome_montagne", "equipment_arme",   "⛰"],
	["biome_foret",    "equipment_anneau", "🌿"],
	["biome_marecage", "equipment_armure", "💧"],
]

# Label de section d'un biome : "icône  NOM DU BIOME" depuis les données.
static func _section_label(biome_id: String, icon: String) -> String:
	var biome := GameData.get_entity(biome_id)
	var nom   := Translations.entity_name(biome, biome_id)
	return "%s  %s" % [icon, nom.to_upper()]

static func _slot_name(slot_idx: int) -> String:
	const SLOT_KEYS := ["arme", "anneau", "armure", "ceinture", "bouclier", "talisman"]
	if slot_idx < SLOT_KEYS.size():
		return Translations.equip_slot_name(SLOT_KEYS[slot_idx])
	return ""

# ═══════════════════════════════════════════════════════════
#  Entrée
# ═══════════════════════════════════════════════════════════

static func build(host: Village) -> void:
	if GameData.village.get("maitrise_actuelle", 0) < 1:
		_build_locked(host)
		return

	for entry in BIOME_EQUIP:
		_build_biome_section(host, entry[0] as String, entry[1] as String,
				_section_label(entry[0] as String, entry[2] as String))

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
	title_lbl.text                 = Translations.T("forge.locked.title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	vb.add_child(title_lbl)

	vb.add_child(_hsep(UIColors.TEXT_MUTED, 0.22))

	var quote := Label.new()
	quote.text               = Translations.T("forge.locked.quote")
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	quote.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(quote)

	var hint := Label.new()
	hint.text                = Translations.T("forge.locked.hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hint.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	host.rp_content.add_child(card)

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
	var at_max   := int(equip.get("maitrise_actuelle", 0)) >= GameData.get_max_tier_for_type(Enums.EntityType.EQUIPMENT)
	var title    := section_label
	if can_f:
		title += "   ⚡"

	var sec  := UIHelpers.collapsible_section(title, biome_color, true, host.panel_ui_state(), section_label)
	host.rp_content.add_child(sec["wrapper"])
	var body := sec["body"] as VBoxContainer
	body.add_theme_constant_override("separation", 6)

	body.add_child(_equip_card(host, equip_id, equip, biome_color, can_f, xp_full, at_max))

static func _equip_card(host: Village, equip_id: String, equip: Dictionary,
		_tcolor: Color, can_forge_it: bool, xp_full: bool, at_max: bool) -> Control:

	# ── Verrouillé (biome découvert mais sous le palier de déblocage) ──
	if not equip.get("est_debloque", false):
		return _locked_equip_card(equip, equip_id)

	var equip_tier  := int(equip.get("maitrise_actuelle", 0))
	var nom         := Translations.entity_name(equip, equip_id)
	var slot_idx    := int(equip.get("slot", 0))
	var slot_name: String = _slot_name(slot_idx)
	var ec          := UIColors.tier_color(equip_tier)
	var next_tier   := equip_tier + 1
	var recipe      := GameData.get_forge_recipe(equip_id, next_tier)
	var xp_cur      := float(equip.get("xp_maitrise_actuelle", 0.0))
	var xp_nxt      := GameData.palier_suivant_cost(Enums.EntityType.EQUIPMENT, equip_tier)

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
	var tt_body    := Translations.T("forge.equip.tt_slot") % [slot_name, GameData.get_tier_name(equip_tier)]
	if not stats_cur.is_empty():
		tt_body += "\n" + _stats_line(stats_cur)
	if not at_max:
		var stats_nxt_tt := _stats_at(equip, next_tier)
		if not stats_nxt_tt.is_empty():
			tt_body += Translations.T("forge.equip.tt_next") % [GameData.get_tier_name(next_tier), _stats_line(stats_nxt_tt)]
	UIHelpers.register_tooltip(xpcard, nom, tt_body, ec, Translations.entity_lore(equip))

	# Ligne comparative « [Palier] stats ─◆─▶ [Palier+1] stats » : en pied
	# de carte aux rangs max / sans recette, sinon INTÉGRÉE au bouton Forger
	# (le joueur voit que c'est CE bouton qui produit cette transformation).
	var next_color := UIColors.tier_color(next_tier)
	var stats_nxt: Dictionary = {}
	if not at_max:
		stats_nxt = _stats_at(equip, next_tier)
	var compare_row := _tier_compare_row(equip_tier, stats_cur,
			next_tier, stats_nxt, not at_max)

	# ── Rang max ───────────────────────────────────────────
	if at_max:
		var max_row := HBoxContainer.new()
		max_row.add_theme_constant_override("separation", 6)
		var max_lbl := Label.new()
		max_lbl.text = Translations.T("forge.equip.max_rank")
		max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		max_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.TIER_LEGENDAIRE)
		max_row.add_child(max_lbl)
		outer.add_child(max_row)
		outer.add_child(compare_row)
		return outer

	# ── Recette manquante ──────────────────────────────────
	if recipe.is_empty():
		var nr := Label.new()
		nr.text = Translations.T("forge.equip.no_recipe")
		nr.add_theme_font_size_override("font_size", 11)
		nr.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		nr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(nr)
		outer.add_child(compare_row)
		return outer

	# ── Ingrédients requis ─────────────────────────────────
	outer.add_child(_small_spacer(2))
	outer.add_child(_recipe_block(recipe))

	# ── Statut XP ─────────────────────────────────────────
	if not xp_full:
		var xp_status := Label.new()
		var pct        := int(clampf(xp_cur / maxf(xp_nxt, 1.0), 0.0, 1.0) * 100.0)
		xp_status.text = Translations.T("forge.equip.low_xp_pct") % pct
		xp_status.add_theme_font_size_override("font_size", 11)
		xp_status.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		xp_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(xp_status)

	# ── Bouton Forger (libellé + aperçu de la transformation) ──
	outer.add_child(_small_spacer(2))
	outer.add_child(_forge_btn(host, equip_id, next_color,
			can_forge_it, compare_row))

	return outer

# Carte d'équipement verrouillé : le biome est découvert (sinon la section
# n'existe pas) mais n'a pas atteint le palier de déblocage de l'équipement.
static func _locked_equip_card(equip: Dictionary, equip_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 4))
	var m  := UIHelpers.margin_of(10)
	card.add_child(m)
	var biome      := GameData.get_entity(equip.get("biome_source_id", "") as String)
	var biome_name := Translations.entity_name(biome, equip.get("biome_source_id", "") as String)
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

# ── Bloc recette ─────────────────────────────────────────────
static func _recipe_block(recipe: Array) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	for req in recipe:
		var ingr_id  := req.get("ingredient_id", "") as String
		var needed   := int(req.get("quantite", 1))
		var ingr     := GameData.get_entity(ingr_id)
		var have     := int(GameData.player["resources"].get(ingr_id, 0))
		var nom      := Translations.entity_name(ingr, ingr_id)
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

		var ingr_lore := Translations.entity_lore(ingr)
		UIHelpers.register_tooltip(card, nom,
				Translations.T("forge.recipe.tt_stock") % [have, needed], ic, ingr_lore)

		vb.add_child(card)
	return vb

# ── Bouton Forger ─────────────────────────────────────────────
# Le bouton ENGLOBE l'aperçu de la transformation (compare_row) : libellé
# « Forger » au-dessus, « [Palier] stats ─◆─▶ [Palier+1] stats » en
# dessous, le tout cliquable d'un bloc.
static func _forge_btn(host: Village, equip_id: String,
		next_color: Color, forgeable: bool, compare_row: Control) -> Control:
	var btn := Button.new()
	btn.disabled              = not forgeable
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bc := next_color if forgeable else UIColors.TEXT_MUTED
	btn.add_theme_stylebox_override("normal",
			UIHelpers.card_style(bc, 0.10 if forgeable else 0.06, 0.80 if forgeable else 0.25, 1, 5))
	btn.add_theme_stylebox_override("hover",
			UIHelpers.card_style(bc, 0.22, 1.0, 2, 5))
	btn.add_theme_stylebox_override("disabled",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 5))

	# Contenu custom (un Button ne layoute pas ses enfants) : MarginContainer
	# plein-rect + sync de la taille mini du bouton sur celle du contenu.
	var lbl := Label.new()
	# Juste « Forger » : l'aperçu intégré dessous explicite déjà le palier cible.
	lbl.text = Translations.T("forge.equip.forge_btn")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", bc)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.add_child(lbl)
	inner.add_child(compare_row)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   8)
	mc.add_theme_constant_override("margin_right",  8)
	mc.add_theme_constant_override("margin_top",    5)
	mc.add_theme_constant_override("margin_bottom", 5)
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_child(inner)
	btn.add_child(mc)
	_set_mouse_ignore(mc)   # le contenu ne doit jamais voler le clic au bouton

	var sync_min := func() -> void:
		btn.custom_minimum_size = mc.get_combined_minimum_size()
	mc.minimum_size_changed.connect(sync_min)
	sync_min.call_deferred()

	if forgeable:
		# Pulse scale quand disponible
		btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
		var tw := btn.create_tween()
		tw.set_loops()
		tw.tween_property(btn, "scale", Vector2(1.015, 1.015), 0.6) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		UIHelpers.add_hover_feedback(btn)

		btn.pressed.connect(func() -> void:
			# Forge réussie → rituel d'ascension, comme toute évolution.
			if GameData.forge(equip_id):
				var e   := GameData.get_entity(equip_id)
				var nom := Translations.entity_name(e, equip_id)
				var nt  := int(e.get("maitrise_actuelle", 0))
				host.launch_evolution_ritual("equipment", equip_id, nom, nt - 1, nt)
		)
	else:
		UIHelpers.register_tooltip(btn, Translations.T("forge.equip.forge_unavail"),
				Translations.T("forge.equip.forge_tt_unavail"),
				UIColors.TEXT_MUTED)

	return btn

# ═══════════════════════════════════════════════════════════
#  Helpers visuels
# ═══════════════════════════════════════════════════════════

# Rend un sous-arbre de Controls transparent à la souris (contenu décoratif
# embarqué dans un Button : le clic doit toujours atteindre le bouton).
static func _set_mouse_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_ignore(child)

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

# ── Ligne comparative de paliers ─────────────────────────────
# « [Palier] ⚔+12 ❤+30  ─◆─▶  [Palier+1] ⚔+18 ❤+45 » sur UNE ligne,
# centrée. Sans palier suivant (rang max) : seule la moitié gauche.
static func _tier_compare_row(cur_tier: int, stats_cur: Dictionary,
		next_tier: int, stats_nxt: Dictionary, show_next: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	hb.add_child(_tier_badge(cur_tier))
	var cur_grp := _stats_inline(stats_cur, true, Color.WHITE)
	if cur_grp:
		hb.add_child(cur_grp)

	if show_next:
		var nc := UIColors.tier_color(next_tier)
		hb.add_child(_compare_sep(UIColors.tier_color(cur_tier), nc))
		hb.add_child(_tier_badge(next_tier))
		var nxt_grp := _stats_inline(stats_nxt, false, nc)
		if nxt_grp:
			hb.add_child(nxt_grp)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(hb)
	return center

# Pilule « nom du palier » aux couleurs du tier.
static func _tier_badge(tier: int) -> Control:
	var tc   := UIColors.tier_color(tier)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UIHelpers.card_style(tc, 0.12, 0.55, 1, 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   7)
	m.add_theme_constant_override("margin_right",  7)
	m.add_theme_constant_override("margin_top",    1)
	m.add_theme_constant_override("margin_bottom", 1)
	pill.add_child(m)
	var lbl := Label.new()
	lbl.text = GameData.get_tier_name(tier)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", tc.lerp(Color.WHITE, 0.25))
	m.add_child(lbl)
	return pill

# Stats compactes « ⚔+12 🛡+3 ❤+30 ⚡+10% » ; couleurs par stat pour le
# palier actuel, couleur du tier cible pour l'aperçu. Null si aucune stat.
static func _stats_inline(stats: Dictionary, use_stat_colors: bool,
		accent: Color) -> Control:
	var entries: Array = [
		["atk",              "⚔", UIColors.STAT_ATK],
		["def",              "🛡", UIColors.STAT_DEF],
		["hp",               "❤", UIColors.STAT_HP],
		["attack_speed_pct", "⚡", UIColors.FILTER_ON],
	]
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 7)
	for e in entries:
		var val := int(stats.get(e[0], 0))
		if val == 0:
			continue
		var l := Label.new()
		l.text = "%s+%d%s" % [e[1], val, "%" if e[0] == "attack_speed_pct" else ""]
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color",
				(e[2] as Color) if use_stat_colors else accent)
		grp.add_child(l)
	if grp.get_child_count() == 0:
		grp.free()
		return null
	return grp

# Séparateur stylé « ──◆──▶ » : dégradé du tier actuel vers le suivant.
static func _compare_sep(from_c: Color, to_c: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	var l1 := ColorRect.new()
	l1.custom_minimum_size = Vector2(10, 1)
	l1.color               = Color(from_c, 0.55)
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l1)
	var dia := Label.new()
	dia.text = "◆"
	dia.add_theme_font_size_override("font_size", 9)
	dia.add_theme_color_override("font_color", to_c)
	hb.add_child(dia)
	var l2 := ColorRect.new()
	l2.custom_minimum_size = Vector2(10, 1)
	l2.color               = Color(to_c, 0.55)
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l2)
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", to_c)
	hb.add_child(arrow)
	return hb

# Formate les stats en string pour les tooltips
static func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	if int(stats.get("atk", 0)) != 0:              parts.append(Translations.T("hero.stat.atk") + " +%d" % int(stats["atk"]))
	if int(stats.get("def", 0)) != 0:              parts.append(Translations.T("hero.stat.def") + " +%d" % int(stats["def"]))
	if int(stats.get("hp", 0)) != 0:               parts.append(Translations.T("hero.stat.hp")  + " +%d" % int(stats["hp"]))
	if int(stats.get("attack_speed_pct", 0)) != 0: parts.append("VIT +%d%%" % int(stats["attack_speed_pct"]))
	return "  ".join(parts)
