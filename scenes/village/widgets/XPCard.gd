class_name XPCard
extends PanelContainer

var xp_fill    := 0.0
var fill_color := Color.WHITE
var _t         := 0.0

const _BUBBLES: Array = [
	[0.08, 2.0, 0.55, 0.00],
	[0.20, 1.5, 0.80, 0.30],
	[0.33, 3.0, 0.45, 0.70],
	[0.45, 1.0, 0.90, 0.15],
	[0.57, 2.5, 0.60, 0.55],
	[0.68, 1.5, 0.70, 0.85],
	[0.78, 2.0, 0.50, 0.40],
	[0.90, 1.0, 0.95, 0.60],
]

func _process(delta: float) -> void:
	if xp_fill > 0.0:
		_t += delta
		queue_redraw()

func _draw() -> void:
	if xp_fill <= 0.0: return
	var w := size.x * xp_fill
	var h := size.y

	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)),
			Color(fill_color.r, fill_color.g, fill_color.b, 0.35))

	for b in _BUBBLES:
		var xf : float = b[0]
		var r  : float = b[1]
		var sp : float = b[2]
		var ph : float = b[3]

		if xf * w < r: continue

		var bx := clampf(xf * w + sin(_t * sp * 3.0 + ph * TAU) * r * 0.6, r, w - r)
		var progress := fmod(_t * sp + ph, 1.0)
		var by       := h + r - progress * (h + r * 2.0)

		var fade  := r * 3.0
		var alpha := clampf(minf((h - by) / fade, by / fade), 0.0, 1.0) * 0.55

		if alpha > 0.01:
			var bc := fill_color
			draw_circle(Vector2(bx, by), r, Color(bc.r, bc.g, bc.b, alpha * 0.45))
			draw_arc(Vector2(bx, by), r, 0.0, TAU, 16,
					Color(bc.r, bc.g, bc.b, alpha), 1.2)
			draw_circle(Vector2(bx - r * 0.3, by - r * 0.3),
					r * 0.28, Color(bc.r, bc.g, bc.b, alpha * 0.8))
