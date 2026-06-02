# ============================================================
# ForgePanel — Contenu du panneau glissant « Forge » du Village.
#
# Construit dans host._rp_content : inventaire d'ingrédients + cartes
# d'équipement forgeables. Module sans état (fonctions statiques) ;
# host = nœud Village (accès à _rp_content, _active_creature, _open_panel).
# ============================================================
class_name ForgePanel

# Point d'entrée : peuple host._rp_content avec le contenu de la Forge.
static func build(host: Village) -> void:
	if GameData.village.get("tier_actuel", 0) < 1:
		var lbl := Label.new()
		lbl.text = "🔨  Le Forgeron\n\n« Je ne peux pas encore\nvous aider. »\n\nLibérez un Fragment pour\nfaire évoluer le Village."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		host._rp_content.add_child(lbl)
		return
	var tcolor := UIColors.tier_color(int(host._active_creature().get("maitrise_actuelle", 0)))

	# ── Inventaire ingrédients ──────────────────────────────
	host._rp_content.add_child(UIHelpers.section_header("◆  INGRÉDIENTS", tcolor))

	var ingr_vb := VBoxContainer.new()
	ingr_vb.add_theme_constant_override("separation", 3)
	host._rp_content.add_child(ingr_vb)

	var has_ingr := false
	for eid in GameData.entities:
		var e: Dictionary = GameData.entities[eid]
		if e.get("entity_type", "") != "ingredient":
			continue
		var qty := int(e.get("quantite_en_stock", 0))
		var nom := e.get("nom_affichage_fr", eid) as String
		has_ingr = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		ingr_vb.add_child(row)

		var is_unique := e.get("est_unique", false) as bool
		var nl := Label.new()
		nl.text = ("%s ✦" % nom) if is_unique else nom
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", UIColors.TEXT_HEADER if qty > 0 else UIColors.TEXT_MUTED)
		row.add_child(nl)

		var ql := Label.new()
		ql.text = "×%d" % qty
		ql.add_theme_font_size_override("font_size", 12)
		ql.add_theme_color_override("font_color", UIColors.FILTER_ON if qty > 0 else UIColors.TEXT_MUTED)
		row.add_child(ql)

		# Tooltip ingrédient.
		var biome_src := e.get("biome_source_id", "") as String
		var biome_e   := GameData.get_entity(biome_src)
		var bname     := biome_e.get("nom_affichage_fr", biome_src) as String if not biome_e.is_empty() else biome_src
		var tt_ingr   := "Biome : %s\nEn stock : %d" % [bname, qty]
		if is_unique:
			tt_ingr += "\nIngrédient unique — une seule obtention."
		UIHelpers.register_tooltip(row, nom, tt_ingr, UIColors.FILTER_ON if qty > 0 else UIColors.TEXT_MUTED)

	if not has_ingr:
		host._rp_content.add_child(UIHelpers.none_label(12))

	# ── Équipements ────────────────────────────────────────
	host._rp_content.add_child(UIHelpers.section_header("◆  ÉQUIPEMENTS", tcolor))

	var equip_ids: Array = ["equipment_arme", "equipment_anneau", "equipment_armure",
		"equipment_ceinture", "equipment_bouclier", "equipment_talisman"]

	for equip_id in equip_ids:
		var equip := GameData.get_entity(equip_id)
		if equip.is_empty():
			continue
		host._rp_content.add_child(_forge_equip_card(host, equip_id, equip, tcolor))

# Noms d'affichage des slots (index = Enums.SlotEquipement).
const SLOT_NAMES: Array = ["Arme", "Anneau", "Armure", "Ceinture", "Bouclier", "Talisman"]

# Construit la carte d'un équipement (verrouillé, max, ou forgeable).
static func _forge_equip_card(host: Village, equip_id: String, equip: Dictionary, tcolor: Color) -> Control:
	if not equip.get("est_debloque", false):
		var locked := PanelContainer.new()
		locked.add_theme_stylebox_override("panel",
				UIHelpers.card_style(UIColors.TEXT_MUTED, 0.06, 0.25, 1, 4))
		var lm := UIHelpers.margin_of(8)
		locked.add_child(lm)
		var lbl := Label.new()
		lbl.text = "🔒  %s  —  Biome non découvert" % equip.get("nom_affichage_fr", equip_id)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		lm.add_child(lbl)
		return locked

	var equip_tier := int(equip.get("maitrise_actuelle", 0))
	var nom        := equip.get("nom_affichage_fr", equip_id) as String
	var slot_idx   := int(equip.get("slot", 0))
	var slot_name  := SLOT_NAMES[slot_idx] if slot_idx < SLOT_NAMES.size() else ""
	var tier_name  := GameData.get_tier_name(equip_tier)
	var at_max     := equip_tier >= GameData.MAX_TIER
	var next_tier  := equip_tier + 1
	var recipe     := GameData.get_forge_recipe(equip_id, next_tier)
	var forgeable  := GameData.can_forge(equip_id)
	var ec         := UIColors.tier_color(equip_tier)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(ec, 0.06, 0.35, 1, 4))

	var m := UIHelpers.margin_of(8)
	card.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)

	# ── Nom + slot + palier ─────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vb.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = nom
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = tier_name
	tier_lbl.add_theme_font_size_override("font_size", 12)
	tier_lbl.add_theme_color_override("font_color", ec)
	header.add_child(tier_lbl)

	if slot_name != "":
		var slot_lbl := Label.new()
		slot_lbl.text = slot_name
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(slot_lbl)

	# ── Stats au palier actuel ──────────────────────────────
	var stats_dict := equip.get("stats_par_palier", {}) as Dictionary
	var stats_at_tier := stats_dict.get(str(equip_tier), {}) as Dictionary
	if not stats_at_tier.is_empty():
		var parts: Array[String] = []
		if stats_at_tier.get("atk", 0) != 0:
			parts.append("ATK +%d" % int(stats_at_tier["atk"]))
		if stats_at_tier.get("def", 0) != 0:
			parts.append("DEF +%d" % int(stats_at_tier["def"]))
		if stats_at_tier.get("hp", 0) != 0:
			parts.append("PV +%d" % int(stats_at_tier["hp"]))
		if stats_at_tier.get("attack_speed_pct", 0) != 0:
			parts.append("VIT +%d%%" % int(stats_at_tier["attack_speed_pct"]))
		if not parts.is_empty():
			var stats_lbl := Label.new()
			stats_lbl.text = "  ".join(parts)
			stats_lbl.add_theme_font_size_override("font_size", 11)
			stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
			vb.add_child(stats_lbl)

	if at_max:
		var max_lbl := Label.new()
		max_lbl.text = "▲ RANG MAX"
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(max_lbl)
		return card

	# ── Recette pour le palier suivant ──────────────────────
	if recipe.is_empty():
		var no_recipe := Label.new()
		no_recipe.text = "Recette non définie"
		no_recipe.add_theme_font_size_override("font_size", 11)
		no_recipe.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vb.add_child(no_recipe)
		return card

	var target_lbl := Label.new()
	target_lbl.text = "→ %s" % GameData.get_tier_name(next_tier)
	target_lbl.add_theme_font_size_override("font_size", 11)
	target_lbl.add_theme_color_override("font_color", UIColors.tier_color(next_tier))
	vb.add_child(target_lbl)

	for req in recipe:
		var ingr_id  := req.get("ingredient_id", "") as String
		var needed   := int(req.get("quantite", 1))
		var ingr     := GameData.get_entity(ingr_id)
		var have     := int(ingr.get("quantite_en_stock", 0))
		var ingr_nom := ingr.get("nom_affichage_fr", ingr_id) as String
		var ok       := have >= needed
		var ingr_c   := UIColors.INGREDIENT_OK if ok else UIColors.INGREDIENT_MISSING
		var row      := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vb.add_child(row)

		var il := Label.new()
		il.text = "  %s" % ingr_nom
		il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		il.add_theme_font_size_override("font_size", 11)
		il.add_theme_color_override("font_color", ingr_c)
		row.add_child(il)

		var ql := Label.new()
		ql.text = "%d / %d" % [have, needed]
		ql.add_theme_font_size_override("font_size", 11)
		ql.add_theme_color_override("font_color", ingr_c)
		row.add_child(ql)

	# ── Bouton Forger ───────────────────────────────────────
	var btn := Button.new()
	btn.text = "🔨  Forger → %s" % GameData.get_tier_name(next_tier)
	btn.disabled = not forgeable
	btn.add_theme_font_size_override("font_size", 12)
	var bc := UIColors.tier_color(next_tier) if forgeable else UIColors.TEXT_MUTED
	btn.add_theme_color_override("font_color", bc)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(bc, 0.12, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(bc, 0.28, 1.0, 1, 4))
	btn.pressed.connect(func() -> void:
		if GameData.forge(equip_id):
			host._open_panel("forge")
	)
	vb.add_child(btn)

	# Tooltip de l'équipement.
	var tt_body := "Slot : %s  ·  Maîtrise : %s" % [slot_name, tier_name]
	if not stats_at_tier.is_empty():
		var sl := _stats_line(stats_at_tier)
		if sl != "":
			tt_body += "\n" + sl
	UIHelpers.register_tooltip(card, nom, tt_body, ec)

	return card

# Formate les stats en ligne lisible.
static func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	if int(stats.get("atk", 0)) != 0:             parts.append("ATK +%d" % int(stats["atk"]))
	if int(stats.get("def", 0)) != 0:             parts.append("DEF +%d" % int(stats["def"]))
	if int(stats.get("hp", 0)) != 0:              parts.append("PV +%d" % int(stats["hp"]))
	if int(stats.get("attack_speed_pct", 0)) != 0: parts.append("VIT +%d%%" % int(stats["attack_speed_pct"]))
	return "  ".join(parts)
