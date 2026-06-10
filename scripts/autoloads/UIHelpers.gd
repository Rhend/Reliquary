# ============================================================
# UIHelpers.gd — Factories UI réutilisables (pattern Factory).
#
# Centralise toutes les constructions de nœuds répétitives du
# projet : marges, styles, cartes XP, tooltips, transitions, etc.
#
# Classe utilitaire (class_name), PAS un autoload : toutes les
# fonctions sont statiques et se résolvent directement sur le
# type → UIHelpers.fonction(). Aucun état interne.
# ============================================================
class_name UIHelpers
extends Node

# ═══════════════════════════════════════════════════════════
#  Conteneurs
# ═══════════════════════════════════════════════════════════

# Applique la même marge (pixels) sur les 4 côtés d'un Control existant.
static func set_margins(ctrl: Control, value: int) -> void:
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		ctrl.add_theme_constant_override(side, value)

# Crée un MarginContainer avec la même marge sur les 4 côtés et le retourne.
static func margin_of(value: int) -> MarginContainer:
	var m := MarginContainer.new()
	set_margins(m, value)
	return m

# Supprime et libère tous les enfants directs d'un nœud.
static func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

# ═══════════════════════════════════════════════════════════
#  Styles
# ═══════════════════════════════════════════════════════════

# Retourne un StyleBoxFlat "carte tier" :
#   fond  = Color(color, bg_alpha)
#   bord  = Color(color, border_alpha)
#   épaisseur border = border_width px
#   coins arrondis   = corner_radius px
static func card_style(color: Color, bg_alpha: float = 0.07,
		border_alpha: float = 0.60, border_width: int = 1,
		corner_radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(color.r, color.g, color.b, bg_alpha)
	s.border_color = Color(color.r, color.g, color.b, border_alpha)
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(corner_radius)
	return s

# ═══════════════════════════════════════════════════════════
#  Composants
# ═══════════════════════════════════════════════════════════

# Section repliable : retourne {wrapper, body}.
# Ajouter wrapper au parent, peupler body avec le contenu.
# Cliquer sur l'en-tête bascule la visibilité du body.
#
# `state` (optionnel) : dictionnaire partagé où l'état ouvert/fermé est
# mémorisé sous la clé `state_key` (par défaut : le titre). Permet de
# conserver les sections ouvertes quand le panneau est reconstruit
# (cf. Village.panel_ui_state()).
static func collapsible_section(title: String, color: Color, start_open: bool = true,
		state: Dictionary = {}, state_key: String = "") -> Dictionary:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Bouton d'en-tête (remplace section_header)
	var btn := Button.new()
	btn.flat                = true
	btn.alignment           = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode          = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_pressed_color", color)
	btn.add_theme_color_override("font_hover_color", Color(color.r, color.g, color.b, 0.75))
	btn.add_theme_stylebox_override("normal",  StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover",   StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())

	var line := ColorRect.new()
	line.color                 = Color(color.r, color.g, color.b, 0.38)
	line.custom_minimum_size   = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hdr_vb := VBoxContainer.new()
	hdr_vb.add_theme_constant_override("separation", 4)
	hdr_vb.add_child(btn)
	hdr_vb.add_child(line)
	wrapper.add_child(hdr_vb)

	var key: String = state_key if state_key != "" else title
	var open: bool  = state.get(key, start_open)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = open
	wrapper.add_child(body)

	btn.text = title + ("  ▼  " if open else "  ▶  ")

	btn.pressed.connect(func() -> void:
		body.visible = not body.visible
		btn.text   = title + ("  ▼  " if body.visible else "  ▶  ")
		state[key] = body.visible
	)
	return {"wrapper": wrapper, "body": body}

static func section_header(title: String, color: Color) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	vb.add_child(lbl)
	var line := ColorRect.new()
	line.color                 = Color(color.r, color.g, color.b, 0.38)
	line.custom_minimum_size   = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(line)
	return vb

# Crée une XPCard (PanelContainer à fond rempli proportionnel à l'XP) déjà stylée
# en « carte de tier » (card_style). Le caller y ajoute ensuite son contenu
# (marge + labels). Factory commune des cartes d'entité du jeu (passifs, biomes,
# récap de cycle…) : centralise la création + le stylebox identiques partout.
static func xp_panel(fill_color: Color, xp_fill: float,
		bg_alpha: float = 0.07, border_alpha: float = 0.60,
		border_width: int = 1, corner_radius: int = 4,
		motif: int = XPCard.Motif.BUBBLES) -> XPCard:
	var card := XPCard.new()
	card.xp_fill    = clampf(xp_fill, 0.0, 1.0)
	card.fill_color = fill_color
	card.motif      = motif
	card.add_theme_stylebox_override("panel",
			card_style(fill_color, bg_alpha, border_alpha, border_width, corner_radius))
	return card

# Carte XP standard d'une entité — DA UNIQUE du jeu pour ce motif.
# XPCard (fond rempli au palier courant) + en-tête « [icône] nom (gauche) |
# palier (badge) | XP (droite) ». À réutiliser partout plutôt que reconstruire
# l'en-tête à la main. Palier max → passer xp_max = 0 → affiche « RANG MAX ».
# icon : préfixe optionnel (emoji/symbole) devant le nom (ex. récap de cycle).
# entity_type : détermine le motif de particules de la barre (cf. XPCard.motif_for_type).
# Retourne { card, header } : ajouter `card` au parent ; `header` (HBox) reste
# accessible pour y greffer un élément optionnel (flèche d'accordéon, gain…).
static func entity_xp_card(display_name: String, tier: int, xp: float, xp_max: float,
		icon: String = "", entity_type: String = "") -> Dictionary:
	var color := UIColors.tier_color(tier)
	var at_max := xp_max <= 0.0
	var frac := 0.0
	if not at_max:
		frac = clampf(xp / xp_max, 0.0, 1.0)

	var card := xp_panel(color, frac, 0.07, 0.60, 1, 4, XPCard.motif_for_type(entity_type))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m := margin_of(8)
	card.add_child(m)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(header)

	if not icon.is_empty():
		var icon_lbl := Label.new()
		icon_lbl.text = icon
		icon_lbl.add_theme_font_size_override("font_size", 14)
		icon_lbl.add_theme_color_override("font_color", color)
		header.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(name_lbl)

	var tbadge := Label.new()
	tbadge.text = GameData.get_tier_name(tier)
	tbadge.add_theme_font_size_override("font_size", 11)
	tbadge.add_theme_color_override("font_color", color)
	header.add_child(tbadge)

	var xp_lbl := Label.new()
	if at_max:
		xp_lbl.text = Translations.T("tier.max_rank")
		xp_lbl.add_theme_color_override("font_color", color)
	else:
		xp_lbl.text = "XP  %s / %s" % [xp_fmt(int(xp)), xp_fmt(int(xp_max))]
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(xp_lbl)

	return {"card": card, "header": header}

# Formate un entier XP avec séparateur de milliers (ex: 1 234).
static func xp_fmt(xp: int) -> String:
	if xp >= 1000:
		var s := str(xp)
		return s.left(s.length() - 3) + " " + s.right(3)
	return str(xp)

# Retourne un Label "Aucun" en TEXT_MUTED — état vide pour les listes.
static func none_label(font_size: int = 13) -> Label:
	var lbl := Label.new()
	lbl.text = Translations.T("ui.none")
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	return lbl

# Attache le feedback hover/press juice standard à n'importe quel Control cliquable.
# Hover  : scale ×1.03 (TRANS_BACK) + modulate ×1.30.
# Press  : squash ×0.95 + flash ×1.55, spring-back vers état hover.
# À appeler juste après avoir mis CURSOR_POINTING_HAND sur le nœud.
static func add_hover_feedback(node: Control) -> void:
	# Array mutable partagé entre lambdas pour éviter CONFUSABLE_CAPTURE_REASSIGNMENT.
	var h: Array = [null]
	node.mouse_entered.connect(func() -> void:
		node.pivot_offset = node.size * 0.5
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = node.create_tween()
		var tw := h[0] as Tween
		tw.set_parallel(true)
		tw.tween_property(node, "modulate", Color(1.30, 1.30, 1.30), 0.13).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector2(1.03, 1.03), 0.16) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	)
	node.mouse_exited.connect(func() -> void:
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = node.create_tween()
		var tw := h[0] as Tween
		tw.set_parallel(true)
		tw.tween_property(node, "modulate", Color.WHITE, 0.20).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector2.ONE, 0.20).set_ease(Tween.EASE_OUT)
	)
	node.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton \
				and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
			return
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = node.create_tween()
		var tw := h[0] as Tween
		tw.tween_property(node, "scale", Vector2(0.95, 0.95), 0.06) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(node, "modulate", Color(1.55, 1.55, 1.55), 0.06)
		tw.tween_property(node, "scale", Vector2(1.03, 1.03), 0.18) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(node, "modulate", Color(1.30, 1.30, 1.30), 0.14)
	)

# Branche un tooltip JRPG sur node : hover → TooltipOverlay.show_for, exit → hide.
static func register_tooltip(node: Control, title: String, body: String,
		color: Color = Color.WHITE, lore: String = "") -> void:
	# Déconnecte le tooltip précédent s'il y en a un (même nœud, nouveau contenu).
	if node.has_meta("_tt_cb"):
		var old_cb: Callable = node.get_meta("_tt_cb")
		if node.mouse_entered.is_connected(old_cb):
			node.mouse_entered.disconnect(old_cb)
	if node.mouse_exited.is_connected(TooltipOverlay.hide_tooltip):
		node.mouse_exited.disconnect(TooltipOverlay.hide_tooltip)
	var cb := func() -> void: TooltipOverlay.show_for(title, body, color, lore)
	node.set_meta("_tt_cb", cb)
	node.mouse_entered.connect(cb)
	node.mouse_exited.connect(TooltipOverlay.hide_tooltip)

# Fondu noir → changement de scène.
# Ajoute un ColorRect noir en overlay sur `root_node`, l'anime en fondu,
# puis change la scène. Durée du fade : 0.25s.
static func fade_to_scene(root_node: Node, scene_path: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_node.add_child(overlay)
	var tw := root_node.create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.22)
	tw.tween_callback(func() -> void:
		root_node.get_tree().change_scene_to_file(scene_path)
	)
