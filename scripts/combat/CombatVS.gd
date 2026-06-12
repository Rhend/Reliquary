# ============================================================
# CombatVS — Séparateur diagonal central de la zone de combat.
#
# Halo doux + deux lignes (3px + 1px) en diagonale : coin supérieur côté
# ennemi (droite) → coin inférieur côté héros (gauche). Le label "VS"
# est posé par-dessus, incliné dans l'axe de la diagonale, fond opaque
# pour couvrir les lignes derrière.
#
# La couleur du trait suit l'ambiance du biome exploré : l'appelant règle
# accent_color (cf. BiomeBackground.accent_for_biome) avant l'ajout à
# l'arbre, ou à tout moment ensuite.
# ============================================================
class_name CombatVS extends Control

# Largeur de la bande du séparateur — les BiomeBackground splittés calent
# la pente de leur découpe dessus (BiomeBackground.set_split).
const BAND_WIDTH := 80.0

# Couleur d'accent du biome courant (trait + liseré du badge VS).
var accent_color: Color = UIColors.TEXT_MUTED:
	set(value):
		accent_color = value
		_apply_accent()
		queue_redraw()

var _vs_box: PanelContainer
var _vs_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bande centrée de largeur fixe entre les deux colonnes, pleine hauteur.
	custom_minimum_size = Vector2(BAND_WIDTH, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_vs_box = PanelContainer.new()
	_vs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs_style = StyleBoxFlat.new()
	_vs_style.bg_color = UIColors.BG_DARK            # opaque : masque les lignes derrière
	_vs_style.set_corner_radius_all(4)
	_vs_style.set_border_width_all(1)
	_vs_style.content_margin_left   = 12
	_vs_style.content_margin_right  = 12
	_vs_style.content_margin_top    = 2
	_vs_style.content_margin_bottom = 2
	_vs_box.add_theme_stylebox_override("panel", _vs_style)
	_apply_accent()

	var lbl := Label.new()
	lbl.text = "VS"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs_box.add_child(lbl)
	add_child(_vs_box)

	resized.connect(_layout_vs)
	_layout_vs()

# Reporte l'accent sur le liseré du badge VS (le trait est géré par _draw).
func _apply_accent() -> void:
	if _vs_style:
		_vs_style.border_color = Color(accent_color, 0.55)

func _layout_vs() -> void:
	await get_tree().process_frame
	var bs := _vs_box.size
	_vs_box.pivot_offset = bs * 0.5
	_vs_box.position     = size * 0.5 - bs * 0.5
	_vs_box.rotation     = -0.32   # légèrement incliné dans l'axe de la diagonale
	queue_redraw()

func _draw() -> void:
	var p1 := Vector2(size.x, 0.0)   # coin supérieur droit (ennemi)
	var p2 := Vector2(0.0, size.y)   # coin inférieur gauche (héros)
	var dir := (p2 - p1).normalized()
	var perp := Vector2(-dir.y, dir.x) * 10.0

	# Halo large très diffus, puis trait principal et filet vif —
	# le tout teinté par la couleur d'accent du biome.
	draw_line(p1, p2, Color(accent_color, 0.14), 10.0, true)
	draw_line(p1, p2, Color(accent_color, 0.70), 3.0, true)
	draw_line(p1 + perp, p2 + perp, Color(accent_color, 0.95), 1.0, true)
