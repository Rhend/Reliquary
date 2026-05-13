# ============================================================
# Village.gd — Hub circulaire JRPG style SNES.
# Tier 0  : orbe cliquable → déblocage Tier 1.
# Tier 1+ : hexagones + panneau JRPG droite (40/60).
# ============================================================
extends Control

# ─── Anneau animé ─────────────────────────────────────────────
class CircleRing extends Control:
	var ring_color    := Color.WHITE
	var ring_radius   := 0.0
	var ring_width    := 13.0
	var fill_fraction := 0.0
	var tier          := 0
	var _t            := 0.0

	const _SPARKS := [0.4, 1.2, 2.1, 2.9, 3.8, 4.6, 5.4]

	func _process(dt: float) -> void:
		_t += dt
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

	# ── Tier 0 : Commun — sobre, un seul anneau discret ───────
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

	# ── Tier 1 : Peu Commun — vivant, corona + shimmer ────────
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

	# ── Tier 2 : Rare — anneau intérieur + double shimmer ─────
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

	# ── Tier 3 : Épique — triple anneau + 3 orbes orbitaux ────
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

	# ── Tier 4 : Légendaire — solaire, rayons + 5 orbes ───────
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

	# ── Tier 5 : Unique — battement de cœur, veines, vivant ───
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

	# ── Helpers ────────────────────────────────────────────────
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

# ─── Orbe cliquable (tier 0) ──────────────────────────────────
class ClickOrb extends Control:
	var tier_color := Color.WHITE
	var callback   : Callable
	var is_hovered := false
	var _t         := 0.0
	var _ptween    : Tween

	func _ready() -> void:
		pivot_offset = size * 0.5
		mouse_entered.connect(func() -> void: is_hovered = true;  queue_redraw())
		mouse_exited.connect( func() -> void: is_hovered = false; queue_redraw())

		var ico := Label.new()
		ico.text = "✦"
		ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		ico.add_theme_font_size_override("font_size", 28)
		ico.anchor_left   = 0.0; ico.anchor_right  = 1.0
		ico.anchor_top    = 0.0; ico.anchor_bottom = 0.0
		ico.offset_top    = 10;  ico.offset_bottom = 56
		ico.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		add_child(ico)

		var lbl := Label.new()
		lbl.text = "CLIC"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", tier_color)
		lbl.anchor_left   = 0.0; lbl.anchor_right  = 1.0
		lbl.anchor_top    = 0.0; lbl.anchor_bottom = 0.0
		lbl.offset_top    = 52;  lbl.offset_bottom = 74
		lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			_pulse()
			callback.call()

	func _pulse() -> void:
		if _ptween: _ptween.kill()
		_ptween = create_tween().set_trans(Tween.TRANS_SINE)
		_ptween.tween_property(self, "scale", Vector2(0.82, 0.82), 0.06)
		_ptween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT)
		_ptween.tween_property(self, "scale", Vector2.ONE,         0.10)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var glow := tier_color
		glow.a = 0.08 + 0.06 * sin(_t * 2.0) + (0.10 if is_hovered else 0.0)
		draw_circle(c, r + 14.0, glow)
		var fill := tier_color.darkened(0.58); fill.a = 0.90
		draw_circle(c, r, fill)
		var border := tier_color; border.a = 0.50 + 0.25 * sin(_t * 2.0)
		draw_arc(c, r, 0.0, TAU, 64, border, 2.5, true)
		if is_hovered:
			var hov := tier_color; hov.a = 0.30
			draw_arc(c, r + 7.0, 0.0, TAU, 32, hov, 5.0, true)

# ─── Hexagone interactif ──────────────────────────────────────
class HexItem extends Control:
	var icon_text   := ""
	var label_text  := ""
	var tier_color  := Color.WHITE
	var callback    : Callable
	var hex_radius  := 58.0
	var is_hovered  := false
	var is_selected := false
	var _htween     : Tween

	func _ready() -> void:
		pivot_offset = size * 0.5

		var lbl := Label.new()
		lbl.text = label_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.anchor_left   = 0.0; lbl.anchor_right  = 1.0
		lbl.anchor_top    = 0.0; lbl.anchor_bottom = 0.0
		lbl.offset_top    = 60;  lbl.offset_bottom = 92   # centré dans 152px
		lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)

		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)

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
		var c   := size * 0.5
		var pts := _hex(c, hex_radius)

		# ── Drop shadow (décalé bas-droite) ───────────────────
		draw_colored_polygon(_hex(c + Vector2(2.5, 4.0), hex_radius), Color(0, 0, 0, 0.40))

		# ── Base ─────────────────────────────────────────────
		var base := tier_color.darkened(0.42); base.a = 0.95
		draw_colored_polygon(pts, base)

		# ── Lumière (demi-haut) ───────────────────────────────
		var top_poly := PackedVector2Array([c, pts[3], pts[4], pts[5], pts[0]])
		draw_colored_polygon(top_poly, Color(1, 1, 1, 0.11))

		# ── Ombre (demi-bas) ─────────────────────────────────
		var bot_poly := PackedVector2Array([c, pts[0], pts[1], pts[2], pts[3]])
		draw_colored_polygon(bot_poly, Color(0, 0, 0, 0.28))

		# ── Biseau intérieur — bord lumineux (haut) ───────────
		var inn := _hex(c, hex_radius - 5.0)
		var bevel_light := Color(1, 1, 1, 0.18)
		draw_line(inn[3], inn[4], bevel_light, 1.0, true)
		draw_line(inn[4], inn[5], bevel_light, 1.5, true)
		draw_line(inn[5], inn[0], bevel_light, 1.0, true)

		# ── Biseau intérieur — bord ombragé (bas) ────────────
		var bevel_dark := Color(0, 0, 0, 0.22)
		draw_line(inn[0], inn[1], bevel_dark, 1.0, true)
		draw_line(inn[1], inn[2], bevel_dark, 1.5, true)
		draw_line(inn[2], inn[3], bevel_dark, 1.0, true)

		# ── Arêtes éclairées extérieures (haut) ───────────────
		var light_edge := tier_color.lightened(0.55); light_edge.a = 0.90
		draw_line(pts[3], pts[4], light_edge, 1.5, true)
		draw_line(pts[4], pts[5], light_edge, 2.5, true)
		draw_line(pts[5], pts[0], light_edge, 1.5, true)

		# ── Arêtes ombragées extérieures (bas) ────────────────
		draw_line(pts[0], pts[1], Color(0, 0, 0, 0.40), 1.5, true)
		draw_line(pts[1], pts[2], Color(0, 0, 0, 0.50), 2.0, true)
		draw_line(pts[2], pts[3], Color(0, 0, 0, 0.40), 1.5, true)

		# ── Effets hover / selected ────────────────────────────
		if is_selected:
			_draw_border(pts, tier_color, 2.5)
			var glow := tier_color; glow.a = 0.28
			_draw_border(_hex(c, hex_radius + 10.0), glow, 5.0)
		elif is_hovered:
			var corona := tier_color; corona.a = 0.22
			draw_colored_polygon(_hex(c, hex_radius + 16.0), corona)
			_draw_border(pts, tier_color.lightened(0.2), 3.0)
			var soft := tier_color; soft.a = 0.40
			_draw_border(_hex(c, hex_radius + 10.0), soft, 6.0)

	func _hex(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(c + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * r)
		return pts

	func _draw_border(pts: PackedVector2Array, col: Color, w: float) -> void:
		for i in 6:
			draw_line(pts[i], pts[(i + 1) % 6], col, w, true)

# ─── Cadre JRPG (panneau droit) ───────────────────────────────
class JRPGPanel extends Control:
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

		# Fond sombre
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.09, 0.97))

		# Bordure extérieure
		var ob := panel_color; ob.a = 0.80
		draw_rect(Rect2(Vector2.ZERO, sz), ob, false, bw)

		# Bordure intérieure
		var ib := panel_color; ib.a = 0.22
		draw_rect(Rect2(Vector2(m, m), sz - Vector2(m * 2.0, m * 2.0)), ib, false, 1.0)

		# Fond barre titre
		var tb := panel_color.darkened(0.55); tb.a = 0.85
		draw_rect(Rect2(Vector2(bw, bw), Vector2(sz.x - bw * 2.0, th)), tb)

		# Séparateur titre (respiration)
		var sep := panel_color; sep.a = 0.55 + 0.20 * sin(_t * 1.8)
		draw_line(Vector2(m * 2.0, th + bw), Vector2(sz.x - m * 2.0, th + bw), sep, 1.5)

		# Shimmer sur barre titre
		var shim_x := fmod(_t * 70.0, sz.x + 30.0) - 15.0
		var shim   := Color.WHITE; shim.a = 0.07
		draw_rect(Rect2(Vector2(shim_x, bw), Vector2(22.0, th - bw)), shim)

		# Ornements coins (diamants)
		_draw_diamond(Vector2(m + 5.0, m + 5.0),             4.5, panel_color)
		_draw_diamond(Vector2(sz.x - m - 5.0, m + 5.0),      4.5, panel_color)
		_draw_diamond(Vector2(m + 5.0, sz.y - m - 5.0),      4.5, panel_color)
		_draw_diamond(Vector2(sz.x - m - 5.0, sz.y - m - 5.0), 4.5, panel_color)

	func _draw_diamond(pos: Vector2, r: float, col: Color) -> void:
		var c := col; c.a = 0.88
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0.0, -r),
			pos + Vector2(r, 0.0),
			pos + Vector2(0.0, r),
			pos + Vector2(-r, 0.0),
		]), c)

# ─── Constantes ───────────────────────────────────────────────
const RING_RADIUS  := 165.0
const HEX_SIZE     := Vector2(152.0, 152.0)
const TIER_0_COLOR := Color(0.38, 0.38, 0.52)
const XP_PER_CLICK := 20.0

# [label, icon, tier_min, callback_name, panel_id]
const MENU_ITEMS: Array = [
	["HÉRO",        "👤", 1, "_go_hero",       "hero"       ],
	["EXPÉDITIONS", "⚔",  1, "_go_adventure",  "adventure"  ],
	["ÉVOLUTIONS",  "▲",  2, "_go_evolutions", "evolutions" ],
	["FORGE",       "🔨", 3, "_go_forge",      "forge"      ],
	["SANCTUAIRE",  "✦",  4, "_go_sanctuary",  "sanctuary"  ],
	["RELIQUE",     "◈",  5, "_go_relic",      "relic"      ],
]

const PANEL_TITLES: Dictionary = {
	"hero":       "HÉRO",
	"adventure":  "EXPÉDITIONS",
	"evolutions": "ÉVOLUTIONS",
	"forge":      "FORGE",
	"sanctuary":  "SANCTUAIRE",
	"relic":      "RELIQUE",
}

# ─── État ─────────────────────────────────────────────────────
var _ring            : CircleRing
var _xp_label        : Label
var _hub_root        : Control
var _rp_root         : Control
var _rp_content      : VBoxContainer
var _rp_title        : Label
var _active_panel_id := ""
var _hex_items       : Dictionary = {}   # panel_id → HexItem

# ─── Init ─────────────────────────────────────────────────────
func _ready() -> void:
	SaveManager.load_save()
	_build_ui()

func _active_creature() -> Dictionary:
	var cid := GameData.player.get("active_creature_id", "") as String
	if cid.is_empty(): return {}
	return GameData.get_entity(cid)

func _current_tier() -> int:
	return _active_creature().get("current_tier", 0) as int

# ─── Construction principale ──────────────────────────────────
func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var creature := _active_creature()
	var tier     := creature.get("current_tier", 0) as int
	if tier == 0:
		_build_tier0(creature)
	else:
		_build_hub(creature, tier)

	_build_debug_buttons()

# ─── Tier 0 : clicker ─────────────────────────────────────────
func _build_tier0(creature: Dictionary) -> void:
	var diam  := (RING_RADIUS + 24.0) * 2.0
	var xp    := creature.get("current_xp", 0.0) as float
	var xpmax := float(GameData.xp_thresholds[1])

	_ring = CircleRing.new()
	_ring.ring_color    = TIER_0_COLOR
	_ring.ring_width    = 13.0
	_ring.fill_fraction = minf(xp / xpmax, 1.0)
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	add_child(_ring)

	var lname := Label.new()
	lname.text = creature.get("name", "Héro") as String
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 15)
	lname.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.2))
	_center(lname, Vector2(0.0, -60.0), Vector2(150.0, 22.0))
	add_child(lname)

	var orb := ClickOrb.new()
	orb.tier_color   = TIER_0_COLOR
	orb.callback     = Callable(self, "_on_hero_click")
	_center(orb, Vector2(0.0, -4.0), Vector2(90.0, 90.0))
	orb.pivot_offset = Vector2(45.0, 45.0)
	add_child(orb)

	_xp_label = Label.new()
	_xp_label.text = "%d / %d XP" % [int(xp), int(xpmax)]
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.3))
	_center(_xp_label, Vector2(0.0, 56.0), Vector2(160.0, 20.0))
	add_child(_xp_label)

# ─── Tier 1+ : hub hexagonal ──────────────────────────────────
func _build_hub(creature: Dictionary, tier: int) -> void:
	var vp     := get_viewport_rect().size
	var tcolor := UIColors.tier_color(tier)
	var _diam_margins := [70.0, 70.0, 82.0, 104.0, 136.0, 164.0]
	var diam: float = RING_RADIUS * 2.0 + float(_diam_margins[tier])

	_hub_root = Control.new()
	_hub_root.size = vp
	add_child(_hub_root)

	_ring = CircleRing.new()
	_ring.ring_color  = tcolor
	_ring.ring_radius = RING_RADIUS
	_ring.tier        = tier
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	_hub_root.add_child(_ring)

	var lname := Label.new()
	lname.text = creature.get("name", "Héro") as String
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 17)
	lname.add_theme_color_override("font_color", tcolor)
	_center(lname, Vector2(0.0, -14.0), Vector2(150.0, 26.0))
	_hub_root.add_child(lname)

	var ltier := Label.new()
	ltier.text = GameData.get_tier_name(tier)
	ltier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ltier.add_theme_font_size_override("font_size", 11)
	ltier.add_theme_color_override("font_color", tcolor.lerp(Color.WHITE, 0.40))
	_center(ltier, Vector2(0.0, 12.0), Vector2(130.0, 20.0))
	_hub_root.add_child(ltier)

	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool: return d[2] <= tier)
	var n := unlocked.size()
	for i in n:
		var ang := -PI * 0.5 + i * TAU / n
		var pos := Vector2(cos(ang), sin(ang)) * RING_RADIUS
		var d: Array = unlocked[i]
		_make_hex(d[0], d[1], tcolor, pos, Callable(self, d[3]), d[4])

# ─── Panneau droite ───────────────────────────────────────────
func _open_panel(panel_id: String) -> void:
	var vp := get_viewport_rect().size

	# Toggle : même hex → fermer
	if _active_panel_id == panel_id and _rp_root != null:
		_close_panel()
		return

	_active_panel_id = panel_id
	_update_hex_selection(panel_id)

	# Panneau déjà ouvert → swap de contenu seulement
	if _rp_root != null:
		if _rp_title:
			_rp_title.text = PANEL_TITLES.get(panel_id, panel_id.to_upper())
		_swap_panel_content(panel_id)
		return

	# Réduire le hub à 40 %
	var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "size:x", vp.x * 0.4, 0.35)

	# Créer le panneau hors écran à droite
	_rp_root = Control.new()
	_rp_root.size     = Vector2(vp.x * 0.6, vp.y)
	_rp_root.position = Vector2(vp.x, 0.0)
	add_child(_rp_root)
	_build_panel_frame(panel_id)

	# Glissement vers la droite du hub
	var pt := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	pt.tween_property(_rp_root, "position:x", vp.x * 0.4, 0.35)

func _close_panel() -> void:
	if _rp_root == null:
		return
	var vp := get_viewport_rect().size
	_active_panel_id = ""
	_update_hex_selection("")

	var pt := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	pt.tween_property(_rp_root, "position:x", vp.x, 0.25)
	pt.tween_callback(func() -> void:
		if _rp_root:
			_rp_root.queue_free()
			_rp_root    = null
			_rp_content = null
			_rp_title   = null
	)

	var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "size:x", vp.x, 0.25)

func _update_hex_selection(active_id: String) -> void:
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.is_selected = (pid == active_id)
		item.queue_redraw()

func _swap_panel_content(panel_id: String) -> void:
	for child in _rp_content.get_children():
		child.queue_free()
	_fill_panel_content(panel_id)

# ─── Construction du cadre JRPG ──────────────────────────────
func _build_panel_frame(panel_id: String) -> void:
	var tcolor := UIColors.tier_color(_current_tier())

	var frame := JRPGPanel.new()
	frame.panel_color = tcolor
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rp_root.add_child(frame)

	# Titre
	_rp_title = Label.new()
	_rp_title.text = PANEL_TITLES.get(panel_id, panel_id.to_upper())
	_rp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rp_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_rp_title.add_theme_font_size_override("font_size", 16)
	_rp_title.add_theme_color_override("font_color", Color.WHITE)
	_rp_title.anchor_left   = 0.0; _rp_title.anchor_right  = 1.0
	_rp_title.anchor_top    = 0.0; _rp_title.anchor_bottom = 0.0
	_rp_title.offset_left   = 6;   _rp_title.offset_right  = -40
	_rp_title.offset_top    = 8;   _rp_title.offset_bottom = 38
	frame.add_child(_rp_title)

	# Bouton fermer (toggle = re-clic hex, mais on garde une croix aussi)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", tcolor)
	close_btn.anchor_left   = 1.0; close_btn.anchor_right  = 1.0
	close_btn.anchor_top    = 0.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left   = -36; close_btn.offset_right  = -6
	close_btn.offset_top    = 5;   close_btn.offset_bottom = 35
	close_btn.pressed.connect(_close_panel)
	frame.add_child(close_btn)

	# Zone de contenu scrollable
	var scroll := ScrollContainer.new()
	scroll.anchor_left   = 0.0; scroll.anchor_right  = 1.0
	scroll.anchor_top    = 0.0; scroll.anchor_bottom = 1.0
	scroll.offset_top    = 44
	scroll.offset_left   = 10;  scroll.offset_right  = -10
	scroll.offset_bottom = -10
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 12)
	scroll.add_child(margin)

	_rp_content = VBoxContainer.new()
	_rp_content.add_theme_constant_override("separation", 10)
	_rp_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_rp_content)

	_fill_panel_content(panel_id)

# ─── Contenu des panneaux ─────────────────────────────────────
func _fill_panel_content(panel_id: String) -> void:
	match panel_id:
		"hero":       _panel_hero()
		"adventure":  _panel_nav("Lancer une expédition", "⚔", "res://scenes/village/adventure_select.tscn")
		"evolutions": _panel_nav("Accéder aux Évolutions", "▲", "res://scenes/village/evolution_hall.tscn")
		"forge":      _panel_nav("Ouvrir la Forge",        "🔨", "res://scenes/village/forge.tscn")
		"sanctuary":  _panel_soon("SANCTUAIRE")
		"relic":      _panel_soon("RELIQUE")

func _panel_hero() -> void:
	var cid    := GameData.player.get("active_creature_id", "") as String
	var c      := GameData.get_entity(cid)
	var tier   := c.get("current_tier", 0) as int
	var xp     := c.get("current_xp",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xpmax  := float(GameData.xp_thresholds[ni])
	var can_ev := tier < GameData.MAX_TIER and xp >= xpmax
	var tcolor := UIColors.tier_color(tier)

	# Nom + tier
	var lname := Label.new()
	lname.text = "%s  —  %s" % [c.get("name", "Héro"), GameData.get_tier_name(tier)]
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 16)
	lname.add_theme_color_override("font_color", tcolor)
	_rp_content.add_child(lname)

	# ── Sous-section STATISTIQUES ─────────────────────────────
	_rp_content.add_child(_section_header("◆  STATISTIQUES", tcolor))

	var eq  := GameData.get_equipment_bonuses()
	var eff := GameData.get_effective_stats(cid)
	var pas := PassiveSystem.get_combat_bonuses()

	var atk_base  := int(eff.get("atk", 0))
	var atk_bonus := int(eq.get("atk", 0)) + int(pas.get("atk_bonus", 0))
	var def_base  := int(eff.get("def", 0))
	var def_bonus := int(pas.get("def_bonus", 0))
	var hp_base   := int(eff.get("hp", 0))
	var hp_bonus  := int(eq.get("hp", 0)) + int(pas.get("hp_bonus", 0))

	for row: Array in [
		["ATK", atk_base + atk_bonus, atk_base, atk_bonus, UIColors.STAT_ATK],
		["DEF", def_base + def_bonus, def_base, def_bonus, UIColors.STAT_DEF],
		["PV",  hp_base  + hp_bonus,  hp_base,  hp_bonus,  UIColors.STAT_HP ],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		_rp_content.add_child(hb)
		var kl := Label.new()
		kl.text = str(row[0]) + " :"
		kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hb.add_child(kl)
		var vl := Label.new()
		vl.text = str(row[1])
		vl.add_theme_font_size_override("font_size", 14)
		vl.add_theme_color_override("font_color", row[4])
		hb.add_child(vl)
		var detail := Label.new()
		detail.text = "(%d + %d)" % [row[2], row[3]]
		detail.add_theme_font_size_override("font_size", 10)
		detail.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hb.add_child(detail)

	if tier < GameData.MAX_TIER:
		var xp_color := UIColors.FILTER_ON if can_ev else UIColors.STAT_HP
		var bar := ProgressBar.new()
		bar.min_value = 0.0; bar.max_value = xpmax
		bar.value     = minf(xp, xpmax)
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(0.0, 16.0)
		var sf := StyleBoxFlat.new(); sf.bg_color = xp_color
		var sb := StyleBoxFlat.new(); sb.bg_color = UIColors.BG_BAR
		bar.add_theme_stylebox_override("fill", sf)
		bar.add_theme_stylebox_override("background", sb)
		bar.add_theme_color_override("font_color", Color.WHITE)
		bar.add_theme_font_size_override("font_size", 10)
		_rp_content.add_child(bar)

		var xl := Label.new()
		xl.text = "XP  %.0f / %.0f" % [xp, xpmax]
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.add_theme_font_size_override("font_size", 10)
		xl.add_theme_color_override("font_color", UIColors.FILTER_ON if can_ev else UIColors.TEXT_MUTED)
		_rp_content.add_child(xl)

		if can_ev:
			var eb := Button.new()
			eb.text = "ÉVOLUER ▲"
			eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			eb.add_theme_color_override("font_color", UIColors.FILTER_ON)
			eb.pressed.connect(func() -> void:
				if MasterySystem.evolve_entity(cid):
					get_tree().reload_current_scene()
			)
			_rp_content.add_child(eb)
	else:
		var ml := Label.new()
		ml.text = "▲ NIVEAU MAXIMUM"
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 11)
		ml.add_theme_color_override("font_color", UIColors.FILTER_ON)
		_rp_content.add_child(ml)

	# ── Sous-section PASSIFS ──────────────────────────────────
	_rp_content.add_child(_section_header("◆  PASSIFS", tcolor))

	var unlocked: Array = c.get("unlocked_passives", [])

	if unlocked.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "Aucun passif débloqué"
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_rp_content.add_child(none_lbl)
	else:
		for pid in unlocked:
			var pdata := GameData.get_entity(pid)
			if not pdata.is_empty():
				_rp_content.add_child(_passive_card(pdata, tcolor))

	# Passifs verrouillés (futurs slots)
	for slot in c.get("passive_slots", []):
		var unlock_t := slot.get("unlock_tier", 99) as int
		var pid      := slot.get("passive_id",  "") as String
		if pid in unlocked:
			continue
		var pdata := GameData.get_entity(pid)
		var pname := pdata.get("name", pid) as String if not pdata.is_empty() else pid
		_rp_content.add_child(_passive_locked_card(pname, unlock_t))

# ─── Helpers sous-sections ────────────────────────────────────
func _section_header(title: String, color: Color) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	vb.add_child(lbl)

	var line := ColorRect.new()
	line.color = Color(color.r, color.g, color.b, 0.38)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(line)

	return vb

func _passive_card(pdata: Dictionary, tcolor: Color) -> Control:
	var rarity := pdata.get("current_tier", 0) as int
	var rcolor := UIColors.tier_color(rarity)
	var rname  := GameData.get_tier_name(rarity)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(rcolor.r, rcolor.g, rcolor.b, 0.07)
	style.border_color = Color(rcolor.r, rcolor.g, rcolor.b, 0.60)
	style.set_border_width_all(1)
	for prop: String in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 4)
	panel.add_theme_stylebox_override("panel", style)

	var m := MarginContainer.new()
	for s: String in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(s, 6)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	m.add_child(vb)

	# Ligne nom + badge rareté
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = pdata.get("name", pdata.get("id", "?")) as String
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(name_lbl)

	var badge := Label.new()
	badge.text = rname
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", rcolor)
	header.add_child(badge)

	for effect in pdata.get("base_stats", {}).get("effects", []):
		var desc := effect.get("description", "") as String
		if desc.is_empty(): continue
		var eff_lbl := Label.new()
		eff_lbl.text = desc
		eff_lbl.add_theme_font_size_override("font_size", 10)
		eff_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(eff_lbl)

	return panel

func _passive_locked_card(pname: String, unlock_tier: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.08, 0.12, 0.6)
	style.border_color = Color(0.25, 0.25, 0.30, 0.4)
	style.set_border_width_all(1)
	for prop: String in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 4)
	panel.add_theme_stylebox_override("panel", style)

	var m := MarginContainer.new()
	for s: String in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(s, 6)
	panel.add_child(m)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var lock_lbl := Label.new()
	lock_lbl.text = "🔒"
	lock_lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(lock_lbl)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = pname
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vb.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = "Débloque au %s" % GameData.get_tier_name(unlock_tier)
	tier_lbl.add_theme_font_size_override("font_size", 9)
	tier_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED.darkened(0.2))
	vb.add_child(tier_lbl)

	return panel

func _panel_nav(desc_text: String, icon: String, scene_path: String) -> void:
	var desc := Label.new()
	desc.text = desc_text
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rp_content.add_child(desc)

	var btn := Button.new()
	btn.text = "%s  Entrer" % icon
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(scene_path))
	_rp_content.add_child(btn)

func _panel_soon(label: String) -> void:
	var lbl := Label.new()
	lbl.text = "✦  %s  ✦\n\nBientôt disponible" % label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_rp_content.add_child(lbl)

# ─── Debug : boutons tier ─────────────────────────────────────
func _build_debug_buttons() -> void:
	var hb := HBoxContainer.new()
	hb.anchor_left = 0.0; hb.anchor_top    = 0.0
	hb.anchor_right = 0.0; hb.anchor_bottom = 0.0
	hb.offset_left = 10; hb.offset_top    = 10
	hb.offset_right = 10; hb.offset_bottom = 10
	hb.add_theme_constant_override("separation", 6)
	add_child(hb)

	var up := Button.new()
	up.text = "Tier +"
	up.pressed.connect(_debug_tier_up)
	hb.add_child(up)

	var dn := Button.new()
	dn.text = "Tier −"
	dn.pressed.connect(_debug_tier_down)
	hb.add_child(dn)

func _debug_tier_up() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("current_tier", 0) as int
	if tier < GameData.MAX_TIER:
		hero["current_tier"] = tier + 1
		hero["current_xp"]   = 0.0
		SaveManager.save()
		get_tree().reload_current_scene()

func _debug_tier_down() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("current_tier", 0) as int
	if tier > 0:
		hero["current_tier"] = tier - 1
		hero["current_xp"]   = 0.0
		SaveManager.save()
		get_tree().reload_current_scene()

# ─── Clicker (tier 0) ─────────────────────────────────────────
func _on_hero_click() -> void:
	var hero  := GameData.get_entity("hero")
	var xp    := hero.get("current_xp", 0.0) as float + XP_PER_CLICK
	hero["current_xp"] = xp
	var xpmax := float(GameData.xp_thresholds[1])
	_ring.fill_fraction = minf(xp / xpmax, 1.0)
	_xp_label.text      = "%d / %d XP" % [int(xp), int(xpmax)]
	EventBus.xp_gained.emit("hero", XP_PER_CLICK)
	if MasterySystem.can_evolve("hero"):
		MasterySystem.evolve_entity("hero")
		SaveManager.save()
		get_tree().reload_current_scene()

# ─── Factory hexagone ─────────────────────────────────────────
func _make_hex(lbl: String, icon: String, tcolor: Color, pos: Vector2, cb: Callable, panel_id: String) -> void:
	var item := HexItem.new()
	item.icon_text  = icon
	item.label_text = lbl
	item.tier_color = tcolor
	item.callback   = cb
	_center(item, pos, HEX_SIZE)
	item.pivot_offset = HEX_SIZE * 0.5   # centrage du scale x1.2
	_hub_root.add_child(item)
	_hex_items[panel_id] = item

# ─── Navigation → panneaux ────────────────────────────────────
func _go_hero()       -> void: _open_panel("hero")
func _go_adventure()  -> void: _open_panel("adventure")
func _go_evolutions() -> void: _open_panel("evolutions")
func _go_forge()      -> void: _open_panel("forge")
func _go_sanctuary()  -> void: _open_panel("sanctuary")
func _go_relic()      -> void: _open_panel("relic")

# ─── Utils ────────────────────────────────────────────────────
func _center(ctrl: Control, pos: Vector2, sz: Vector2) -> void:
	ctrl.anchor_left   = 0.5; ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5; ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = pos.x - sz.x * 0.5
	ctrl.offset_right  = pos.x + sz.x * 0.5
	ctrl.offset_top    = pos.y - sz.y * 0.5
	ctrl.offset_bottom = pos.y + sz.y * 0.5
