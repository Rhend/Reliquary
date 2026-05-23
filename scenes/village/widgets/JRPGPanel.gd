class_name JRPGPanel
extends Control

var panel_color := Color.WHITE
var _t          := 0.0

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var sz := size
	var bw := 2.0
	var m  := 5.0
	var th := 38.0

	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.09, 0.97))

	var ob := panel_color; ob.a = 0.80
	draw_rect(Rect2(Vector2.ZERO, sz), ob, false, bw)

	var ib := panel_color; ib.a = 0.22
	draw_rect(Rect2(Vector2(m, m), sz - Vector2(m * 2.0, m * 2.0)), ib, false, 1.0)

	var tb := panel_color.darkened(0.55); tb.a = 0.85
	draw_rect(Rect2(Vector2(bw, bw), Vector2(sz.x - bw * 2.0, th)), tb)

	var sep := panel_color; sep.a = 0.55 + 0.20 * sin(_t * 1.8)
	draw_line(Vector2(m * 2.0, th + bw), Vector2(sz.x - m * 2.0, th + bw), sep, 1.5)

	var shim_x := fmod(_t * 70.0, sz.x + 30.0) - 15.0
	var shim   := Color.WHITE; shim.a = 0.07
	draw_rect(Rect2(Vector2(shim_x, bw), Vector2(22.0, th - bw)), shim)

	_draw_diamond(Vector2(m + 5.0, m + 5.0),               4.5, panel_color)
	_draw_diamond(Vector2(sz.x - m - 5.0, m + 5.0),        4.5, panel_color)
	_draw_diamond(Vector2(m + 5.0, sz.y - m - 5.0),        4.5, panel_color)
	_draw_diamond(Vector2(sz.x - m - 5.0, sz.y - m - 5.0), 4.5, panel_color)

func _draw_diamond(pos: Vector2, r: float, col: Color) -> void:
	var c := col; c.a = 0.88
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, -r),
		pos + Vector2(r, 0.0),
		pos + Vector2(0.0, r),
		pos + Vector2(-r, 0.0),
	]), c)
