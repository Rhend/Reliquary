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

# ─── Cimetière : mémorial numérique (champ de stèles holographiques) ──
# Chaque case porte une stèle fine verticale lumineuse, alignée en grille régulière,
# posée sur un socle plat discret. Pas de pierres tombales : des dalles holographiques.
static func cimetieres(h) -> void:
	if h._excel.cimetieres.is_empty():
		return
	var s := HoloMesh3D.st()       # socles (décor discret)
	var n := 0
	var sg := HoloMesh3D.st()      # stèles + chapelle (glow)
	var ng := 0
	for b in h._excel.cimetieres:
		var bb: Rect2i = b["bbox"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col_stele: Color = h._moduler(Color(0.52, 0.68, 0.84), centre)   # cyan-ardoise lumineux
		var col_socle: Color = h._moduler(Color(0.34, 0.44, 0.56), centre)
		var cells: Array = b["cells"]
		# Hauteur tapée → facteur d'élancement des stèles/chapelle (défaut = 1, look actuel).
		var fy: float = maxf(0.3, b["hauteur_m"] / maxf(0.5, h._excel.hauteur_defaut_m))
		# Enceinte : contour bas lumineux qui ceinture le champ (lecture « mémorial clos »).
		ng += _contour_cimetiere(h, cells, col_stele, sg)
		# Portail face aux routes (un peu plus haut que la clôture → vraie entrée).
		ng += h._portes_vers_routes(cells, h.unite_maison * 0.6, col_stele, sg)
		# Chapelle au centre du bloc (si le champ est assez grand) : on repère la case
		# la plus proche du centre, elle accueille la chapelle au lieu d'une stèle.
		var cell_chapelle := Vector2i(-9999, -9999)
		if cells.size() >= 4:
			var gcx := bb.position.x + (bb.size.x - 1) * 0.5
			var gcy := bb.position.y + (bb.size.y - 1) * 0.5
			var best := 1.0e9
			for cell: Vector2i in cells:
				var dd := Vector2(float(cell.x) - gcx, float(cell.y) - gcy).length_squared()
				if dd < best:
					best = dd; cell_chapelle = cell
		for cell: Vector2i in cells:
			var c: Vector3 = h._world(cell.x, cell.y, 0.0)
			n += Geo.carre_plat(s, c, h.taille_cellule * 0.30, col_socle)
			if cell == cell_chapelle:
				continue   # la chapelle occupe cette case (pas de stèle)
			# Stèle = dalle fine verticale + barre de tête (mémoriel holographique).
			var w: float = h.taille_cellule * 0.18
			var d: float = h.taille_cellule * 0.05
			var hs: float = h.unite_maison * 1.05 * fy
			ng += HoloMesh3D.box(sg, c, w, hs, d, col_stele)
			ng += HoloMesh3D.line(sg, c + Vector3(-w * 0.6, hs * 0.78, 0),
					c + Vector3(w * 0.6, hs * 0.78, 0), col_stele)
		if cell_chapelle.x > -9000:
			ng += _chapelle(h, h._world(cell_chapelle.x, cell_chapelle.y, 0.0), col_stele, sg, fy)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "CimetiereSocles", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "CimetiereSteles", h._mat_lieu_decor)

# Petite chapelle holographique : nef (boîte) + toit à deux pans (faîtage + pignons)
# + croix sur le faîtage. Repère central du mémorial. Renvoie le nb d'arêtes.
static func _chapelle(h, c: Vector3, col: Color, s: SurfaceTool, fy: float = 1.0) -> int:
	var w: float = h.taille_cellule * 0.55
	var d: float = h.taille_cellule * 0.78
	var hw := w * 0.5
	var hd := d * 0.5
	var wall: float = h.unite_maison * 1.4 * fy
	var roof: float = h.unite_maison * 0.95 * fy
	var n := HoloMesh3D.box(s, c, w, wall, d, col)        # nef (murs)
	var ry := c.y + wall + roof
	var ridge_a := Vector3(c.x, ry, c.z - hd)             # faîtage (axe Z)
	var ridge_b := Vector3(c.x, ry, c.z + hd)
	var tla := Vector3(c.x - hw, c.y + wall, c.z - hd)
	var tra := Vector3(c.x + hw, c.y + wall, c.z - hd)
	var tlb := Vector3(c.x - hw, c.y + wall, c.z + hd)
	var trb := Vector3(c.x + hw, c.y + wall, c.z + hd)
	n += HoloMesh3D.line(s, ridge_a, ridge_b, col)        # faîtage
	n += HoloMesh3D.line(s, tla, ridge_a, col) + HoloMesh3D.line(s, tra, ridge_a, col)   # pignon avant
	n += HoloMesh3D.line(s, tlb, ridge_b, col) + HoloMesh3D.line(s, trb, ridge_b, col)   # pignon arrière
	n += HoloMesh3D.line(s, tla, tlb, col) + HoloMesh3D.line(s, tra, trb, col)           # bas des pans
	# Croix au-dessus du pignon avant.
	var cross_h: float = h.unite_maison * 0.7
	var top := ridge_a + Vector3(0, cross_h, 0)
	n += HoloMesh3D.line(s, ridge_a, top, col)
	var arm: float = h.taille_cellule * 0.1
	var ay := ridge_a.y + cross_h * 0.6
	n += HoloMesh3D.line(s, Vector3(c.x - arm, ay, ridge_a.z), Vector3(c.x + arm, ay, ridge_a.z), col)
	return n

# Enceinte du mémorial : contour bas qui ceinture le champ de stèles (lecture « clos »).
# Pour chaque côté frontière du bloc : ligne au sol + parapet bas + montants aux bouts.
# Renvoie le nombre d'arêtes.
static func _contour_cimetiere(h, cells: Array, col: Color, s: SurfaceTool) -> int:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var hw: float = h.unite_maison * 0.4   # mur bas (sous les stèles)
	var up := Vector3(0, hw, 0)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
			var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
			n += HoloMesh3D.line(s, a0, b0, col)             # liseré au sol
			n += HoloMesh3D.line(s, a0 + up, b0 + up, col)   # parapet bas
			n += HoloMesh3D.line(s, a0, a0 + up, col)        # montants aux bouts
			n += HoloMesh3D.line(s, b0, b0 + up, col)
	return n
