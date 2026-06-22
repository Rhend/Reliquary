# ============================================================
# TooltipOverlay — Tooltip JRPG oldschool global.
#
# Autoload CanvasLayer (layer 20). Affiché sur hover via
# UIHelpers.register_tooltip(node, title, body, color).
#
# Feel : apparition différée (anti-flicker quand on balaie une
# liste), fondu + zoom à l'ouverture, bascule instantanée d'une
# carte à l'autre (pas de clignotement), suivi de souris amorti,
# clamp aux bords du viewport.
# ============================================================
extends CanvasLayer

const MAX_WIDTH:  float = 340.0
const OFFSET:     Vector2 = Vector2(16.0, 12.0)
const MARGIN_PAD: float = 8.0
const SHOW_DELAY:   float = 0.10  # délai avant apparition (anti-flicker)
const FOLLOW_SPEED: float = 14.0  # amortissement du suivi de souris

var _panel:       PanelContainer
var _diamond_lbl: Label
var _title_lbl:   Label
var _lore_lbl:    Label
var _sep:         TextureRect
var _sep_grad:    Gradient
var _body_lbl:    RichTextLabel   # BBCode : autorise une colorisation par segment
var _border_color: Color = UIColors.TEXT_MUTED
var _show_token: int = 0   # invalide les apparitions différées obsolètes
var _fade_tw: Tween

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(120, 0)
	add_child(_panel)

	var mg := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(s, 12)
	_panel.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	mg.add_child(vb)

	# ── Titre : losange d'accent + nom ────────────────────────
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	vb.add_child(title_row)

	_diamond_lbl = Label.new()
	_diamond_lbl.text = "◆"
	_diamond_lbl.add_theme_font_size_override("font_size", 10)
	_diamond_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_diamond_lbl)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 15)
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Largeur FIXE : un Label autowrap sans largeur minimale rapporte une
	# hauteur minimale délirante au premier layout (1 mot par ligne) — le
	# panneau devient immensément haut. Idem lore/corps.
	_title_lbl.custom_minimum_size = Vector2(MAX_WIDTH - 24.0, 0)
	title_row.add_child(_title_lbl)

	_lore_lbl = Label.new()
	_lore_lbl.add_theme_font_size_override("font_size", 11)
	_lore_lbl.add_theme_constant_override("line_spacing", 2)
	_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore_lbl.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_lore_lbl.visible = false
	vb.add_child(_lore_lbl)

	# ── Séparateur en dégradé (transparent → accent → transparent) ──
	_sep_grad = Gradient.new()
	_sep_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_sep_grad.colors  = PackedColorArray([
		Color.TRANSPARENT, Color(1, 1, 1, 0.5), Color.TRANSPARENT])
	var sep_tex := GradientTexture1D.new()
	sep_tex.gradient = _sep_grad
	sep_tex.width = 128
	_sep = TextureRect.new()
	_sep.texture = sep_tex
	_sep.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_sep.stretch_mode = TextureRect.STRETCH_SCALE
	_sep.custom_minimum_size = Vector2(0, 2)
	_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_sep)

	# Corps en RichTextLabel (BBCode) : le texte simple s'affiche tel quel, mais
	# les appelants peuvent colorer des segments ([color=#RRGGBB]…[/color]) — ex.
	# liste d'entités prêtes à évoluer, chaque palier dans sa couleur de rareté.
	_body_lbl = RichTextLabel.new()
	_body_lbl.bbcode_enabled = true
	_body_lbl.fit_content    = true
	_body_lbl.scroll_active  = false
	_body_lbl.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.add_theme_font_size_override("normal_font_size", 12)
	_body_lbl.add_theme_constant_override("line_separation", 4)
	_body_lbl.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	vb.add_child(_body_lbl)

	_apply_style()

func _process(delta: float) -> void:
	if not _panel.visible:
		return
	# Suivi amorti : le tooltip « traîne » légèrement derrière le curseur.
	var k := 1.0 - exp(-FOLLOW_SPEED * delta)
	_panel.global_position = _panel.global_position.lerp(_target_pos(), k)

# Position cible : sous-droite du curseur, mais BASCULE au-dessus / à gauche
# quand ça déborde d'un bord — au lieu de clamper PAR-DESSUS l'élément survolé.
# Sans ça, sur un bouton ancré en bas (fin d'expédition), le tooltip se faisait
# clamper sur le bouton et masquait/gênait le clic (B5).
func _target_pos() -> Vector2:
	var mp  := _panel.get_viewport().get_mouse_position()
	var vp  := _panel.get_viewport_rect().size
	var ps  := _panel.size
	var pos := mp + OFFSET
	# Débordement en bas → afficher au-dessus du curseur (hors hitbox d'un bouton bas).
	if pos.y + ps.y + MARGIN_PAD > vp.y:
		pos.y = mp.y - ps.y - OFFSET.y
	# Débordement à droite → afficher à gauche du curseur.
	if pos.x + ps.x + MARGIN_PAD > vp.x:
		pos.x = mp.x - ps.x - OFFSET.x
	pos.x = clampf(pos.x, MARGIN_PAD, vp.x - ps.x - MARGIN_PAD)
	pos.y = clampf(pos.y, MARGIN_PAD, vp.y - ps.y - MARGIN_PAD)
	return pos

# Affiche le tooltip avec titre, lore (optionnel), corps et couleur d'accent.
func show_for(title: String, body: String, color: Color, lore: String = "") -> void:
	_show_token += 1
	var token := _show_token

	_border_color = color
	_title_lbl.text = title
	_title_lbl.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	_diamond_lbl.add_theme_color_override("font_color", color)
	_lore_lbl.text    = lore
	_lore_lbl.visible = not lore.is_empty()
	_lore_lbl.add_theme_color_override("font_color",
			Color(color.lerp(Color.WHITE, 0.30), 0.80))
	_body_lbl.text  = body
	_body_lbl.add_theme_color_override("default_color", UIColors.TOOLTIP_BODY)
	_sep.visible = not (lore.is_empty() and body.is_empty())
	var sep_c := color.lerp(Color.WHITE, 0.20)
	_sep_grad.colors = PackedColorArray([
		Color.TRANSPARENT, Color(sep_c.r, sep_c.g, sep_c.b, 0.90), Color.TRANSPARENT])
	_apply_style()

	# Déjà affiché (ou en cours de fondu) → bascule instantanée : en balayant
	# une liste de cartes, le tooltip suit sans clignoter.
	if _panel.visible and _panel.modulate.a > 0.05:
		_kill_fade()
		_panel.modulate.a = 1.0
		_panel.scale = Vector2.ONE
		_panel.reset_size()
		return

	# Sinon : apparition différée, annulée si la souris repart entre-temps.
	get_tree().create_timer(SHOW_DELAY).timeout.connect(func() -> void:
		if token == _show_token:
			_reveal()
	)

# Masque le tooltip (fondu rapide).
func hide_tooltip() -> void:
	_show_token += 1
	if not _panel.visible:
		return
	_kill_fade()
	_fade_tw = create_tween().set_parallel(true)
	_fade_tw.tween_property(_panel, "modulate:a", 0.0, 0.10).set_ease(Tween.EASE_IN)
	_fade_tw.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.10).set_ease(Tween.EASE_IN)
	_fade_tw.chain().tween_callback(func() -> void: _panel.visible = false)

# Apparition : fondu + zoom depuis le coin côté curseur.
func _reveal() -> void:
	_kill_fade()
	_panel.visible = true
	_panel.reset_size()                       # taille du nouveau contenu
	_panel.global_position = _target_pos()    # snap : pas de glissade d'arrivée
	_panel.pivot_offset = Vector2.ZERO
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_fade_tw = create_tween().set_parallel(true)
	_fade_tw.tween_property(_panel, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT)
	_fade_tw.tween_property(_panel, "scale", Vector2.ONE, 0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _kill_fade() -> void:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(
			UIColors.BG_DARK.r, UIColors.BG_DARK.g, UIColors.BG_DARK.b, 0.97)
	s.border_color = Color(
			_border_color.r, _border_color.g, _border_color.b, 0.85)
	s.set_border_width_all(1)
	s.set_border_width(SIDE_TOP, 2)   # liseré d'accent plus marqué en haut
	s.set_corner_radius_all(5)
	s.shadow_color  = Color(0, 0, 0, 0.55)
	s.shadow_size   = 10
	s.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", s)
