# ============================================================
# ExpeStyle — Factories de la peau cyberpunk INTÉRIMAIRE du pipeline
# expédition (chantier 10). class_name statique (pattern Balance/UIHelpers,
# PAS un autoload).
#
# AVEC les tokens UIColors.CYBER_*, c'est ici que vivent TOUS les choix
# visuels de l'habillage (styles, police, effets) : la DA de Christophe
# remplacera ces deux points — aucun littéral de style dispersé dans l'UI
# d'expédition. Direction actée : fonds quasi-noirs bleutés, bordures fines
# lumineuses, accents néon cyan/magenta (rouge = Artefact/danger seulement),
# typographie technique (monospace — le héros est un matricule R-XXX,
# l'esthétique terminal est diégétique), effets sobres (scanlines légères).
# Lisibilité PRIORITAIRE : aucune info de jeu dégradée par l'habillage.
# ============================================================
class_name ExpeStyle

const SCANLINES_SHADER := preload("res://scenes/ui/cyber_scanlines.gdshader")

# Police technique (monospace système, repli en cascade) — cache statique.
static var _mono: SystemFont = null

static func police_mono() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = ["Consolas", "Cascadia Mono", "JetBrains Mono",
				"DejaVu Sans Mono", "monospace"]
	return _mono

# Label en police technique (l'équivalent cyberpunk d'UIHelpers.label).
static func label_mono(texte: String, taille: int, couleur: Color) -> Label:
	var l := Label.new()
	l.text = texte
	l.add_theme_font_override("font", police_mono())
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	return l

# Panneau cyberpunk : fond sombre bleuté, bordure fine lumineuse, angles
# quasi-droits, halo doux (shadow de la couleur d'accent).
static func style_panneau(accent: Color, alpha_fond := 0.92, epaisseur := 1,
		rayon := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIColors.CYBER_BG_PANEL, alpha_fond)
	s.border_color = Color(accent, 0.85)
	s.set_border_width_all(epaisseur)
	s.set_corner_radius_all(rayon)
	s.shadow_color = Color(accent, 0.16)
	s.shadow_size = 8
	s.set_content_margin_all(8)
	return s

# Style de bouton néon (état paramétré par l'alpha du fond).
static func _style_bouton(accent: Color, alpha_fond: float, epaisseur := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, alpha_fond)
	s.border_color = Color(accent, 0.9)
	s.set_border_width_all(epaisseur)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(8)
	return s

# Habille un Button EXISTANT en néon (les boutons créés dynamiquement —
# cibles, objets — passent ici, un seul point de style).
static func habiller_bouton(b: Button, accent: Color, taille_police := 15) -> Button:
	b.add_theme_font_override("font", police_mono())
	b.add_theme_font_size_override("font_size", taille_police)
	b.add_theme_color_override("font_color", accent.lightened(0.35))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", UIColors.CYBER_TEXTE_MUTED)
	b.add_theme_stylebox_override("normal", _style_bouton(accent, 0.10))
	b.add_theme_stylebox_override("hover", _style_bouton(accent, 0.28))
	b.add_theme_stylebox_override("pressed", _style_bouton(accent, 0.40))
	b.add_theme_stylebox_override("disabled", _style_bouton(UIColors.CYBER_TEXTE_MUTED, 0.06))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

# Bouton néon neuf (texte + accent).
static func bouton(texte: String, accent: Color, taille_police := 15,
		taille_min := Vector2(0, 40)) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = taille_min
	return habiller_bouton(b, accent, taille_police)

# Chip fine (file d'initiative, pills) — bordure lumineuse, fond très sombre.
static func style_chip(accent: Color, alpha_fond := 0.85) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIColors.CYBER_BG_PANEL_2, alpha_fond)
	s.border_color = Color(accent, 0.75)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	return s

# Scanlines sobres au-dessus de `hote` (plein écran, souris ignorée).
# Retourne l'overlay (l'appelant peut le replacer dans l'ordre des enfants).
static func scanlines(hote: Control, force := 0.10) -> ColorRect:
	var sl := ColorRect.new()
	sl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sl.color = Color.WHITE   # la couleur vient du shader (COLOR réécrit)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SCANLINES_SHADER
	mat.set_shader_parameter("force", force)
	sl.material = mat
	hote.add_child(sl)
	return sl

# Couleur d'accent d'un CAMP de combat (joueur = cyan, adverse = magenta).
static func accent_camp(est_joueur: bool) -> Color:
	return UIColors.CYBER_ACCENT if est_joueur else UIColors.CYBER_ACCENT_2

# ─── Variante NÉON appuyée (inventaire de l'Atelier, 14/10/2026) ──────────
# Même peau, effets plus francs : bordure de 2 px pleinement lumineuse + halo
# large. `intensite` pilote l'alpha du halo (0 = aucun, 1 = normal, >1 fort).

static func style_neon(accent: Color, intensite := 1.0, alpha_fond := 0.90,
		epaisseur := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIColors.CYBER_BG_PANEL, alpha_fond)
	s.border_color = Color(accent, 1.0)
	s.set_border_width_all(epaisseur)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(accent, clampf(0.34 * intensite, 0.0, 0.8))
	s.shadow_size = 14
	s.set_content_margin_all(10)
	return s

# Bouton néon à halo (cases d'inventaire, onglets actifs) : même habillage que
# `habiller_bouton`, plus un halo qui s'allume au survol / à la sélection.
static func habiller_bouton_neon(b: Button, accent: Color, taille_police := 15,
		halo := 0.25) -> Button:
	habiller_bouton(b, accent, taille_police)
	for etat: String in ["normal", "hover", "pressed"]:
		var s := b.get_theme_stylebox(etat) as StyleBoxFlat
		if s == null:
			continue
		s = s.duplicate() as StyleBoxFlat
		# Fond OPAQUE (mélange accent/fond) : le halo est dessiné SOUS le fond, un
		# fond translucide laisserait toute la case teintée par son ombre.
		s.bg_color = Color(UIColors.CYBER_BG_PANEL_2).lerp(Color(accent, 1.0), s.bg_color.a)
		s.border_color = Color(accent, 1.0)
		s.set_border_width_all(2 if etat != "normal" else 1)
		s.shadow_color = Color(accent, halo * (1.6 if etat != "normal" else 1.0))
		s.shadow_size = 8 if etat == "normal" else 12
		b.add_theme_stylebox_override(etat, s)
	return b

# Titre à halo néon (contour + ombre diffuse de la couleur d'accent).
static func label_neon(texte: String, taille: int, accent: Color) -> Label:
	var l := label_mono(texte, taille, accent.lightened(0.25))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(accent, 0.22))
	l.add_theme_color_override("font_shadow_color", Color(accent, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 8)
	return l

# Pulsation douce de la luminosité d'un nœud (sélection « vivante »). Le tween
# est lié au nœud : il meurt avec lui.
static func pulser(noeud: CanvasItem, amplitude := 0.30, periode := 1.1) -> void:
	var haut := Color(1.0 + amplitude, 1.0 + amplitude, 1.0 + amplitude, 1.0)
	var tw := noeud.create_tween().set_loops()
	tw.tween_property(noeud, "modulate", haut, periode * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(noeud, "modulate", Color.WHITE, periode * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
