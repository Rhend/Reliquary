# ============================================================
# holo_decor — Familles de décor STATEFUL extraites de HoloMap3D (refactor).
#
# Pattern : `static func famille(h)` où `h` = le noeud HoloMap3D (NON typé →
# pas de cycle class_name). On accède aux helpers partagés et aux propriétés
# via `h.*` (_excel, _world, _moduler, _ajouter_mesh, unite_maison, …) ; les
# locales issues de `h.*` sont typées EXPLICITEMENT (inférence Variant interdite
# par le projet). Appelé via `const Decor := preload(...)` côté HoloMap3D.
# ============================================================
extends RefCounted

const Geo := preload("res://scenes/holomap3d/build/holo_geo.gd")

# ─── Colline / désert : relief de bordure (apparence ocre) ────
# Les cases ocre peintes en périphérie forment un ruban de relief inerte qui cadre la
# ville. Chaque case reçoit une « butte » basse (hauteur variée déterministe) → dunes
# continues. Le gradient de richesse les ternit encore vers l'extérieur (désert mort).
static func collines(h) -> void:
	if h._excel.collines.is_empty():
		return
	var s := HoloMesh3D.st()
	var n := 0
	var base_col := Color(0.74, 0.62, 0.40)   # ocre sable (DA holo, faible glow)
	for cell: Vector2i in h._excel.collines:
		var c: Vector3 = h._world(cell.x, cell.y, 0.0)
		# Hash déterministe par case → hauteur + léger décalage du sommet (organique).
		var hsh := float(((cell.x * 73856093) ^ (cell.y * 19349663)) & 0xFFFF) / 65535.0
		var jsh := float(((cell.x * 19349663) ^ (cell.y * 83492791)) & 0xFFFF) / 65535.0
		var haut: float = h.unite_maison * lerpf(0.7, 2.0, hsh)
		var jx: float = (jsh - 0.5) * h.taille_cellule * 0.4
		var jz: float = (hsh - 0.5) * h.taille_cellule * 0.4
		n += Geo.butte(s, c, h.taille_cellule * 0.62, haut, h._moduler(base_col, c), jx, jz)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "CollinesRelief", h._mat_ambiance)
