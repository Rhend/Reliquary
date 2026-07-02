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

# Tronc de pyramide (frustum) wireframe : base rect sx×sz au sol, sommet rétréci
# d'un facteur `k` (0..1) à hauteur `h` → parois BISEAUTÉES (tour fuselée, chapeau).
static func frustum(s: SurfaceTool, c: Vector3, sx: float, sz: float, h: float, k: float, col: Color) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var tx := hx * k
	var tz := hz * k
	var y1 := c.y + h
	var b := [
		c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz),
		c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz)]
	var t := [
		Vector3(c.x - tx, y1, c.z - tz), Vector3(c.x + tx, y1, c.z - tz),
		Vector3(c.x + tx, y1, c.z + tz), Vector3(c.x - tx, y1, c.z + tz)]
	var n := 0
	for i in 4:
		n += line(s, b[i], b[(i + 1) % 4], col)   # base
		n += line(s, t[i], t[(i + 1) % 4], col)   # sommet
		n += line(s, b[i], t[i], col)              # arête biseautée
	return n

# Faces pleines d'un frustum (4 parois biseautées + toit ; base omise).
static func frustum_faces(s: SurfaceTool, c: Vector3, sx: float, sz: float, h: float, k: float) -> int:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var tx := hx * k
	var tz := hz * k
	var y1 := c.y + h
	var b := [
		c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz),
		c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz)]
	var t := [
		Vector3(c.x - tx, y1, c.z - tz), Vector3(c.x + tx, y1, c.z - tz),
		Vector3(c.x + tx, y1, c.z + tz), Vector3(c.x - tx, y1, c.z + tz)]
	var n := 0
	for i in 4:
		var p0: Vector3 = b[i]
		var p1: Vector3 = b[(i + 1) % 4]
		var q1: Vector3 = t[(i + 1) % 4]
		var q0: Vector3 = t[i]
		var nrm := (p1 - p0).cross(q0 - p0).normalized()
		n += _quad(s, p0, p1, q1, q0, nrm)
	n += _quad(s, t[0], t[1], t[2], t[3], Vector3(0, 1, 0))   # toit
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

# Points des anneaux de latitude d'un demi-ellipsoïde (base au sol centrée `c`) :
# Array d'anneaux, chaque anneau = Array de `seg` Vector3 alignés en angle.
static func _dome_pts(c: Vector3, rx: float, rz: float, h: float, anneaux: int, seg: int) -> Array:
	var pts: Array = []
	for k in range(0, anneaux + 1):
		var t := float(k) / float(anneaux + 1)
		var f := sqrt(maxf(0.0, 1.0 - t * t))
		var ring: Array = []
		for i in seg:
			var a := TAU * float(i) / float(seg)
			ring.append(c + Vector3(cos(a) * rx * f, h * t, sin(a) * rz * f))
		pts.append(ring)
	return pts

# Dôme GÉODÉSIQUE wireframe (demi-ellipsoïde triangulé) : anneaux de latitude
# reliés par méridiens segmentés + DIAGONALES → treillis de triangles (structure
# architecturale, plus une cage à oiseaux). Base au sol centrée `c`, hauteur h.
static func dome(s: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, col: Color, anneaux: int = 3, seg: int = 14) -> int:
	var pts := _dome_pts(c, rx, rz, h, anneaux, seg)
	var apex := c + Vector3(0, h, 0)
	var n := 0
	for k in pts.size():
		var ring: Array = pts[k]
		for i in seg:
			n += line(s, ring[i], ring[(i + 1) % seg], col)        # anneau de latitude
			if k + 1 < pts.size():
				var up: Array = pts[k + 1]
				n += line(s, ring[i], up[i], col)                   # méridien
				n += line(s, ring[i], up[(i + 1) % seg], col)       # diagonale (triangulation)
			else:
				n += line(s, ring[i], apex, col)                    # éventail vers l'apex
	return n

# Faces pleines du dôme (mêmes anneaux que `dome`) pour l'occlusion holo :
# le dôme devient un volume sombre habillé du treillis, cohérent avec les boîtes.
static func dome_faces(sf: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, anneaux: int = 3, seg: int = 14) -> int:
	var pts := _dome_pts(c, rx, rz, h, anneaux, seg)
	var apex := c + Vector3(0, h, 0)
	var n := 0
	for k in pts.size():
		var ring: Array = pts[k]
		for i in seg:
			var p0: Vector3 = ring[i]
			var p1: Vector3 = ring[(i + 1) % seg]
			if k + 1 < pts.size():
				var up: Array = pts[k + 1]
				var q0: Vector3 = up[i]
				var q1: Vector3 = up[(i + 1) % seg]
				n += _quad(sf, p0, p1, q1, q0, (p1 - p0).cross(q0 - p0).normalized())
			else:
				n += _tri(sf, p0, p1, apex, (p1 - p0).cross(apex - p0).normalized())
	return n
