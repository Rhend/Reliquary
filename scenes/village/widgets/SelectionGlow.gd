# ============================================================
# SelectionGlow — Surcouche de sélection : liseré or + luciole.
#
# Overlay plein-rect posé sur la carte du biome sélectionné dans le
# panneau Expéditions : dessine une fine bordure dorée arrondie et une
# luciole lumineuse (point + halo + traîne) qui parcourt le périmètre
# du rectangle en boucle. Transparent à la souris, activable via
# `visible` (AdventurePanel le bascule au fil des sélections).
# ============================================================
class_name SelectionGlow
extends Control

const BORDER_WIDTH := 2
const CORNER_RADIUS := 4
const FIREFLY_SPEED := 90.0   # px/s le long du périmètre
const TRAIL_COUNT   := 4      # segments de traîne derrière la luciole

var _dist     := 0.0          # distance parcourue sur le périmètre
var _border   := StyleBoxFlat.new()
var _glow_tex : GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border.bg_color     = Color(0, 0, 0, 0)
	_border.border_color = Color(UIColors.SELECTION_GOLD, 0.85)
	_border.set_border_width_all(BORDER_WIDTH)
	_border.set_corner_radius_all(CORNER_RADIUS)
	_glow_tex = UIHelpers.radial_glow_tex(48, [0.0, 0.35, 1.0], [1.0, 0.45, 0.0])

func _process(delta: float) -> void:
	if not visible or size.x <= 0.0:
		return
	_dist = fposmod(_dist + FIREFLY_SPEED * delta, 2.0 * (size.x + size.y))
	queue_redraw()

func _draw() -> void:
	_border.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	# Traîne : points décroissants derrière la luciole.
	for i in range(TRAIL_COUNT, 0, -1):
		var q := _point_at(_dist - float(i) * 6.0)
		draw_circle(q, 1.5 - float(i) * 0.25,
				Color(UIColors.SELECTION_GOLD, 0.40 - float(i) * 0.08),
				true, -1.0, true)

	# Luciole : halo doux + cœur brillant.
	var p := _point_at(_dist)
	draw_texture_rect(_glow_tex, Rect2(p - Vector2(11, 11), Vector2(22, 22)),
			false, Color(UIColors.SELECTION_GOLD, 0.55))
	draw_circle(p, 1.8, Color(1.0, 0.96, 0.80, 0.95), true, -1.0, true)

# Point sur le périmètre du rectangle à la distance d (sens horaire
# depuis le coin haut-gauche).
func _point_at(d: float) -> Vector2:
	var w := size.x
	var h := size.y
	d = fposmod(d, 2.0 * (w + h))
	if d < w:
		return Vector2(d, 0.0)
	d -= w
	if d < h:
		return Vector2(w, d)
	d -= h
	if d < w:
		return Vector2(w - d, h)
	d -= w
	return Vector2(0.0, h - d)
