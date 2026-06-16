# ============================================================
# CycleSummaryScreen.gd — Écran de résultat d'expédition.
#
# Affiché après victoire, défaite ou interruption volontaire.
# Structure :
#   1. Bannière « RETOUR AU VILLAGE » + aura — l'issue est racontée par
#      la COULEUR (vert victoire / or interruption / rouge défaite)
#   2. Puces de stats (combats, événements, butin, XP totale) à compteurs
#   3. Sections : Découvertes, Ressources, Répartition XP, Évolutions
#      (sections vides absentes)
#
# Le panneau est une colonne centrée (PANEL_WIDTH) — pas de pleine
# largeur : les lignes restent lisibles. La couleur d'accent vient du
# résultat (vert/rouge/or), les sections gardent la DA des panneaux.
# La logique XP / évolution n'est pas modifiée ici.
# ============================================================
extends Control

const PANEL_WIDTH := 880.0

# Durée de remplissage d'une barre XP (lecture confortable).
const XP_FILL_TIME    := 1.06

# Révélation séquentielle du résumé : chaque élément apparaît ~1 s après le
# précédent (retour playtest : on veut savourer le récap). Double-clic souris =
# tout afficher d'un coup (_skip_to_end). REVEAL_STAGGER = cadence entre éléments.
const REVEAL_STAGGER := 0.9
const FADE_IN_TIME   := 0.5

var _fade_nodes: Array = []   # Controls révélés un par un (ordre de construction)
var _xp_anims:   Array = []   # {card, xp_label, gained, before_frac, after_frac}
var _counters:   Array = []   # {label, chip, to, fmt} — compteurs des puces de stats
var _banner_box: Control
var _aura:       TextureRect
var _banner_fx:  SummaryFX    # shine + burst au-dessus de la bannière

# ─── Pilotage de la séquence (révélation lente + skip) ───────
var _running_tweens: Array      = []      # tweens à tuer au skip (aura exclue)
var _seq_done:       bool       = false   # séquence terminée OU sautée
var _xp_by_card:     Dictionary = {}      # XPCard → données d'anim (déclenché au reveal)

# ═══════════════════════════════════════════════════════════
func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	_run_animation_sequence()

# ═══════════════════════════════════════════════════════════
#  Construction UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var data := CycleData.last_cycle_summary
	if data.is_empty():
		_go_to_village()
		return

	var hero   := GameData.get_entity("hero")
	var tcolor := UIColors.tier_color(hero.get("maitrise_actuelle", 0) as int)

	var biome      := GameData.get_entity(data.get("biome_id", "") as String)
	var biome_name := Translations.entity_name(biome)

	# Couleur du résultat — accent de tout l'écran. Le titre, lui, est
	# neutre (« Retour au village ») : seule la couleur raconte l'issue
	# (vert victoire / or interruption / rouge défaite).
	var rcolor := UIColors.LOG_DEFEAT
	if data.get("interrupted", false):
		rcolor = UIColors.FILTER_ON
	elif data.get("victory", false):
		rcolor = UIColors.LOG_VICTORY
	var rtext := Translations.T("cycle.banner_title")

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	# Poussières lumineuses derrière le panneau (teintées par le résultat).
	var ambient := SummaryFX.new()
	ambient.mode   = SummaryFX.Mode.AMBIENT
	ambient.accent = rcolor
	ambient.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(ambient)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer_margin.add_theme_constant_override(side, 16)
	add_child(outer_margin)

	# Colonne centrée — la pleine largeur 1280 rendait les lignes illisibles.
	var panel := PanelContainer.new()
	panel.custom_minimum_size   = Vector2(PANEL_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.045, 0.055, 0.095, 0.98)
	ps.border_color = Color(rcolor.r, rcolor.g, rcolor.b, 0.45)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(10)
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size  = 18
	panel.add_theme_stylebox_override("panel", ps)
	outer_margin.add_child(panel)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	_build_banner(col, rtext, rcolor, biome_name)
	_build_stat_chips(col, data, rcolor)

	# ── Séparateur ──────────────────────────────────────────
	var sep_line := ColorRect.new()
	sep_line.color                 = Color(rcolor.r, rcolor.g, rcolor.b, 0.30)
	sep_line.custom_minimum_size   = Vector2(0, 1)
	sep_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sep_line)
	_fade_register(sep_line)

	# ── Contenu scrollable ──────────────────────────────────
	var content_m := MarginContainer.new()
	content_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_m.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		content_m.add_theme_constant_override(side, 18)
	col.add_child(content_m)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_m.add_child(scroll)

	# Marge droite : évite que les valeurs touchent la scrollbar.
	var scroll_m := MarginContainer.new()
	scroll_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_m.add_theme_constant_override("margin_right", 14)
	scroll.add_child(scroll_m)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 16)
	scroll_m.add_child(vb)

	_fill_content(vb, data, biome, biome_name, tcolor)

	# ── Footer : Retour au village uniquement ────────────────
	var btn_m := MarginContainer.new()
	btn_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m.add_theme_constant_override("margin_left", 18)
	btn_m.add_theme_constant_override("margin_right", 18)
	btn_m.add_theme_constant_override("margin_top", 8)
	btn_m.add_theme_constant_override("margin_bottom", 14)
	col.add_child(btn_m)

	var btn := Button.new()
	btn.text = Translations.T("cycle.back_village")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 50)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", rcolor.lightened(0.20))
	btn.add_theme_color_override("font_hover_color", rcolor.lightened(0.45))
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(rcolor, 0.10, 0.70, 1, 8))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(rcolor, 0.22, 1.0, 1, 8))
	btn.pressed.connect(_go_to_village)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(btn)
	btn_m.add_child(btn)
	_fade_register(btn_m)

# ── Bannière de résultat : aura radiale + titre + sous-titre ──
func _build_banner(col: VBoxContainer, rtext: String, rcolor: Color,
		biome_name: String) -> void:
	var zone := Control.new()
	zone.custom_minimum_size   = Vector2(0, 104)
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	col.add_child(zone)

	_aura = TextureRect.new()
	_aura.texture = UIHelpers.radial_glow_tex(256, [0.0, 0.55, 1.0], [0.50, 0.16, 0.0])
	_aura.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_aura.stretch_mode = TextureRect.STRETCH_SCALE
	_aura.modulate     = Color(rcolor.r, rcolor.g, rcolor.b, 0.0)
	_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(_aura)

	_banner_box = VBoxContainer.new()
	_banner_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	(_banner_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_banner_box as VBoxContainer).add_theme_constant_override("separation", 2)
	_banner_box.modulate.a = 0.0
	zone.add_child(_banner_box)

	var title := Label.new()
	title.text = "✦   %s   ✦" % rtext.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", rcolor.lightened(0.30))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_banner_box.add_child(title)

	var sub := Label.new()
	sub.text = Translations.T("cycle.title") % biome_name.to_upper()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	_banner_box.add_child(sub)

	# Shine périodique + burst de révélation, par-dessus le titre.
	_banner_fx = SummaryFX.new()
	_banner_fx.mode   = SummaryFX.Mode.BANNER
	_banner_fx.accent = rcolor
	_banner_fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	zone.add_child(_banner_fx)

# ── Puces de stats : valeur à compteur + libellé ────────────
func _build_stat_chips(col: VBoxContainer, data: Dictionary, rcolor: Color) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 0)
	m.add_theme_constant_override("margin_bottom", 14)
	col.add_child(m)
	_fade_register(m)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var events       := int(data.get("events", 0))
	var events_total := int(data.get("events_total", 0))
	_stat_chip(row, "⚔", float(data.get("combats_won", 0)),
			Translations.T("cycle.stat.combats"), UIColors.LOG_COMBAT,
			func(v: float) -> String: return "%d" % int(v))
	_stat_chip(row, "✦", float(events),
			Translations.T("cycle.stat.events"), UIColors.LOG_EVENT,
			func(v: float) -> String: return "%d / %d" % [int(v), events_total])
	_stat_chip(row, "🎒", float(data.get("loot_total", 0)),
			Translations.T("cycle.stat.loot"), UIColors.LOG_LOOT,
			func(v: float) -> String: return "%d" % int(v))
	_stat_chip(row, "✨", float(data.get("xp_total", 0.0)),
			Translations.T("cycle.stat.xp"), rcolor,
			func(v: float) -> String: return UIHelpers.xp_fmt(int(v)))

func _stat_chip(row: HBoxContainer, icon: String, value: float,
		label: String, color: Color, fmt: Callable) -> void:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(150, 0)
	chip.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.08, 0.35, 1, 8))
	row.add_child(chip)

	var m := UIHelpers.margin_of(8)
	chip.add_child(m)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	m.add_child(vb)

	var val_lbl := Label.new()
	val_lbl.text = fmt.call(0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 19)
	val_lbl.add_theme_color_override("font_color", color.lightened(0.25))
	vb.add_child(val_lbl)

	var name_lbl := Label.new()
	name_lbl.text = "%s %s" % [icon, label.to_upper()]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vb.add_child(name_lbl)

	_counters.append({"label": val_lbl, "chip": chip, "to": value, "fmt": fmt})

# ═══════════════════════════════════════════════════════════
#  Contenu
# ═══════════════════════════════════════════════════════════

func _fill_content(vb: VBoxContainer, data: Dictionary,
		biome: Dictionary, biome_name: String, tcolor: Color) -> void:
	_section_discoveries(vb, data, biome, tcolor)
	_section_loot(vb, data, tcolor)
	_section_xp(vb, data, biome_name, tcolor)
	_section_evolutions(vb)

# ── Section 1 : Découvertes de CETTE expédition ────────────
# Liste les entités vues pour la PREMIÈRE fois pendant ce cycle (et la
# créature Unique si elle vient d'être vaincue). La progression cumulée
# « Entités x/y » du biome vit dans le panneau Expéditions — ici on ne
# célèbre que la nouveauté. Section ABSENTE si rien de neuf : son
# apparition est l'événement.
func _section_discoveries(vb: VBoxContainer, data: Dictionary,
		biome: Dictionary, tcolor: Color) -> void:
	var newd          := data.get("new_discoveries", []) as Array
	var unique_beaten := data.get("unique_beaten", false) as bool
	if newd.is_empty() and not unique_beaten:
		return

	var sec := UIHelpers.collapsible_section(Translations.T("cycle.section.discoveries"), tcolor)
	vb.add_child(sec["wrapper"])
	_fade_register(sec["wrapper"])
	var body_dec := sec["body"] as VBoxContainer

	for eid: String in newd:
		var e := GameData.get_entity(eid)
		var cat_label := ""
		var cat_color := UIColors.CARD_NEUTRAL
		match e.get("entity_type", ""):
			Enums.EntityType.CREATURE:
				cat_label = Translations.T("adv.cat.creature")
				cat_color = UIColors.TYPE_CREATURE
			Enums.EntityType.TRAP:
				cat_label = Translations.T("adv.cat.trap")
				cat_color = UIColors.TYPE_TRAP
			Enums.EntityType.BENEDICTION:
				cat_label = Translations.T("adv.cat.blessing")
				cat_color = UIColors.TYPE_BENEDICTION
		body_dec.add_child(_discovery_new_row(cat_label, cat_color,
				Translations.entity_name(e, eid)))

	if unique_beaten:
		var uniq_id := (biome.get("creature_unique", {}) as Dictionary).get("id", "") as String
		var uname   := Translations.entity_name(GameData.get_entity(uniq_id), uniq_id)
		body_dec.add_child(_unique_beaten_row(uname))

# Ligne « Catégorie · Nom         NOUVEAU » d'une première rencontre.
func _discovery_new_row(cat_label: String, cat_color: Color, nom: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(cat_color, 0.06, 0.40, 1, 4))
	_fade_register(panel)

	var m := UIHelpers.margin_of(6)
	panel.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	m.add_child(hb)

	if cat_label != "":
		var cl := Label.new()
		cl.text = cat_label + " · "
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", Color(cat_color, 0.85))
		hb.add_child(cl)

	var nl := Label.new()
	nl.text = nom
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.add_theme_font_size_override("font_size", 12)
	nl.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(nl)

	var badge := Label.new()
	badge.text = Translations.T("cycle.discovery.new")
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", UIColors.SELECTION_GOLD)
	hb.add_child(badge)
	return panel

# Ligne « ★ Créature unique vaincue · Nom » (couleur Unique).
func _unique_beaten_row(nom: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TIER_UNIQUE, 0.08, 0.55, 1, 4))
	_fade_register(panel)

	var m := UIHelpers.margin_of(6)
	panel.add_child(m)
	var lbl := Label.new()
	lbl.text = "★  %s · %s" % [Translations.T("cycle.discovery.unique_beaten"), nom]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UIColors.TIER_UNIQUE.lightened(0.25))
	m.add_child(lbl)
	return panel

# ── Section 2 : Ressources collectées (puces) ──────────────
func _section_loot(vb: VBoxContainer, data: Dictionary, tcolor: Color) -> void:
	var loot_detail := data.get("loot_detail", {}) as Dictionary
	if loot_detail.is_empty():
		return
	var sec := UIHelpers.collapsible_section(Translations.T("cycle.section.resources"), tcolor)
	vb.add_child(sec["wrapper"])
	_fade_register(sec["wrapper"])
	var body_loot := sec["body"] as VBoxContainer

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_loot.add_child(flow)

	for item_id: String in loot_detail:
		var qty       := int(loot_detail[item_id])
		var item      := GameData.get_entity(item_id)
		var nom       := Translations.entity_name(item, item_id)
		var is_unique := item.get("est_unique", false) as bool
		var ic        := UIColors.TIER_LEGENDAIRE if is_unique else UIColors.FILTER_ON

		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIHelpers.card_style(ic, 0.08, 0.40, 1, 6))
		flow.add_child(chip)

		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 10)
		m.add_theme_constant_override("margin_right", 10)
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(m)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		m.add_child(hb)

		var nl := Label.new()
		nl.text = ("✦ %s" % nom) if is_unique else nom
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(nl)

		var ql := Label.new()
		ql.text = "×%d" % qty
		ql.add_theme_font_size_override("font_size", 12)
		ql.add_theme_color_override("font_color", ic)
		hb.add_child(ql)

# ── Section 3 : Répartition XP ─────────────────────────────
# Section ABSENTE si aucune entité n'a gagné d'XP ce cycle.
func _section_xp(vb: VBoxContainer, data: Dictionary,
		biome_name: String, tcolor: Color) -> void:
	# Collecte d'abord les lignes affichables (gain > 0, entité connue) :
	# la section n'est construite que s'il y en a au moins une.
	var rows: Array = []   # [icône, label, entity, gained]
	var cid := data.get("hero_id", "") as String
	rows.append(["⚔", Translations.T("cycle.hero_label"), GameData.get_entity(cid), data.get("xp_hero", 0.0) as float])
	rows.append(["🌿", biome_name, GameData.get_entity(data.get("biome_id", "") as String), data.get("xp_biome", 0.0) as float])

	var entities_xp := data.get("xp_entities_detail", {}) as Dictionary
	for ent_id: String in entities_xp:
		var e := GameData.get_entity(ent_id)
		var icon := "🐾"
		match e.get("entity_type", ""):
			Enums.EntityType.TRAP:        icon = "▲"
			Enums.EntityType.BENEDICTION: icon = "✦"
		rows.append([icon, Translations.entity_name(e, ent_id), e, entities_xp[ent_id] as float])

	var detail := data.get("xp_passives_detail", {}) as Dictionary
	for passive_id: String in detail:
		var p := GameData.get_entity(passive_id)
		rows.append(["⚡", Translations.entity_name(p, passive_id), p, detail[passive_id] as float])

	var equip_detail := data.get("xp_equip_detail", {}) as Dictionary
	for equip_id: String in equip_detail:
		var eq := GameData.get_entity(equip_id)
		rows.append(["🔨", Translations.entity_name(eq, equip_id), eq, equip_detail[equip_id] as float])

	var shown: Array = rows.filter(func(r: Array) -> bool:
		return (r[3] as float) > 0.0 and not (r[2] as Dictionary).is_empty())
	if shown.is_empty():
		return

	var sec_xp := UIHelpers.collapsible_section(Translations.T("cycle.section.xp"), tcolor)
	vb.add_child(sec_xp["wrapper"])
	_fade_register(sec_xp["wrapper"])
	var body_xp := sec_xp["body"] as VBoxContainer
	for r: Array in shown:
		_xp_entity(body_xp, r[0] as String, r[1] as String, r[2] as Dictionary, r[3] as float)

# Ajoute une ligne XP pour une entité ayant reçu de l'XP ce cycle (sinon ignorée).
# La couleur de la carte = couleur du palier (tier) courant de l'entité.
# xp_avant = XP au début du cycle, xp_apres = XP à la fin, xp_max = seuil du palier courant.
func _xp_entity(vb: VBoxContainer, icon: String, label: String, entity: Dictionary,
		gained: float) -> void:
	if gained <= 0.0 or entity.is_empty():
		return
	var tier      := entity.get("maitrise_actuelle", 0) as int
	var xp_max    := _next_tier_threshold(entity)
	var xp_apres  := entity.get("xp_maitrise_actuelle", 0.0) as float
	var xp_avant  := maxf(xp_apres - gained, 0.0)
	var avant_frac := clampf(xp_avant / xp_max, 0.0, 1.0) if xp_max > 0.0 else 0.0
	var apres_frac := clampf(xp_apres / xp_max, 0.0, 1.0) if xp_max > 0.0 else 1.0

	var card := _xp_card(icon, label, tier, xp_apres, xp_max, entity.get("entity_type", "") as String)
	(card["card"] as XPCard).xp_fill = avant_frac
	vb.add_child(card["container"])
	_fade_register(card["container"])
	_xp_anims.append({
		"card":        card["card"],
		"xp_label":    card["xp_label"],
		"gained":      gained,
		"before_frac": avant_frac,
		"after_frac":  apres_frac,
	})

# ── Section 4 : Évolutions disponibles ─────────────────────
# Section ABSENTE quand rien n'est prêt à évoluer : son apparition
# signale à elle seule qu'une évolution attend le joueur.
func _section_evolutions(vb: VBoxContainer) -> void:
	var evolvable: Array[String] = []
	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") == Enums.EntityType.EQUIPMENT:
			continue
		if MasterySystem.can_evolve(eid):
			evolvable.append(eid)
	if evolvable.is_empty():
		return

	var sec_ev := UIHelpers.collapsible_section(Translations.T("cycle.section.evolutions"), UIColors.FILTER_ON)
	vb.add_child(sec_ev["wrapper"])
	_fade_register(sec_ev["wrapper"])
	var body_ev := sec_ev["body"] as VBoxContainer
	for eid in evolvable:
		_evolution_card(body_ev, eid, GameData.entities[eid] as Dictionary)

func _evolution_card(vb: VBoxContainer, entity_id: String, entity: Dictionary) -> void:
	var tier := entity.get("maitrise_actuelle", 0) as int
	var nc   := UIColors.tier_color(tier + 1)
	var nom  := Translations.entity_name(entity, entity_id)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.10, 0.60, 1, 4))
	vb.add_child(panel)
	_fade_register(panel)

	var m := UIHelpers.margin_of(8)
	panel.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = nom
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = "%s  →  %s" % [GameData.get_tier_name(tier), GameData.get_tier_name(tier + 1)]
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", nc)
	info.add_child(tier_lbl)

	var btn := Button.new()
	btn.text = Translations.T("btn.evolve")
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", nc)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(nc, 0.15, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(nc, 0.30, 1.0, 1, 4))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var etype := entity.get("entity_type", Enums.EntityType.CREATURE) as String
	btn.pressed.connect(_launch_evolution.bind(entity_id, nom, etype, tier))
	hb.add_child(btn)

# Déclenche l'évolution (manuel) puis le rituel — réutilise le flux existant.
func _launch_evolution(entity_id: String, entity_name: String,
		entity_type: String, from_tier: int) -> void:
	if not MasterySystem.evolve_entity(entity_id):
		return
	SaveManager.save()
	GameData.pending_evolution = {
		"entity_type": entity_type,
		"entity_id":   entity_id,
		"entity_name": entity_name,
		"from_tier":   from_tier,
		"to_tier":     from_tier + 1,
	}
	get_tree().change_scene_to_file("res://scenes/village/EvolutionRitual.tscn")

# ═══════════════════════════════════════════════════════════
#  Animations
# ═══════════════════════════════════════════════════════════

func _fade_register(node: Control) -> void:
	node.modulate.a = 0.0
	_fade_nodes.append(node)

# Révélation LENTE et séquentielle : bannière en punch, puis chaque élément
# (puces, séparateur, sections, lignes, cartes XP, bouton) apparaît l'un après
# l'autre toutes les REVEAL_STAGGER s. Le joueur peut tout afficher d'un coup
# par un double-clic souris (_skip_to_end).
func _run_animation_sequence() -> void:
	await get_tree().process_frame
	if _banner_box == null:
		return

	# Carte XP → ses données d'anim, déclenchées au reveal de la carte.
	for xp: Dictionary in _xp_anims:
		_xp_by_card[xp["card"]] = xp

	# Bannière : punch-in (scale TRANS_BACK) + fondu + burst d'étincelles.
	_banner_box.pivot_offset = _banner_box.size * 0.5
	_banner_box.scale = Vector2(1.35, 1.35)
	var tw := _track(create_tween()).set_parallel(true)
	tw.tween_property(_banner_box, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner_box, "scale", Vector2.ONE, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_banner_fx.fire_burst).set_delay(0.18)

	# Aura : respiration continue derrière le titre (NON suivie → survit au skip).
	var pa := create_tween().set_loops()
	pa.tween_property(_aura, "modulate:a", 0.42, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pa.tween_property(_aura, "modulate:a", 0.20, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Révélation un élément à la fois, ~REVEAL_STAGGER s d'intervalle.
	var master := _track(create_tween())
	for i in _fade_nodes.size():
		master.tween_interval(REVEAL_STAGGER)
		master.tween_callback(_reveal_node.bind(i))
	master.tween_callback(func() -> void: _seq_done = true)

# Révèle l'élément i en fondu, et déclenche l'anim qui lui est rattachée
# (compteurs des puces pour le 1er élément, remplissage pour une carte XP).
func _reveal_node(i: int) -> void:
	if _seq_done:
		return
	var node := _fade_nodes[i] as Control
	if not is_instance_valid(node):
		return
	var tw := _track(create_tween())
	tw.tween_property(node, "modulate:a", 1.0, FADE_IN_TIME).set_ease(Tween.EASE_OUT)

	if i == 0:                       # puces de stats (1er nœud enregistré)
		_start_counters()
	if _xp_by_card.has(node):        # carte de répartition XP
		_animate_xp_card(_xp_by_card[node] as Dictionary, 0.0)

# Compteurs des puces de stats — chaque puce « pop » à la fin du sien.
func _start_counters() -> void:
	for c: Dictionary in _counters:
		var lbl  := c["label"] as Label
		var fmt  := c["fmt"] as Callable
		var chip := c["chip"] as Control
		var ctw := _track(create_tween())
		ctw.tween_method(func(v: float) -> void: lbl.text = fmt.call(v),
				0.0, c["to"] as float, 0.80) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		ctw.tween_callback(_pop.bind(chip))

func _track(tw: Tween) -> Tween:
	_running_tweens.append(tw)
	return tw

# Double-clic souris : stoppe la séquence et affiche tout dans son état final.
func _input(event: InputEvent) -> void:
	if _seq_done:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.double_click:
			_skip_to_end()
			get_viewport().set_input_as_handled()

func _skip_to_end() -> void:
	if _seq_done:
		return
	_seq_done = true
	for t in _running_tweens:
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	if is_instance_valid(_banner_box):
		_banner_box.modulate.a = 1.0
		_banner_box.scale      = Vector2.ONE
	for node: Control in _fade_nodes:
		if is_instance_valid(node):
			node.modulate.a = 1.0
	for c: Dictionary in _counters:
		var lbl := c["label"] as Label
		if is_instance_valid(lbl):
			lbl.text = (c["fmt"] as Callable).call(c["to"] as float)
	for xp: Dictionary in _xp_anims:
		var card := xp["card"] as XPCard
		var xlbl := xp["xp_label"] as Label
		if is_instance_valid(card):
			card.xp_fill    = xp["after_frac"]
			card.gain_start = -1.0
			card.gain_t     = 0.0
		if is_instance_valid(xlbl):
			xlbl.text = "+%.0f XP" % (xp["gained"] as float)

# Petit rebond d'accentuation (fin de compteur, fin de barre XP).
func _pop(node: Control, amount: float = 1.05) -> void:
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * amount, 0.10) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Anime une carte : remplissage avant → après + compteur « +X XP » en or,
# puis fondu du segment gagné vers la couleur du tier.
func _animate_xp_card(xp: Dictionary, delay: float) -> void:
	var card   : XPCard = xp["card"]
	var xp_lbl : Label  = xp["xp_label"]
	var gained : float  = xp["gained"]
	var before : float  = xp["before_frac"]
	var after  : float  = xp["after_frac"]

	card.xp_fill    = before
	card.gain_start = before
	card.gain_t     = 1.0
	xp_lbl.text     = "+0 XP"

	var tw := _track(create_tween())
	tw.set_parallel(true)
	tw.tween_property(card, "xp_fill", after, XP_FILL_TIME) \
			.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void:
		xp_lbl.text = "+%.0f XP" % v
	, 0.0, gained, XP_FILL_TIME).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Fin du remplissage : gerbe d'étincelles + petit rebond de la carte,
	# puis fondu or → couleur du tier. set_parallel(false) : tout ce qui
	# suit doit s'enchaîner (chain() ne chaînerait que le tweener suivant).
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		card.spawn_completion_sparks()
		_pop(card, 1.015)
	)
	tw.tween_property(card, "gain_t", 0.0, 0.5) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void: card.gain_start = -1.0)

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

# Seuil XP du prochain tier de l'entité (dernier seuil si au max).
func _next_tier_threshold(entity: Dictionary) -> float:
	var tier := entity.get("maitrise_actuelle", 0) as int
	var next_idx := tier + 1
	if tier >= GameData.get_max_tier_for_type(entity.get("entity_type", "")) or next_idx >= GameData.xp_thresholds.size():
		return float(GameData.xp_thresholds.back())
	return float(GameData.xp_thresholds[next_idx])

# Carte XP du récap : carte d'entité commune (UIHelpers.entity_xp_card —
# même DA que les panneaux du Village : fond rempli, « icône | nom | palier |
# XP à droite ») + un gain « +X XP » vert greffé à droite de l'en-tête, animé
# (compteur 0→gain) en parallèle du remplissage du fond.
# Retourne { container, card, xp_label } pour l'animation (_animate_xp_card).
func _xp_card(icon: String, label: String, tier: int,
		xp_apres: float, xp_max: float, entity_type: String = "") -> Dictionary:
	var built := UIHelpers.entity_xp_card(label, tier, xp_apres, xp_max, icon, entity_type)
	var card := built["card"] as XPCard
	var header := built["header"] as HBoxContainer

	var gain_lbl := Label.new()
	gain_lbl.text = "+0 XP"
	gain_lbl.add_theme_font_size_override("font_size", 12)
	gain_lbl.add_theme_color_override("font_color", UIColors.LOG_VICTORY)
	header.add_child(gain_lbl)

	return {"container": card, "card": card, "xp_label": gain_lbl}

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

func _go_to_village() -> void:
	UIHelpers.fade_to_scene(self, "res://scenes/village/village.tscn")
