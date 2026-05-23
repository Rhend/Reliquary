class_name HexItem
extends Control

var icon_text    := ""
var label_text   := ""
var tier_color   := Color.WHITE
var tier         := 1
var callback     : Callable
var hex_radius   := 58.0
var outward_dir  := Vector2.RIGHT
var is_hovered   := false
var is_selected  := false
var _htween      : Tween
var _t           := 0.0

func _ready() -> void:
	pivot_offset = size * 0.5
	var ico := Label.new()
	ico.text = icon_text
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ico.add_theme_font_size_override("font_size", 40)
	ico.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ico)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _on_enter() -> void:
	is_hovered = true
	_tween_scale(1.2)
	queue_redraw()

func _on_exit() -> void:
	is_hovered = false
	_tween_scale(1.0)
	queue_redraw()

func _tween_scale(target: float) -> void:
	if _htween: _htween.kill()
	_htween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_htween.tween_property(self, "scale", Vector2(target, target), 0.15)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		if _htween: _htween.kill()
		_htween = create_tween().set_trans(Tween.TRANS_SINE)
		_htween.tween_property(self, "scale", Vector2(0.88, 0.88), 0.07)
		_htween.tween_callback(callback)

func _draw() -> void:
	var c := size * 0.5
	match tier:
		1: _round(c, false)
		2: _round(c, true)
		3: _hexa(c, false, false)
		4: _hexa(c, true,  false)
		5: _hexa(c, true,  true)
		_: _round(c, false)
	_callout(c)

func _callout(c: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fsz  := 13
	var r    := hex_radius * (0.78 if tier <= 2 else 0.92)

	var text_w  := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var bar_len := text_w + 60.0

	var p0       := c + outward_dir * r
	var p1       := c + outward_dir * (r + 28.0)
	var bd       := 1.0 if outward_dir.x >= 0.0 else -1.0
	var p2       := p1 + Vector2(bd * bar_len, 0.0)
	var stem_len := p0.distance_to(p1)
	var total    := stem_len + bar_len

	var black := Color(0.0, 0.0, 0.0, 0.40)
	var base  := Color(tier_color.r, tier_color.g, tier_color.b,
			0.72 + 0.10 * sin(_t * 1.8))

	var glow := Color(tier_color.r, tier_color.g, tier_color.b,
			0.08 + 0.05 * sin(_t * 1.5))
	draw_line(p0, p1, glow, 8.0, true)
	draw_line(p1, p2, glow, 8.0, true)

	draw_line(p0, p1, black, 3.0, true)
	draw_line(p1, p2, black, 3.0, true)
	draw_line(p0, p1, base, 1.5, true)
	draw_line(p1, p2, base, 1.5, true)

	var dot_r := 2.0 + 0.7 * sin(_t * 3.2)
	draw_circle(p0, dot_r + 1.5, black)
	draw_circle(p0, dot_r, base)

	var prog := fmod(_t * 0.55, 1.0)
	var dist := prog * total
	var pp   : Vector2
	if dist <= stem_len:
		pp = p0.lerp(p1, dist / stem_len)
	else:
		pp = p1.lerp(p2, (dist - stem_len) / bar_len)
	var pa   := sin(prog * PI)
	var pc   := tier_color.lightened(0.45); pc.a = pa * 0.85
	var pcg  := Color(pc.r, pc.g, pc.b, pa * 0.25)
	draw_circle(pp, 5.5, pcg)
	draw_circle(pp, 2.8, pc)
	draw_circle(pp, 1.2, Color(1.0, 1.0, 1.0, pa * 0.90))

	var tx  := minf(p1.x, p2.x)
	var tp  := Vector2(tx, p1.y - 6.0)
	var tco := Color(0.0, 0.0, 0.0, 0.50)
	for ofs: Vector2 in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]:
		draw_string(font, tp + ofs, label_text,
				HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz, tco)
	draw_string(font, tp, label_text,
			HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz,
			tier_color.lightened(0.35))

func _round(c: Vector2, with_fx: bool) -> void:
	var r: float = hex_radius * 0.78
	if with_fx:
		var og := tier_color; og.a = 0.08 + 0.05 * sin(_t * 1.4)
		draw_circle(c, r + 12.0, og)
	draw_circle(c + Vector2(2.0, 3.5), r, Color(0, 0, 0, 0.35))
	var fill := tier_color.darkened(0.45); fill.a = 0.92
	draw_circle(c, r, fill)
	draw_arc(c, r - 4.0, -PI * 0.80, -PI * 0.20, 16, Color(1, 1, 1, 0.22), 4.0, true)
	draw_arc(c, r - 4.0,  PI * 0.20,  PI * 0.80, 16, Color(0, 0, 0, 0.25), 4.0, true)
	var border := tier_color; border.a = 0.50 + 0.22 * sin(_t * 1.8)
	draw_arc(c, r, 0.0, TAU, 64, border, 2.0, true)
	if with_fx:
		var rim := tier_color.lightened(0.35); rim.a = 0.45
		draw_arc(c, r - 2.0, 0.0, TAU, 64, rim, 1.0, true)
		var outline := tier_color; outline.a = 0.28 + 0.12 * sin(_t * 1.5)
		draw_arc(c, r + 9.0, 0.0, TAU, 64, outline, 1.5, true)
		var sa := _t * 1.3
		var sh := tier_color.lightened(0.65); sh.a = 0.82
		draw_arc(c, r, sa, sa + 1.0, 20, sh, 3.5, true)
	if is_selected:
		var gr: float = 12.0 if with_fx else 8.0
		var glow := tier_color; glow.a = 0.35
		draw_arc(c, r + gr, 0.0, TAU, 48, glow, 5.0, true)
		draw_arc(c, r, 0.0, TAU, 64, tier_color, 2.5, true)
	elif is_hovered:
		var ex: float = 14.0 if with_fx else 12.0
		var corona := tier_color; corona.a = 0.20
		draw_circle(c, r + ex, corona)
		draw_arc(c, r, 0.0, TAU, 64, tier_color.lightened(0.2), 3.0, true)

func _hexa(c: Vector2, with_fx: bool, with_pulse: bool) -> void:
	var eff_r: float = hex_radius
	if with_pulse:
		eff_r += sin(_t * 2.5) * 3.0
	var pts := _hex(c, eff_r)

	draw_colored_polygon(_hex(c + Vector2(2.5, 4.0), eff_r), Color(0, 0, 0, 0.40))

	var base := tier_color.darkened(0.42); base.a = 0.95
	draw_colored_polygon(pts, base)
	draw_colored_polygon(PackedVector2Array([c, pts[3], pts[4], pts[5], pts[0]]), Color(1, 1, 1, 0.11))
	draw_colored_polygon(PackedVector2Array([c, pts[0], pts[1], pts[2], pts[3]]), Color(0, 0, 0, 0.28))

	var inn := _hex(c, eff_r - 5.0)
	draw_line(inn[3], inn[4], Color(1, 1, 1, 0.18), 1.0, true)
	draw_line(inn[4], inn[5], Color(1, 1, 1, 0.23), 1.5, true)
	draw_line(inn[5], inn[0], Color(1, 1, 1, 0.18), 1.0, true)
	draw_line(inn[0], inn[1], Color(0, 0, 0, 0.22), 1.0, true)
	draw_line(inn[1], inn[2], Color(0, 0, 0, 0.22), 1.5, true)
	draw_line(inn[2], inn[3], Color(0, 0, 0, 0.22), 1.0, true)

	var le := tier_color.lightened(0.55); le.a = 0.90
	draw_line(pts[3], pts[4], le, 1.5, true)
	draw_line(pts[4], pts[5], le, 2.5, true)
	draw_line(pts[5], pts[0], le, 1.5, true)
	draw_line(pts[0], pts[1], Color(0, 0, 0, 0.40), 1.5, true)
	draw_line(pts[1], pts[2], Color(0, 0, 0, 0.50), 2.0, true)
	draw_line(pts[2], pts[3], Color(0, 0, 0, 0.40), 1.5, true)

	if with_fx:
		var oc := tier_color; oc.a = 0.32 + 0.15 * sin(_t * 1.8)
		_draw_border(_hex(c, eff_r + 8.0), oc, 1.8)
		var ef    := fmod(_t * 1.1, TAU) / TAU * 6.0
		var eidx  := int(ef) % 6
		var efrac : float = fmod(ef, 1.0)
		var ps    := pts[eidx].lerp(pts[(eidx + 1) % 6], efrac)
		var pe    := pts[eidx].lerp(pts[(eidx + 1) % 6], minf(efrac + 0.38, 1.0))
		var sh    := tier_color.lightened(0.70); sh.a = 0.88
		draw_line(ps, pe, sh, 3.5, true)

	if is_selected:
		_draw_border(pts, tier_color, 2.5)
		var glow := tier_color; glow.a = 0.28
		_draw_border(_hex(c, eff_r + 10.0), glow, 5.0)
	elif is_hovered:
		var expand: float = 16.0
		if with_fx: expand = 20.0
		var corona := tier_color; corona.a = 0.22
		draw_colored_polygon(_hex(c, eff_r + expand), corona)
		_draw_border(pts, tier_color.lightened(0.2), 3.0)
		var soft := tier_color; soft.a = 0.40
		_draw_border(_hex(c, eff_r + 10.0), soft, 6.0)

func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * r)
	return pts

func _draw_border(pts: PackedVector2Array, col: Color, w: float) -> void:
	for i in 6:
		draw_line(pts[i], pts[(i + 1) % 6], col, w, true)
