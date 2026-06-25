# ============================================================
# HoloMesh3D — Fabrique statique de maillages d'ARÊTES (PRIMITIVE_LINES).
#
# Helpers partagés entre HoloMap3D (terrain/ville/circuits/grille) et
# HoloLocation3D (base/pin/anneau) pour construire des wireframes holo.
# Chaque arête porte sa vertex color (cyan base / magenta accent) ; le
# matériau holo_line lit COLOR pour l'émission.
# ============================================================
class_name HoloMesh3D

# Nouveau SurfaceTool prêt à recevoir des segments de lignes.
static func st() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	return s

# Finalise en ArrayMesh (null si aucune ligne — évite un mesh vide invalide).
static func commit(s: SurfaceTool, compte: int) -> ArrayMesh:
	if compte <= 0:
		return null
	return s.commit()

static func line(s: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	s.set_color(col); s.add_vertex(a)
	s.set_color(col); s.add_vertex(b)

# Boîte wireframe : base centrée en `c` (au sol), s'élevant de `sy` sur +Y.
static func box(s: SurfaceTool, c: Vector3, sx: float, sy: float, sz: float, col: Color) -> void:
	var hx := sx * 0.5
	var hz := sz * 0.5
	var b0 := c + Vector3(-hx, 0, -hz)
	var b1 := c + Vector3( hx, 0, -hz)
	var b2 := c + Vector3( hx, 0,  hz)
	var b3 := c + Vector3(-hx, 0,  hz)
	var up := Vector3(0, sy, 0)
	# Bas
	line(s, b0, b1, col); line(s, b1, b2, col); line(s, b2, b3, col); line(s, b3, b0, col)
	# Haut
	line(s, b0 + up, b1 + up, col); line(s, b1 + up, b2 + up, col)
	line(s, b2 + up, b3 + up, col); line(s, b3 + up, b0 + up, col)
	# Montantes
	line(s, b0, b0 + up, col); line(s, b1, b1 + up, col)
	line(s, b2, b2 + up, col); line(s, b3, b3 + up, col)

# Boucle de cercle dans le plan XZ (anneau au sol), centrée en `c`.
static func circle(s: SurfaceTool, c: Vector3, r: float, col: Color, seg: int = 32) -> void:
	var prev := c + Vector3(r, 0, 0)
	for i in range(1, seg + 1):
		var ang := TAU * float(i) / float(seg)
		var cur := c + Vector3(cos(ang) * r, 0, sin(ang) * r)
		line(s, prev, cur, col)
		prev = cur

# Diamant (octaèdre) wireframe : centre `c`, demi-largeur `r`, demi-hauteur `h`.
static func diamond(s: SurfaceTool, c: Vector3, r: float, h: float, col: Color) -> void:
	var top := c + Vector3(0, h, 0)
	var bot := c + Vector3(0, -h, 0)
	var mids := [
		c + Vector3( r, 0, 0), c + Vector3(0, 0,  r),
		c + Vector3(-r, 0, 0), c + Vector3(0, 0, -r),
	]
	for i in 4:
		line(s, top, mids[i], col)
		line(s, bot, mids[i], col)
		line(s, mids[i], mids[(i + 1) % 4], col)
