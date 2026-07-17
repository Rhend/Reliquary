# ============================================================
# BuildingPanel — Panneau de gestion d'un bâtiment de quartier (Chantier 4 ;
# coûts refondus au chantier 12 : Euren + Modules).
#
# Ouvert depuis une pièce d'un quartier (cf. Village.DISTRICTS /
# VillageBuildings.ROOM_TO_BUILDING). Deux états :
#   • Gelé (Couturier) : carte verrouillée, aucune action.
#   • Gestion : palier courant + bonus actifs + aperçu/coût du palier suivant
#     + bouton Améliorer (débite Euren + Modules — plus aucune ressource de
#     biome ; les ROUTES ont été supprimées au chantier 12, la couche gestion
#     est accessible d'emblée).
#
# 100 % API publique du Village (host.rp_content). Les actions passent par
# VillageBuildings ; le rafraîchissement vient des signaux resources_changed /
# village_buildings_changed (Village._on_resources_changed_refresh).
# ============================================================
class_name BuildingPanel

# Canaux exprimés en pourcentage (value fraction → entier %).
const PCT_CHANNELS: Array[String] = [
	"atk_pct", "def_pct", "hp_max_pct", "crit_pct", "regen_pct",
	"xp_distributed_pct", "bless_effect_pct", "drop_rare_pct",
	"ambush_gauge_start_pct", "all_expedition_gauge_start_pct",
	"forge_points_reduction_arme", "forge_points_reduction_armure",
	"forge_points_reduction_anneau", "forge_xp_reduction_arme",
	"forge_xp_reduction_armure", "forge_xp_reduction_anneau",
]

static func build(host: Village, building_id: String) -> void:
	var b := GameData.get_entity(building_id)
	if b.is_empty():
		return

	_add_header(host, b, building_id)

	# Lore
	var lore := Translations.entity_lore(b)
	if lore != "":
		var ll := UIHelpers.label(lore, 11, UIColors.TEXT_MUTED)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		host.rp_content.add_child(ll)

	if b.get("gele", false):
		_add_note(host, Translations.T("building.frozen"), UIColors.TEXT_MUTED)
		return

	_add_bonuses_card(host, building_id)
	_add_upgrade_card(host, building_id)

# ═══════════════════════════════════════════════════════════
#  En-tête : nom + pilule de palier
# ═══════════════════════════════════════════════════════════

static func _add_header(host: Village, b: Dictionary, building_id: String) -> void:
	var tier := VillageBuildings.building_tier(building_id)
	var tcolor := _tier_color(tier)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := UIHelpers.label(Translations.entity_name(b, building_id), 16, tcolor.lerp(Color.WHITE, 0.30))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	row.add_child(_tier_pill(tier))
	host.rp_content.add_child(row)

# ═══════════════════════════════════════════════════════════
#  Bonus actifs
# ═══════════════════════════════════════════════════════════

static func _add_bonuses_card(host: Village, building_id: String) -> void:
	var tier := VillageBuildings.building_tier(building_id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(_tier_color(tier), 0.05, 0.20, 1, 6))
	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)

	vb.add_child(UIHelpers.label(Translations.T("building.bonuses.title"), 12, UIColors.TEXT_HEADER))

	var effects := VillageBuildings.building_effects(building_id, tier)
	if effects.is_empty():
		# Reliquaire (registre des succès) ou bâtiment encore Délabré.
		var none := UIHelpers.label(Translations.T("building.bonuses.none") if tier < 0 \
				else Translations.T("building.bonuses.registry"), 11, UIColors.TEXT_MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(none)
	else:
		for ch in effects:
			vb.add_child(_effect_label(ch, effects[ch], UIColors.LOG_VICTORY))
	host.rp_content.add_child(card)

# ═══════════════════════════════════════════════════════════
#  Amélioration (palier suivant)
# ═══════════════════════════════════════════════════════════

static func _add_upgrade_card(host: Village, building_id: String) -> void:
	var tier := VillageBuildings.building_tier(building_id)
	if tier >= Balance.BUILDING_MAX_TIER:
		_add_note(host, Translations.T("building.max_rank"), UIColors.TIER_LEGENDAIRE)
		return

	var next_tier := tier + 1
	var nc := UIColors.tier_color(next_tier)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.06, 0.30, 1, 6))
	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)

	vb.add_child(UIHelpers.label(
			Translations.T("building.upgrade.title") % GameData.get_tier_name(next_tier),
			12, nc.lerp(Color.WHITE, 0.25)))

	# Bonus débloqués au palier suivant (incréments bruts du .tres).
	var gained: Array = (GameData.get_entity(building_id).get("bonus_par_palier", {}) as Dictionary).get(next_tier, [])
	for effect in gained:
		vb.add_child(_effect_label(str(effect.get("channel", "")), float(effect.get("value", 0.0)), nc))

	# Coût + bouton.
	vb.add_child(_cost_block(VillageBuildings.building_cost(building_id)))
	var can := VillageBuildings.can_upgrade_building(building_id)
	vb.add_child(_action_btn(Translations.T("building.upgrade.btn"), can,
			func() -> void: VillageBuildings.upgrade_building(building_id)))
	host.rp_content.add_child(card)

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

# Bloc « coût » (chantier 12) : une carte par devise (Euren, puis Modules si
# le palier en demande) avec solde have / need coloré.
static func _cost_block(cost: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lignes: Array = [
		["◈ " + Translations.T("currency.euren"), int(roundf(float(cost.get("euren", 0.0)))),
				int(roundf(ProgressionHeros.euren()))],
		["◧ " + Translations.T("currency.modules"), int(cost.get("modules", 0)),
				ProgressionHeros.modules()],
	]
	for ligne: Array in lignes:
		var need := int(ligne[1])
		if need <= 0:
			continue   # devise non demandée à ce palier (Modules avant T2)
		var have := int(ligne[2])
		var ok := have >= need
		var ic := UIColors.INGREDIENT_OK if ok else UIColors.INGREDIENT_MISSING

		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UIHelpers.card_style(ic, 0.05, 0.20, 1, 3))
		var m := UIHelpers.margin_of(5)
		card.add_child(m)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		m.add_child(row)

		row.add_child(UIHelpers.label("✓" if ok else "✗", 12, ic))

		var nl := UIHelpers.label(str(ligne[0]), 11, ic)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)

		row.add_child(UIHelpers.label("%d / %d" % [have, need], 11, ic))
		vb.add_child(card)
	return vb

# Bouton d'action (reconstruire route / améliorer) : vert si possible, gris sinon.
static func _action_btn(label: String, enabled: bool, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.disabled = not enabled
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	var c := UIColors.INGREDIENT_OK if enabled else UIColors.TEXT_MUTED
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_disabled_color", UIColors.TEXT_MUTED)
	btn.add_theme_stylebox_override("normal",
			UIHelpers.card_style(c, 0.10 if enabled else 0.05, 0.70 if enabled else 0.25, 1, 5))
	btn.add_theme_stylebox_override("hover", UIHelpers.card_style(c, 0.22, 1.0, 2, 5))
	btn.add_theme_stylebox_override("disabled",
			UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.18, 1, 5))
	if enabled:
		btn.pressed.connect(on_press)
	return btn

# Ligne décrivant un effet (canal + valeur), localisée.
static func _effect_label(channel: String, value: float, color: Color) -> Label:
	var lbl := UIHelpers.label("•  " + _effect_text(channel, value), 11, color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

# Texte localisé d'un effet selon son canal.
static func _effect_text(channel: String, value: float) -> String:
	if channel == "":
		return ""
	if channel in PCT_CHANNELS:
		return Translations.T("village.bonus." + channel) % int(round(value * 100.0))
	match channel:
		"ignore_first_lethal":
			return Translations.T("village.bonus.ignore_first_lethal")
		"debuff_immunity_tier":
			return Translations.T("village.bonus.debuff_immunity_tier") % GameData.get_tier_name(int(value))
		"debuff_start_reduction", "bless_antidote_extra":
			return Translations.T("village.bonus." + channel) % int(value)
	return channel

static func _add_note(host: Village, text: String, color: Color) -> void:
	var lbl := UIHelpers.label(text, 12, color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.rp_content.add_child(lbl)

# Pilule « palier » (Délabré ou nom du palier) aux couleurs du tier.
static func _tier_pill(tier: int) -> Control:
	var tc := _tier_color(tier)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UIHelpers.card_style(tc, 0.12, 0.55, 1, 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 7)
	m.add_theme_constant_override("margin_right", 7)
	m.add_theme_constant_override("margin_top", 1)
	m.add_theme_constant_override("margin_bottom", 1)
	pill.add_child(m)
	m.add_child(UIHelpers.label(
			Translations.T("building.delabre") if tier < 0 else GameData.get_tier_name(tier),
			10, tc.lerp(Color.WHITE, 0.25)))
	return pill

# Couleur d'un palier de bâtiment ; Délabré (-1) → gris discret.
static func _tier_color(tier: int) -> Color:
	return UIColors.TEXT_MUTED if tier < 0 else UIColors.tier_color(tier)
