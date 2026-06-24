class_name JRPGPanel
extends Control

var panel_color := Color.WHITE
var _t          := randf() * 6.0   # phase aléatoire : les panels ne grésillent pas en chœur

const RAD := 18.0   # rayon des coins — contour arrondi façon tube néon
const PAD := 5.0    # marge tout autour : le contour (et son trait net) reste DANS le cadre

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var sz := size
	var bw := 3.0
	var m  := 5.0
	var th := 38.0

	# Scintillement néon : pulsation lente + épisode de grésillement (~0.6 s).
	var pulse   := 0.80 + 0.20 * sin(_t * 2.2)
	var flicker := UIHelpers.neon_flicker(_t)
	var energy  := pulse * flicker

	# Rect de travail rentré de PAD sur tout le pourtour.
	var fr := Rect2(Vector2(PAD, PAD), sz - Vector2(PAD * 2.0, PAD * 2.0))
	var top := fr.position.y

	# Fond sombre à coins arrondis (cohérent avec le contour néon).
	var outer := _rounded_rect(fr, RAD)
	draw_colored_polygon(outer, Color(0.04, 0.05, 0.09, 0.97))

	# Glow néon du cadre : passes larges translucides derrière le trait net (intensifié).
	for g: Array in [[28.0, 0.09], [18.0, 0.14], [10.0, 0.21], [5.0, 0.30]]:
		var gc := panel_color; gc.a = (g[1] as float) * energy
		draw_polyline(outer, gc, g[0] as float, true)

	# Trait net avivé (cœur du tube néon).
	var ob := panel_color.lerp(Color.WHITE, 0.55); ob.a = 0.98 * flicker
	draw_polyline(outer, ob, bw, true)

	# Liseré interne, arrondi lui aussi.
	var inner := _rounded_rect(fr.grow(-m), RAD - 4.0)
	var ib := panel_color; ib.a = 0.22
	draw_polyline(inner, ib, 1.5, true)

	# Barre de titre : fond sombre à coins SUPÉRIEURS arrondis (épouse le cadre).
	var tb := panel_color.darkened(0.55); tb.a = 0.85
	draw_colored_polygon(_top_rounded(Rect2(fr.position + Vector2(bw, bw),
			Vector2(fr.size.x - bw * 2.0, th)), RAD - bw), tb)

	# Séparateur sous le titre : halo + cœur avivé, pulsé.
	var sep_y  := top + bw + th
	var sep_a  := 0.55 + 0.20 * sin(_t * 1.8)
	var sep_p1 := Vector2(fr.position.x + m * 2.0, sep_y)
	var sep_p2 := Vector2(fr.end.x - m * 2.0, sep_y)
	for g: Array in [[9.0, 0.14], [4.0, 0.24]]:
		var sg := panel_color; sg.a = (g[1] as float) * sep_a
		draw_line(sep_p1, sep_p2, sg, g[0] as float)
	var sep := panel_color.lerp(Color.WHITE, 0.30); sep.a = sep_a
	draw_line(sep_p1, sep_p2, sep, 2.0)

# ─── Géométrie : rectangles à coins arrondis ─────────────────

# Boucle fermée d'un rectangle à coins arrondis (sens horaire), prête pour
# draw_polyline (contour) ou draw_colored_polygon (remplissage).
func _rounded_rect(rect: Rect2, rad: float, seg: int = 6) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	rad = minf(rad, minf(s.x, s.y) * 0.5)
	var pts := PackedVector2Array()
	_arc(pts, p + Vector2(rad, rad),               rad, PI,        PI * 1.5, seg)  # haut-gauche
	_arc(pts, p + Vector2(s.x - rad, rad),         rad, PI * 1.5,  TAU,      seg)  # haut-droite
	_arc(pts, p + Vector2(s.x - rad, s.y - rad),   rad, 0.0,       PI * 0.5, seg)  # bas-droite
	_arc(pts, p + Vector2(rad, s.y - rad),         rad, PI * 0.5,  PI,       seg)  # bas-gauche
	pts.append(pts[0])
	return pts

# Polygone à coins SUPÉRIEURS arrondis, bas droit (pour la barre de titre).
func _top_rounded(rect: Rect2, rad: float, seg: int = 6) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	rad = minf(rad, minf(s.x * 0.5, s.y))
	var pts := PackedVector2Array()
	pts.append(p + Vector2(0.0, s.y))                                          # bas-gauche
	_arc(pts, p + Vector2(rad, rad),       rad, PI,       PI * 1.5, seg)        # haut-gauche
	_arc(pts, p + Vector2(s.x - rad, rad), rad, PI * 1.5, TAU,      seg)        # haut-droite
	pts.append(p + Vector2(s.x, s.y))                                          # bas-droite
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, rad: float,
		a0: float, a1: float, seg: int) -> void:
	for i in seg + 1:
		var a: float = lerpf(a0, a1, float(i) / float(seg))
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
