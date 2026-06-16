# ============================================================
# WelcomeOverlay — Message d'accueil modal au démarrage.
#
# Présente le jeu (tout évolue, alliés comme ennemis), précise qu'il
# s'agit d'un prototype (PoC) et sollicite les retours du joueur.
#
# Affiché par Village au lancement tant que GameSettings.welcome_dismissed
# est false. Contrairement au SettingsOverlay, un clic hors de la carte ne
# ferme PAS l'overlay : seul le bouton « Commencer » valide la lecture.
# Si la case « ne plus voir » est cochée à la validation, l'overlay ne
# réapparaîtra plus aux démarrages suivants.
#
# Usage (Village) :
#   add_child(WelcomeOverlay.new())
# ============================================================
class_name WelcomeOverlay
extends ColorRect

var _dont_show := false   # survit aux reconstructions (changement de langue)

func _ready() -> void:
	color        = Color(0.0, 0.0, 0.0, 0.55)
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloque toute interaction avec le hub
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	GameSettings.language_changed.connect(_on_language_changed)
	_build()

# Échap est neutralisé tant que l'accueil est ouvert : on force le clic sur
# « Commencer » (sinon Village ouvrirait le panneau Paramètres derrière).
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()

func _on_language_changed(_lang: String) -> void:
	UIHelpers.clear_children(self)
	_build()

# ─── Construction ─────────────────────────────────────────────

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	# Carte opaque : la lecture ne doit pas être parasitée par le hub derrière.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color     = UIColors.BG_CARD
	style.border_color = Color(UIColors.TIER_PEU_COMMUN, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var mg := UIHelpers.margin_of(22)
	card.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	mg.add_child(vb)

	# ── Titre ─────────────────────────────────────────────────
	var title_lbl := Label.new()
	title_lbl.text = Translations.T("welcome.title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UIColors.TIER_PEU_COMMUN)
	vb.add_child(title_lbl)

	vb.add_child(_sep())

	# ── Corps (RichTextLabel pour le gras [b]…[/b]) ───────────
	var body := RichTextLabel.new()
	body.bbcode_enabled         = true
	body.fit_content            = true
	body.scroll_active          = false
	body.autowrap_mode          = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size    = Vector2(0, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_font_size_override("bold_font_size", 14)
	body.add_theme_color_override("default_color", UIColors.TOOLTIP_BODY)
	body.text = Translations.T("welcome.body")
	vb.add_child(body)

	vb.add_child(_sep())

	# ── Case « ne plus voir » ─────────────────────────────────
	var check := CheckBox.new()
	check.text            = Translations.T("welcome.dont_show")
	check.button_pressed  = _dont_show
	check.focus_mode      = Control.FOCUS_NONE
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check.add_theme_font_size_override("font_size", 13)
	check.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	check.toggled.connect(func(v: bool) -> void: _dont_show = v)
	vb.add_child(check)

	# ── Bouton de validation ──────────────────────────────────
	var start_btn := Button.new()
	start_btn.text = Translations.T("welcome.start")
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.focus_mode = Control.FOCUS_NONE
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_btn.add_theme_font_size_override("font_size", 15)
	start_btn.add_theme_color_override("font_color", UIColors.TIER_PEU_COMMUN)
	start_btn.add_theme_stylebox_override("normal",
			UIHelpers.card_style(UIColors.TIER_PEU_COMMUN, 0.10, 0.45, 1, 6))
	start_btn.add_theme_stylebox_override("hover",
			UIHelpers.card_style(UIColors.TIER_PEU_COMMUN, 0.22, 0.85, 1, 6))
	start_btn.add_theme_stylebox_override("pressed",
			UIHelpers.card_style(UIColors.TIER_PEU_COMMUN, 0.30, 1.00, 1, 6))
	start_btn.pressed.connect(_validate)
	vb.add_child(start_btn)

func _validate() -> void:
	if _dont_show:
		GameSettings.set_welcome_dismissed(true)
	queue_free()

# ─── Fabriques ────────────────────────────────────────────────

func _sep() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.color                 = Color(1.0, 1.0, 1.0, 0.15)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sep
