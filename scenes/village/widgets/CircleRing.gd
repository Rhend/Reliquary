class_name CircleRing
extends Control

var ring_color    := Color.WHITE
var ring_radius   := 0.0
var ring_width    := 13.0
var fill_fraction := 0.0
var tier          := 0
var _t            := 0.0

const _SPARKS := [0.4, 1.2, 2.1, 2.9, 3.8, 4.6, 5.4]

func _process(dt: float) -> void:
	_t += dt
	pivot_offset = size * 0.5
	rotation += dt * 0.18
	queue_redraw()

func _base_w() -> float:
	match tier:
		0: return 10.0
		1: return 13.0
		2: return 13.0
		3: return 15.0
		4: return 17.0
		_: return 18.0

func _draw() -> void:
	var c := size * 0.5
	var w := _base_w()
	var r := ring_radius if ring_radius > 0.0 else minf(size.x, size.y) * 0.5 - w * 0.5
	match tier:
		0: _commun(c, r, w)
		1: _peu_commun(c, r, w)
		2: _rare(c, r, w)
		3: _epique(c, r, w)
		4: _legendaire(c, r, w)
		5: _unique(c, r)
		_: _commun(c, r, w)
	if fill_fraction > 0.0:
		var prog_end := -PI * 0.5 + fill_fraction * TAU
		var prog     := ring_color.lightened(0.45); prog.a = 0.95
		draw_arc(c, r, -PI * 0.5, prog_end, 96, prog, w * 1.15, true)

func _commun(c: Vector2, r: float, w: float) -> void:
	var corona := ring_color; corona.a = 0.07 + 0.03 * sin(_t * 1.2)
	draw_arc(c, r + 8.0, 0.0, TAU, 64, corona, w * 1.6, true)
	var main := ring_color; main.a = 0.55 + 0.18 * sin(_t * 1.3)
	draw_arc(c, r, 0.0, TAU, 96, main, w, true)
	_borders(c, r, w)
	var sa := _t * 0.50
	var sh := ring_color.lightened(0.35); sh.a = 0.50
	draw_arc(c, r, sa, sa + 0.65, 10, sh, w * 0.45, true)
	_sparks(c, r, w, 4, 0.09, 1.4)

func _peu_commun(c: Vector2, r: float, w: float) -> void:
	var corona := ring_color; corona.a = 0.12 + 0.06 * sin(_t * 1.4)
	draw_arc(c, r + 10.0, 0.0, TAU, 96, corona, w * 2.0, true)
	var main := ring_color; main.a = 0.72 + 0.22 * sin(_t * 1.9)
	draw_arc(c, r, 0.0, TAU, 128, main, w, true)
	_borders(c, r, w)
	var rim := ring_color.lightened(0.3); rim.a = 0.50
	draw_arc(c, r + w * 0.5 - 1.0, 0.0, TAU, 64, rim, 1.0, true)
	var sa := _t * 0.75
	var sh := ring_color.lightened(0.55); sh.a = 0.75
	draw_arc(c, r, sa, sa + 1.1, 24, sh, w * 0.55, true)
	_sparks(c, r, w, 6, 0.12, 2.0)

func _rare(c: Vector2, r: float, w: float) -> void:
	var corona := ring_color; corona.a = 0.14 + 0.07 * sin(_t * 1.6)
	draw_arc(c, r + 12.0, 0.0, TAU, 96, corona, w * 2.4, true)
	var main := ring_color; main.a = 0.75 + 0.20 * sin(_t * 2.0)
	draw_arc(c, r, 0.0, TAU, 128, main, w, true)
	_borders(c, r, w)
	var inner_col := ring_color; inner_col.a = 0.38 + 0.14 * sin(_t * 1.5 + 1.0)
	draw_arc(c, r - 22.0, 0.0, TAU, 64, inner_col, 2.0, true)
	var rim := ring_color.lightened(0.4); rim.a = 0.55
	draw_arc(c, r + w * 0.5 - 1.0, 0.0, TAU, 64, rim, 1.2, true)
	for i in 2:
		var sa := _t * (0.85 + i * 0.25) + i * PI
		var sh := ring_color.lightened(0.45 + i * 0.1); sh.a = 0.75 - i * 0.22
		draw_arc(c, r, sa, sa + (1.1 - i * 0.3), 20, sh, w * (0.58 - i * 0.14), true)
	_sparks(c, r, w, 7, 0.14, 2.2)

func _epique(c: Vector2, r: float, w: float) -> void:
	draw_arc(c, r + 24.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.08 + 0.05 * sin(_t * 1.2)), w * 3.8, true)
	draw_arc(c, r + 10.0, 0.0, TAU, 96, Color(ring_color.r, ring_color.g, ring_color.b, 0.18 + 0.08 * sin(_t * 1.8)), w * 2.2, true)
	draw_arc(c, r + 30.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.28 + 0.12 * sin(_t * 2.2)), 1.5, true)
	var main := ring_color; main.a = 0.78 + 0.18 * sin(_t * 2.0)
	draw_arc(c, r, 0.0, TAU, 128, main, w, true)
	_borders(c, r, w)
	var inner := ring_color; inner.a = 0.40 + 0.15 * sin(_t * 1.7 + 0.5)
	draw_arc(c, r - 22.0, 0.0, TAU, 64, inner, 2.5, true)
	var rim := ring_color.lightened(0.45); rim.a = 0.62
	draw_arc(c, r + w * 0.5 - 1.0, 0.0, TAU, 64, rim, 1.5, true)
	for i in 3:
		var sa := _t * (0.9 + i * 0.15) + i * TAU / 3.0
		var sh := ring_color.lightened(0.45 + i * 0.1); sh.a = 0.68 - i * 0.12
		draw_arc(c, r, sa, sa + (1.0 - i * 0.1), 18, sh, w * (0.58 - i * 0.10), true)
	for i in 3:
		var angle := _t * 0.80 + i * TAU / 3.0
		var op := c + Vector2(cos(angle), sin(angle)) * (r + 34.0)
		draw_circle(op, 9.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.22))
		var orb := ring_color; orb.a = 0.80 + 0.18 * sin(_t * 2.0 + i * 1.5)
		draw_circle(op, 3.5 + 1.0 * sin(_t * 2.5 + i), orb)
	_sparks(c, r, w, 7, 0.14, 2.5)

func _legendaire(c: Vector2, r: float, w: float) -> void:
	draw_arc(c, r + 40.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.05 + 0.03 * sin(_t * 1.0)), w * 5.5, true)
	draw_arc(c, r + 22.0, 0.0, TAU, 96, Color(ring_color.r, ring_color.g, ring_color.b, 0.12 + 0.06 * sin(_t * 1.4)), w * 3.2, true)
	draw_arc(c, r + 8.0,  0.0, TAU, 96, Color(ring_color.r, ring_color.g, ring_color.b, 0.22 + 0.10 * sin(_t * 1.9)), w * 2.0, true)
	draw_arc(c, r + 34.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.30 + 0.12 * sin(_t * 2.0)), 1.5, true)
	draw_arc(c, r + 46.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.18 + 0.08 * sin(_t * 1.6 + 0.8)), 1.0, true)
	var main := ring_color; main.a = 0.85 + 0.14 * sin(_t * 2.2)
	draw_arc(c, r, 0.0, TAU, 128, main, w, true)
	_borders(c, r, w)
	var inner := ring_color; inner.a = 0.45 + 0.18 * sin(_t * 1.8 + 0.3)
	draw_arc(c, r - 25.0, 0.0, TAU, 64, inner, 3.0, true)
	var rim1 := ring_color.lightened(0.5); rim1.a = 0.65
	draw_arc(c, r + w * 0.5 - 1.0, 0.0, TAU, 64, rim1, 1.5, true)
	var rim2 := ring_color.lightened(0.3); rim2.a = 0.35
	draw_arc(c, r - w * 0.5 + 1.0, 0.0, TAU, 64, rim2, 1.0, true)
	for i in 8:
		var angle := i * TAU / 8.0 + _t * 0.10
		var blink := 0.5 + 0.5 * sin(_t * 2.8 + i * 0.85)
		if blink > 0.28:
			var ray := ring_color.lightened(0.6); ray.a = blink * 0.50
			var p1 := c + Vector2(cos(angle), sin(angle)) * (r + w * 0.5 + 3.0)
			var p2 := c + Vector2(cos(angle), sin(angle)) * (r + w * 0.5 + 14.0 + blink * 10.0)
			draw_line(p1, p2, ray, 1.8, true)
	for i in 4:
		var sa := _t * (0.92 + i * 0.13) + i * TAU / 4.0
		var sh := ring_color.lightened(0.38 + i * 0.08); sh.a = 0.72 - i * 0.12
		draw_arc(c, r, sa, sa + (0.9 - i * 0.08), 18, sh, w * (0.55 - i * 0.08), true)
	for i in 3:
		var angle := _t * 0.9 + i * TAU / 3.0
		var op := c + Vector2(cos(angle), sin(angle)) * (r + 36.0)
		draw_circle(op, 11.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.25))
		var orb := ring_color; orb.a = 0.88
		draw_circle(op, 4.0 + 1.2 * sin(_t * 2.5 + i), orb)
	for i in 2:
		var angle := _t * 0.5 + i * PI + 0.4
		var op := c + Vector2(cos(angle), sin(angle)) * (r + 50.0)
		draw_circle(op, 7.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.20))
		var orb := ring_color.lightened(0.3); orb.a = 0.70
		draw_circle(op, 3.0, orb)
	_sparks(c, r, w, 7, 0.17, 2.8)

func _unique(c: Vector2, r: float) -> void:
	var beat: float = absf(sin(_t * 2.4)) * 0.7 + absf(sin(_t * 4.8)) * 0.3
	var w:    float = 18.0 + beat * 5.0
	draw_arc(c, r + 58.0, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, 0.05 + 0.08 * beat), w * 6.0, true)
	draw_arc(c, r + 28.0, 0.0, TAU, 96, Color(ring_color.r, ring_color.g, ring_color.b, 0.14 + 0.12 * beat), w * 3.0, true)
	draw_arc(c, r + 10.0, 0.0, TAU, 96, Color(ring_color.r, ring_color.g, ring_color.b, 0.24 + 0.16 * beat), w * 1.8, true)
	var _layer_r: Array[float] = [0.0, 34.0, 46.0]
	for layer in 3:
		var pb: float = absf(sin(_t * 2.4 + layer * 0.5))
		var lr: float = r + _layer_r[layer]
		var lw: float = w if layer == 0 else 1.8
		var la: float = (0.82 + 0.16 * pb) if layer == 0 else (0.30 + 0.22 * pb)
		var lc        := ring_color; lc.a = la
		draw_arc(c, lr, 0.0, TAU, 128 - layer * 32, lc, lw, true)
	_borders(c, r, w)
	var rim := ring_color.lightened(0.35); rim.a = 0.55 + 0.30 * beat
	draw_arc(c, r + w * 0.5 - 1.0, 0.0, TAU, 64, rim, 1.5, true)
	for i in 8:
		var ang: float = i * TAU / 8.0 + _t * 0.06
		var vp:  float = 0.28 + 0.42 * absf(sin(_t * 2.8 + i * 1.1))
		var vc         := ring_color.lightened(0.25); vc.a = vp
		draw_arc(c, r, ang, ang + 0.28, 6, vc, w * 0.85, true)
	for i in 3:
		var sa := _t * (1.1 + i * 0.18) + i * TAU / 3.0
		var sh := ring_color.lightened(0.45 + i * 0.12); sh.a = 0.82 - i * 0.18
		draw_arc(c, r, sa, sa + 1.2, 22, sh, w * (0.55 - i * 0.10), true)
	for i in 3:
		var angle := _t * 1.1 + i * TAU / 3.0
		var op   := c + Vector2(cos(angle), sin(angle)) * (r + 28.0)
		draw_circle(op, 9.0 + beat * 3.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.28))
		var orb  := ring_color; orb.a = 0.90
		draw_circle(op, 3.5 + 1.5 * beat, orb)
	for i in 3:
		var angle := _t * 0.7 + i * TAU / 3.0 + PI / 6.0
		var op   := c + Vector2(cos(angle), sin(angle)) * (r + 46.0)
		draw_circle(op, 6.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.20))
		var orb  := ring_color.lightened(0.2); orb.a = 0.75
		draw_circle(op, 2.5, orb)
	var solo_a := _t * 1.6 + 0.3
	var solo_p := c + Vector2(cos(solo_a), sin(solo_a)) * (r + 60.0)
	draw_circle(solo_p, 5.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.18))
	var solo_c := ring_color.lightened(0.5); solo_c.a = 0.75 + 0.25 * beat
	draw_circle(solo_p, 3.5, solo_c)
	_sparks(c, r, w, 7, 0.20, 3.0)

func _borders(c: Vector2, r: float, w: float) -> void:
	draw_arc(c, r + w * 0.5 + 0.5, 0.0, TAU, 64, Color(0, 0, 0, 0.55), 1.5, true)
	draw_arc(c, r - w * 0.5 - 0.5, 0.0, TAU, 64, Color(0, 0, 0, 0.55), 1.5, true)

func _sparks(c: Vector2, r: float, w: float, count: int, speed: float, max_r: float) -> void:
	for i in count:
		var a: float = _SPARKS[i % _SPARKS.size()] + _t * speed
		var sp := c + Vector2(cos(a), sin(a)) * (r + w + 7.0)
		var bl := 0.5 + 0.5 * sin(_t * 2.2 + i * 1.4)
		if bl > 0.55:
			var sc := ring_color; sc.a = (bl - 0.55) * 2.2
			draw_circle(sp, 1.5 + bl * max_r, sc)
