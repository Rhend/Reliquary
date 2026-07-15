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

# Variante IMMÉDIATE : détache tout de suite (la libération reste différée).
# Requise quand le conteneur est reconstruit plusieurs fois dans la même
# frame (ex. file d'initiative CTB) — queue_free seul laisse les anciens
# enfants comptés/affichés jusqu'à la fin de frame (doublons transitoires).
static func clear_children_now(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

# ═══════════════════════════════════════════════════════════
#  Texte
# ═══════════════════════════════════════════════════════════

# Label stylé en une ligne : pose texte + taille de police + couleur.
# Centralise le boilerplate Label.new()/add_theme_*_override répété ~150× dans
# le projet. Le caller peut ensuite poser ses props supplémentaires (alignement,
# size_flags, autowrap…) sur le Label retourné.
static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

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

# Scintillement néon partagé (cadre de panel, contour des XPCard) : reste à 1.0
# la plupart du temps, puis « grésille » ~0.6 s par cycle (créneaux rapides entre
# sombre et clair) avant de se rallumer franchement. `t` = horloge locale du nœud.
static func neon_flicker(t: float) -> float:
	const PERIOD := 3.8   # un épisode de grésillement toutes les ~3.8 s
	const WINDOW := 0.6   # durée d'un épisode (~0.5–0.7 s)
	var ph := fmod(t, PERIOD)
	if ph < PERIOD - WINDOW:
		return 1.0
	var u := (ph - (PERIOD - WINDOW)) / WINDOW     # 0→1 sur la fenêtre
	# Créneaux rapides + plancher qui remonte : le tube se rallume en bafouillant.
	var buzz: float = 1.0 if sin(u * TAU * 11.0) > 0.0 else lerpf(0.35, 0.85, u)
	return buzz

# Texture radiale blanche → transparente (dégradé interpolé par le GPU :
# aucun banding, contrairement à des disques concentriques empilés).
# `offsets`/`alphas` décrivent le falloff du centre (0.0) au bord (1.0).
# À dessiner via draw_texture_rect(tex, rect, false, couleur) — la couleur
# module la teinte ET l'alpha global. Construire UNE fois (dans _ready).
static func radial_glow_tex(px: int, offsets: Array[float],
		alphas: Array[float]) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := PackedColorArray()
	for a in alphas:
		cols.append(Color(1, 1, 1, a))
	g.offsets = PackedFloat32Array(offsets)
	g.colors  = cols
	var tex := GradientTexture2D.new()
	tex.gradient  = g
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = px
	tex.height    = px
	return tex

# ═══════════════════════════════════════════════════════════
#  Effets flottants (chiffres / textes qui montent + fondu)
# ═══════════════════════════════════════════════════════════

# Texte flottant générique : monte verticalement et se fond, sur la couche FX
# `host` (Control). Mutualise le mécanisme historique de CombatRing (dégâts /
# soins / poison) pour qu'il serve aussi à l'XP flottante en scène de combat.
# `punch` : gros détourage + claquement d'échelle (réservé aux temps forts).
static func float_text(host: Control, text: String, font_size: int, color: Color,
		start_pos: Vector2, rise: float = 60.0, punch: bool = false,
		life: float = 1.2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 6 if punch else 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = start_pos
	host.add_child(lbl)

	if punch:
		lbl.scale = Vector2(1.6, 1.6)
		lbl.resized.connect(func() -> void:
			lbl.pivot_offset = lbl.size * 0.5
		, CONNECT_ONE_SHOT)
		host.create_tween().tween_property(lbl, "scale", Vector2.ONE, 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tw := host.create_tween()
	tw.tween_property(lbl, "position:y", start_pos.y - rise, life * 0.83) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, life * 0.58).set_delay(life * 0.25)
	# Suppression garantie via un timer indépendant du Tween.
	host.get_tree().create_timer(life).timeout.connect(lbl.queue_free)
	return lbl

# Halo de palier : anneau lumineux qui jaillit (expansion + fondu) à `center`,
# teinté `color`. Sert à marquer « palier atteignable » de façon impossible à
# rater. Le TextureRect et son tween appartiennent à `host` (auto-libérés avec).
static func tier_halo_burst(host: Control, center: Vector2, color: Color,
		final_radius: float = 110.0) -> void:
	# Anneau : creux au centre, crête à mi-rayon, éteint au bord.
	var tex := radial_glow_tex(128, [0.0, 0.5, 1.0], [0.0, 0.85, 0.0])
	var d := final_radius * 2.0
	var tr := TextureRect.new()
	tr.texture        = tex
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode   = TextureRect.STRETCH_SCALE
	tr.size           = Vector2(d, d)
	tr.pivot_offset   = Vector2(d, d) * 0.5
	tr.position       = center - Vector2(d, d) * 0.5
	tr.modulate       = Color(color.r, color.g, color.b, 0.95)
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)

	tr.scale = Vector2(0.25, 0.25)
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(tr, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	host.get_tree().create_timer(0.7).timeout.connect(tr.queue_free)

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
	# Le contour est désormais le NÉON dessiné par XPCard lui-même : on retire la
	# bordure du stylebox (on garde fond + coins arrondis) et on transmet rayon +
	# épaisseur pour que le tube néon épouse exactement la carte.
	var sb := card_style(fill_color, bg_alpha, border_alpha, border_width, corner_radius)
	sb.set_border_width_all(0)
	card.add_theme_stylebox_override("panel", sb)
	card.corner_rad = float(corner_radius)
	card.border_w   = float(border_width)
	return card

# Carte XP standard d'une entité — DA UNIQUE du jeu pour ce motif.
# XPCard (fond rempli au palier courant) + en-tête « [icône] nom (gauche) |
# palier + XP (CENTRE) | extras (droite) ». À réutiliser partout plutôt que
# reconstruire l'en-tête à la main. Palier max → xp_max = 0 → « RANG MAX ».
# icon : préfixe optionnel (emoji/symbole) devant le nom (ex. récap de cycle).
# entity_type : détermine le motif de particules de la barre (cf. XPCard.motif_for_type).
# Retourne { card, header } : ajouter `card` au parent ; tout élément greffé
# ensuite sur `header` (compteur, badge de slot, gain « +X XP », flèche
# d'accordéon…) atterrit TOUT À DROITE, après le bloc central.
static func entity_xp_card(display_name: String, tier: int, xp: float, xp_max: float,
		icon: String = "", entity_type: String = "") -> Dictionary:
	var color := UIColors.tier_color(tier)
	var at_max := xp_max <= 0.0
	var frac := 0.0
	if not at_max:
		frac = clampf(xp / xp_max, 0.0, 1.0)

	var card := xp_panel(color, frac, 0.07, 0.60, 1, 4, XPCard.motif_for_type(entity_type))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# COUCHE 1 — flux normal : nom (+icône) à gauche, extras de l'appelant à
	# droite. Pilote la hauteur de la carte. left_box en EXPAND_FILL pousse les
	# extras contre le bord droit. Boîtes en IGNORE : leurs zones vides laissent
	# passer le clic vers la carte (sélection de biome, etc.).
	var m := margin_of(8)
	card.add_child(m)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(header)

	var left_box := HBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 8)
	left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(left_box)

	var right_box := HBoxContainer.new()
	right_box.alignment = BoxContainer.ALIGNMENT_END
	right_box.add_theme_constant_override("separation", 8)
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(right_box)

	if not icon.is_empty():
		var icon_lbl := Label.new()
		icon_lbl.text = icon
		icon_lbl.add_theme_font_size_override("font_size", 14)
		icon_lbl.add_theme_color_override("font_color", color)
		left_box.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	left_box.add_child(name_lbl)

	# COUCHE 2 — bloc central (palier + XP) SUPERPOSÉ et centré sur la carte.
	# XPCard est un PanelContainer : il empile ses enfants en plein cadre, donc
	# ce CenterContainer occupe la même zone que la couche 1 et centre son
	# contenu à largeur/2 — position INDÉPENDANTE de la longueur du nom à gauche,
	# donc identique (pixel-perfect) d'une carte à l'autre. margin_of pose des
	# marges égales → la couche 1 est aussi centrée verticalement : les deux
	# couches restent sur la même ligne.
	var center_overlay := CenterContainer.new()
	center_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(center_overlay)

	var center_box := HBoxContainer.new()
	center_box.add_theme_constant_override("separation", 8)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_overlay.add_child(center_box)

	var tbadge := Label.new()
	tbadge.text = GameData.get_tier_name(tier)
	tbadge.add_theme_font_size_override("font_size", 11)
	tbadge.add_theme_color_override("font_color", color)
	center_box.add_child(tbadge)

	var xp_lbl := Label.new()
	if at_max:
		xp_lbl.text = Translations.T("tier.max_rank")
		xp_lbl.add_theme_color_override("font_color", color)
	else:
		xp_lbl.text = "XP  %s / %s" % [xp_fmt(int(xp)), xp_fmt(int(xp_max))]
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	xp_lbl.add_theme_font_size_override("font_size", 10)
	center_box.add_child(xp_lbl)

	# `header` renvoyé = colonne DROITE : tout extra greffé par l'appelant
	# (compteur, badge de slot, gain « +X XP », flèche d'accordéon) atterrit là,
	# aligné à droite, sans déséquilibrer le centrage du bloc central.
	return {"card": card, "header": right_box}

# Formate un entier XP avec séparateur de milliers (ex: 1 234).
static func xp_fmt(xp: int) -> String:
	if xp >= 1000:
		var s := str(xp)
		return s.left(s.length() - 3) + " " + s.right(3)
	return str(xp)

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

# ═══════════════════════════════════════════════════════════
#  Bouton Évoluer (juicy)
# ═══════════════════════════════════════════════════════════

# Bande de reflet diagonale (transparent → blanc → transparent) pour le
# balayage lumineux des boutons. Construite à la demande (boutons rares).
static func _shine_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors  = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width  = 64
	tex.height = 64
	tex.fill_from = Vector2(0.15, 0.0)
	tex.fill_to   = Vector2(0.85, 0.45)   # bande inclinée
	return tex

# Bouton d'évolution premium, coloré au tier CIBLE :
#   • respiration au repos (échelle + lueur de bordure synchronisées) ;
#   • reflet lumineux balayant périodique + au survol ;
#   • hover : pop ×1.07 (TRANS_BACK) ; press : squash ×0.94 puis rebond.
# L'appelant branche `pressed` et le tooltip (cf. Village.make_evolve_btn).
static func evolve_button(text: String, color: Color, font_size: int = 14) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	# Styleboxes dédiées — la bordure de `normal` est animée (lueur).
	var normal_sb := card_style(color, 0.14, 0.70, 1, 5)
	var hover_sb  := card_style(color, 0.30, 1.00, 2, 5)
	var press_sb  := card_style(color, 0.42, 1.00, 2, 5)
	btn.add_theme_stylebox_override("normal",  normal_sb)
	btn.add_theme_stylebox_override("hover",   hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	btn.resized.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5
	)

	# ── Reflet balayant ───────────────────────────────────────
	btn.clip_contents = true
	var shine := TextureRect.new()
	shine.texture = _shine_tex()
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	shine.stretch_mode = TextureRect.STRETCH_SCALE
	shine.visible = false
	btn.add_child(shine)
	var sweep := func() -> void:
		if not btn.is_visible_in_tree():
			return
		shine.size = Vector2(maxf(btn.size.x * 0.30, 36.0), btn.size.y)
		shine.position = Vector2(-shine.size.x, 0.0)
		shine.visible = true
		var stw := btn.create_tween()
		stw.tween_property(shine, "position:x", btn.size.x, 0.55) \
				.set_ease(Tween.EASE_IN_OUT)
		stw.tween_callback(func() -> void: shine.visible = false)

	# ── Respiration : échelle + lueur de bordure synchronisées ──
	# Array mutable partagé entre lambdas (évite CONFUSABLE_CAPTURE_REASSIGNMENT).
	var idle: Array = [null]
	var glow := func(a: float) -> void:
		normal_sb.border_color = Color(color.r, color.g, color.b, a)
	var start_pulse := func() -> void:
		if is_instance_valid(idle[0]):
			(idle[0] as Tween).kill()
		var tw := btn.create_tween().set_loops()
		idle[0] = tw
		tw.set_parallel(true)
		tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.65).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(glow, 0.45, 1.0, 0.65)
		tw.chain().tween_property(btn, "scale", Vector2.ONE, 0.65).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_method(glow, 1.0, 0.45, 0.65)

	# ── Hover / press ─────────────────────────────────────────
	var hov: Array = [null]
	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(idle[0]): (idle[0] as Tween).kill()
		if is_instance_valid(hov[0]):  (hov[0] as Tween).kill()
		hov[0] = btn.create_tween()
		(hov[0] as Tween).tween_property(btn, "scale", Vector2(1.07, 1.07), 0.14) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		sweep.call()   # petit reflet immédiat : récompense le survol
	)
	btn.mouse_exited.connect(func() -> void:
		if is_instance_valid(hov[0]): (hov[0] as Tween).kill()
		hov[0] = btn.create_tween()
		(hov[0] as Tween).tween_property(btn, "scale", Vector2.ONE, 0.18) \
				.set_ease(Tween.EASE_OUT)
		(hov[0] as Tween).tween_callback(start_pulse)
	)
	btn.button_down.connect(func() -> void:
		if is_instance_valid(hov[0]): (hov[0] as Tween).kill()
		hov[0] = btn.create_tween()
		(hov[0] as Tween).tween_property(btn, "scale", Vector2(0.94, 0.94), 0.06) \
				.set_ease(Tween.EASE_IN)
	)
	btn.button_up.connect(func() -> void:
		if is_instance_valid(hov[0]): (hov[0] as Tween).kill()
		hov[0] = btn.create_tween()
		(hov[0] as Tween).tween_property(btn, "scale", Vector2(1.07, 1.07), 0.16) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	)

	btn.ready.connect(func() -> void:
		start_pulse.call()
		# Balayage périodique du reflet.
		var loop_tw := btn.create_tween().set_loops()
		loop_tw.tween_interval(2.6)
		loop_tw.tween_callback(sweep)
	)
	return btn

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
