# ============================================================
# CombatVS — Séparateur diagonal central de la zone de combat.
#
# Deux lignes fines (3px + 1px) en diagonale : coin supérieur côté
# ennemi (droite) → coin inférieur côté héro (gauche). Le label "VS"
# est posé par-dessus, incliné dans l'axe de la diagonale, fond opaque
# pour couvrir les lignes derrière.
# ============================================================
class_name CombatVS extends Control

var _vs_box: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Band centré de largeur fixe entre les deux colonnes, pleine hauteur.
	custom_minimum_size = Vector2(80, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_vs_box = PanelContainer.new()
	_vs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIColors.BG_DARK            # opaque : masque les lignes derrière
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 2
	sb.content_margin_bottom = 2
	_vs_box.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = "VS"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs_box.add_child(lbl)
	add_child(_vs_box)

	resized.connect(_layout_vs)
	_layout_vs()

func _layout_vs() -> void:
	await get_tree().process_frame
	var bs := _vs_box.size
	_vs_box.pivot_offset = bs * 0.5
	_vs_box.position     = size * 0.5 - bs * 0.5
	_vs_box.rotation     = -0.32   # légèrement incliné dans l'axe de la diagonale
	queue_redraw()

func _draw() -> void:
	var p1 := Vector2(size.x, 0.0)   # coin supérieur droit (ennemi)
	var p2 := Vector2(0.0, size.y)   # coin inférieur gauche (héro)
	var dir := (p2 - p1).normalized()
	var perp := Vector2(-dir.y, dir.x) * 10.0

	draw_line(p1, p2, Color(UIColors.TEXT_MUTED, 0.55), 3.0, true)
	draw_line(p1 + perp, p2 + perp, Color(UIColors.TEXT_MUTED, 0.85), 1.0, true)
