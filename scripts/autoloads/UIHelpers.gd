# ============================================================
# UIHelpers.gd — Autoload de factories UI réutilisables.
#
# Centralise toutes les constructions de nœuds répétitives du
# projet : marges, styles, barres XP, headers de scènes, etc.
#
# Toutes les fonctions sont statiques → UIHelpers.fonction().
# Aucun état interne : ce script ne fait que fabriquer des nœuds.
# Classe utilitaire (class_name), pas un autoload : les appels statiques
# se résolvent directement sur le type.
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

# Initialise parent comme scène fullscreen : fond BG_DARK + VBoxContainer zero-gap.
# Retourne le VBoxContainer racine, prêt à recevoir les sections de la scène.
static func fullscreen_root(parent: Control) -> VBoxContainer:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	parent.add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	parent.add_child(root)
	return root

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

# Retourne un VBoxContainer contenant un Label titre coloré + un ColorRect séparateur.
# Utilisé comme en-tête de sous-section dans Village.gd, CombatScene.gd, etc.
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

# Retourne un PanelContainer stylisé tier : card_style + section_header + contenu du builder.
# builder(vbox: VBoxContainer) est appelé pour peupler le contenu sous le header.
static func info_panel(title: String, color: Color, builder: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", card_style(color))
	var m := margin_of(8)
	panel.add_child(m)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	m.add_child(vbox)
	vbox.add_child(section_header(title, color))
	builder.call(vbox)
	return panel

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
		xp_lbl.text = "RANG MAX"
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
	lbl.text = "Aucun"
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

# Retourne la barre de navigation commune aux scènes secondaires :
#   [← Village]  TITRE CENTRÉ
# on_back est connecté au pressed du bouton retour.
# Branche un tooltip JRPG sur node : hover → TooltipOverlay.show_for, exit → hide.
static func register_tooltip(node: Control, title: String, body: String, color: Color = Color.WHITE) -> void:
	node.mouse_entered.connect(func() -> void: TooltipOverlay.show_for(title, body, color))
	node.mouse_exited.connect(TooltipOverlay.hide_tooltip)

static func scene_header_bar(title: String, color: Color, on_back: Callable) -> Control:
	var bar  := PanelContainer.new()
	var m    := margin_of(14)
	bar.add_child(m)
	var hbox := HBoxContainer.new()
	m.add_child(hbox)
	var back := Button.new()
	back.text = "← Village"
	back.pressed.connect(on_back)
	hbox.add_child(back)
	var lbl := Label.new()
	lbl.text                 = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	hbox.add_child(lbl)
	return bar
