# ============================================================
# Village.gd — Hub central du jeu.
#
# Tier 0  : orbe cliquable → XP manual → déblocage Tier 1.
# Tier 1+ : hub hexagonal + panneau JRPG glissant (40/60 viewport).
#
# Inner classes :
#   CircleRing — anneau XP animé autour du hub.
#   ClickOrb   — orbe cliquable (tier 0 uniquement).
#   HexItem    — bouton hexagonal interactif (tier 1+).
#   JRPGPanel  — cadre dessiné du panneau droit.
#   XPCard     — PanelContainer avec barre XP animée en fond.
# ============================================================
extends Control

# ─── Anneau animé ─────────────────────────────────────────────
class CircleRing extends Control:
	var ring_color    := Color.WHITE   # teinte principale de l'anneau (= couleur du tier)
	var ring_radius   := 0.0           # rayon en pixels ; 0 = auto depuis la taille du Control
	var ring_width    := 13.0          # épaisseur de l'arc principal (pixels)
	var fill_fraction := 0.0           # fraction XP affichée [0..1] en arc de progression
	var tier          := 0             # tier actuel — détermine quelle méthode _draw utilise
	var _t            := 0.0           # accumulateur de temps pour les animations cycliques

	const _SPARKS := [0.4, 1.2, 2.1, 2.9, 3.8, 4.6, 5.4]

	func _process(dt: float) -> void:
		_t += dt
		pivot_offset = size * 0.5
		rotation += dt * 0.18   # rotation horaire douce (~10°/s)
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
	var tier_color := Color.WHITE   # teinte de l'orbe (= TIER_0_COLOR au tier 0)
	var callback   : Callable       # appelé à chaque clic gauche
	var is_hovered := false         # true si la souris est sur l'orbe (hover visuel)
	var _t         := 0.0           # accumulateur de temps pour les animations cycliques
	var _ptween    : Tween          # tween du pulse de clic — tué avant chaque nouveau clic

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
	var icon_text    := ""              # emoji affiché au centre du bouton
	var label_text   := ""              # texte du callout (ex: "HÉRO", "EXPÉDITIONS")
	var tier_color   := Color.WHITE     # couleur du tier — teinte toute la forme et le callout
	var tier         := 1               # tier du héro — détermine le rendu (rond vs hexagone)
	var callback     : Callable         # appelé après l'animation de press
	var hex_radius   := 58.0            # rayon de l'hexagone (utilisé pour les tiers 3–5)
	var outward_dir  := Vector2.RIGHT   # direction du callout depuis le centre du hub
	var is_hovered   := false           # état hover — affiche la corona et le contour
	var is_selected  := false           # état sélectionné — affiche un glow plus marqué
	var _htween      : Tween            # tween hover/press — tué avant chaque nouveau
	var _t           := 0.0             # accumulateur de temps pour les animations cycliques

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

		# Glow de fond (respire)
		var glow := Color(tier_color.r, tier_color.g, tier_color.b,
				0.08 + 0.05 * sin(_t * 1.5))
		draw_line(p0, p1, glow, 8.0, true)
		draw_line(p1, p2, glow, 8.0, true)

		# Outline + trait principal
		draw_line(p0, p1, black, 3.0, true)
		draw_line(p1, p2, black, 3.0, true)
		draw_line(p0, p1, base, 1.5, true)
		draw_line(p1, p2, base, 1.5, true)

		# Dot de départ qui respire
		var dot_r := 2.0 + 0.7 * sin(_t * 3.2)
		draw_circle(p0, dot_r + 1.5, black)
		draw_circle(p0, dot_r, base)

		# Pulse qui voyage de p0 → p1 → p2 en boucle
		var prog := fmod(_t * 0.55, 1.0)
		var dist := prog * total
		var pp   : Vector2
		if dist <= stem_len:
			pp = p0.lerp(p1, dist / stem_len)
		else:
			pp = p1.lerp(p2, (dist - stem_len) / bar_len)
		var pa   := sin(prog * PI)  # fade entrée/sortie
		var pc   := tier_color.lightened(0.45); pc.a = pa * 0.85
		var pcg  := Color(pc.r, pc.g, pc.b, pa * 0.25)
		draw_circle(pp, 5.5, pcg)
		draw_circle(pp, 2.8, pc)
		draw_circle(pp, 1.2, Color(1.0, 1.0, 1.0, pa * 0.90))

		# Texte centré sur la barre, outline léger
		var tx  := minf(p1.x, p2.x)
		var tp  := Vector2(tx, p1.y - 6.0)
		var tco := Color(0.0, 0.0, 0.0, 0.50)
		for ofs: Vector2 in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]:
			draw_string(font, tp + ofs, label_text,
					HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz, tco)
		draw_string(font, tp, label_text,
				HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz,
				tier_color.lightened(0.35))

	# ── Tier 1 & 2 : boutons ronds ────────────────────────────
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

	# ── Tier 3 / 4 / 5 : hexagones ────────────────────────────
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

# ─── Cadre JRPG (panneau droit) ───────────────────────────────
class JRPGPanel extends Control:
	var panel_color := Color.WHITE   # couleur du cadre (= couleur du tier actif)
	var _t          := 0.0           # accumulateur de temps pour le shimmer et le séparateur animé

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

class XPCard extends PanelContainer:
	var xp_fill    := 0.0           # fraction [0..1] de la largeur remplie par la barre XP
	var fill_color := Color.WHITE   # couleur de la barre et des bulles (= couleur du tier)
	var _t         := 0.0           # accumulateur de temps pour l'animation des bulles montantes

	# [x_fraction, radius, vitesse, phase]
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

		# Remplissage de base
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)),
				Color(fill_color.r, fill_color.g, fill_color.b, 0.35))

		# Bulles qui montent de bas en haut
		for b in _BUBBLES:
			var xf : float = b[0]
			var r  : float = b[1]
			var sp : float = b[2]
			var ph : float = b[3]

			if xf * w < r: continue   # hors de la zone remplie

			# Légère oscillation horizontale
			var bx := clampf(xf * w + sin(_t * sp * 3.0 + ph * TAU) * r * 0.6, r, w - r)
			# Montée continue de bas en haut, en boucle
			var progress := fmod(_t * sp + ph, 1.0)
			var by       := h + r - progress * (h + r * 2.0)

			# Fondu à l'entrée (bas) et à la sortie (haut)
			var fade  := r * 3.0
			var alpha := clampf(minf((h - by) / fade, by / fade), 0.0, 1.0) * 0.55

			if alpha > 0.01:
				var bc := fill_color
				# Corps de la bulle (cercle semi-transparent)
				draw_circle(Vector2(bx, by), r, Color(bc.r, bc.g, bc.b, alpha * 0.45))
				# Contour pour le rendu "bulle"
				draw_arc(Vector2(bx, by), r, 0.0, TAU, 16,
						Color(bc.r, bc.g, bc.b, alpha), 1.2)
				# Reflet lumineux en haut-gauche de la bulle
				draw_circle(Vector2(bx - r * 0.3, by - r * 0.3),
						r * 0.28, Color(bc.r, bc.g, bc.b, alpha * 0.8))

# ─── Constantes ───────────────────────────────────────────────
const RING_RADIUS  := 165.0
const HEX_SIZE     := Vector2(152.0, 152.0)
const TIER_0_COLOR := Color(0.38, 0.38, 0.52)
const XP_PER_CLICK := 20.0

# [label, icon, tier_min, callback_name, panel_id]
const MENU_ITEMS: Array = [
	["HÉRO",        "👤", 1, "_go_hero",      "hero"      ],
	["EXPÉDITIONS", "⚔",  1, "_go_adventure", "adventure" ],
	["FORGE",       "🔨", 2, "_go_forge",     "forge"     ],
	["SANCTUAIRE",  "✦",  3, "_go_sanctuary", "sanctuary" ],
	["RELIQUE",     "◈",  4, "_go_relic",     "relic"     ],
	["?",           "?",  5, "_go_tbd",       "tbd"       ],
]

const PANEL_TITLES: Dictionary = {
	"hero":      "HÉRO",
	"adventure": "EXPÉDITIONS",
	"forge":     "FORGE",
	"sanctuary": "SANCTUAIRE",
	"relic":     "RELIQUE",
	"tbd":       "?",
}

# ─── État ─────────────────────────────────────────────────────
var _ring            : CircleRing         # anneau animé central (XP fill + tier visuel)
var _xp_label        : Label              # label "X / Y XP" sous l'orbe (tier 0 uniquement)
var _hub_root        : Control            # conteneur du hub hexagonal (tier 1+)
var _rp_root         : Control            # panneau droit JRPG — null si fermé
var _rp_content      : VBoxContainer      # zone de contenu scrollable du panneau droit
var _rp_title        : Label              # label titre dans la barre du panneau droit
var _active_panel_id      := ""           # id du panneau ouvert ("hero", "adventure", …)
var _adv_selected_biome_id := ""          # biome sélectionné dans le panneau Expéditions
var _hex_items            : Dictionary = {}   # panel_id → HexItem, pour gérer l'état sélectionné

# ─── Init ─────────────────────────────────────────────────────
# Construit l'UI au démarrage (la sauvegarde est déjà chargée par Main.gd).
func _ready() -> void:
	_build_ui()

# Retourne le dictionnaire d'entité de la créature active, ou {} si absente.
func _active_creature() -> Dictionary:
	var cid := GameData.player.get("active_creature_id", "") as String
	if cid.is_empty(): return {}
	return GameData.get_entity(cid)

# Tier actuel de la créature active — détermine le layout et les couleurs du hub.
func _current_tier() -> int:
	return _active_creature().get("current_tier", 0) as int

# ─── Construction principale ──────────────────────────────────
# Point d'entrée de construction : tier 0 → orbe cliquable, tier 1+ → hub hexagonal.
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
	_build_fullscreen_btn()

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
	lname.text = "Village"
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
# Construit le hub circulaire avec les hexagones débloqués par le tier.
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
	lname.text = "Village"
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
# Ouvre le panneau JRPG pour panel_id. Re-clic sur le même id → ferme (toggle).
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

# Ferme le panneau droit avec une animation de glissement vers la droite.
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

# Met à jour l'état is_selected de tous les HexItems selon le panneau ouvert.
func _update_hex_selection(active_id: String) -> void:
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.is_selected = (pid == active_id)
		item.queue_redraw()

# Vide _rp_content et réinjecte le contenu pour panel_id (panneau déjà ouvert).
func _swap_panel_content(panel_id: String) -> void:
	UIHelpers.clear_children(_rp_content)
	_fill_panel_content(panel_id)

# ─── Construction du cadre JRPG ──────────────────────────────
# Crée le JRPGPanel, le titre, le bouton fermer et la zone scrollable.
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

	var margin := UIHelpers.margin_of(12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	_rp_content = VBoxContainer.new()
	_rp_content.add_theme_constant_override("separation", 10)
	_rp_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_rp_content)

	_fill_panel_content(panel_id)

# ─── Contenu des panneaux ─────────────────────────────────────
# Dispatch vers la fonction de contenu correspondant à panel_id.
func _fill_panel_content(panel_id: String) -> void:
	match panel_id:
		"hero":      _panel_hero()
		"adventure": _panel_adventure()
		"forge":     _panel_soon("FORGE")
		"sanctuary": _panel_soon("SANCTUAIRE")
		"relic":     _panel_soon("RELIQUE")
		"tbd":       _panel_soon("?")

# Panneau Héro : nom, tier, stats (base+bonus), barre XP, passifs débloqués.
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
	_rp_content.add_child(UIHelpers.section_header("◆  STATISTIQUES", tcolor))

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
		_rp_content.add_child(UIHelpers.xp_bar(xp, xpmax, xp_color))

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
	_rp_content.add_child(UIHelpers.section_header("◆  PASSIFS", tcolor))

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


# Retourne une XPCard pour un passif : nom, badge tier, barre XP, effets du palier.
func _passive_card(pdata: Dictionary, _tcolor: Color) -> Control:
	var rarity   := pdata.get("current_tier", 0) as int
	var rcolor   := UIColors.tier_color(rarity)
	var rname    := GameData.get_tier_name(rarity)
	var has_evos := rarity < GameData.MASTERY_TIERS.size() - 1

	# Calcul de la progression XP vers le palier suivant
	var xp_cur  : float = pdata.get("current_xp", 0.0) as float
	var xp_need : int   = 0
	var xp_fill := 0.0
	if has_evos and rarity + 1 < GameData.xp_thresholds.size():
		xp_need = int(GameData.xp_thresholds[rarity + 1])
		if xp_need > 0:
			xp_fill = clampf(xp_cur / float(xp_need), 0.0, 1.0)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Carte principale avec barre XP en fond ──────────────
	var panel := XPCard.new()
	panel.xp_fill    = xp_fill
	panel.fill_color = rcolor
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(rcolor))
	if has_evos:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_add_hover_feedback(panel)
	wrapper.add_child(panel)

	var m := UIHelpers.margin_of(6)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	m.add_child(vb)

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

	var arrow := Label.new()
	arrow.text = "  ▶" if has_evos else ""
	arrow.add_theme_font_size_override("font_size", 9)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	header.add_child(arrow)

	var cur_effs: Array = _tier_effects(pdata, rarity)
	var eff_descs: Array[String] = []
	for effect in cur_effs:
		var desc := effect.get("description", "") as String
		if not desc.is_empty():
			eff_descs.append(desc)

	var xp_text := ""
	var xp_color := UIColors.TEXT_MUTED
	if rarity >= GameData.MAX_TIER:
		xp_text  = "RANG MAX"
		xp_color = rcolor
	else:
		xp_text = "%s / %s XP" % [_xp_fmt(int(xp_cur)), _xp_fmt(xp_need)]

	for i in eff_descs.size():
		var hb := HBoxContainer.new()
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(hb)

		var eff_lbl := Label.new()
		eff_lbl.text = eff_descs[i]
		eff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_lbl.add_theme_font_size_override("font_size", 10)
		eff_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hb.add_child(eff_lbl)

		if i == eff_descs.size() - 1:
			var xp_lbl := Label.new()
			xp_lbl.text = xp_text
			xp_lbl.add_theme_font_size_override("font_size", 10)
			xp_lbl.add_theme_color_override("font_color", xp_color)
			xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hb.add_child(xp_lbl)

	if eff_descs.is_empty():
		var xp_lbl := Label.new()
		xp_lbl.text = xp_text
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color", xp_color)
		xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		xp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(xp_lbl)

	# ── Arbre d'évolutions (caché par défaut) ─────────────────
	var evo_tree := VBoxContainer.new()
	evo_tree.add_theme_constant_override("separation", 2)
	evo_tree.visible = false
	wrapper.add_child(evo_tree)

	var unlock_hdr := Label.new()
	unlock_hdr.text = "— À DÉBLOQUER —"
	unlock_hdr.add_theme_font_size_override("font_size", 9)
	unlock_hdr.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	unlock_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evo_tree.add_child(unlock_hdr)

	for t in range(rarity + 1, GameData.MASTERY_TIERS.size()):
		evo_tree.add_child(_evo_row(t, rarity, pdata))

	if has_evos:
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				evo_tree.visible = not evo_tree.visible
				arrow.text = "  ▼" if evo_tree.visible else "  ▶"
		)

	return wrapper

func _evo_row(t: int, base_rarity: int, pdata: Dictionary) -> Control:
	var tc      := UIColors.tier_color(t)
	var tn      := GameData.get_tier_name(t)
	var indent  := (t - base_rarity) * 14
	var xp_cur  : float = pdata.get("current_xp", 0.0) as float
	var is_max  : bool  = t >= GameData.MAX_TIER
	var xp_need : int   = 0
	if not is_max and t + 1 < GameData.xp_thresholds.size():
		xp_need = int(GameData.xp_thresholds[t + 1])
	var xp_fill := 0.0
	if xp_need > 0:
		xp_fill = clampf(xp_cur / float(xp_need), 0.0, 1.0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", indent)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := XPCard.new()
	panel.xp_fill    = xp_fill
	panel.fill_color = tc
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(tc, 0.06, 0.38, 1, 3))
	margin.add_child(panel)

	var pm := UIHelpers.margin_of(4)
	panel.add_child(pm)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm.add_child(vb)

	# Ligne rareté + XP X/Y
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)

	var name_lbl := Label.new()
	name_lbl.text = "→  " + tn
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", tc)
	hb.add_child(name_lbl)

	var xp_lbl := Label.new()
	xp_lbl.text = "RANG MAX" if is_max else "%s / %s XP" % [_xp_fmt(int(xp_cur)), _xp_fmt(xp_need)]
	xp_lbl.add_theme_font_size_override("font_size", 9)
	xp_lbl.add_theme_color_override("font_color", tc if is_max else UIColors.TEXT_MUTED)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(xp_lbl)

	# Effets du palier
	for effect in _tier_effects(pdata, t):
		var desc := effect.get("description", "") as String
		if desc.is_empty(): continue
		var eff_lbl := Label.new()
		eff_lbl.text = desc
		eff_lbl.add_theme_font_size_override("font_size", 9)
		eff_lbl.add_theme_color_override("font_color", tc.darkened(0.2))
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(eff_lbl)

	return margin

# Retourne la liste d'effets pour le palier t, ou les effets de base si absent.
func _tier_effects(pdata: Dictionary, t: int) -> Array:
	var te_list: Array = pdata.get("tier_effects", [])
	if t < te_list.size():
		var effs: Array = te_list[t].get("effects", [])
		if not effs.is_empty(): return effs
	return pdata.get("base_stats", {}).get("effects", [])

# Formate un entier XP avec séparateur de milliers (ex: 1 234).
func _xp_fmt(xp: int) -> String:
	if xp >= 1000:
		var s := str(xp)
		return s.left(s.length() - 3) + " " + s.right(3)
	return str(xp)

# ═══════════════════════════════════════════════════════════
#  Panneau Expéditions — sélection de biome intégrée
# ═══════════════════════════════════════════════════════════

# Panneau Expéditions : placeholder ou bouton de départ + accordéon des biomes disponibles.
func _panel_adventure() -> void:
	var tier   := _current_tier()
	var tcolor := UIColors.tier_color(tier)

	# Invalide la sélection si l'entité n'existe plus (pas d'auto-select)
	if not _adv_selected_biome_id.is_empty() and GameData.get_entity(_adv_selected_biome_id).is_empty():
		_adv_selected_biome_id = ""

	# ── Slot supérieur : placeholder OU bouton ────────────────
	var no_biome_selected := _adv_selected_biome_id.is_empty()

	# Encadré neutre (aucun biome choisi)
	var placeholder := PanelContainer.new()
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.custom_minimum_size   = Vector2(0, 52)
	placeholder.visible = no_biome_selected
	placeholder.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.06, 0.25, 1, 6))
	var ph_lbl := Label.new()
	ph_lbl.text = "Choisir un biome pour partir en expédition"
	ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ph_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ph_lbl.add_theme_font_size_override("font_size", 13)
	ph_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	placeholder.add_child(ph_lbl)
	_rp_content.add_child(placeholder)

	# Bouton actif (biome sélectionné)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", tcolor)
	btn.visible = not no_biome_selected
	if not no_biome_selected:
		var bname: String = str(GameData.get_entity(_adv_selected_biome_id).get("name", _adv_selected_biome_id)).to_upper()
		btn.text = "⚔   PARTIR EN EXPÉDITION — " + bname
	else:
		btn.text = "⚔   PARTIR EN EXPÉDITION"
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	btn.pressed.connect(_on_start_selected_expedition)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_add_hover_feedback(btn)
	_rp_content.add_child(btn)

	# ── Séparateur ────────────────────────────────────────────
	_rp_content.add_child(HSeparator.new())

	# ── Liste des biomes (accordéon) ──────────────────────────
	_rp_content.add_child(UIHelpers.section_header("◆  BIOMES DISPONIBLES", tcolor))

	# Références partagées entre les closures pour l'accordéon
	var contents:     Dictionary = {}   # biome_id → VBoxContainer (détail)
	var arrows:       Dictionary = {}   # biome_id → Label (▶ / ▼)
	var biome_names:  Dictionary = {}   # biome_id → nom affiché (pour le bouton)

	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != "biome":
			continue
		var bid := eid
		biome_names[bid] = e.get("name", bid).to_upper()

		var result  := _adv_biome_card(bid, e)
		var wrapper := result["wrapper"] as Control
		var panel   := result["panel"]   as Control
		var section := result["section"] as VBoxContainer
		var arrow   := result["arrow"]   as Label
		contents[bid] = section
		arrows[bid]   = arrow

		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton \
					and ev.button_index == MOUSE_BUTTON_LEFT \
					and ev.pressed):
				return
			var bname := biome_names.get(bid, bid) as String
			if bid == _adv_selected_biome_id:
				section.visible = not section.visible
				arrow.text = "  ▼" if section.visible else "  ▶"
				btn.text = ("⚔   PARTIR EN EXPÉDITION — " + bname) if section.visible \
						else "⚔   PARTIR EN EXPÉDITION"
			else:
				if _adv_selected_biome_id in contents \
						and is_instance_valid(contents[_adv_selected_biome_id]):
					contents[_adv_selected_biome_id].visible = false
					arrows[_adv_selected_biome_id].text = "  ▶"
				_adv_selected_biome_id = bid
				section.visible = true
				arrow.text = "  ▼"
				btn.text = "⚔   PARTIR EN EXPÉDITION — " + bname
				placeholder.visible = false
				btn.visible = true
		)
		_rp_content.add_child(wrapper)

# Lance l'aventure sur le biome sélectionné et bascule vers CombatScene.
func _on_start_selected_expedition() -> void:
	if _adv_selected_biome_id.is_empty():
		return
	GameData.player["active_biome_id"] = _adv_selected_biome_id
	AdventureSystem.start_adventure(_adv_selected_biome_id)
	get_tree().change_scene_to_file("res://scenes/combat/CombatScene.tscn")

# Construit la carte accordéon d'un biome avec ses catégories (créatures, pièges, etc.).
# Retourne { wrapper, panel, section, arrow } pour que _panel_adventure connecte le gui_input.
func _adv_biome_card(biome_id: String, biome: Dictionary) -> Dictionary:
	var btier  := biome.get("current_tier", 0) as int
	var bcolor := UIColors.tier_color(btier)
	var bdisp  := MasteryRegistry.get_mastery_display(biome_id)
	var pools  := MasteryRegistry.get_biome_entity_pools(biome_id)

	var xp_fill := 0.0
	if not bdisp.is_empty() and not bdisp.get("at_max", false) and bdisp.get("xp_max", 0.0) > 0.0:
		xp_fill = clampf(bdisp["xp"] / bdisp["xp_max"], 0.0, 1.0)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Panneau principal (toujours visible, XPCard avec fill XP) ──
	var panel := XPCard.new()
	panel.xp_fill    = xp_fill
	panel.fill_color = bcolor
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_add_hover_feedback(panel)
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(bcolor))
	wrapper.add_child(panel)

	var pm := UIHelpers.margin_of(8)
	panel.add_child(pm)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 4)
	pm.add_child(pvb)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	pvb.add_child(hdr)

	var name_lbl := Label.new()
	name_lbl.text = biome.get("name", biome_id).to_upper()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	hdr.add_child(name_lbl)

	var tlbl := Label.new()
	tlbl.text = GameData.get_tier_name(btier)
	tlbl.add_theme_font_size_override("font_size", 11)
	tlbl.add_theme_color_override("font_color", bcolor)
	hdr.add_child(tlbl)

	var arrow := Label.new()
	arrow.text = "  ▶"
	arrow.add_theme_font_size_override("font_size", 10)
	arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	hdr.add_child(arrow)

	if not bdisp.is_empty():
		var xp_lbl := Label.new()
		if bdisp.get("at_max", false):
			xp_lbl.text = "RANG MAX"
			xp_lbl.add_theme_color_override("font_color", bcolor)
		else:
			xp_lbl.text = "XP  %s / %s" % [_xp_fmt(int(bdisp.get("xp", 0.0))), _xp_fmt(int(bdisp.get("xp_max", 0.0)))]
			xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pvb.add_child(xp_lbl)

	# ── Section catégories (repliée par défaut) ───────────────
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	wrapper.add_child(section)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 12)
	indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(indent)

	var cat_vb := VBoxContainer.new()
	cat_vb.add_theme_constant_override("separation", 3)
	indent.add_child(cat_vb)

	_adv_category_card(cat_vb, "CRÉATURES",    pools["creatures"],    UIColors.TYPE_CREATURE)
	_adv_category_card(cat_vb, "PIÈGES",       pools["traps"],        UIColors.TYPE_TRAP)
	_adv_category_card(cat_vb, "BÉNÉDICTIONS", pools["benedictions"], UIColors.TYPE_BENEDICTION)
	_adv_ingredient_section(cat_vb, pools["ingredients"])

	return {"wrapper": wrapper, "panel": panel, "section": section, "arrow": arrow}

# Carte catégorie cliquable (Créatures / Pièges / Bénédictions) avec compteur de découverte.
# Panneau cliquable + liste d'entités repliée en dessous.
func _adv_category_card(parent: VBoxContainer, label: String, pool: Array, color: Color) -> void:
	if pool.is_empty():
		return
	var total      := pool.size()
	var discovered := MasteryRegistry.count_discovered(pool)

	var cat_wrap := VBoxContainer.new()
	cat_wrap.add_theme_constant_override("separation", 2)
	cat_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(cat_wrap)

	var nc := UIColors.CARD_NEUTRAL
	var cat_panel := PanelContainer.new()
	cat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_add_hover_feedback(cat_panel)
	cat_panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.06, 0.38, 1, 3))
	cat_wrap.add_child(cat_panel)

	var cpm := UIHelpers.margin_of(6)
	cat_panel.add_child(cpm)

	var chdr := HBoxContainer.new()
	chdr.add_theme_constant_override("separation", 8)
	cpm.add_child(chdr)

	var clbl := Label.new()
	clbl.text = label
	clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clbl.add_theme_font_size_override("font_size", 11)
	clbl.add_theme_color_override("font_color", nc)
	chdr.add_child(clbl)

	var count_lbl := Label.new()
	count_lbl.text = "%d / %d" % [discovered, total]
	count_lbl.add_theme_font_size_override("font_size", 10)
	count_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	chdr.add_child(count_lbl)

	var cat_arrow := Label.new()
	cat_arrow.text = "  ▶"
	cat_arrow.add_theme_font_size_override("font_size", 10)
	cat_arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	chdr.add_child(cat_arrow)

	# Liste des entités (repliée par défaut)
	var ent_section := VBoxContainer.new()
	ent_section.add_theme_constant_override("separation", 3)
	ent_section.visible = false
	cat_wrap.add_child(ent_section)

	var ent_indent := MarginContainer.new()
	ent_indent.add_theme_constant_override("margin_left", 10)
	ent_indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ent_section.add_child(ent_indent)

	var ent_vb := VBoxContainer.new()
	ent_vb.add_theme_constant_override("separation", 3)
	ent_indent.add_child(ent_vb)

	_adv_entity_rows(ent_vb, pool, color)

	cat_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			ent_section.visible = not ent_section.visible
			cat_arrow.text = "  ▼" if ent_section.visible else "  ▶"
	)

# Remplit parent avec une XPCard par entité du pool. Entités non découvertes → ligne "????".
func _adv_entity_rows(parent: VBoxContainer, pool: Array, color: Color) -> void:
	var total := pool.size()
	for i: int in range(total):
		var entry    := pool[i] as Dictionary
		var entry_id := entry.get("id", "") as String
		var is_known := MasteryRegistry.is_discovered(entry_id)

		if is_known:
			var entity      := GameData.get_entity(entry_id)
			var bentry      := GameData.player.get("bestiary", {}).get(entry_id, {}) as Dictionary
			var is_equip    : bool = entity.get("entity_type", "") == "equipment"
			var entity_tier := 0
			var entity_xp   := 0.0
			var at_max      := false

			if not entity.is_empty() and not is_equip:
				entity_tier = entity.get("current_tier", 0)
				entity_xp   = entity.get("current_xp",   0.0)
				at_max      = entity_tier >= GameData.MAX_TIER
			elif not bentry.is_empty():
				entity_tier = bentry.get("tier", entry.get("tier", 0))
				entity_xp   = bentry.get("xp",   0.0)
				at_max      = entity_tier >= GameData.MAX_TIER
			else:
				entity_tier = entry.get("tier", 0)

			var ec       := UIColors.tier_color(entity_tier)   # couleur tier : carte + badge + XP
			var xp_need  := 0
			var xp_fill  := 0.0
			if not at_max and not is_equip and entity_tier + 1 < GameData.xp_thresholds.size():
				xp_need = int(GameData.xp_thresholds[entity_tier + 1])
				if xp_need > 0:
					xp_fill = clampf(entity_xp / float(xp_need), 0.0, 1.0)

			var panel := XPCard.new()
			panel.xp_fill    = xp_fill
			panel.fill_color = ec
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.add_theme_stylebox_override("panel", UIHelpers.card_style(ec, 0.06, 0.38, 1, 3))
			parent.add_child(panel)

			var pm := UIHelpers.margin_of(4)
			panel.add_child(pm)

			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pm.add_child(hb)

			var name_lbl := Label.new()
			name_lbl.text = entry.get("name", "?")
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 11)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			hb.add_child(name_lbl)

			var tbadge := Label.new()
			tbadge.text = GameData.get_tier_name(entity_tier)
			tbadge.add_theme_font_size_override("font_size", 10)
			tbadge.add_theme_color_override("font_color", ec)   # tier color : badge maîtrise
			hb.add_child(tbadge)

			if not is_equip:
				var xp_text := "RANG MAX" if at_max \
						else "%s / %s XP" % [_xp_fmt(int(entity_xp)), _xp_fmt(xp_need)]
				var xp_lbl := Label.new()
				xp_lbl.text = xp_text
				xp_lbl.add_theme_font_size_override("font_size", 9)
				xp_lbl.add_theme_color_override("font_color", ec if at_max else UIColors.TEXT_MUTED)
				xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				hb.add_child(xp_lbl)
		else:
			# Entité non découverte — style "À DÉBLOQUER"
			var panel := PanelContainer.new()
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.04, 0.20, 1, 3))
			parent.add_child(panel)

			var pm := UIHelpers.margin_of(4)
			panel.add_child(pm)

			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pm.add_child(hb)

			var unk := Label.new()
			unk.text = "????   %d / %d" % [i + 1, total]
			unk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			unk.add_theme_font_size_override("font_size", 11)
			unk.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
			hb.add_child(unk)

# Carte catégorie dédiée aux ingrédients de biome.
# Verrouillée tant que village_tier < 2 : affiche uniquement un message de prérequis.
# Débloquée : liste nom (couleur tier), plage de quantité et chance de drop par item.
func _adv_ingredient_section(parent: VBoxContainer, pool: Array) -> void:
	if pool.is_empty():
		return
	var locked: bool = GameData.player.get("village_tier", 0) < 2
	var nc := UIColors.CARD_NEUTRAL

	var cat_wrap := VBoxContainer.new()
	cat_wrap.add_theme_constant_override("separation", 2)
	cat_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(cat_wrap)

	var cat_panel := PanelContainer.new()
	cat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not locked:
		cat_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_add_hover_feedback(cat_panel)
	cat_panel.add_theme_stylebox_override("panel", UIHelpers.card_style(nc, 0.06, 0.38, 1, 3))
	cat_wrap.add_child(cat_panel)

	var cpm := UIHelpers.margin_of(6)
	cat_panel.add_child(cpm)

	var chdr := HBoxContainer.new()
	chdr.add_theme_constant_override("separation", 8)
	cpm.add_child(chdr)

	var clbl := Label.new()
	clbl.text = "INGRÉDIENTS"
	clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clbl.add_theme_font_size_override("font_size", 11)
	clbl.add_theme_color_override("font_color", nc)
	chdr.add_child(clbl)

	if locked:
		var lock_lbl := Label.new()
		lock_lbl.text = "Village Tier 2"
		lock_lbl.add_theme_font_size_override("font_size", 10)
		lock_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		chdr.add_child(lock_lbl)
		return

	var cat_arrow := Label.new()
	cat_arrow.text = "  ▶"
	cat_arrow.add_theme_font_size_override("font_size", 10)
	cat_arrow.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	chdr.add_child(cat_arrow)

	var ent_section := VBoxContainer.new()
	ent_section.add_theme_constant_override("separation", 3)
	ent_section.visible = false
	cat_wrap.add_child(ent_section)

	var ent_indent := MarginContainer.new()
	ent_indent.add_theme_constant_override("margin_left", 10)
	ent_indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ent_section.add_child(ent_indent)

	var ent_vb := VBoxContainer.new()
	ent_vb.add_theme_constant_override("separation", 3)
	ent_indent.add_child(ent_vb)

	for entry: Dictionary in pool:
		var ec := UIColors.tier_color(int(entry.get("tier", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		ent_vb.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = entry.get("name", "?")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", ec)
		row.add_child(name_lbl)

		var qty_min := int(entry.get("qty_min", 1))
		var qty_max := int(entry.get("qty_max", 1))
		var qty_lbl := Label.new()
		qty_lbl.text = ("×%d–%d" % [qty_min, qty_max]) if qty_min != qty_max else ("×%d" % qty_min)
		qty_lbl.add_theme_font_size_override("font_size", 10)
		qty_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(qty_lbl)

		var chance_lbl := Label.new()
		chance_lbl.text = "%d%%" % int(float(entry.get("chance", 0.0)) * 100.0)
		chance_lbl.add_theme_font_size_override("font_size", 10)
		chance_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(chance_lbl)

	cat_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			ent_section.visible = not ent_section.visible
			cat_arrow.text = "  ▼" if ent_section.visible else "  ▶"
	)

# Feedback hover + press sur n'importe quelle carte cliquable.
# Hover  : scale x1.03 avec overshoot (TRANS_BACK) + brightnes x1.30.
# Press  : scale down x0.95 + flash x1.55, puis spring-back vers état hover.
# Appeler juste après avoir mis CURSOR_POINTING_HAND.
func _add_hover_feedback(panel: Control) -> void:
	# Array utilisé comme conteneur mutable partagé entre les lambdas.
	# Évite le warning CONFUSABLE_CAPTURE_REASSIGNMENT sur une variable Tween locale.
	var h: Array = [null]

	panel.mouse_entered.connect(func() -> void:
		panel.pivot_offset = panel.size * 0.5
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = panel.create_tween()
		var tw := h[0] as Tween
		tw.set_parallel(true)
		tw.tween_property(panel, "modulate", Color(1.30, 1.30, 1.30), 0.13) \
				.set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "scale", Vector2(1.03, 1.03), 0.16) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	)
	panel.mouse_exited.connect(func() -> void:
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = panel.create_tween()
		var tw := h[0] as Tween
		tw.set_parallel(true)
		tw.tween_property(panel, "modulate", Color.WHITE, 0.20).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.20).set_ease(Tween.EASE_OUT)
	)
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton \
				and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
			return
		if is_instance_valid(h[0]): (h[0] as Tween).kill()
		h[0] = panel.create_tween()
		var tw := h[0] as Tween
		# Enfoncement rapide
		tw.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.06) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(panel, "modulate", Color(1.55, 1.55, 1.55), 0.06)
		# Spring-back vers état hover
		tw.tween_property(panel, "scale", Vector2(1.03, 1.03), 0.18) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(panel, "modulate", Color(1.30, 1.30, 1.30), 0.14)
	)

# Panneau générique "Bientôt disponible" pour les fonctionnalités non implémentées.
func _panel_soon(label: String) -> void:
	var lbl := Label.new()
	lbl.text = "✦  %s  ✦\n\nBientôt disponible" % label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_rp_content.add_child(lbl)

# ─── Debug : boutons tier ─────────────────────────────────────
# Ajoute les boutons "Tier +/-" pour tester visuellement les tiers sans sauvegarder.
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

# Ajoute le bouton ⛶ en haut à droite pour basculer le plein écran.
func _build_fullscreen_btn() -> void:
	var btn := Button.new()
	btn.text = "⛶"
	btn.flat = true
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 0.0; btn.anchor_bottom = 0.0
	btn.offset_left   = -34; btn.offset_right  = -6
	btn.offset_top    = 6;   btn.offset_bottom = 34
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.tooltip_text = "Plein écran  (F11)"
	btn.pressed.connect(func() -> void: GameSettings.set_fullscreen(not GameSettings.fullscreen))
	add_child(btn)

# Incrémente le tier du héro, réinitialise son XP et recharge la scène.
func _debug_tier_up() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("current_tier", 0) as int
	if tier < GameData.MAX_TIER:
		hero["current_tier"] = tier + 1
		hero["current_xp"]   = 0.0
		SaveManager.save()
		get_tree().reload_current_scene()

# Décrémente le tier du héro, réinitialise son XP et recharge la scène.
func _debug_tier_down() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("current_tier", 0) as int
	if tier > 0:
		hero["current_tier"] = tier - 1
		hero["current_xp"]   = 0.0
		SaveManager.save()
		get_tree().reload_current_scene()

# ─── Clicker (tier 0) ─────────────────────────────────────────
# Ajoute XP_PER_CLICK XP au héro et évolue automatiquement si le seuil est atteint.
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
# Crée un HexItem, le positionne sur le hub et l'enregistre dans _hex_items.
func _make_hex(lbl: String, icon: String, tcolor: Color, pos: Vector2, cb: Callable, panel_id: String) -> void:
	var item := HexItem.new()
	item.icon_text   = icon
	item.label_text  = lbl
	item.tier_color  = tcolor
	item.tier        = _current_tier()
	item.outward_dir = pos.normalized()
	item.callback    = cb
	_center(item, pos, HEX_SIZE)
	item.pivot_offset = HEX_SIZE * 0.5   # centrage du scale x1.2
	_hub_root.add_child(item)
	_hex_items[panel_id] = item

# ─── Navigation → panneaux ────────────────────────────────────
func _go_hero()       -> void: _open_panel("hero")
func _go_adventure()  -> void: _open_panel("adventure")
func _go_forge()     -> void: _open_panel("forge")
func _go_sanctuary() -> void: _open_panel("sanctuary")
func _go_relic()     -> void: _open_panel("relic")
func _go_tbd()       -> void: _open_panel("tbd")

# ─── Utils ────────────────────────────────────────────────────
# Positionne ctrl centré sur pos avec la taille sz, en mode ancre centre.
func _center(ctrl: Control, pos: Vector2, sz: Vector2) -> void:
	ctrl.anchor_left   = 0.5; ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5; ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = pos.x - sz.x * 0.5
	ctrl.offset_right  = pos.x + sz.x * 0.5
	ctrl.offset_top    = pos.y - sz.y * 0.5
	ctrl.offset_bottom = pos.y + sz.y * 0.5
