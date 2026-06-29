# ============================================================
# holo_geo — Helpers géométriques PURS extraits de HoloMap3D (refactor).
#
# Fonctions statiques sans état : ne dépendent que de leurs arguments et de
# HoloMesh3D (class_name global). Appelées via `const Geo := preload(...)` côté
# HoloMap3D → pas de class_name ici, donc aucune régénération du cache de
# classes (cf. CLAUDE.md). Comportement strictement identique à l'origine.
# ============================================================
extends RefCounted

# Ligne pointillée a→b (segments `dash`, trous `gap`). Renvoie le nb de segments.
static func dashes(s: SurfaceTool, a: Vector3, b: Vector3, col: Color, dash: float, gap: float) -> int:
	var L := a.distance_to(b)
	if L < 0.001:
		return 0
	var dir := (b - a) / L
	var n := 0
	var d := 0.0
	while d < L:
		n += HoloMesh3D.line(s, a + dir * d, a + dir * minf(d + dash, L), col)
		d += dash + gap
	return n

# Ligne pointillée le long d'une POLYLIGNE 3D (suit un profil, ex. rampe de pont).
static func dashes_poly(s: SurfaceTool, pts: Array, col: Color, dash: float, gap: float) -> int:
	var n := 0
	var on := true
	var rem := dash
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 1e-5:
			continue
		var dir := (b - a) / seg
		var d := 0.0
		while d < seg - 1e-6:
			var step := minf(rem, seg - d)
			if on:
				n += HoloMesh3D.line(s, a + dir * d, a + dir * (d + step), col)
			d += step
			rem -= step
			if rem <= 1e-5:
				on = not on
				rem = dash if on else gap
	return n

# Cercle vertical (plan XY si `xy`, sinon YZ), centré à l'origine.
static func cercle_plan(s: SurfaceTool, r: float, col: Color, seg: int, xy: bool) -> int:
	var prev := Vector3(r, 0, 0) if xy else Vector3(0, r, 0)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := Vector3(cos(a) * r, sin(a) * r, 0) if xy else Vector3(0, cos(a) * r, sin(a) * r)
		n += HoloMesh3D.line(s, prev, cur, col)
		prev = cur
	return n

# i-ème direction d'une distribution sphérique régulière (spirale de Fibonacci).
static func point_sphere(i: int, n: int) -> Vector3:
	var phi := PI * (3.0 - sqrt(5.0))
	var y := 1.0 - (float(i) / float(maxi(1, n - 1))) * 2.0
	var rad := sqrt(maxf(0.0, 1.0 - y * y))
	var th := phi * float(i)
	return Vector3(cos(th) * rad, y, sin(th) * rad)

static func beam_vert(s: SurfaceTool, v: Vector3, t: float, side: float, hw: float, col: Color) -> void:
	s.set_color(col)
	s.set_uv(Vector2(t, 0.0))
	s.set_uv2(Vector2(side, hw))
	s.add_vertex(v)

# Profil du tablier le long de la travée (t∈[0,1]) : rampe / sur les `rf` premiers,
# plateau au milieu, rampe \ sur les `rf` derniers. `alt` = hauteur du plateau.
static func profil_pont(t: float, alt: float, rf: float) -> float:
	if t < rf:
		return alt * (t / rf)
	if t > 1.0 - rf:
		return alt * ((1.0 - t) / rf)
	return alt

# Point sur une ellipse ajustée à la bbox (k = fraction du demi-axe), à hauteur y.
static func pt_ell(c: Vector3, ax: float, az: float, k: float, a: float, y: float) -> Vector3:
	return c + Vector3(cos(a) * ax * k, y, sin(a) * az * k)

# Anneau elliptique (échelle k, hauteur y). Renvoie le nb d'arêtes.
static func anneau_ell(s: SurfaceTool, c: Vector3, ax: float, az: float, k: float, y: float, col: Color, seg: int) -> int:
	var prev := pt_ell(c, ax, az, k, 0.0, y)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := pt_ell(c, ax, az, k, a, y)
		n += HoloMesh3D.line(s, prev, cur, col)
		prev = cur
	return n

# Butte basse : base hexagonale + arêtes vers un sommet (légèrement décalé) → dune.
static func butte(s: SurfaceTool, c: Vector3, r: float, h: float, col: Color, jx: float, jz: float) -> int:
	var seg := 6
	var apex := c + Vector3(jx, h, jz)
	var prev := c + Vector3(r, 0, 0)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := c + Vector3(cos(a) * r, 0, sin(a) * r)
		n += HoloMesh3D.line(s, prev, cur, col)   # contour au sol
		n += HoloMesh3D.line(s, cur, apex, col)   # arête vers le sommet
		prev = cur
	return n

# Petit carré plat (plan XZ) centré en `c`, demi-côté `r`.
static func carre_plat(s: SurfaceTool, c: Vector3, r: float, col: Color) -> int:
	var a := c + Vector3(-r, 0, -r)
	var b := c + Vector3(r, 0, -r)
	var d := c + Vector3(r, 0, r)
	var e := c + Vector3(-r, 0, r)
	return HoloMesh3D.line(s, a, b, col) + HoloMesh3D.line(s, b, d, col) \
			+ HoloMesh3D.line(s, d, e, col) + HoloMesh3D.line(s, e, a, col)

# Sème `nb` segments sur une route : base = départ, UV2 = vecteur de trajet
# complet, COLOR.a = multiplicateur de vitesse (le shader translate selon UV.x).
static func semer_voitures(s: SurfaceTool, depart: Vector3, trajet: Vector3, carlen: float,
		rng: RandomNumberGenerator, couleur: Color, nb: int, vit_mult: float) -> void:
	var dirn := trajet.normalized()
	var uv2 := Vector2(trajet.x, trajet.z)
	var c := Color(couleur.r, couleur.g, couleur.b, vit_mult)
	for _v in maxi(0, nb):
		var ph := rng.randf()
		var p0 := depart
		var p1 := depart + dirn * carlen
		s.set_color(c); s.set_uv(Vector2(ph, 0)); s.set_uv2(uv2); s.add_vertex(p0)
		s.set_color(c); s.set_uv(Vector2(ph, 0)); s.set_uv2(uv2); s.add_vertex(p1)
