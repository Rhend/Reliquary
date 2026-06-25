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
