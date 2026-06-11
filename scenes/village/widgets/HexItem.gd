class_name HexItem
extends Control

var label_text      := ""
var tier_color      := Color.WHITE
var tier            := 1
var callback        : Callable
var hex_radius      := 58.0
var outward_dir     := Vector2.RIGHT
var is_hovered      := false
var is_selected     := false
var has_notification := false   # étoile dorée = action disponible
var _htween         : Tween
var _t              := 0.0

# ─── Énergie intérieure ───────────────────────────────────────
# Plus d'icône : le contenu de la bulle EST le feedback. _energy pilote
# l'intensité de l'animation interne (cœur + tourbillon), lissée dans
# _process pour des transitions organiques entre les états :
#   0.0 = repos · ~0.45 = hover (« bouillonnement », promesse du clic)
#   1.0 = sélectionné (cœur d'énergie chargé qui tourbillonne en continu)
# Le clic déclenche en plus une onde de charge (_burst_t) : la boule
# d'énergie se remplit du centre vers le bord.
const BURST_DUR := 0.45
var _energy  := 0.0
var _burst_t := 99.0   # temps écoulé depuis le clic ; 99 = inactif

# Sprite radial doux : modelé des pastilles rondes + lueurs d'énergie.
var _shade_tex: GradientTexture2D

func _ready() -> void:
	pivot_offset = size * 0.5
	_shade_tex = UIHelpers.radial_glow_tex(64,
			[0.0, 0.35, 1.0], [1.0, 0.55, 0.0])
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)

func _process(dt: float) -> void:
	_t += dt
	_burst_t += dt
	var target := 1.0 if is_selected else (0.45 if is_hovered else 0.0)
	_energy = lerpf(_energy, target, 1.0 - exp(-dt * 6.0))
	queue_redraw()

# Le hover ne grossit plus la bulle : il « réveille » son contenu (_energy).
func _on_enter() -> void:
	is_hovered = true
	queue_redraw()

func _on_exit() -> void:
	is_hovered = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_burst_t = 0.0   # onde de charge intérieure
		if _htween: _htween.kill()
		_htween = create_tween().set_trans(Tween.TRANS_SINE)
		_htween.tween_property(self, "scale", Vector2(0.92, 0.92), 0.06)
		_htween.tween_callback(callback)
		_htween.tween_property(self, "scale", Vector2.ONE, 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	if has_notification:
		_draw_badge(c)

# Étoile d'évolution — éclat doré en haut à droite de la bulle :
# halo qui respire, étoile 4 branches en rotation lente, contre-étoile
# blanche, cœur brillant et particule en orbite. Or = langage visuel
# de la progression (FILTER_ON / Légendaire), bien plus invitant que
# l'ancienne pastille rouge « erreur ».
func _draw_badge(c: Vector2) -> void:
	var r    := hex_radius * 0.78
	var bpos := c + Vector2(r * 0.70, -r * 0.70)
	var gold := Color(1.0, 0.82, 0.25)

	# Respiration : douce la plupart du temps, petit pic régulier (twinkle).
	var breath  := 0.5 + 0.5 * sin(_t * 2.4)
	var twinkle := pow(maxf(sin(_t * 1.2), 0.0), 8.0)   # flash bref périodique
	var srad    := 9.0 + 1.8 * breath + 3.0 * twinkle

	# Halo doux (sprite radial GPU — aucun cercle dur)
	_shade(bpos, srad * 2.4, Color(gold, 0.28 + 0.22 * breath + 0.25 * twinkle))

	# Étoile 4 branches en rotation lente + contre-étoile blanche
	var rot := _t * 0.7
	_draw_spark(bpos, srad, rot, Color(1.0, 0.86, 0.40, 0.95))
	_draw_spark(bpos, srad * 0.52, -rot * 1.7, Color(1.0, 1.0, 1.0, 0.85))

	# Cœur brillant
	draw_circle(bpos, 2.0 + 1.0 * breath, Color(1.0, 1.0, 1.0, 0.95), true, -1.0, true)

	# Particule en orbite (étincelle qui tourne autour de l'étoile)
	var oa  := _t * 1.6
	var opp := bpos + Vector2(cos(oa), sin(oa)) * (srad * 1.6)
	var ofl := 0.55 + 0.45 * sin(_t * 5.0)
	draw_circle(opp, 2.6, Color(gold, 0.30 * ofl))
	draw_circle(opp, 1.2, Color(1.0, 0.95, 0.70, 0.90 * ofl))

# Étoile 4 branches (losanges croisés) : 8 sommets alternés long/court.
func _draw_spark(p: Vector2, r: float, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var rad := r if i % 2 == 0 else r * 0.28
		var a   := rot + float(i) * PI / 4.0
		pts.append(p + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, col)

func _callout(c: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fsz  := 17
	var r    := hex_radius * (0.78 if tier <= 2 else 0.92)

	var text_w  := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var bar_len := text_w + 60.0

	var p0       := c + outward_dir * r
	var p1       := c + outward_dir * (r + 28.0)
	var bd       := 1.0 if outward_dir.x >= 0.0 else -1.0
	var p2       := p1 + Vector2(bd * bar_len, 0.0)
	var stem_len := p0.distance_to(p1)
	var total    := stem_len + bar_len

	var black := Color(0.0, 0.0, 0.0, 0.45)
	var base  := Color(tier_color.r, tier_color.g, tier_color.b,
			0.90 + 0.10 * sin(_t * 1.8))

	# Halo de lueur autour de la ligne
	var glow := Color(tier_color.r, tier_color.g, tier_color.b,
			0.28 + 0.12 * sin(_t * 1.5))
	draw_line(p0, p1, glow, 6.0, true)
	draw_line(p1, p2, glow, 6.0, true)

	draw_line(p0, p1, black, 2.0, true)
	draw_line(p1, p2, black, 2.0, true)
	draw_line(p0, p1, base, 1.2, true)
	draw_line(p1, p2, base, 1.2, true)

	var dot_r := 1.8 + 0.5 * sin(_t * 3.2)
	draw_circle(p0, dot_r + 2.0, Color(tier_color.r, tier_color.g, tier_color.b, 0.35))
	draw_circle(p0, dot_r + 1.0, black)
	draw_circle(p0, dot_r, base)

	# Particule animée le long du callout
	var prog := fmod(_t * 0.55, 1.0)
	var dist := prog * total
	var pp   : Vector2
	if dist <= stem_len:
		pp = p0.lerp(p1, dist / stem_len)
	else:
		pp = p1.lerp(p2, (dist - stem_len) / bar_len)
	var pa   := sin(prog * PI)
	var pc   := tier_color.lightened(0.55); pc.a = pa * 0.95
	var pcg  := Color(pc.r, pc.g, pc.b, pa * 0.40)
	draw_circle(pp, 5.0, pcg)
	draw_circle(pp, 2.5, pc)
	draw_circle(pp, 1.0, Color(1.0, 1.0, 1.0, pa))

	var tx  := minf(p1.x, p2.x)
	var tp  := Vector2(tx, p1.y - 6.0)
	var tco := Color(0.0, 0.0, 0.0, 0.70)
	for ofs: Vector2 in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]:
		draw_string(font, tp + ofs, label_text,
				HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz, tco)
	draw_string(font, tp, label_text,
			HORIZONTAL_ALIGNMENT_CENTER, bar_len, fsz,
			tier_color.lightened(0.65))

func _round(c: Vector2, with_fx: bool) -> void:
	var r: float = hex_radius * 0.78

	# Lueur de fond permanente
	var bloom := tier_color; bloom.a = 0.18 + 0.08 * sin(_t * 1.4)
	draw_circle(c, r + 18.0, bloom)

	if with_fx:
		var og := tier_color; og.a = 0.22 + 0.10 * sin(_t * 1.4)
		draw_circle(c, r + 12.0, og)

	draw_circle(c + Vector2(2.0, 3.5), r, Color(0, 0, 0, 0.45))
	var fill := tier_color.darkened(0.20); fill.a = 0.96
	draw_circle(c, r, fill)
	# Modelé sphérique doux : lumière en haut, ombre en bas (dégradés GPU —
	# remplace les anciens croissants blanc/noir à bandes dures).
	# Les sprites s'éteignent avant le bord du disque : rien ne déborde.
	_shade(c + Vector2(0.0, -r * 0.40), r * 0.58, Color(1, 1, 1, 0.30))
	_shade(c + Vector2(0.0,  r * 0.42), r * 0.56, Color(0, 0, 0, 0.32))
	_inner_energy(c, r * 0.86)
	# Bordure lumineuse pulsée
	var border := tier_color.lightened(0.15); border.a = 0.75 + 0.25 * sin(_t * 1.8)
	draw_arc(c, r, 0.0, TAU, 64, border, 2.5, true)

	if with_fx:
		var rim := tier_color.lightened(0.55); rim.a = 0.60
		draw_arc(c, r - 2.0, 0.0, TAU, 64, rim, 1.5, true)
		var outline := tier_color; outline.a = 0.45 + 0.20 * sin(_t * 1.5)
		draw_arc(c, r + 9.0, 0.0, TAU, 64, outline, 2.0, true)
		var sa := _t * 1.3
		var sh := tier_color.lightened(0.80); sh.a = 0.92
		draw_arc(c, r, sa, sa + 1.0, 20, sh, 4.5, true)

	if is_selected:
		# Halo externe diffus
		var gr: float = 16.0 if with_fx else 12.0
		var outer := tier_color; outer.a = 0.55
		draw_arc(c, r + gr, 0.0, TAU, 48, outer, 9.0, true)
		# Contour brillant bien visible
		var bright := tier_color.lightened(0.70); bright.a = 1.0
		draw_arc(c, r, 0.0, TAU, 64, bright, 4.0, true)
		# Liseré blanc intérieur
		draw_arc(c, r - 3.0, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.55), 1.5, true)
	elif is_hovered:
		# Pas de couronne externe : le feedback hover vient du contenu
		# (_inner_energy), juste un liseré pour souligner la forme.
		draw_arc(c, r, 0.0, TAU, 64, tier_color.lightened(0.4), 3.5, true)

func _hexa(c: Vector2, with_fx: bool, with_pulse: bool) -> void:
	var eff_r: float = hex_radius
	if with_pulse:
		eff_r += sin(_t * 2.5) * 3.0
	var pts := _hex(c, eff_r)

	# Lueur de fond permanente
	var bloom := tier_color; bloom.a = 0.20 + 0.08 * sin(_t * 1.3)
	draw_colored_polygon(_hex(c, eff_r + 20.0), bloom)

	draw_colored_polygon(_hex(c + Vector2(2.5, 4.0), eff_r), Color(0, 0, 0, 0.50))

	var base := tier_color.darkened(0.22); base.a = 0.97
	draw_colored_polygon(pts, base)
	# Biseaux internes lumineux/sombres
	draw_colored_polygon(PackedVector2Array([c, pts[3], pts[4], pts[5], pts[0]]), Color(1, 1, 1, 0.18))
	draw_colored_polygon(PackedVector2Array([c, pts[0], pts[1], pts[2], pts[3]]), Color(0, 0, 0, 0.32))

	var inn := _hex(c, eff_r - 5.0)
	draw_line(inn[3], inn[4], Color(1, 1, 1, 0.28), 1.0, true)
	draw_line(inn[4], inn[5], Color(1, 1, 1, 0.35), 1.5, true)
	draw_line(inn[5], inn[0], Color(1, 1, 1, 0.28), 1.0, true)
	draw_line(inn[0], inn[1], Color(0, 0, 0, 0.28), 1.0, true)
	draw_line(inn[1], inn[2], Color(0, 0, 0, 0.28), 1.5, true)
	draw_line(inn[2], inn[3], Color(0, 0, 0, 0.28), 1.0, true)

	# Arêtes basses lumineuses
	var le := tier_color.lightened(0.65); le.a = 0.95
	draw_line(pts[3], pts[4], le, 2.0, true)
	draw_line(pts[4], pts[5], le, 3.0, true)
	draw_line(pts[5], pts[0], le, 2.0, true)
	draw_line(pts[0], pts[1], Color(0, 0, 0, 0.50), 1.5, true)
	draw_line(pts[1], pts[2], Color(0, 0, 0, 0.60), 2.0, true)
	draw_line(pts[2], pts[3], Color(0, 0, 0, 0.50), 1.5, true)

	_inner_energy(c, eff_r * 0.70)

	# Bordure externe pulsée
	var border := tier_color.lightened(0.20); border.a = 0.65 + 0.25 * sin(_t * 1.8)
	_draw_border(pts, border, 2.0)

	if with_fx:
		var oc := tier_color; oc.a = 0.50 + 0.20 * sin(_t * 1.8)
		_draw_border(_hex(c, eff_r + 8.0), oc, 2.5)
		var ef    := fmod(_t * 1.1, TAU) / TAU * 6.0
		var eidx  := int(ef) % 6
		var efrac : float = fmod(ef, 1.0)
		var ps    := pts[eidx].lerp(pts[(eidx + 1) % 6], efrac)
		var pe    := pts[eidx].lerp(pts[(eidx + 1) % 6], minf(efrac + 0.38, 1.0))
		var sh    := tier_color.lightened(0.80); sh.a = 0.95
		draw_line(ps, pe, sh, 4.5, true)

	if is_selected:
		# Halo externe diffus
		var outer := tier_color; outer.a = 0.55
		_draw_border(_hex(c, eff_r + 12.0), outer, 9.0)
		# Contour brillant bien visible
		var bright := tier_color.lightened(0.70); bright.a = 1.0
		_draw_border(pts, bright, 4.0)
		# Liseré blanc intérieur
		_draw_border(_hex(c, eff_r - 3.0), Color(1.0, 1.0, 1.0, 0.55), 1.5)
	elif is_hovered:
		# Pas de couronne externe : le feedback hover vient du contenu
		# (_inner_energy), juste un liseré pour souligner la forme.
		_draw_border(pts, tier_color.lightened(0.4), 3.5)

# Sprite radial doux centré (modelé lumière/ombre des pastilles rondes).
func _shade(center: Vector2, radius: float, col: Color) -> void:
	draw_texture_rect(_shade_tex,
			Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
			false, col)

# ─── Animation intérieure : cœur d'énergie + tourbillon ──────
# `ir` = rayon intérieur disponible (l'animation ne déborde jamais).
func _inner_energy(c: Vector2, ir: float) -> void:
	var e := _energy
	var bursting := _burst_t < BURST_DUR
	if e <= 0.02 and not bursting:
		return

	# 1. Cœur d'énergie : grossit, s'éclaircit et pulse plus vite avec e.
	var pulse  := 1.0 + 0.07 * sin(_t * (2.2 + 3.0 * e))
	var core_r := ir * (0.18 + 0.52 * e) * pulse
	var core_a := 0.30 + 0.50 * e
	_shade(c, core_r * 2.1, Color(tier_color.lightened(0.40), core_a * 0.55))
	draw_circle(c, core_r * 0.50,
			Color(tier_color.lightened(0.75), core_a), true, -1.0, true)

	# 2. Tourbillon : 3 bras spiraux (segments d'arc enroulés autour du
	#    cœur) — lents et discrets au hover, rapides et nets en sélection.
	var spin := _t * (0.9 + 2.8 * e)
	for arm in 3:
		var ph := spin + float(arm) * TAU / 3.0
		for s in 4:
			var fr  := (float(s) + 0.5) / 4.0          # 0 = centre → 1 = bord
			var rr  := ir * (0.30 + 0.58 * fr)
			var ang := ph + fr * 2.6                   # enroulement spiral
			var sa  := (0.08 + 0.45 * e) * (1.0 - fr * 0.55)
			var col := tier_color.lightened(0.55); col.a = sa
			draw_arc(c, rr, ang, ang + 0.55 - 0.18 * fr, 8, col,
					2.6 - 1.2 * fr, true)

	# 3. Onde de charge au clic : la boule se remplit du centre au bord.
	if bursting:
		var bp := _burst_t / BURST_DUR
		var eo := 1.0 - pow(1.0 - bp, 3.0)             # ease-out cubique
		var br := ir * eo
		var ba := 1.0 - bp
		draw_circle(c, br, Color(tier_color.lightened(0.55), ba * 0.30),
				true, -1.0, true)
		draw_arc(c, br, 0.0, TAU, 48,
				Color(tier_color.lightened(0.85), ba * 0.9), 3.0, true)

func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * r)
	return pts

func _draw_border(pts: PackedVector2Array, col: Color, w: float) -> void:
	for i in 6:
		draw_line(pts[i], pts[(i + 1) % 6], col, w, true)
