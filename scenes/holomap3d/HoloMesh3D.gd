# ============================================================
# HoloMesh3D — Fabrique statique de maillages d'ARÊTES (PRIMITIVE_LINES).
#
# Helpers partagés (HoloMap3D, HoloLocation3D) pour construire des wireframes
# holo. Chaque arête porte sa vertex color ; le matériau holo_line lit COLOR
# pour l'émission. Les fonctions de dessin renvoient le NOMBRE de segments
# ajoutés (l'appelant cumule pour savoir si le mesh est non vide).
# ============================================================
class_name HoloMesh3D

static func st() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	return s

# SurfaceTool en triangles (faces pleines des bâtiments).
static func st_tri() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

static func _tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> int:
	s.set_normal(nrm); s.add_vertex(a)
	s.set_normal(nrm); s.add_vertex(b)
	s.set_normal(nrm); s.add_vertex(c)
	return 3

static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> int:
	return _tri(s, a, b, c, nrm) + _tri(s, a, c, d, nrm)

# Faces pleines d'une boîte (toit + 4 côtés ; sol omis, jamais visible).
# Base centrée en `c` au sol, hauteur `sy` sur +Y. Normales posées par face
# (orientent la grille de fenêtres dans holo_face).
static func box_faces(s: SurfaceTool, c: Vector3, sx: float, sy: float, sz: float) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var y0 := c.y
	var y1 := c.y + sy
	var b0 := Vector3(c.x - hx, y0, c.z - hz)
	var b1 := Vector3(c.x + hx, y0, c.z - hz)
	var b2 := Vector3(c.x + hx, y0, c.z + hz)
	var b3 := Vector3(c.x - hx, y0, c.z + hz)
	var t0 := Vector3(c.x - hx, y1, c.z - hz)
	var t1 := Vector3(c.x + hx, y1, c.z - hz)
	var t2 := Vector3(c.x + hx, y1, c.z + hz)
	var t3 := Vector3(c.x - hx, y1, c.z + hz)
	var n := 0
	n += _quad(s, t0, t1, t2, t3, Vector3(0, 1, 0))   # toit
	n += _quad(s, b0, b1, t1, t0, Vector3(0, 0, -1))
	n += _quad(s, b1, b2, t2, t1, Vector3(1, 0, 0))
	n += _quad(s, b2, b3, t3, t2, Vector3(0, 0, 1))
	n += _quad(s, b3, b0, t0, t3, Vector3(-1, 0, 0))
	return n

# Finalise (null si aucune ligne — évite un mesh vide invalide).
static func commit(s: SurfaceTool, compte: int) -> ArrayMesh:
	if compte <= 0:
		return null
	return s.commit()

static func line(s: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> int:
	s.set_color(col); s.add_vertex(a)
	s.set_color(col); s.add_vertex(b)
	return 1

# Boîte wireframe (12 arêtes) : base centrée en `c` (au sol), hauteur `sy` sur +Y.
static func box(s: SurfaceTool, c: Vector3, sx: float, sy: float, sz: float, col: Color) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var b0 := c + Vector3(-hx, 0, -hz)
	var b1 := c + Vector3( hx, 0, -hz)
	var b2 := c + Vector3( hx, 0,  hz)
	var b3 := c + Vector3(-hx, 0,  hz)
	var up := Vector3(0, sy, 0)
	line(s, b0, b1, col); line(s, b1, b2, col); line(s, b2, b3, col); line(s, b3, b0, col)
	line(s, b0 + up, b1 + up, col); line(s, b1 + up, b2 + up, col)
	line(s, b2 + up, b3 + up, col); line(s, b3 + up, b0 + up, col)
	line(s, b0, b0 + up, col); line(s, b1, b1 + up, col)
	line(s, b2, b2 + up, col); line(s, b3, b3 + up, col)
	return 12

# Boucles horizontales d'étages (subdivision interne légère) : `count` anneaux
# répartis entre la base et le sommet (exclus). Lecture « immeuble à étages ».
static func etages(s: SurfaceTool, c: Vector3, sx: float, sy: float, sz: float, col: Color, count: int) -> int:
	if count <= 0:
		return 0
	var hx := sx * 0.5
	var hz := sz * 0.5
	var n := 0
	for k in range(1, count + 1):
		var y := sy * float(k) / float(count + 1)
		var p0 := c + Vector3(-hx, y, -hz)
		var p1 := c + Vector3( hx, y, -hz)
		var p2 := c + Vector3( hx, y,  hz)
		var p3 := c + Vector3(-hx, y,  hz)
		n += line(s, p0, p1, col) + line(s, p1, p2, col) \
				+ line(s, p2, p3, col) + line(s, p3, p0, col)
	return n

# Boucle de cercle dans le plan XZ (anneau au sol), centrée en `c`.
static func circle(s: SurfaceTool, c: Vector3, r: float, col: Color, seg: int = 32) -> int:
	var prev := c + Vector3(r, 0, 0)
	var n := 0
	for i in range(1, seg + 1):
		var ang := TAU * float(i) / float(seg)
		var cur := c + Vector3(cos(ang) * r, 0, sin(ang) * r)
		n += line(s, prev, cur, col)
		prev = cur
	return n

# Diamant (octaèdre) wireframe : centre `c`, demi-largeur `r`, demi-hauteur `h`.
static func diamond(s: SurfaceTool, c: Vector3, r: float, h: float, col: Color) -> int:
	var top := c + Vector3(0, h, 0)
	var bot := c + Vector3(0, -h, 0)
	var mids := [
		c + Vector3( r, 0, 0), c + Vector3(0, 0,  r),
		c + Vector3(-r, 0, 0), c + Vector3(0, 0, -r),
	]
	var n := 0
	for i in 4:
		n += line(s, top, mids[i], col)
		n += line(s, bot, mids[i], col)
		n += line(s, mids[i], mids[(i + 1) % 4], col)
	return n

# ─── Formes paramétriques (gabarit Excel : C/P/D + Boîte/Gradins) ──
# Anneau elliptique (plan XZ) centré en `c`, demi-axes rx (X) et rz (Z).
static func ellipse(s: SurfaceTool, c: Vector3, rx: float, rz: float, col: Color, seg: int = 28) -> int:
	var prev := c + Vector3(rx, 0, 0)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := c + Vector3(cos(a) * rx, 0, sin(a) * rz)
		n += line(s, prev, cur, col)
		prev = cur
	return n

# Cylindre wireframe : base au sol centrée `c`, demi-emprise rx/rz, hauteur `h`.
# `meridiens` arêtes verticales reliant les deux ellipses.
static func cylinder(s: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, col: Color, seg: int = 28, meridiens: int = 10) -> int:
	var n := 0
	n += ellipse(s, c, rx, rz, col, seg)
	n += ellipse(s, c + Vector3(0, h, 0), rx, rz, col, seg)
	for m in maxi(0, meridiens):
		var a := TAU * float(m) / float(meridiens)
		var p := Vector3(cos(a) * rx, 0, sin(a) * rz)
		n += line(s, c + p, c + p + Vector3(0, h, 0), col)
	return n

# Faces pleines d'un cylindre (paroi + toit) pour l'occlusion holo.
static func cylinder_faces(s: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, seg: int = 28) -> int:
	var n := 0
	var top := c + Vector3(0, h, 0)
	var prev := Vector2(rx, 0.0)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := Vector2(cos(a) * rx, sin(a) * rz)
		var b0 := c + Vector3(prev.x, 0, prev.y)
		var b1 := c + Vector3(cur.x, 0, cur.y)
		var t0 := top + Vector3(prev.x, 0, prev.y)
		var t1 := top + Vector3(cur.x, 0, cur.y)
		var nrm := Vector3(cos(a), 0, sin(a))
		n += _quad(s, b0, b1, t1, t0, nrm)        # paroi
		n += _tri(s, top, t1, t0, Vector3(0, 1, 0))  # toit (éventail)
		prev = cur
	return n

# Pyramide wireframe : base rect sx×sz centrée `c` au sol, apex à hauteur `h`.
static func pyramid(s: SurfaceTool, c: Vector3, sx: float, sz: float, h: float, col: Color) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var b := [
		c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz),
		c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz)]
	var apex := c + Vector3(0, h, 0)
	var n := 0
	for i in 4:
		n += line(s, b[i], b[(i + 1) % 4], col)   # base
		n += line(s, b[i], apex, col)              # arête montante
	return n

# Faces pleines d'une pyramide (4 triangles latéraux ; base omise).
static func pyramid_faces(s: SurfaceTool, c: Vector3, sx: float, sz: float, h: float) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var b := [
		c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz),
		c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz)]
	var apex := c + Vector3(0, h, 0)
	var n := 0
	for i in 4:
		var p0: Vector3 = b[i]
		var p1: Vector3 = b[(i + 1) % 4]
		var nrm := (p1 - p0).cross(apex - p0).normalized()
		n += _tri(s, p0, p1, apex, nrm)
	return n

# Dôme wireframe (demi-ellipsoïde) : `anneaux` cercles de latitude + `meridiens`
# arcs verticaux + cercle de base. Base au sol centrée `c`, demi-axes rx/rz, hauteur h.
static func dome(s: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, col: Color, anneaux: int = 3, meridiens: int = 10) -> int:
	var n := 0
	n += ellipse(s, c, rx, rz, col, 28)
	for k in range(1, anneaux + 1):
		var t := float(k) / float(anneaux + 1)
		var f := sqrt(maxf(0.0, 1.0 - t * t))
		n += ellipse(s, c + Vector3(0, h * t, 0), rx * f, rz * f, col, 24)
	for m in maxi(0, meridiens):
		var ang := TAU * float(m) / float(meridiens)
		var dir := Vector3(cos(ang) * rx, 0, sin(ang) * rz)
		var prev := c + dir
		var pas := 6
		for i in range(1, pas + 1):
			var t := float(i) / float(pas)
			var f := sqrt(maxf(0.0, 1.0 - t * t))
			var cur := c + dir * f + Vector3(0, h * t, 0)
			n += line(s, prev, cur, col)
			prev = cur
	return n
