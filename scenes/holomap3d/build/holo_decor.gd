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
const Props := preload("res://scenes/holomap3d/build/holo_props.gd")

const METRES_PAR_CASE := 10.0   # convention du gabarit (cf. Carte Holo/SPECS_ASSETS.md)

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
	var sf := HoloMesh3D.st_tri()  # faces du mur d'enceinte (occlusion sombre)
	var nf := 0
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
		# MUR D'ENCEINTE haut (paroi sombre + couronnement) percé d'un PORTAIL
		# monumental sur le côté connecté à une route (piliers + fronton + croix).
		var rmur: Array = _mur_cimetiere(h, cells, h.unite_maison * 1.35 * fy, col_socle, col_stele, s, sf, sg)
		n += rmur[0]; nf += rmur[1]; ng += rmur[2]
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
		# Rangées le long du grand axe du bloc → allées de mémorial lisibles.
		var range_x := bb.size.x >= bb.size.y
		for cell: Vector2i in cells:
			var c: Vector3 = h._world(cell.x, cell.y, 0.0)
			n += Geo.carre_plat(s, c, h.taille_cellule * 0.30, col_socle)
			if cell == cell_chapelle:
				continue   # la chapelle occupe cette case (pas de stèle)
			# DEUX petites stèles par case, alignées en rangée, silhouette VARIÉE
			# (hash) : dalle à barre de tête ou obélisque effilé → un vrai champ de
			# tombes irrégulier, plus un gros bloc unique par case.
			var off: Vector3 = (Vector3(1, 0, 0) if range_x else Vector3(0, 0, 1)) * (h.taille_cellule * 0.20)
			var k := 0
			for pc: Vector3 in [c - off, c + off]:
				k += 1
				var hv: float = h._hash01(cell, 23 + k)
				var hs: float = h.unite_maison * lerpf(0.50, 0.80, hv) * fy
				if hv < 0.72:
					var w: float = h.taille_cellule * 0.11
					var d: float = h.taille_cellule * 0.04
					if range_x:
						ng += HoloMesh3D.box(sg, pc, w, hs, d, col_stele)
						ng += HoloMesh3D.line(sg, pc + Vector3(-w * 0.7, hs * 0.8, 0),
								pc + Vector3(w * 0.7, hs * 0.8, 0), col_stele)
					else:
						ng += HoloMesh3D.box(sg, pc, d, hs, w, col_stele)
						ng += HoloMesh3D.line(sg, pc + Vector3(0, hs * 0.8, -w * 0.7),
								pc + Vector3(0, hs * 0.8, w * 0.7), col_stele)
				else:
					ng += HoloMesh3D.pyramid(sg, pc, h.taille_cellule * 0.09,
							h.taille_cellule * 0.09, hs * 1.35, col_stele)
			# Cyprès : ~1 case sur 5, arbre-flamme sombre au coin (verticalité feutrée).
			if h._hash01(cell, 29) < 0.20:
				var pt := c + Vector3(h.taille_cellule * 0.30, 0, h.taille_cellule * 0.30)
				n += HoloMesh3D.pyramid(s, pt, h.taille_cellule * 0.14, h.taille_cellule * 0.14,
						h.unite_maison * 1.5 * fy, h._moduler(Color(0.22, 0.50, 0.30), centre))
		if cell_chapelle.x > -9000:
			ng += _chapelle(h, h._world(cell_chapelle.x, cell_chapelle.y, 0.0), col_stele, sg, fy)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "CimetiereSocles", h._mat_ambiance)
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "CimetiereMurFaces")
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
# Mur d'enceinte HAUT du cimetière : paroi sombre occluse (faces) + arêtes (bas /
# corniche / crête / montants), percée d'un PORTAIL monumental sur le premier côté
# donnant sur une ROUTE (piliers lumineux + linteau + fronton + croix). Renvoie
# [arêtes sombres, faces, arêtes glow].
static func _mur_cimetiere(h, cells: Array, mh: float, col: Color, col_vif: Color,
		s: SurfaceTool, sf: SurfaceTool, sg: SurfaceTool) -> Array:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Côté du portail : premier côté frontière dont le voisin est une route.
	var porte_cell := Vector2i(-9999, -9999)
	var porte_dir := Vector2i.ZERO
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if not setd.has(c + d) and h._routes_set.has(c + d):
				porte_cell = c
				porte_dir = d
				break
		if porte_cell.x > -9000:
			break
	var n := 0
	var nf := 0
	var ng := 0
	var up := Vector3(0, mh, 0)
	var eps: float = h.taille_cellule * 0.05
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
			var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
			if c == porte_cell and d == porte_dir:
				ng += _portail_cimetiere(h, a0, b0, mh, col_vif, sg)
				continue   # le portail remplace la paroi sur ce segment
			# Paroi : bas + corniche (2/3) + crête + montants, face sombre occluse.
			n += HoloMesh3D.line(s, a0, b0, col)
			n += HoloMesh3D.line(s, a0 + up * 0.66, b0 + up * 0.66, col)
			n += HoloMesh3D.line(s, a0 + up, b0 + up, col)
			n += HoloMesh3D.line(s, a0, a0 + up, col)
			n += HoloMesh3D.line(s, b0, b0 + up, col)
			var inward := Vector3(-float(d.x), 0, -float(d.y)) * eps
			nf += HoloMesh3D._quad(sf, a0 + inward, b0 + inward, b0 + inward + up, a0 + inward + up,
					Vector3(float(d.x), 0, float(d.y)))
	return [n, nf, ng]

# Portail monumental (segment a0→b0, paroi de hauteur mh) : deux piliers plus hauts
# que le mur, linteau double, fronton triangulaire coiffé d'une croix, et retours de
# mur de part et d'autre de l'ouverture. Renvoie le nb d'arêtes glow.
static func _portail_cimetiere(h, a0: Vector3, b0: Vector3, mh: float, col: Color, s: SurfaceTool) -> int:
	var mid := (a0 + b0) * 0.5
	var half := (b0 - a0) * 0.5
	var jl := mid - half * 0.42   # pilier gauche (ouverture ~42 % du côté)
	var jr := mid + half * 0.42
	var gh := mh * 1.30           # piliers plus hauts que le mur
	var w: float = h.taille_cellule * 0.09
	var n := 0
	# Retours de mur (crête + base) entre les coins et les piliers.
	for paire: Array in [[a0, jl], [b0, jr]]:
		var p0: Vector3 = paire[0]
		var p1: Vector3 = paire[1]
		n += HoloMesh3D.line(s, p0, p1, col)
		n += HoloMesh3D.line(s, p0 + Vector3(0, mh, 0), p1 + Vector3(0, mh, 0), col)
		n += HoloMesh3D.line(s, p0, p0 + Vector3(0, mh, 0), col)
	# Piliers + boules de faîte.
	for p: Vector3 in [jl, jr]:
		n += HoloMesh3D.box(s, p, w, gh, w, col)
		n += HoloMesh3D.diamond(s, p + Vector3(0, gh + w * 0.8, 0), w * 0.7, w * 0.9, col)
	# Linteau double (architrave) au-dessus de l'ouverture.
	n += HoloMesh3D.line(s, jl + Vector3(0, gh, 0), jr + Vector3(0, gh, 0), col)
	n += HoloMesh3D.line(s, jl + Vector3(0, gh * 0.88, 0), jr + Vector3(0, gh * 0.88, 0), col)
	# Fronton triangulaire + croix (signature mémorial, cf. chapelle).
	var apex := mid + Vector3(0, gh + mh * 0.45, 0)
	n += HoloMesh3D.line(s, jl + Vector3(0, gh, 0), apex, col)
	n += HoloMesh3D.line(s, jr + Vector3(0, gh, 0), apex, col)
	var cross_h: float = h.unite_maison * 0.5
	var top := apex + Vector3(0, cross_h, 0)
	n += HoloMesh3D.line(s, apex, top, col)
	var arm: Vector3 = half.normalized() * (h.taille_cellule * 0.08)
	var ay := apex + Vector3(0, cross_h * 0.62, 0)
	n += HoloMesh3D.line(s, ay - arm, ay + arm, col)
	return n

# ─── Terrains de sport : stades de baseball holographiques ────
static func terrains(h) -> void:
	if h._excel.terrains.is_empty():
		return
	var sg := HoloMesh3D.st_tri()   # gazon
	var ng := 0
	var s := HoloMesh3D.st()        # structure (terre / lignes / gradins)
	var n := 0
	var sn := HoloMesh3D.st()       # éléments lumineux (projecteurs, écran)
	var nn := 0
	for t in h._excel.terrains:
		var r := _stade_baseball(h, t["bbox"], sg, s, sn)
		ng += r[0]; n += r[1]; nn += r[2]
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "StadeGazon", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "StadeStructure", h._mat_decor)
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "StadeLumieres", h._mat_neon)

# Stade de baseball complet, ajusté à la bbox (ellipses → tout ratio remplit) :
# terrain (gazon + INFIELD en terre + carré de gazon intérieur + losange + clôture
# VERTICALE + poteaux de faute) + TRIBUNES en fer à cheval autour du marbre (le champ
# extérieur reste ouvert) coiffées d'un auvent, abris des joueurs, backstop,
# PROJECTEURS et TABLEAU d'affichage.
static func _stade_baseball(h, bbox: Rect2i, sg: SurfaceTool, s: SurfaceTool, sn: SurfaceTool) -> Array:
	var cx := bbox.position.x + (bbox.size.x - 1) * 0.5
	var cy := bbox.position.y + (bbox.size.y - 1) * 0.5
	var ax: float = float(bbox.size.x) * h.taille_cellule * 0.5
	var az: float = float(bbox.size.y) * h.taille_cellule * 0.5
	var c: Vector3 = h._world(cx, cy, 0.0)
	var kf := 0.56     # bord du terrain (clôture) en fraction du demi-axe
	var vert := Color(0.32, 0.70, 0.36)
	var vert_a := Color(0.15, 0.38, 0.19, 0.5)
	var terre := Color(0.80, 0.58, 0.35)
	var terre_a := Color(0.62, 0.42, 0.22, 0.45)
	var blanc := Color(0.92, 0.96, 1.0)
	var jaune := Color(1.0, 0.85, 0.30)
	var acier := Color(0.42, 0.48, 0.58)
	var n := 0
	var ng := 0
	var nn := 0
	# Marbre côté +Z ; le champ s'ouvre vers −Z (poteaux de faute à ±45° du centre).
	var home := c + Vector3(0, 0, az * 0.40) + Vector3(0, 0.02, 0)
	var a_rf := -PI * 0.25
	var a_lf := -PI * 0.75
	var rfp := Geo.pt_ell(c, ax, az, kf, a_rf, 0.02)
	var lfp := Geo.pt_ell(c, ax, az, kf, a_lf, 0.02)
	var seg := 30
	# Gazon (territoire bon) : éventail du marbre vers l'arc de clôture.
	var prevg := rfp
	for i in range(1, seg + 1):
		var a := lerpf(a_rf, a_lf, float(i) / float(seg))
		var cur := Geo.pt_ell(c, ax, az, kf, a, 0.02)
		sg.set_color(vert_a); sg.add_vertex(home)
		sg.set_color(vert_a); sg.add_vertex(prevg)
		sg.set_color(vert_a); sg.add_vertex(cur)
		ng += 1
		prevg = cur
	# Lignes de faute + repères du losange.
	n += HoloMesh3D.line(s, home, rfp, blanc)
	n += HoloMesh3D.line(s, home, lfp, blanc)
	var d1 := (rfp - home).normalized()
	var d3 := (lfp - home).normalized()
	var m := (d1 + d3).normalized()          # axe marbre → centre du champ
	var wv := (d1 - d3).normalized()         # perpendiculaire (1re ↔ 3e base)
	var b := minf(ax, az) * kf * 0.42
	var first := home + d1 * b
	var third := home + d3 * b
	var second := home + (d1 + d3) * b
	# INFIELD en terre : éventail plein autour du losange (posé sur le gazon).
	var rd := b * 1.42
	var lift := Vector3(0, 0.012, 0)
	var prevd := home + d1 * rd + lift
	for i in range(1, 13):
		var dirv := d1.lerp(d3, float(i) / 12.0).normalized()
		var cur := home + dirv * rd + lift
		sg.set_color(terre_a); sg.add_vertex(home + lift)
		sg.set_color(terre_a); sg.add_vertex(prevd)
		sg.set_color(terre_a); sg.add_vertex(cur)
		ng += 1
		prevd = cur
	# Carré de gazon INTÉRIEUR au cœur du losange (le contraste terre/gazon du vrai infield).
	var dc := home + (d1 + d3) * (b * 0.5)   # centre du losange
	var lift2 := Vector3(0, 0.024, 0)
	var q: Array[Vector3] = []
	for p: Vector3 in [home, first, second, third]:
		q.append(p.lerp(dc, 0.18) + lift2)
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for idx: int in tri:
			sg.set_color(Color(0.20, 0.50, 0.24, 0.55)); sg.add_vertex(q[idx])
		ng += 1
	# Losange + bases + rectangles des batteurs + monticule et sa plaque.
	n += HoloMesh3D.line(s, home, first, terre)
	n += HoloMesh3D.line(s, first, second, terre)
	n += HoloMesh3D.line(s, second, third, terre)
	n += HoloMesh3D.line(s, third, home, terre)
	for base: Vector3 in [first, second, third, home]:
		n += Geo.carre_plat(s, base, h.taille_cellule * 0.06, blanc)
	for o: float in [-0.14, 0.14]:
		n += Geo.carre_plat(s, home + wv * (b * o), b * 0.055, blanc)
	n += HoloMesh3D.circle(s, dc, b * 0.14, terre, 12)
	n += HoloMesh3D.line(s, dc - wv * (b * 0.04), dc + wv * (b * 0.04), blanc)
	# ── Clôture VERTICALE du champ extérieur (lisses basse/haute + poteaux) + warning track ──
	var fh := minf(ax, az) * 0.10
	var prev := rfp
	var prevt := rfp + Vector3(0, fh, 0)
	var prev2 := Geo.pt_ell(c, ax, az, kf * 0.93, a_rf, 0.02)
	for i in range(1, seg + 1):
		var a := lerpf(a_rf, a_lf, float(i) / float(seg))
		var cur := Geo.pt_ell(c, ax, az, kf, a, 0.02)
		var curt := cur + Vector3(0, fh, 0)
		var cur2 := Geo.pt_ell(c, ax, az, kf * 0.93, a, 0.02)
		n += HoloMesh3D.line(s, prev, cur, vert)
		n += HoloMesh3D.line(s, prevt, curt, Color(vert, 0.8))
		if i % 3 == 0:
			n += HoloMesh3D.line(s, cur, curt, Color(vert, 0.55))
		n += HoloMesh3D.line(s, prev2, cur2, Color(vert, 0.6))
		prev = cur; prevt = curt; prev2 = cur2
	# Poteaux de faute (jaunes, glow) aux deux bouts de la clôture.
	for fp: Vector3 in [rfp, lfp]:
		nn += HoloMesh3D.line(sn, fp, fp + Vector3(0, fh * 2.6, 0), jaune)
	# Backstop : écran grillagé derrière le marbre (poteaux + lisse + filet en X).
	var bsc := home - m * (b * 0.42)
	var bh2 := minf(ax, az) * 0.12
	var bl := bsc - wv * (b * 0.45)
	var br := bsc + wv * (b * 0.45)
	for p: Vector3 in [bl, bsc, br]:
		n += HoloMesh3D.line(s, p, p + Vector3(0, bh2, 0), acier)
	n += HoloMesh3D.line(s, bl + Vector3(0, bh2, 0), br + Vector3(0, bh2, 0), acier)
	n += HoloMesh3D.line(s, bl, br + Vector3(0, bh2, 0), Color(acier, 0.45))
	n += HoloMesh3D.line(s, br, bl + Vector3(0, bh2, 0), Color(acier, 0.45))
	# Abris des joueurs (dugouts) : auvents bas le long des deux lignes de faute.
	for dv: Vector3 in [d1, d3]:
		var out_f := (dv - m).normalized()
		var p0d := home + dv * (b * 0.35) + out_f * (b * 0.18)
		var p1d := home + dv * (b * 0.85) + out_f * (b * 0.18)
		var hh2 := minf(ax, az) * 0.045
		n += HoloMesh3D.line(s, p0d, p0d + Vector3(0, hh2, 0), acier)
		n += HoloMesh3D.line(s, p1d, p1d + Vector3(0, hh2, 0), acier)
		n += HoloMesh3D.line(s, p0d + Vector3(0, hh2, 0), p1d + Vector3(0, hh2, 0), acier)
		n += HoloMesh3D.line(s, p0d, p1d, Color(acier, 0.5))
	# ── TRIBUNES en fer à cheval : elles n'entourent QUE le marbre et les lignes de
	# faute (d'un poteau à l'autre en passant par +Z) ; le champ extérieur reste
	# ouvert sur la clôture — silhouette de vrai stade au lieu d'un bol fermé. ──
	var hb := minf(ax, az) * 0.42
	var a0s := a_rf + 0.10
	var a1s := a_lf + TAU - 0.10
	var nb_t := 4
	var segs := 40
	var k0 := kf * 1.10
	for t in nb_t:
		var k := lerpf(k0, 1.0, float(t) / float(nb_t - 1))
		var yy := lerpf(0.03, hb, float(t) / float(nb_t - 1))
		var pv := Geo.pt_ell(c, ax, az, k, a0s, yy)
		for i in range(1, segs + 1):
			var a := lerpf(a0s, a1s, float(i) / float(segs))
			var cur := Geo.pt_ell(c, ax, az, k, a, yy)
			n += HoloMesh3D.line(s, pv, cur, acier)
			pv = cur
	for i in range(0, segs + 1, 4):
		var a := lerpf(a0s, a1s, float(i) / float(segs))
		var pv := Geo.pt_ell(c, ax, az, k0, a, 0.03)
		for t in range(1, nb_t):
			var k := lerpf(k0, 1.0, float(t) / float(nb_t - 1))
			var yy := lerpf(0.03, hb, float(t) / float(nb_t - 1))
			var cur := Geo.pt_ell(c, ax, az, k, a, yy)
			n += HoloMesh3D.line(s, pv, cur, Color(acier, 0.55))   # crémaillère
			pv = cur
		n += HoloMesh3D.line(s, Geo.pt_ell(c, ax, az, 1.0, a, hb),
				Geo.pt_ell(c, ax, az, 1.0, a, 0.0), Color(acier, 0.55))   # béquille arrière
	# Auvent au-dessus de la tribune du marbre (toit léger sur poteaux + chevrons).
	var ca0 := PI * 0.5 - 0.55
	var ca1 := PI * 0.5 + 0.55
	var csegs := 8
	var kfront := lerpf(k0, 1.0, 0.35)
	var pf := Geo.pt_ell(c, ax, az, kfront, ca0, hb * 1.22)
	var pb := Geo.pt_ell(c, ax, az, 1.02, ca0, hb * 1.32)
	for i in range(1, csegs + 1):
		var a := lerpf(ca0, ca1, float(i) / float(csegs))
		var cf := Geo.pt_ell(c, ax, az, kfront, a, hb * 1.22)
		var cb := Geo.pt_ell(c, ax, az, 1.02, a, hb * 1.32)
		n += HoloMesh3D.line(s, pf, cf, acier)
		n += HoloMesh3D.line(s, pb, cb, acier)
		if i % 2 == 0:
			n += HoloMesh3D.line(s, cf, cb, Color(acier, 0.7))                     # chevron
			n += HoloMesh3D.line(s, Geo.pt_ell(c, ax, az, 1.0, a, hb), cb, acier)  # poteau
		pf = cf; pb = cb
	# ── Projecteurs : 2 grands mâts derrière la clôture du champ + 3 sur la couronne ──
	var bw := minf(ax, az) * 0.055
	for la: float in [-PI * 0.33, -PI * 0.67]:
		var basep := Geo.pt_ell(c, ax, az, kf * 1.12, la, 0.0)
		var topp := basep + Vector3(0, hb * 1.15, 0)
		n += HoloMesh3D.line(s, basep, topp, acier)
		nn += Geo.carre_plat(sn, topp + Vector3(0, bw, 0), bw, Color(1.0, 0.98, 0.85))
		nn += Geo.carre_plat(sn, topp + Vector3(0, bw * 2.1, 0), bw * 0.75, Color(1.0, 0.98, 0.85))
	for la: float in [PI * 0.10, PI * 0.5, PI * 0.90]:
		var basep := Geo.pt_ell(c, ax, az, 1.0, la, hb)
		var topp := basep + Vector3(0, hb * 0.55, 0)
		n += HoloMesh3D.line(s, basep, topp, acier)
		nn += Geo.carre_plat(sn, topp + Vector3(0, bw, 0), bw, Color(1.0, 0.98, 0.85))
	# ── Tableau d'affichage au centre du champ (au-delà de la clôture, −Z) ──
	var sb := Geo.pt_ell(c, ax, az, kf * 1.14, -PI * 0.5, hb * 0.48)
	var sw := ax * 0.28
	var sh := hb * 0.30
	var p0 := sb + Vector3(-sw, sh, 0)
	var p1 := sb + Vector3(sw, sh, 0)
	var p2 := sb + Vector3(sw, -sh, 0)
	var p3 := sb + Vector3(-sw, -sh, 0)
	nn += HoloMesh3D.line(sn, p0, p1, Color(0.40, 0.90, 1.0))
	nn += HoloMesh3D.line(sn, p1, p2, Color(0.40, 0.90, 1.0))
	nn += HoloMesh3D.line(sn, p2, p3, Color(0.40, 0.90, 1.0))
	nn += HoloMesh3D.line(sn, p3, p0, Color(0.40, 0.90, 1.0))
	for i in 3:
		var yy := lerpf(-sh, sh, float(i + 1) / 4.0)
		nn += HoloMesh3D.line(sn, sb + Vector3(-sw, yy, 0), sb + Vector3(sw, yy, 0), Color(0.40, 0.90, 1.0, 0.5))
	# Mâts du tableau jusqu'au sol.
	n += HoloMesh3D.line(s, sb + Vector3(-sw * 0.7, -sh, 0), sb + Vector3(-sw * 0.7, -hb * 0.48, 0), acier)
	n += HoloMesh3D.line(s, sb + Vector3(sw * 0.7, -sh, 0), sb + Vector3(sw * 0.7, -hb * 0.48, 0), acier)
	return [ng, n, nn]

# ─── Parking (apparence gris clair) : aire de stationnement plate au sol ──────
# Traité PAR LOT (cases connexes) : muret béton tout autour (cloisonne le lieu),
# rangées de places ALIGNÉES sur la grille (places entières, jamais coupées) de
# part et d'autre d'une allée de circulation fléchée (sens alterné une rangée sur
# deux). Surface plate (aucun volume) ; le gradient délave les marquages au bord.
static func parkings(h) -> void:
	if h._excel.parkings.is_empty():
		return
	var setd := {}
	for c: Vector2i in h._excel.parkings:
		setd[c] = true
	var s := HoloMesh3D.st()        # marquages + rail de muret (glow)
	var n := 0
	var sm := HoloMesh3D.st()       # muret béton (structure)
	var nmur := 0
	var mats := HoloMesh3D.st()     # mâts de lampadaires (sombres)
	var nm := 0
	var tetes := HoloMesh3D.st()    # têtes lumineuses (glow chaud)
	var nt := 0
	var y := 0.03
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var col_mur := Color(0.46, 0.49, 0.55)
	var murh: float = h.unite_maison * 0.5
	var hc: float = h.taille_cellule * 0.5    # demi-case (place pleine, bord à bord)
	var vus := {}
	for start: Vector2i in h._excel.parkings:
		if vus.has(start):
			continue
		# Lot = cases parking 4-connexes (flood-fill).
		var lot: Array = []
		var pile: Array = [start]
		while not pile.is_empty():
			var cc: Vector2i = pile.pop_back()
			if vus.has(cc) or not setd.has(cc):
				continue
			vus[cc] = true
			lot.append(cc)
			for d: Vector2i in dirs:
				pile.append(cc + d)
		# Orientation : allées le long du GRAND axe de la bbox du lot.
		var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
		for c2: Vector2i in lot:
			minx = mini(minx, c2.x); miny = mini(miny, c2.y)
			maxx = maxi(maxx, c2.x); maxy = maxi(maxy, c2.y)
		var horiz := (maxx - minx) >= (maxy - miny)
		var av := Vector3(1, 0, 0) if horiz else Vector3(0, 0, 1)   # axe des allées (long)
		var bv := Vector3(0, 0, 1) if horiz else Vector3(1, 0, 0)   # axe perpendiculaire (rangées)
		# ── Marquages : LOGIQUE de lot (pas le même motif partout) ──
		# Le rôle d'une case dépend de son indice de RANGÉE (le long de B) : une rangée
		# sur 3 est une ALLÉE de circulation (fléchée, sens alterné), les autres sont des
		# rangées de PLACES (dos à dos). Tout est aligné sur la grille → places entières.
		var b0idx := miny if horiz else minx
		for cell: Vector2i in lot:
			var c: Vector3 = h._world(cell.x, cell.y, y)
			var col: Color = h._moduler(Color(0.74, 0.79, 0.88), c)
			var row: int = (cell.y if horiz else cell.x) - b0idx
			if row % 3 == 1:
				# ALLÉE de circulation : bords + flèche (sens alterné une allée sur deux).
				n += HoloMesh3D.line(s, c + av * (-hc) + bv * (-hc), c + av * hc + bv * (-hc), col)
				n += HoloMesh3D.line(s, c + av * (-hc) + bv * hc,    c + av * hc + bv * hc,    col)
				@warning_ignore("integer_division")
				var sgn := 1.0 if (((row - 1) / 3) % 2 == 0) else -1.0
				var tip: Vector3 = c + av * (sgn * h.taille_cellule * 0.30)
				n += HoloMesh3D.line(s, c - av * (sgn * h.taille_cellule * 0.12), tip, col)   # hampe
				n += HoloMesh3D.line(s, tip, tip - av * (sgn * h.taille_cellule * 0.13) + bv * (h.taille_cellule * 0.08), col)
				n += HoloMesh3D.line(s, tip, tip - av * (sgn * h.taille_cellule * 0.13) - bv * (h.taille_cellule * 0.08), col)
			else:
				# Rangée de PLACES : fonds (±0.5) + séparateur central (dos à dos) +
				# séparateurs de places tous les 0.5 case (alignés bord à bord, entiers).
				n += HoloMesh3D.line(s, c + av * (-hc) + bv * (-hc), c + av * hc + bv * (-hc), col)  # bord -
				n += HoloMesh3D.line(s, c + av * (-hc) + bv * hc,    c + av * hc + bv * hc,    col)  # bord +
				n += HoloMesh3D.line(s, c + av * (-hc),              c + av * hc,              col)  # dos à dos
				for k: float in [-0.5, 0.0]:
					var u: Vector3 = c + av * (k * h.taille_cellule)
					n += HoloMesh3D.line(s, u + bv * (-hc), u + bv * hc, col)   # séparateur de place
		# ── Muret béton ceinturant le lot (base + sommet + poteaux) + rail glow ──
		for cell: Vector2i in lot:
			for d: Vector2i in dirs:
				if setd.has(cell + d):
					continue
				var seg: Array = h._cote_cellule(cell, d)
				var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
				var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
				var up := Vector3(0, murh, 0)
				nmur += HoloMesh3D.line(sm, a0, b0, col_mur)            # base
				nmur += HoloMesh3D.line(sm, a0 + up, b0 + up, col_mur)  # sommet
				nmur += HoloMesh3D.line(sm, a0, a0 + up, col_mur)       # poteau A
				nmur += HoloMesh3D.line(sm, b0, b0 + up, col_mur)       # poteau B
				n += HoloMesh3D.line(s, a0 + up, b0 + up, Color(0.55, 0.75, 1.0))  # rail néon (lisibilité)
		# ── Lampadaire d'angle (1 par lot) ──
		var lc: Vector2i = lot[0]
		var base: Vector3 = h._world(lc.x - 0.3, lc.y - 0.3, 0.0)
		var tete: Vector3 = base + Vector3(0, h.unite_maison * 1.4, 0)
		nm += HoloMesh3D.line(mats, base, tete, Color(0.35, 0.38, 0.42))
		nt += HoloMesh3D.diamond(tetes, tete, h.taille_cellule * 0.08, h.unite_maison * 0.18, Color(1.0, 0.82, 0.50))
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "ParkingMarquage", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(sm, nmur), "ParkingMuret", h._mat_decor)
	h._ajouter_mesh(HoloMesh3D.commit(mats, nm), "ParkingLampMats", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(tetes, nt), "ParkingLampTetes", h._mat_neon)

# ─── Usine désaffectée : hall bas et large + toit en dents de scie + cheminée ──
# Métal corrodé : la couleur (brun rouille) est ternie par le gradient. Hauteur
# plafonnée (jamais une tour). Faces sombres comme les bâtiments.
static func usines(h) -> void:
	if h._excel.usines.is_empty():
		return
	var s := HoloMesh3D.st()       # coque corrodée (sombre, peu de glow)
	var sf := HoloMesh3D.st_tri()
	var sn := HoloMesh3D.st()       # accents NÉON (verrières, conduits, cheminée)
	var sb := HoloMesh3D.st()       # balises rouges de cheminée (clignotent, _mat_balise)
	var su := SurfaceTool.new()    # fumée (billboards de volutes, shader holo_fumee)
	su.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x05111E
	var n := 0
	var nf := 0
	var nn := 0
	var nb := 0
	var nfu := 0
	var ch_h: float = h.unite_maison * 2.4   # hauteur de cheminée (cf. _cheminee_neon)
	for b in h._excel.usines:
		var bb: Rect2i = b["bbox"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.40, 0.30, 0.24, 0.85), centre)    # brun rouille sombre
		var neon: Color = h._moduler(Color(1.0, 0.50, 0.16), centre)           # néon orange industriel
		# Hauteur tapée honorée (sans plafond) : « 9 » sur une usine = usine de 9 m.
		# Sans chiffre, la hauteur par défaut (≈ 1 unité) garde le hall bas et large.
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var r: Array = h._bati_boite(b["cells"], haut, col, s, sf)
		n += r[0]; nf += r[1]
		nn += h._portes_vers_routes(b["cells"], minf(h.unite_maison * 0.75, haut * 0.85), neon, sn)  # entrées face aux routes
		nn += _toit_sheds_neon(h, bb, haut, neon, sn)       # verrières en dents de scie (glow)
		nn += _crete_toit(h, b["cells"], haut, neon, sn)     # contour néon du toit (le hall se lit)
		nn += _conduits_facade(h, bb, haut, neon, sn)        # tuyauterie ceinturant le hall
		nn += _rack_tuyaux(h, bb, haut, neon, sn)            # rack de conduits au-dessus du toit
		var rs: Array = _silos(h, bb, haut, col, neon, s, sf, sn)   # cuves qui percent le toit
		n += rs[0]; nf += rs[1]; nn += rs[2]
		# 3 cheminées réparties sur le grand axe du hall, chacune avec son panache.
		var x0 := float(bb.position.x); var x1 := float(bb.position.x + bb.size.x - 1)
		var y0 := float(bb.position.y); var y1 := float(bb.position.y + bb.size.y - 1)
		var span_x := bb.size.x >= bb.size.y
		for f: float in [0.2, 0.5, 0.8]:
			var gx := lerpf(x0, x1, f) if span_x else lerpf(x0, x1, 0.28)
			var gy := lerpf(y0, y1, 0.28) if span_x else lerpf(y0, y1, f)
			var cbase: Vector3 = h._world(gx, gy, haut)
			var rc: Array = _cheminee_neon(h, cbase, neon, sn, sb)
			nn += rc[0]; nb += rc[1]
			nfu += _semer_fumee(h, su, cbase + Vector3(0, ch_h + h.unite_maison * 0.12, 0), rng)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Usines")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "UsinesFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "UsinesNeon", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(sb, nb), "UsinesBalises", h._mat_balise)
	if nfu > 0:
		var miu := MeshInstance3D.new()
		miu.name = "UsinesFumee"
		miu.mesh = su.commit()
		miu.material_override = h._mat_fumee
		h._monde.add_child(miu)

# Sème un panache de fumée : des QUADS billboard (bouffées) posés au sommet, chacun
# avec sa phase et sa taille. Le shader holo_fumee les fait monter/gonfler/estomper
# en disques doux → vrai nuage de volutes (et non des traits). Renvoie le nb de tris.
static func _semer_fumee(h, s: SurfaceTool, sommet: Vector3, rng: RandomNumberGenerator) -> int:
	var coins := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var ordre := [0, 1, 2, 0, 2, 3]
	var n := 0
	for _i in 26:
		var ph := rng.randf()
		# Faible dispersion au sol → colonne serrée qui colle à la cheminée.
		var jit := Vector3((rng.randf() - 0.5) * h.taille_cellule * 0.12, 0.0,
				(rng.randf() - 0.5) * h.taille_cellule * 0.12)
		var base := sommet + jit
		var taille: float = h.taille_cellule * (0.22 + 0.12 * rng.randf())   # demi-taille de base
		var a := 0.18 + 0.16 * rng.randf()
		for idx: int in ordre:
			s.set_color(Color(1, 1, 1, a))
			s.set_uv(Vector2(ph, taille))
			s.set_uv2(coins[idx])
			s.add_vertex(base)
		n += 2
	return n

# Verrières en dents de scie (sheds industriels) ÉMISSIVES : chaque dent = montant
# vertical + crête + pente vitrée (mullions lumineux) → silhouette « usine » nette,
# qui glow. Réparties sur le grand axe.
static func _toit_sheds_neon(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var y0 := float(bb.position.y) - 0.5
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.5
	var span_x := bb.size.x >= bb.size.y
	var longn: int = bb.size.x if span_x else bb.size.y
	@warning_ignore("integer_division")
	var nb := clampi(int(longn / 2), 2, 7)
	var th: float = h.unite_maison * 0.6
	var n := 0
	for k in nb:
		var fa := float(k) / float(nb)         # début de la dent (crête haute)
		var fb := float(k + 1) / float(nb)     # fin (retombée au niveau du toit)
		var a0: Vector3; var a1: Vector3       # crête (haut)
		var b0: Vector3; var b1: Vector3       # bas (côté pente)
		var r0: Vector3; var r1: Vector3       # pied du montant (sous la crête)
		if span_x:
			var ga := lerpf(x0, x1, fa); var gb := lerpf(x0, x1, fb)
			a0 = h._world(ga, y0, haut + th); a1 = h._world(ga, y1, haut + th)
			b0 = h._world(gb, y0, haut); b1 = h._world(gb, y1, haut)
			r0 = h._world(ga, y0, haut); r1 = h._world(ga, y1, haut)
		else:
			var ga := lerpf(y0, y1, fa); var gb := lerpf(y0, y1, fb)
			a0 = h._world(x0, ga, haut + th); a1 = h._world(x1, ga, haut + th)
			b0 = h._world(x0, gb, haut); b1 = h._world(x1, gb, haut)
			r0 = h._world(x0, ga, haut); r1 = h._world(x1, ga, haut)
		n += HoloMesh3D.line(s, a0, a1, col)   # crête vitrée
		n += HoloMesh3D.line(s, r0, a0, col)   # montant vertical (la « dent »)
		n += HoloMesh3D.line(s, r1, a1, col)
		n += HoloMesh3D.line(s, r0, r1, col)   # base de la dent
		n += HoloMesh3D.line(s, a0, b0, col)   # pente vitrée
		n += HoloMesh3D.line(s, a1, b1, col)
		for m in 2:                            # mullions sur la pente (verre)
			var t := float(m + 1) / 3.0
			n += HoloMesh3D.line(s, a0.lerp(b0, t), a1.lerp(b1, t), col)
	return n

# Crête de toit NÉON : contour du toit du hall (côtés frontière du bloc, au niveau
# haut) → le volume de l'usine ressort du tissu sombre, le toit se lit de loin.
static func _crete_toit(h, cells: Array, haut: float, col: Color, s: SurfaceTool) -> int:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			n += HoloMesh3D.line(s, h._world(seg[0].x, seg[0].y, haut + 0.012),
					h._world(seg[1].x, seg[1].y, haut + 0.012), col)
	return n

# Tuyauterie industrielle : 2 conduits lumineux qui ceinturent le hall à mi-hauteur
# (anneaux périmètre) → lecture « usine » immédiate, même de loin.
static func _conduits_facade(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var y0 := float(bb.position.y) - 0.5
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.5
	var n := 0
	for yf: float in [0.42, 0.72]:
		var yy := haut * yf
		var c0: Vector3 = h._world(x0, y0, yy); var c1: Vector3 = h._world(x1, y0, yy)
		var c2: Vector3 = h._world(x1, y1, yy); var c3: Vector3 = h._world(x0, y1, yy)
		n += HoloMesh3D.line(s, c0, c1, col) + HoloMesh3D.line(s, c1, c2, col) \
				+ HoloMesh3D.line(s, c2, c3, col) + HoloMesh3D.line(s, c3, c0, col)
	return n

# Cheminée ÉMISSIVE posée en `base` (sur le toit) : fût lumineux + 2 anneaux. La
# balise rouge du sommet part dans `sb` (matériau des balises → elle CLIGNOTE au
# même rythme que les balises de tour). Renvoie [nb néon, nb balise].
static func _cheminee_neon(h, base: Vector3, col: Color, s: SurfaceTool, sb: SurfaceTool) -> Array:
	var w: float = h.taille_cellule * 0.16
	var ch: float = h.unite_maison * 2.4
	var n := HoloMesh3D.box(s, base, w, ch, w, col)
	for rf: float in [0.55, 0.8]:
		n += HoloMesh3D.circle(s, base + Vector3(0, ch * rf, 0), w * 0.95, col, 10)
	var nb := HoloMesh3D.diamond(sb, base + Vector3(0, ch + w, 0), w * 0.7, w * 0.9, Color(1.0, 0.32, 0.20))
	return [n, nb]

# Rack de tuyauterie AU-DESSUS du toit : 2 conduits parallèles sur potelets, le
# long du grand axe (même ligne que les cheminées, au-dessus des crêtes de sheds)
# → colonne vertébrale industrielle qui relie les cheminées.
static func _rack_tuyaux(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x); var x1 := float(bb.position.x + bb.size.x - 1)
	var y0 := float(bb.position.y); var y1 := float(bb.position.y + bb.size.y - 1)
	var span_x := bb.size.x >= bb.size.y
	var ry: float = haut + h.unite_maison * 0.75   # au-dessus des crêtes (0.6)
	var ecart := 0.09                               # demi-écart des 2 conduits (cellules)
	var lat := 0.28                                 # même ligne latérale que les cheminées
	var a0: Vector3; var a1: Vector3; var b0: Vector3; var b1: Vector3
	if span_x:
		var gy := lerpf(y0, y1, lat)
		a0 = h._world(lerpf(x0, x1, 0.06), gy - ecart, ry); a1 = h._world(lerpf(x0, x1, 0.94), gy - ecart, ry)
		b0 = h._world(lerpf(x0, x1, 0.06), gy + ecart, ry); b1 = h._world(lerpf(x0, x1, 0.94), gy + ecart, ry)
	else:
		var gx := lerpf(x0, x1, lat)
		a0 = h._world(gx - ecart, lerpf(y0, y1, 0.06), ry); a1 = h._world(gx - ecart, lerpf(y0, y1, 0.94), ry)
		b0 = h._world(gx + ecart, lerpf(y0, y1, 0.06), ry); b1 = h._world(gx + ecart, lerpf(y0, y1, 0.94), ry)
	var n := HoloMesh3D.line(s, a0, a1, col) + HoloMesh3D.line(s, b0, b1, col)
	var nbp := clampi(maxi(bb.size.x, bb.size.y), 3, 8)
	for k in nbp + 1:                              # potelets + traverses régulières
		var t := float(k) / float(nbp)
		var pa := a0.lerp(a1, t)
		var pb := b0.lerp(b1, t)
		n += HoloMesh3D.line(s, Vector3(pa.x, haut, pa.z), pa, col)
		n += HoloMesh3D.line(s, Vector3(pb.x, haut, pb.z), pb, col)
		n += HoloMesh3D.line(s, pa, pb, col)
	return n

# Cuves de stockage (silos) : 2 cylindres côté opposé aux cheminées, qui PERCENT
# le toit (la partie basse est occluse par le hall) — coiffe + cerclages néon.
# Renvoie [nb arêtes coque, nb faces, nb néon].
static func _silos(h, bb: Rect2i, haut: float, col: Color, neon: Color,
		s: SurfaceTool, sf: SurfaceTool, sn: SurfaceTool) -> Array:
	var x0 := float(bb.position.x); var x1 := float(bb.position.x + bb.size.x - 1)
	var y0 := float(bb.position.y); var y1 := float(bb.position.y + bb.size.y - 1)
	var span_x := bb.size.x >= bb.size.y
	var r: float = h.taille_cellule * 0.26
	var sh: float = haut + h.unite_maison * 1.05   # dépasse nettement du toit
	var n := 0
	var nf := 0
	var nn := 0
	for f: float in [0.34, 0.56]:
		var gx := lerpf(x0, x1, f) if span_x else lerpf(x0, x1, 0.74)
		var gy := lerpf(y0, y1, 0.74) if span_x else lerpf(y0, y1, f)
		var c: Vector3 = h._world(gx, gy, 0.0)
		n += HoloMesh3D.cylinder(s, c, r, r, sh, col, 14, 5)
		nf += HoloMesh3D.cylinder_faces(sf, c, r * 0.96, r * 0.96, sh, 14)
		for rf: float in [0.62, 0.82]:             # cerclages (au-dessus du toit)
			nn += HoloMesh3D.ellipse(sn, c + Vector3(0, sh * rf, 0), r * 1.03, r * 1.03, neon, 14)
		nn += HoloMesh3D.ellipse(sn, c + Vector3(0, sh, 0), r * 0.55, r * 0.55, neon, 12)   # coiffe
	return [n, nf, nn]

# ─── Casse auto : enclos grillagé + épaves de voitures + piles de carcasses + grue ──
# Lecture « casse de bagnoles » : clôture basse (rail néon de sécurité), vraies épaves
# (caisse + cabine + phare), piles de carcasses ÉCRASÉES (dalles empilées), et une grue
# à électro-aimant ANIMÉE (prise/dépose de carcasses en boucle, cf. _grue_casse).
# Deux couches : structure sombre + accents glow (néon).
static func casses(h) -> void:
	if h._excel.casses.is_empty():
		return
	var s := HoloMesh3D.st()       # structure sombre (clôture, caisses, dalles)
	var sg := HoloMesh3D.st()      # accents NÉON (rail, phares, aimant de grue)
	var n := 0
	var ng := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0xCA55E
	for b in h._excel.casses:
		var centre: Vector3 = h._centre_bbox(b["bbox"])
		var col: Color = h._moduler(Color(0.52, 0.33, 0.16, 0.95), centre)   # tôle rouille sombre
		var neon: Color = h._moduler(Color(1.0, 0.55, 0.18), centre)          # néon ambre-rouille (glow)
		var fy: float = maxf(0.3, b["hauteur_m"] / maxf(0.5, h._excel.hauteur_defaut_m))
		var hw: float = h.unite_maison * 1.15 * fy
		# Clôture d'enceinte HAUTE (poteaux + grillage) + rail néon + PORTAIL d'entrée
		# intégré à la clôture sur le côté donnant sur une route.
		var rc := _cloture_casse(h, b["cells"], hw, col, neon, s, sg)
		n += rc[0]; ng += rc[1]
		# Grues à aimant : une au plus central du bloc, une DEUXIÈME au plus loin de
		# la première (flèche orientée différemment) si le bloc est assez grand.
		var cells: Array = b["cells"]
		var cell_grue := Vector2i(-9999, -9999)
		if cells.size() >= 6:
			var bb: Rect2i = b["bbox"]
			var gcx := bb.position.x + (bb.size.x - 1) * 0.5
			var gcy := bb.position.y + (bb.size.y - 1) * 0.5
			var best := 1.0e9
			for cell: Vector2i in cells:
				var dd := Vector2(float(cell.x) - gcx, float(cell.y) - gcy).length_squared()
				if dd < best:
					best = dd; cell_grue = cell
		var cell_grue2 := Vector2i(-9999, -9999)
		if cells.size() >= 10:
			var best2 := -1.0
			for cell: Vector2i in cells:
				if cell == cell_grue:
					continue
				var dd2 := Vector2(float(cell.x - cell_grue.x), float(cell.y - cell_grue.y)).length_squared()
				if dd2 > best2:
					best2 = dd2; cell_grue2 = cell
		# Remplissage ORGANISÉ (comme une vraie casse) : MURS de carcasses empilées
		# adossés à la clôture (cases frontière), épaves éparses + piles de pneus
		# dans les allées intérieures, grue au centre.
		var setd := {}
		for cell: Vector2i in cells:
			setd[cell] = true
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for cell: Vector2i in cells:
			var c: Vector3 = h._world(cell.x, cell.y, 0.0)
			if cell == cell_grue or cell == cell_grue2:
				# Flèche orientée VERS L'INTÉRIEUR de l'enclos (jamais au-dessus de la
				# clôture) : chaque grue vise le centre du bloc depuis son pied.
				var vers_centre := Vector3(centre.x - c.x, 0.0, centre.z - c.z)
				var tang := vers_centre.normalized() if vers_centre.length() > h.taille_cellule * 0.3 \
						else Vector3(1, 0, 0)
				var rg := _grue_casse(h, c, col, neon, s, sg, tang)
				n += rg[0]; ng += rg[1]
				continue
			var frontiere := false
			for d: Vector2i in dirs:
				if not setd.has(cell + d):
					frontiere = true
					break
			var roll := rng.randf()
			if frontiere:
				if roll < 0.72:      # mur de carcasses le long de la clôture
					var rp := _pile_carcasses(h, c, col, neon, rng, s, sg)
					n += rp[0]; ng += rp[1]
				elif roll < 0.88:
					var re := _epave_voiture(h, c, col, neon, rng, s, sg)
					n += re[0]; ng += re[1]
			else:
				if roll < 0.45:
					var re := _epave_voiture(h, c, col, neon, rng, s, sg)
					n += re[0]; ng += re[1]
				elif roll < 0.64:    # stock de pneus dans les allées
					n += _pile_pneus(h, c, col, rng, s)
			# sinon : case laissée vide (allée de circulation entre les tas)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Casses")
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "CassesNeon", h._mat_neon)

# Clôture d'une casse : poteaux aux coins de chaque côté frontière + grillage (trame
# en X discrète) + rail NÉON au sommet (lisibilité « enclos »). Le premier côté
# frontière donnant sur une ROUTE reçoit le PORTAIL d'entrée à la place du grillage.
# Renvoie [arêtes, glow].
static func _cloture_casse(h, cells: Array, hw: float, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var ng := 0
	var up := Vector3(0, hw, 0)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Côté du portail : premier côté frontière dont le voisin est une route.
	var porte_cell := Vector2i(-9999, -9999)
	var porte_dir := Vector2i.ZERO
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if not setd.has(c + d) and h._routes_set.has(c + d):
				porte_cell = c
				porte_dir = d
				break
		if porte_cell.x > -9000:
			break
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
			var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
			if c == porte_cell and d == porte_dir:
				ng += _portail_casse(h, a0, b0, hw, neon, sg)
				continue   # le portail remplace le grillage sur ce segment
			n += HoloMesh3D.line(s, a0, b0, col)             # lisse basse (sol)
			n += HoloMesh3D.line(s, a0, a0 + up, col)        # poteau A
			n += HoloMesh3D.line(s, b0, b0 + up, col)        # poteau B
			n += HoloMesh3D.line(s, a0, b0 + up, col)        # grillage (croix)
			n += HoloMesh3D.line(s, b0, a0 + up, col)
			ng += HoloMesh3D.line(sg, a0 + up, b0 + up, neon)  # rail néon de sécurité (sommet)
	return [n, ng]

# Portail d'entrée de la casse (segment a0→b0 face à une route) : deux poteaux hauts
# reliés par un portique, enseigne suspendue au portique, et deux vantaux grillagés à
# écharpe diagonale entrouverts au centre. Tout en néon (glow). Renvoie le nb d'arêtes.
static func _portail_casse(h, a0: Vector3, b0: Vector3, hw: float, col: Color, s: SurfaceTool) -> int:
	var mid := (a0 + b0) * 0.5
	var half := (b0 - a0) * 0.5
	var jl := mid - half * 0.84   # poteau gauche
	var jr := mid + half * 0.84   # poteau droit
	var ph := hw * 1.35           # poteaux plus hauts que la clôture
	var w: float = h.taille_cellule * 0.08
	var n := 0
	for p: Vector3 in [jl, jr]:
		n += HoloMesh3D.box(s, p, w, ph, w, col)
	# Portique (traverse haute) reliant les poteaux.
	n += HoloMesh3D.line(s, jl + Vector3(0, ph, 0), jr + Vector3(0, ph, 0), col)
	# Enseigne suspendue sous le portique (cadre + barre de « texte »).
	var e0 := mid - half * 0.34 + Vector3(0, ph, 0)
	var e1 := mid + half * 0.34 + Vector3(0, ph, 0)
	var eh := hw * 0.22
	n += HoloMesh3D.line(s, e0, e0 - Vector3(0, eh, 0), col)
	n += HoloMesh3D.line(s, e1, e1 - Vector3(0, eh, 0), col)
	n += HoloMesh3D.line(s, e0 - Vector3(0, eh, 0), e1 - Vector3(0, eh, 0), col)
	n += HoloMesh3D.line(s, e0 - Vector3(0, eh * 0.5, 0), e1 - Vector3(0, eh * 0.5, 0), col)
	# Deux vantaux coulissants (cadre + écharpe), entrouverts au centre (~20 % du côté).
	var gh := hw * 0.85
	for cote: Array in [[jl, mid - half * 0.10], [jr, mid + half * 0.10]]:
		var p0: Vector3 = cote[0]
		var p1: Vector3 = cote[1]
		var vup := Vector3(0, gh, 0)
		n += HoloMesh3D.line(s, p0, p1, col)
		n += HoloMesh3D.line(s, p0 + vup, p1 + vup, col)
		n += HoloMesh3D.line(s, p1, p1 + vup, col)
		n += HoloMesh3D.line(s, p0, p1 + vup, col)   # écharpe diagonale
	return n

# Pile de carcasses ÉCRASÉES : 2 à 4 dalles très plates empilées (cube de ferraille),
# une arête néon une dalle sur deux → on distingue chaque voiture. Renvoie [arêtes, glow].
static func _pile_carcasses(h, c: Vector3, col: Color, neon: Color, rng: RandomNumberGenerator, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var n := 0
	var ng := 0
	var nb := 2 + rng.randi() % 3
	var y := 0.0
	for k in nb:
		var w: float = h.taille_cellule * lerpf(0.42, 0.54, rng.randf())
		var d := w * lerpf(0.62, 0.80, rng.randf())
		var hh: float = h.unite_maison * lerpf(0.10, 0.16, rng.randf())   # dalle aplatie (voiture compactée)
		var ox: float = (rng.randf() - 0.5) * h.taille_cellule * 0.07
		var oz: float = (rng.randf() - 0.5) * h.taille_cellule * 0.07
		var p := c + Vector3(ox, y, oz)
		n += HoloMesh3D.box(s, p, w, hh, d, col)
		if k % 2 == 1:   # liseré néon de séparation → lecture « voitures distinctes empilées »
			ng += HoloMesh3D.line(sg, p + Vector3(-w * 0.5, hh * 0.5, 0),
					p + Vector3(w * 0.5, hh * 0.5, 0), neon)
		y += hh + h.unite_maison * 0.015
	return [n, ng]

# Carrosserie futuriste (coque en goutte d'eau effilée + bulle de cockpit facettée)
# centrée en `c`, orientée selon `tang`. Silhouette PARTAGÉE : épave posée au sol
# et carcasse suspendue à la grue. Renvoie le nb d'arêtes.
static func _carrosserie(h, c: Vector3, tang: Vector3, col: Color, s: SurfaceTool) -> int:
	var perp := Vector3(-tang.z, 0.0, tang.x)
	var hl: float = h.taille_cellule * 0.22    # demi-longueur
	var hw: float = h.taille_cellule * 0.10    # demi-largeur (au maître-bau)
	var ht: float = h.taille_cellule * 0.085   # hauteur de la bulle
	var up := Vector3(0, ht, 0)
	# Empreinte en goutte d'eau (identique au trafic : nez / maître-bau / poupe).
	var nez := c + tang * hl
	var ml := c + tang * (hl * 0.18) - perp * hw
	var mr := c + tang * (hl * 0.18) + perp * hw
	var pl := c - tang * hl - perp * (hw * 0.45)
	var pr := c - tang * hl + perp * (hw * 0.45)
	var n := 0
	n += HoloMesh3D.line(s, nez, mr, col)
	n += HoloMesh3D.line(s, mr, pr, col)
	n += HoloMesh3D.line(s, pr, pl, col)
	n += HoloMesh3D.line(s, pl, ml, col)
	n += HoloMesh3D.line(s, ml, nez, col)
	# Bulle de cockpit facettée (apex bas, légèrement reculé).
	var apex := c - tang * (hl * 0.08) + up
	var poupe := (pl + pr) * 0.5
	n += HoloMesh3D.line(s, apex, nez, col)
	n += HoloMesh3D.line(s, apex, ml, col)
	n += HoloMesh3D.line(s, apex, mr, col)
	n += HoloMesh3D.line(s, apex, poupe, col)
	return n

# Épave de voiture posée au sol, orientée le long de X ou Y au hasard, phare néon
# à l'avant (petite balise → « c'est une voiture »). Renvoie [arêtes, glow].
static func _epave_voiture(h, c: Vector3, col: Color, neon: Color, rng: RandomNumberGenerator, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var tang := Vector3(0, 0, 1) if rng.randf() < 0.5 else Vector3(1, 0, 0)
	var n := _carrosserie(h, c, tang, col, s)
	var ng := HoloMesh3D.diamond(sg, c + tang * (h.taille_cellule * 0.22) + Vector3(0, h.taille_cellule * 0.02, 0),
			h.taille_cellule * 0.04, h.taille_cellule * 0.045, neon)
	return [n, ng]

# Pile de pneus : 2 à 4 anneaux empilés, léger désaxage → stock de pneus d'allée.
static func _pile_pneus(h, c: Vector3, col: Color, rng: RandomNumberGenerator, s: SurfaceTool) -> int:
	var n := 0
	var r: float = h.taille_cellule * 0.10
	var nb := 2 + rng.randi() % 3
	var eh: float = h.unite_maison * 0.09
	var y := eh * 0.5
	for _k in nb:
		var p := c + Vector3((rng.randf() - 0.5) * r * 0.5, y, (rng.randf() - 0.5) * r * 0.5)
		n += HoloMesh3D.circle(s, p, r, col, 10)
		y += eh
	return n

# Grue à électro-aimant ANIMÉE : mât treillis statique + TOURELLE pivotante
# (flèche, contrepoids, câble, aimant, carcasse) en Node3D dédiés, animés par un
# Tween EN BOUCLE : descente du câble → prise d'une carcasse → levée → rotation →
# dépose → retour à vide. La casse vit. Renvoie [arêtes, glow] (statique seul —
# les parties mobiles portent leurs propres meshes). `tang` = direction de départ
# de la flèche (vers l'intérieur de l'enclos, le débattement reste autour d'elle).
static func _grue_casse(h, base: Vector3, col: Color, neon: Color, s: SurfaceTool, _sg: SurfaceTool,
		tang: Vector3 = Vector3(1, 0, 0)) -> Array:
	var n := 0
	var tc: float = h.taille_cellule
	var mw: float = tc * 0.10
	var mh: float = h.unite_maison * 2.6
	n += HoloMesh3D.box(s, base, mw, mh, mw, col)              # mât (statique)
	# ── Tourelle : tout ce qui bouge, en coords LOCALES (flèche le long de +X) ──
	var tourelle := Node3D.new()
	tourelle.name = "GrueTourelle"
	tourelle.position = base + Vector3(0, mh, 0)
	var yaw0 := atan2(-tang.z, tang.x)
	var sweep := 0.75                       # demi-débattement (rad) autour de `tang`
	tourelle.rotation.y = yaw0 - sweep      # départ : au-dessus du tas de prise
	h._monde.add_child(tourelle)
	var fl: float = tc * 0.9                                   # longueur de flèche
	var tip := Vector3(fl, 0, 0)
	var back := Vector3(-tc * 0.32, 0, 0)
	var knee := Vector3(0, -mh * 0.16, 0)
	var sd := HoloMesh3D.st()
	var nd := 0
	nd += HoloMesh3D.line(sd, back, tip, col)                  # membrure haute de la flèche
	nd += HoloMesh3D.line(sd, knee, tip, col)                  # treillis avant
	nd += HoloMesh3D.line(sd, knee, back, col)                 # treillis arrière
	nd += HoloMesh3D.box(sd, back + Vector3(0, -tc * 0.16, 0),
			tc * 0.16, tc * 0.18, tc * 0.16, col)              # contrepoids
	var fleche := MeshInstance3D.new()
	fleche.name = "Fleche"
	fleche.mesh = HoloMesh3D.commit(sd, nd)
	fleche.material_override = h._mat_decor
	tourelle.add_child(fleche)
	# Câble : ligne UNITAIRE (0 → −1) pendue au bout de flèche, étirée via scale.y.
	var scab := HoloMesh3D.st()
	HoloMesh3D.line(scab, Vector3.ZERO, Vector3(0, -1, 0), neon)
	var cable := MeshInstance3D.new()
	cable.name = "Cable"
	cable.mesh = HoloMesh3D.commit(scab, 1)
	cable.material_override = h._mat_neon
	cable.position = tip
	tourelle.add_child(cable)
	# Chariot au bout du câble : électro-aimant (glow) + carcasse saisie (cachée à vide).
	var chariot := Node3D.new()
	chariot.name = "Chariot"
	tourelle.add_child(chariot)
	var sa := HoloMesh3D.st()
	var na := HoloMesh3D.box(sa, Vector3.ZERO, tc * 0.20, tc * 0.10, tc * 0.20, neon)
	var aimant := MeshInstance3D.new()
	aimant.name = "Aimant"
	aimant.mesh = HoloMesh3D.commit(sa, na)
	aimant.material_override = h._mat_neon
	chariot.add_child(aimant)
	var sc := HoloMesh3D.st()
	var nc := _carrosserie(h, Vector3(0, -tc * 0.16, 0), Vector3(0, 0, 1), col, sc)
	var carcasse := MeshInstance3D.new()
	carcasse.name = "Carcasse"
	carcasse.mesh = HoloMesh3D.commit(sc, nc)
	carcasse.material_override = h._mat_decor
	carcasse.visible = false
	chariot.add_child(carcasse)
	# ── Boucle de travail (Tween infini) : prise → levée → rotation → dépose ──
	var up: float = mh * 0.5      # câble relevé (course de croisière)
	var low: float = mh * 0.92    # câble déroulé (l'aimant frôle le sol)
	cable.scale = Vector3(1, up, 1)
	chariot.position = tip + Vector3(0, -up, 0)
	# Phase/durées légèrement variées par grue (hash de la base) → jamais synchrones.
	var ph: float = h._hash01(Vector2i(int(base.x * 37.0), int(base.z * 37.0)), 7)
	var t_cab := 1.3 + 0.3 * ph
	var t_rot := 2.0 + 0.5 * ph
	var tw := tourelle.create_tween().set_loops()
	tw.tween_interval(0.4 + ph)
	_grue_cable(tw, cable, chariot, up, low, t_cab)            # descend sur le tas
	tw.tween_callback(func() -> void: carcasse.visible = true)  # l'aimant accroche
	tw.tween_interval(0.35)
	_grue_cable(tw, cable, chariot, low, up, t_cab)            # remonte chargé
	tw.tween_property(tourelle, "rotation:y", yaw0 + sweep, t_rot) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_grue_cable(tw, cable, chariot, up, low, t_cab)            # descend pour déposer
	tw.tween_callback(func() -> void: carcasse.visible = false) # lâche la carcasse
	tw.tween_interval(0.35)
	_grue_cable(tw, cable, chariot, low, up, t_cab)            # remonte à vide
	tw.tween_property(tourelle, "rotation:y", yaw0 - sweep, t_rot) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return [n, 0]

# Ajoute au tween la course du câble : la ligne unitaire s'étire (scale.y) pendant
# que le chariot (aimant + carcasse) suit son extrémité — les deux en parallèle.
static func _grue_cable(tw: Tween, cable: MeshInstance3D, chariot: Node3D, de: float, vers: float, dur: float) -> void:
	tw.tween_property(cable, "scale:y", vers, dur).from(de) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(chariot, "position:y", -vers, dur).from(-de) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ─── Supermarché / hypermarché : volume bas + DÉBAUCHE d'enseignes lumineuses ──
# Coque basse sombre noyée sous le néon : bandeau-marquee qui ceinture tout le toit,
# grille lumineuse de verrières au sommet, panneau géant dressé sur le toit, et entrée
# illuminée en façade. C'est le néon (ambre + cyan) qui porte l'identité, pas la boîte.
static func supermarches(h) -> void:
	if h._excel.supermarches.is_empty():
		return
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var sn := HoloMesh3D.st()   # enseignes ambre (glow)
	var sc := HoloMesh3D.st()   # accents cyan (glow)
	var sgl := HoloMesh3D.st_tri()   # nappes de lumière chaude (ambiance)
	var n := 0
	var nf := 0
	var nn := 0
	var ncy := 0
	var ngl := 0
	for b in h._excel.supermarches:
		var bb: Rect2i = b["bbox"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.36, 0.37, 0.44, 0.85), centre)   # coque béton sombre
		var ambre: Color = h._moduler(Color(1.0, 0.60, 0.18), centre)
		var cyan: Color = h._moduler(Color(0.32, 0.95, 1.0), centre)
		# Hauteur tapée honorée (sans plafond) ; défaut bas → volume étalé d'hyper.
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var r: Array = h._bati_boite(b["cells"], haut, col, s, sf)
		n += r[0]; nf += r[1]
		nn += _enseignes_marquee(h, bb, haut, ambre, sn)        # bandeau lumineux périmètre
		# Panneau de toit : prop de l'artiste si présent, sinon procédural (secours).
		# Le prop vit dans son propre mesh → matériau néon doux dédié (_mat_prop),
		# ou plat en mode brut (calibrage DA).
		var prop: Dictionary = Props.aretes("supermarche_panneau_toit")
		if prop.is_empty():
			nn += _billboard_toit(h, bb, haut, ambre, cyan, sn, sc)
		else:
			var sp := HoloMesh3D.st()
			var spf := HoloMesh3D.st_tri()
			var rp: Array = _prop_sur_toit(h, prop, b["cells"], bb, haut, ambre, cyan, sp, sp, spf)
			h._ajouter_mesh(HoloMesh3D.commit(sp, rp[0] + rp[1]), "SupermarchesProp",
					h._mat_prop if PROP_NEON else _mat_brut())
			h._ajouter_mesh(HoloMesh3D.commit(spf, rp[2]), "SupermarchesPropFond",
					h._mat_prop_fond if PROP_NEON else _mat_brut())
		ncy += _toit_skylights(h, bb, haut, cyan, sc)           # grille de verrières (toit)
		var rcvc: Array = _cvc_toit(h, bb, haut, col, s, sf)    # blocs techniques sur le toit
		n += rcvc[0]; nf += rcvc[1]
		# Entrée principale ORIENTÉE vers la route (atrium vitré + auvent + tapis
		# d'accueil) + TOTEM publicitaire dressé au bord de cette même route.
		var ent := _cote_entree(h, b["cells"])
		ncy += _entree_facade(h, ent, haut, cyan, sc)
		var rt: Array = _totem_enseigne(h, ent, haut, ambre, cyan, sn, sc)
		nn += rt[0]; ncy += rt[1]
		ngl += _ambiance_supermarche(h, bb, haut, ambre, sgl)   # lueur intérieure + débord au sol
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Supermarches")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "SupermarchesFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "SupermarchesEnseignes", h._mat_enseigne)
	h._ajouter_mesh(HoloMesh3D.commit(sc, ncy), "SupermarchesAccents", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(sgl, ngl), "SupermarchesAmbiance", h._mat_glow_chaud)

# Ambiance lumineuse : une nappe chaude à l'intérieur du volume (le magasin « éclairé »)
# + une nappe au sol qui déborde (light spill ambré sur le parvis). Additif → halo.
static func _ambiance_supermarche(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var y0 := float(bb.position.y) - 0.5
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.5
	var n := 0
	# Lueur intérieure (plan chaud baignant le volume, vu à travers le wireframe).
	n += _quad_plat(h, s, x0, y0, x1, y1, haut * 0.45, Color(col.r, col.g, col.b, 0.16))
	# Débord lumineux au sol (le magasin éclaire ses abords).
	var m := 0.7
	n += _quad_plat(h, s, x0 - m, y0 - m, x1 + m, y1 + m, 0.016, Color(col.r, col.g, col.b, 0.09))
	return n

# Quad plat (2 triangles) dans le plan XZ aux coins de grille (x0,y0)-(x1,y1), à
# hauteur `yy`. Couleur uniforme (vertex color → émission additive).
static func _quad_plat(h, s: SurfaceTool, x0: float, y0: float, x1: float, y1: float, yy: float, col: Color) -> int:
	var p0: Vector3 = h._world(x0, y0, yy); var p1: Vector3 = h._world(x1, y0, yy)
	var p2: Vector3 = h._world(x1, y1, yy); var p3: Vector3 = h._world(x0, y1, yy)
	for v in [p0, p1, p2, p0, p2, p3]:
		s.set_color(col); s.add_vertex(v)
	return 2

# Bandeau-marquee : double rail lumineux sur TOUT le périmètre du toit + ampoules
# verticales rapprochées → enseigne commerciale qui ceinture le magasin.
static func _enseignes_marquee(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var y0 := float(bb.position.y) - 0.5
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.5
	var band: float = h.unite_maison * 0.45
	var n := 0
	for yy: float in [haut, haut + band]:   # rails haut/bas du bandeau, périmètre complet
		var c0: Vector3 = h._world(x0, y0, yy); var c1: Vector3 = h._world(x1, y0, yy)
		var c2: Vector3 = h._world(x1, y1, yy); var c3: Vector3 = h._world(x0, y1, yy)
		n += HoloMesh3D.line(s, c0, c1, col) + HoloMesh3D.line(s, c1, c2, col) \
				+ HoloMesh3D.line(s, c2, c3, col) + HoloMesh3D.line(s, c3, c0, col)
	# Ampoules : montants verticaux serrés le long des 4 arêtes.
	var aretes := [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]]
	for e: Array in aretes:
		var steps := 6
		for k in range(steps + 1):
			var t := float(k) / float(steps)
			var px := lerpf(e[0], e[2], t)
			var py := lerpf(e[1], e[3], t)
			n += HoloMesh3D.line(s, h._world(px, py, haut), h._world(px, py, haut + band), col)
	return n

# Verrières de toit : grille lumineuse fine posée à plat sur le toit (skylights / blocs
# de clim) → lecture « grande surface » vue du dessus.
static func _toit_skylights(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.4
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.4
	var y0 := float(bb.position.y) - 0.4
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.4
	var yy := haut + 0.012
	var n := 0
	var nx := clampi(bb.size.x, 2, 8)
	var ny := clampi(bb.size.y, 2, 8)
	for k in range(nx + 1):
		var gx := lerpf(x0, x1, float(k) / float(nx))
		n += HoloMesh3D.line(s, h._world(gx, y0, yy), h._world(gx, y1, yy), col)
	for k in range(ny + 1):
		var gy := lerpf(y0, y1, float(k) / float(ny))
		n += HoloMesh3D.line(s, h._world(x0, gy, yy), h._world(x1, gy, yy), col)
	return n

# Flag de CALIBRAGE DA : true = les props artistes reçoivent le néon doux dédié
# (_mat_prop : émission moitié des enseignes, sans cœur blanc) ; false = lignes
# plates unshaded (aucun effet) pour juger la géométrie brute.
const PROP_NEON := true

# Matériau plat du mode brut : ALBEDO = couleur de sommet, rien d'autre
# (en GL Compatibility, unshaded affiche l'ALBEDO tel quel). Sans culling :
# sert aussi aux triangles `fond`, lisibles des deux côtés.
static func _mat_brut() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ─── Prop artiste posé sur un toit ────────────────────────────
# Fraction du PETIT côté du toit que le prop doit occuper : l'échelle est
# PROPORTIONNELLE AU BÂTIMENT (agrandit comme réduit) — à l'échelle réelle
# « mètres », le prop disparaissait face aux volumes exagérés de la ville.
const PROP_EMPRISE_TOIT := 0.85

# Pose un prop .glb (holo_props) au centre du toit, face « texte » (+Z local,
# cf. SPECS_ASSETS.md) tournée vers la route d'entrée. Échelle UNIFORME (les
# proportions de l'artiste sont gardées — pas le rail vertical exagéré ×2,5),
# dimensionnée dynamiquement : la plus grande emprise horizontale du prop =
# PROP_EMPRISE_TOIT × petit côté du toit. Le prop est recentré et son pied posé
# sur le toit via son AABB (robuste aux pivots approximatifs). Les arêtes cadre
# (ambre) / texte (cyan) partent en lignes néon ; les triangles `fond` partent
# dans `sf` (plaque sombre opaque, matériau h._mat_prop_fond).
# Renvoie [nb lignes cadre, nb lignes texte, nb triangles fond].
static func _prop_sur_toit(h, prop: Dictionary, cells: Array, bb: Rect2i, haut: float,
		ambre: Color, cyan: Color, sn: SurfaceTool, sc: SurfaceTool, sf: SurfaceTool) -> Array:
	var aabb: AABB = prop["aabb"]
	var sg: float = h.taille_cellule / METRES_PAR_CASE   # mètres → monde (échelle sol)
	var toit: float = float(mini(bb.size.x, bb.size.y)) * h.taille_cellule
	sg *= toit * PROP_EMPRISE_TOIT / maxf(0.001, maxf(aabb.size.x, aabb.size.z) * sg)
	var sv: float = sg
	var ent := _cote_entree(h, cells)
	var dir: Vector2i = ent["dir"]
	var ay := atan2(float(dir.x), float(dir.y))          # +Z local → vers la route
	var base: Vector3 = h._centre_bbox(bb)
	base.y = haut
	var centre := aabb.get_center()
	var n := [0, 0, 0]
	var groupes: Array = [["cadre", ambre, sn], ["texte", cyan, sc]]
	for gi in groupes.size():
		var pts: PackedVector3Array = prop[groupes[gi][0]]
		var col: Color = groupes[gi][1]
		var s: SurfaceTool = groupes[gi][2]
		for i in range(0, pts.size(), 2):
			n[gi] += HoloMesh3D.line(s,
					_prop_pt(pts[i], centre, aabb, ay, sg, sv, base),
					_prop_pt(pts[i + 1], centre, aabb, ay, sg, sv, base), col)
	var fond: PackedVector3Array = prop.get("fond", PackedVector3Array())
	var col_fond := Color(0.04, 0.05, 0.09)   # visible seulement en mode brut (vertex color)
	for i in range(0, fond.size() - 2, 3):
		for j in 3:
			sf.set_color(col_fond)
			sf.add_vertex(_prop_pt(fond[i + j], centre, aabb, ay, sg, sv, base))
		n[2] += 1
	return n

# Point local du prop (mètres) → monde : recentrage XZ, pied calé sur le toit,
# rotation Y, puis échelles sol/verticale distinctes.
static func _prop_pt(p: Vector3, centre: Vector3, aabb: AABB, ay: float,
		sg: float, sv: float, base: Vector3) -> Vector3:
	var l := Vector3(p.x - centre.x, p.y - aabb.position.y, p.z - centre.z)
	l = l.rotated(Vector3.UP, ay)
	return base + Vector3(l.x * sg, l.y * sv, l.z * sg)

# Panneau publicitaire géant dressé sur le toit (plan XY, centré) : cadre ambre +
# barres horizontales cyan (le « texte » de l'enseigne) → totem visible de loin.
# SECOURS : utilisé seulement si le prop artiste supermarche_panneau_toit.glb est absent.
static func _billboard_toit(h, bb: Rect2i, haut: float, col: Color, col2: Color, s: SurfaceTool, sc: SurfaceTool) -> int:
	var c: Vector3 = h._centre_bbox(bb)
	var bw: float = maxf(h.taille_cellule * 1.2, float(mini(bb.size.x, bb.size.y)) * h.taille_cellule * 0.55)
	var bh: float = h.unite_maison * 1.7
	var y := haut
	var p0 := c + Vector3(-bw * 0.5, y, 0)
	var p1 := c + Vector3(bw * 0.5, y, 0)
	var p2 := c + Vector3(bw * 0.5, y + bh, 0)
	var p3 := c + Vector3(-bw * 0.5, y + bh, 0)
	var n := HoloMesh3D.line(s, p0, p1, col) + HoloMesh3D.line(s, p1, p2, col) \
			+ HoloMesh3D.line(s, p2, p3, col) + HoloMesh3D.line(s, p3, p0, col)
	# Béquilles obliques vers l'arrière (le panneau ne flotte plus au-dessus du toit).
	for sx: float in [-0.30, 0.30]:
		n += HoloMesh3D.line(s, c + Vector3(bw * sx, y + bh * 0.8, 0),
				c + Vector3(bw * sx, y, bw * 0.22), col)
	for m in 2:   # barres « texte » cyan
		var t := float(m + 1) / 3.0
		HoloMesh3D.line(sc, c + Vector3(-bw * 0.38, y + bh * t, 0), c + Vector3(bw * 0.38, y + bh * t, 0), col2)
	return n

# Côté d'entrée d'un bloc : direction frontière la plus EXPOSÉE à la route (le plus
# de cases donnant sur une route) + case médiane de ce linéaire. Sans route adjacente,
# premier côté frontière trouvé. Renvoie {"cell": Vector2i, "dir": Vector2i}.
static func _cote_entree(h, cells: Array) -> Dictionary:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var best_d := Vector2i.ZERO
	var best: Array = []
	for d: Vector2i in dirs:
		var arr: Array = []
		for c: Vector2i in cells:
			if not setd.has(c + d) and h._routes_set.has(c + d):
				arr.append(c)
		if arr.size() > best.size():
			best = arr
			best_d = d
	if best.is_empty():
		for c: Vector2i in cells:
			for d: Vector2i in dirs:
				if not setd.has(c + d):
					return {"cell": c, "dir": d}
		return {"cell": cells[0], "dir": Vector2i(0, 1)}
	var horiz := best_d.y != 0
	best.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x < b.x) if horiz else (a.y < b.y))
	@warning_ignore("integer_division")
	var milieu := best.size() / 2
	return {"cell": best[milieu], "dir": best_d}

# Entrée principale : ATRIUM vitré sur le côté d'entrée (montants serrés + linteau)
# coiffé d'un AUVENT débordant vers le trottoir sur béquilles obliques, et tapis
# d'accueil lumineux qui traverse le parvis vers la route.
static func _entree_facade(h, ent: Dictionary, haut: float, col: Color, s: SurfaceTool) -> int:
	var cmid: Vector2i = ent["cell"]
	var d: Vector2i = ent["dir"]
	var seg: Array = h._cote_cellule(cmid, d)
	var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
	var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
	var out := Vector3(float(d.x), 0.0, float(d.y))
	var eh := haut * 0.72
	var n := 0
	# Vitrine : montants verticaux serrés + linteau (la façade s'ouvre en verre).
	for k in 6:
		var t := lerpf(0.06, 0.94, float(k) / 5.0)
		var p := a0.lerp(b0, t)
		n += HoloMesh3D.line(s, p + Vector3(0, 0.02, 0), p + Vector3(0, eh, 0), col)
	n += HoloMesh3D.line(s, a0.lerp(b0, 0.06) + Vector3(0, eh, 0),
			a0.lerp(b0, 0.94) + Vector3(0, eh, 0), col)
	# Auvent : cadre horizontal débordant vers la route + béquilles obliques.
	var ve := Vector3(0, eh + h.unite_maison * 0.10, 0)
	var o: Vector3 = out * (h.taille_cellule * 0.42)
	var q0 := a0 + ve
	var q1 := b0 + ve
	n += HoloMesh3D.line(s, q0, q1, col)
	n += HoloMesh3D.line(s, q0 + o, q1 + o, col)
	n += HoloMesh3D.line(s, q0, q0 + o, col)
	n += HoloMesh3D.line(s, q1, q1 + o, col)
	n += HoloMesh3D.line(s, a0.lerp(b0, 0.06) + Vector3(0, eh * 0.55, 0), q0 + o, col)   # béquille
	n += HoloMesh3D.line(s, a0.lerp(b0, 0.94) + Vector3(0, eh * 0.55, 0), q1 + o, col)
	# Tapis d'accueil : double trait au sol qui traverse le parvis vers la route.
	for tt: float in [0.40, 0.60]:
		var p := a0.lerp(b0, tt) + Vector3(0, 0.02, 0)
		n += HoloMesh3D.line(s, p, p + out * (h.taille_cellule * 0.9), col)
	return n

# Totem publicitaire : pylône dressé au bord de la route près de l'entrée, caissons
# lumineux dégressifs empilés (cadres ambre + barres « texte » cyan) → la signature
# verticale d'hypermarché visible de loin. Renvoie [nb arêtes ambre, nb arêtes cyan].
static func _totem_enseigne(h, ent: Dictionary, haut: float, ambre: Color, cyan: Color,
		sn: SurfaceTool, sc: SurfaceTool) -> Array:
	var cmid: Vector2i = ent["cell"]
	var d: Vector2i = ent["dir"]
	var seg: Array = h._cote_cellule(cmid, d)
	var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
	var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
	var lat := (b0 - a0).normalized()
	var base: Vector3 = a0 - lat * (h.taille_cellule * 0.18) \
			+ Vector3(float(d.x), 0.0, float(d.y)) * (h.taille_cellule * 0.28)
	var th: float = haut + h.unite_maison * 1.9
	var nn := HoloMesh3D.line(sn, base, base + Vector3(0, th, 0), ambre)   # mât
	var ncy := 0
	var cw: float = h.taille_cellule * 0.30
	var y := th
	for k in 3:
		var chh: float = h.unite_maison * (0.55 - 0.08 * float(k))
		var c0: Vector3 = base + Vector3(0, y - chh, 0)
		nn += _cadre_vertical(sn, c0, lat, cw * (1.0 - 0.15 * float(k)) * 0.5, chh, ambre)
		ncy += HoloMesh3D.line(sc, c0 + Vector3(0, chh * 0.5, 0) - lat * (cw * 0.35),
				c0 + Vector3(0, chh * 0.5, 0) + lat * (cw * 0.35), cyan)
		y -= chh + h.unite_maison * 0.14
	return [nn, ncy]

# Cadre rectangulaire vertical (plan lat×Y) : base centrée en c0, demi-largeur hw,
# hauteur hh. Renvoie le nb d'arêtes.
static func _cadre_vertical(s: SurfaceTool, c0: Vector3, lat: Vector3, hw: float, hh: float, col: Color) -> int:
	var p0 := c0 - lat * hw
	var p1 := c0 + lat * hw
	var p2 := p1 + Vector3(0, hh, 0)
	var p3 := p0 + Vector3(0, hh, 0)
	return HoloMesh3D.line(s, p0, p1, col) + HoloMesh3D.line(s, p1, p2, col) \
			+ HoloMesh3D.line(s, p2, p3, col) + HoloMesh3D.line(s, p3, p0, col)

# Blocs techniques (CVC) sur le toit : quelques caissons sombres posés à des positions
# déterministes → le toit d'hyper ne se lit plus comme une dalle nue sous la grille.
# Renvoie [nb arêtes, nb faces].
static func _cvc_toit(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool, sf: SurfaceTool) -> Array:
	var x0 := float(bb.position.x); var x1 := float(bb.position.x + bb.size.x - 1)
	var y0 := float(bb.position.y); var y1 := float(bb.position.y + bb.size.y - 1)
	var n := 0
	var nf := 0
	var k := 0
	for f: Array in [[0.22, 0.30], [0.68, 0.26], [0.45, 0.70], [0.78, 0.66]]:
		k += 1
		var c: Vector3 = h._world(lerpf(x0, x1, f[0]), lerpf(y0, y1, f[1]), haut)
		var w: float = h.taille_cellule * (0.26 + 0.05 * float(k % 2))
		var hh: float = h.unite_maison * 0.30
		n += HoloMesh3D.box(s, c, w, hh, w * 0.8, col)
		nf += HoloMesh3D.box_faces(sf, c, w * 0.92, hh, w * 0.74)
	return [n, nf]

# ─── Parcs : nappe verte au sol + arbres ──────────────────────
# Nappe de sol des parcs (shader holo_parc) posée à plat sous les arbres, alignée aux
# routes. Une tuile par case (couleur portée par le shader → sommets blancs). Dessiné
# AVANT decor (les arbres se posent par-dessus). Skip les cases d'un parc-LIEU
# (rendu tier-coloré dédié).
static func parcs_sol(h) -> void:
	if h._parc.is_empty():
		return
	var st := HoloMesh3D.st_tri()
	var nt := 0
	var hw: float = h.taille_cellule * 0.5
	for k in h._parc:
		var cell := k as Vector2i
		if h._lieu_sol.has(cell) or h._lieu_arbres.has(cell):
			continue
		var c: Vector3 = h._world(cell.x, cell.y, 0.01)
		var p0 := c + Vector3(-hw, 0, -hw)
		var p1 := c + Vector3(hw, 0, -hw)
		var p2 := c + Vector3(hw, 0, hw)
		var p3 := c + Vector3(-hw, 0, hw)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.set_color(Color.WHITE); st.add_vertex(v)
		nt += 2
	h._ajouter_mesh(HoloMesh3D.commit(st, nt), "ParcsSolExcel", h._mat_parc)

# Décor végétal : vaguelettes d'eau + arbres des parcs (verts épars, ou colorés/glow
# pour les cases d'un parc-LIEU). Deux meshes : décor ambiant + décor de lieu.
static func decor(h) -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var ce := Color(h.couleur_eau, 0.7)
	var cp := Color(h.couleur_parc, 0.7)
	# Eau : courtes vaguelettes horizontales.
	for k in h._eau:
		var cell := k as Vector2i
		var c: Vector3 = h._world(cell.x, cell.y, 0.012)
		var hw: float = h.taille_cellule * 0.4
		n += HoloMesh3D.line(s, c + Vector3(-hw, 0, -0.05 * h.taille_cellule),
				c + Vector3(hw, 0, -0.05 * h.taille_cellule), ce)
		n += HoloMesh3D.line(s, c + Vector3(-hw, 0, 0.18 * h.taille_cellule),
				c + Vector3(hw, 0, 0.18 * h.taille_cellule), ce)
	# Parc : arbres holo VARIÉS (arbre-scan à anneaux, houppier diamant, cyprès),
	# hauteur et position légèrement chahutées → bosquets organiques au lieu d'une
	# grille de croix identiques. ~1 arbre sur 8 est « bio-lum » : couleur néon
	# vive (cyan/magenta) + anneau de rétro-éclairage au sol, sur _mat_neon →
	# halo + respiration (la végétation modifiée du parc cyberpunk).
	# Les arbres SOUS un lieu sans bâtiment passent à la couleur de palier du lieu
	# et dans un mesh à part (matériau qui glow) : la parcelle EST le lieu.
	var sl := HoloMesh3D.st()
	var nl := 0
	var sn := HoloMesh3D.st()
	var nn := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x515A11
	for k in h._parc:
		var cell := k as Vector2i
		var c: Vector3 = h._world(cell.x, cell.y, 0.0)
		var ht: float = h.unite_maison * lerpf(0.9, 1.5, rng.randf())
		if h._lieu_arbres.has(cell):
			# Cellule choisie d'un parc-lieu : arbre coloré (glow).
			var lc := Color(h._lieu_arbres[cell] as Color, 0.9)
			nl += _arbre_parc(h, sl, c, ht, lc, rng.randf())
		elif h._lieu_sol.has(cell):
			continue   # reste du sol du lieu : laissé vide (peu d'arbres voulus)
		elif rng.randf() <= 0.70:
			var jit: Vector3 = Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5) \
					* (h.taille_cellule * 0.35)
			var pos := c + jit
			if rng.randf() < 0.12:
				# Arbre bio-lum : néon vif + anneau de rétro-éclairage au sol.
				var vif := Color(0.35, 0.95, 1.0, 0.9) if rng.randf() < 0.6 \
						else Color(0.95, 0.45, 1.0, 0.9)
				nn += _arbre_parc(h, sn, pos, ht, vif, rng.randf())
				nn += HoloMesh3D.circle(sn, pos + Vector3(0, 0.015, 0),
						h.taille_cellule * 0.26, Color(vif, 0.5), 16)
			else:
				# Arbre ordinaire : vert terni vers la périphérie.
				var tc: Color = h._moduler(cp, c)
				n += _arbre_parc(h, s, pos, ht, tc, rng.randf())
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Decor", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(sl, nl), "DecorLieu", h._mat_lieu_decor)
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "DecorNeon", h._mat_neon)

# Arbre holo de parc, silhouette choisie par `hv` :
#   < 0.45 → arbre-scan : tronc + 3 anneaux de canopée horizontaux (tranches topo) ;
#   < 0.80 → houppier diamant (l'ancien look, gardé pour la variété) ;
#   sinon  → cyprès effilé (flamme verticale).
static func _arbre_parc(h, s: SurfaceTool, c: Vector3, ht: float, col: Color, hv: float) -> int:
	var n := 0
	var cr: float = h.taille_cellule
	if hv < 0.45:
		n += HoloMesh3D.line(s, c, c + Vector3(0, ht * 1.05, 0), col)
		for lvl: Array in [[0.55, 0.24], [0.78, 0.18], [0.98, 0.10]]:
			n += HoloMesh3D.circle(s, c + Vector3(0, ht * (lvl[0] as float), 0),
					cr * (lvl[1] as float), col, 10)
	elif hv < 0.80:
		n += HoloMesh3D.line(s, c, c + Vector3(0, ht, 0), col)
		n += HoloMesh3D.diamond(s, c + Vector3(0, ht + ht * 0.4, 0), cr * 0.22, ht * 0.5, col)
	else:
		n += HoloMesh3D.pyramid(s, c, cr * 0.13, cr * 0.13, ht * 1.6, col)
	return n

# ─── Prison : enceinte fortifiée + miradors aux angles + cour creuse + champ de force ──
# Apparence cyberpunk fermée (DA holo wireframe). Volume bas-moyen, emprise large et
# fermée. Soumise au gradient centre→périphérie comme les autres apparences. Inerte par
# défaut (un ID dans une case en fait un lieu via le système standard).
static func prisons(h) -> void:
	if h._excel.prisons.is_empty():
		return
	var s := HoloMesh3D.st()        # structure sombre (enceinte, miradors)
	var sg := HoloMesh3D.st()       # accents néon (rail de crête, projecteurs)
	var champ := HoloMesh3D.st()    # champ de force (mesh à part : matériau clignotant)
	var n := 0
	var ng := 0
	var nc := 0
	for b in h._excel.prisons:
		var bb: Rect2i = b["bbox"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.40, 0.43, 0.49, 0.95), centre)   # béton froid
		var neon: Color = h._moduler(Color(0.45, 0.85, 1.0), centre)          # néon de sécurité (cyan)
		var champ_col: Color = h._moduler(Color(0.55, 0.95, 1.0), centre)
		var mur_h: float = maxf(h.unite_maison * 2.2, h._hauteur_monde(float(b["hauteur_m"])) * 0.55)
		# Enceinte : murs périmétriques épais (côtés frontière) + créneaux + rail néon.
		var rc := _enceinte_prison(h, b["cells"], mur_h, col, neon, s, sg)
		n += rc[0]; ng += rc[1]
		# Portail d'entrée face aux routes.
		ng += h._portes_vers_routes(b["cells"], mur_h * 0.7, neon, sg)
		# Miradors aux 4 coins de la bbox (postes de garde surélevés) + FAISCEAU de
		# recherche qui plonge dans la cour et BALAIE en va-et-vient (rail
		# d'animation des projecteurs, cf. HoloMap3D._process).
		var corners := [bb.position, bb.position + Vector2i(bb.size.x - 1, 0),
				bb.position + Vector2i(0, bb.size.y - 1), bb.position + Vector2i(bb.size.x - 1, bb.size.y - 1)]
		var idx := 0
		for cc: Vector2i in corners:
			var rm := _mirador(h, h._world(cc.x, cc.y, 0.0), mur_h, col, neon, s, sg)
			n += rm[0]; ng += rm[1]
			var tete: Vector3 = h._world(cc.x, cc.y, mur_h * 1.35 + h.unite_maison * 0.9)
			var aimx: float = centre.x - tete.x
			var aimz: float = centre.z - tete.z
			var dist := sqrt(aimx * aimx + aimz * aimz)
			if dist < 0.001:
				continue
			var node := _searchlight_mirador(h, tete, dist * 0.42, neon)
			node.set_meta("base_yaw", atan2(-aimz, aimx))   # +X local vise la cour
			node.set_meta("amp", deg_to_rad(26.0))
			node.set_meta("phase", float(idx) * 1.4)        # désynchronise les 4 coins
			h._monde.add_child(node)
			h._projecteurs.append(node)
			idx += 1
		# Champ de force au sommet : grille d'énergie au-dessus de la COUR (intérieur creux).
		nc += _champ_force(h, b["cells"], mur_h * 1.04, champ_col, champ)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Prisons")
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "PrisonsNeon", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(champ, nc), "PrisonsChampForce", h._mat_balise)

# Mur d'enceinte : sur chaque côté frontière, paroi (bas + crête + montants aux bouts) +
# créneaux (merlons) sur la crête + rail néon. Renvoie [arêtes sombres, arêtes néon].
static func _enceinte_prison(h, cells: Array, mur_h: float, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var ng := 0
	var up := Vector3(0, mur_h, 0)
	var cren := Vector3(0, mur_h * 0.16, 0)   # hauteur des merlons
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
			var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
			n += HoloMesh3D.line(s, a0, b0, col)            # base
			n += HoloMesh3D.line(s, a0 + up, b0 + up, col)  # crête
			n += HoloMesh3D.line(s, a0, a0 + up, col)       # montant A
			n += HoloMesh3D.line(s, b0, b0 + up, col)       # montant B
			# Créneaux : 3 merlons dressés sur la crête.
			for t: float in [0.2, 0.5, 0.8]:
				var p := (a0 + up).lerp(b0 + up, t)
				n += HoloMesh3D.line(s, p, p + cren, col)
			ng += HoloMesh3D.line(sg, a0 + up, b0 + up, neon)  # rail néon de crête
			ng += _barbele(h, a0 + up, b0 + up, neon, sg)      # concertina au sommet
	return [n, ng]

# Fil de barbelé CONCERTINA : hélice serrée courant au-dessus de la crête a→b
# (boucles dans le plan perpendiculaire au mur) → la spirale de barbelé classique
# des enceintes de prison, en wireframe glow. Renvoie le nb d'arêtes.
static func _barbele(h, a: Vector3, b: Vector3, col: Color, s: SurfaceTool) -> int:
	var dirv := b - a
	var lon := dirv.length()
	if lon < 0.001:
		return 0
	var t := dirv / lon
	var perp := Vector3(-t.z, 0.0, t.x)
	var r: float = h.taille_cellule * 0.065
	var tours := maxi(3, int(round(lon / (r * 3.0))))   # densité des boucles
	var pas := 10                                        # segments par tour
	var total := tours * pas
	var n := 0
	var prev := Vector3.ZERO
	for i in total + 1:
		var f := float(i) / float(total)
		var ang := TAU * float(i) / float(pas)
		var p := a + dirv * f + Vector3(0, r + sin(ang) * r, 0) + perp * (cos(ang) * r)
		if i > 0:
			n += HoloMesh3D.line(s, prev, p, col)
		prev = p
	return n

# Mirador : poste de garde sur pilotis (4 montants) + cabine (caisse) + projecteur néon.
static func _mirador(h, base: Vector3, mur_h: float, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var n := 0
	var ng := 0
	var hh := mur_h * 1.35
	var w: float = h.taille_cellule * 0.34
	var corners := [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
	for off: Vector3 in corners:
		n += HoloMesh3D.line(s, base + off, base + off + Vector3(0, hh, 0), col)   # pilotis
	# Cabine (caisse) au sommet + projecteur néon (œil de garde).
	n += HoloMesh3D.box(s, base + Vector3(0, hh, 0), w * 2.4, h.unite_maison * 0.9, w * 2.4, col)
	ng += HoloMesh3D.diamond(sg, base + Vector3(0, hh + h.unite_maison * 0.5, 0),
			h.taille_cellule * 0.1, h.taille_cellule * 0.14, neon)
	return [n, ng]

# Faisceau de mirador : cône de lumière qui plonge de la cabine vers la cour +
# nappe elliptique au sol. Node orientable (+X local = visée), la rotation.y est
# animée par HoloMap3D._process comme les autres projecteurs.
static func _searchlight_mirador(h, tete: Vector3, reach: float, col: Color) -> Node3D:
	var node := Node3D.new()
	node.name = "ProjecteurMirador"
	node.position = tete
	var s := HoloMesh3D.st()
	var n := 0
	var poolc := Vector3(reach, -tete.y, 0)   # y monde = 0 → local -tete.y
	var pr: float = h.taille_cellule * 0.42
	n += HoloMesh3D.circle(s, poolc, pr, col, 16)
	n += HoloMesh3D.line(s, Vector3.ZERO, poolc, col)      # axe du faisceau
	for a: float in [0.0, 90.0, 180.0, 270.0]:              # cône (4 génératrices)
		var rad := deg_to_rad(a)
		n += HoloMesh3D.line(s, Vector3.ZERO, poolc + Vector3(cos(rad) * pr, 0, sin(rad) * pr), col)
	var mi := MeshInstance3D.new()
	mi.name = "FaisceauMesh"
	mi.mesh = HoloMesh3D.commit(s, n)
	mi.material_override = h._mat_neon
	node.add_child(mi)
	return node

# ─── Commissariat de police : poste institutionnel compact ────
# PAS un complexe carcéral : volume bas/moyen ouvert sur la rue (aucune enceinte,
# aucun mirador, aucune cour fermée). Identité : bandeau lumineux bleu qui ceinture
# la façade, entrée marquée côté route (portique + auvent + écusson + perron),
# antenne de communication sur le toit, et GYROPHARES bleus (matériau balise → ils
# CLIGNOTENT) sur le toit et sur les voitures de patrouille stationnées devant.
# Soumis au gradient centre→périphérie comme les autres apparences ; inerte par
# défaut (un ID dans une case en fait un lieu via le système standard).
static func commissariats(h) -> void:
	if h._excel.commissariats.is_empty():
		return
	var s := HoloMesh3D.st()        # structure sombre (coque, perron, mât, voitures)
	var sf := HoloMesh3D.st_tri()   # faces d'occlusion
	var sn := HoloMesh3D.st()       # accents néon bleus (bandeau, entrée, antenne)
	var sb := HoloMesh3D.st()       # gyrophares (matériau balise → clignotent)
	var n := 0
	var nf := 0
	var nn := 0
	var nb := 0
	for b in h._excel.commissariats:
		var bb: Rect2i = b["bbox"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.30, 0.38, 0.55, 0.9), centre)   # bleu nuit institutionnel
		var neon: Color = h._moduler(Color(0.35, 0.65, 1.0), centre)         # bleu police (glow)
		var gyro: Color = h._moduler(Color(0.25, 0.55, 1.0), centre)         # bleu gyrophare (clignote)
		# Hauteur tapée honorée (chiffre = hauteur seule) ; défaut = volume bas/moyen.
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var cells: Array = b["cells"]
		var r: Array = h._bati_boite(cells, haut, col, s, sf)
		n += r[0]; nf += r[1]
		# Bandeau lumineux bleu : double rail néon ceinturant le volume à mi-hauteur
		# (la signature « poste de police » qui se lit de loin).
		nn += _bandeau_commissariat(h, cells, haut, neon, sn)
		# Entrée marquée côté route + antenne + gyrophares/patrouille.
		var ent := _cote_entree(h, cells)
		nn += _entree_commissariat(h, ent, haut, neon, sn)
		var ra: Array = _antenne_commissariat(h, bb, haut, col, neon, gyro, s, sn, sb)
		n += ra[0]; nn += ra[1]; nb += ra[2]
		var rg: Array = _patrouille_commissariat(h, ent, haut, col, gyro, s, sb)
		n += rg[0]; nb += rg[1]
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Commissariats")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "CommissariatsFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "CommissariatsNeon", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(sb, nb), "CommissariatsGyros", h._mat_balise)

# Bandeau institutionnel : double rail néon sur chaque côté frontière du bloc, à
# mi-hauteur de façade (la bande bleue des commissariats). Renvoie le nb d'arêtes.
static func _bandeau_commissariat(h, cells: Array, haut: float, col: Color, s: SurfaceTool) -> int:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			for yf: float in [0.52, 0.60]:
				n += HoloMesh3D.line(s, h._world(seg[0].x, seg[0].y, haut * yf),
						h._world(seg[1].x, seg[1].y, haut * yf), col)
	return n

# Entrée marquée : portique (jambages + linteau) + auvent débordant + écusson
# (losange-insigne au-dessus de la porte) + perron de deux marches vers la rue.
static func _entree_commissariat(h, ent: Dictionary, haut: float, col: Color, s: SurfaceTool) -> int:
	var cmid: Vector2i = ent["cell"]
	var d: Vector2i = ent["dir"]
	var seg: Array = h._cote_cellule(cmid, d)
	var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
	var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
	var out := Vector3(float(d.x), 0.0, float(d.y))
	var eh: float = minf(h.unite_maison * 0.9, haut * 0.7)
	var jl := a0.lerp(b0, 0.34)
	var jr := a0.lerp(b0, 0.66)
	var n := 0
	n += HoloMesh3D.line(s, jl + Vector3(0, 0.02, 0), jl + Vector3(0, eh, 0), col)   # jambage
	n += HoloMesh3D.line(s, jr + Vector3(0, 0.02, 0), jr + Vector3(0, eh, 0), col)
	n += HoloMesh3D.line(s, jl + Vector3(0, eh, 0), jr + Vector3(0, eh, 0), col)     # linteau
	# Auvent débordant vers la rue.
	var o: Vector3 = out * (h.taille_cellule * 0.22)
	n += HoloMesh3D.line(s, jl + Vector3(0, eh, 0) + o, jr + Vector3(0, eh, 0) + o, col)
	n += HoloMesh3D.line(s, jl + Vector3(0, eh, 0), jl + Vector3(0, eh, 0) + o, col)
	n += HoloMesh3D.line(s, jr + Vector3(0, eh, 0), jr + Vector3(0, eh, 0) + o, col)
	# Écusson au-dessus de la porte (losange → insigne de police).
	var mid := (jl + jr) * 0.5
	n += HoloMesh3D.diamond(s, mid + Vector3(0, eh + h.unite_maison * 0.12, 0),
			h.taille_cellule * 0.07, h.taille_cellule * 0.10, col)
	# Perron : deux marches lumineuses qui descendent vers la rue.
	for k in 2:
		var t := float(k + 1) * 0.16
		n += HoloMesh3D.line(s, jl + out * (h.taille_cellule * t) + Vector3(0, 0.02, 0),
				jr + out * (h.taille_cellule * t) + Vector3(0, 0.02, 0), col)
	return n

# Antenne de communication sur le toit : mât haubané + traverses relais (néon) +
# petite parabole + balise bleue clignotante au sommet. Renvoie [arêtes, néon, balise].
static func _antenne_commissariat(h, bb: Rect2i, haut: float, col: Color, neon: Color,
		gyro: Color, s: SurfaceTool, sn: SurfaceTool, sb: SurfaceTool) -> Array:
	# Mât à l'angle du toit (coin de bbox, dégagé de la façade d'entrée).
	var base: Vector3 = h._world(float(bb.position.x) + 0.22, float(bb.position.y) + 0.22, haut)
	var mh: float = h.unite_maison * 1.6
	var top := base + Vector3(0, mh, 0)
	var n := HoloMesh3D.line(s, base, top, col)
	# Haubans vers le toit.
	n += HoloMesh3D.line(s, top + Vector3(0, -mh * 0.25, 0),
			base + Vector3(h.taille_cellule * 0.22, 0, 0), col)
	n += HoloMesh3D.line(s, top + Vector3(0, -mh * 0.25, 0),
			base + Vector3(0, 0, h.taille_cellule * 0.22), col)
	var nn := 0
	for yf: float in [0.55, 0.72, 0.89]:   # traverses relais (barreaux lumineux)
		var p := base + Vector3(0, mh * yf, 0)
		nn += HoloMesh3D.line(sn, p + Vector3(-h.taille_cellule * 0.10, 0, 0),
				p + Vector3(h.taille_cellule * 0.10, 0, 0), neon)
	# Petite parabole à mi-mât.
	nn += HoloMesh3D.ellipse(sn, base + Vector3(h.taille_cellule * 0.08, mh * 0.4, 0),
			h.taille_cellule * 0.07, h.taille_cellule * 0.05, neon, 10)
	# Balise bleue clignotante au sommet.
	var nbal := HoloMesh3D.diamond(sb, top + Vector3(0, h.taille_cellule * 0.05, 0),
			h.taille_cellule * 0.05, h.taille_cellule * 0.07, gyro)
	return [n, nn, nbal]

# ═══ Repère de parcelle ORIENTÉ ROUTE (grand parc / université / musée) ═══
# (u = latéral 0..1, v = profondeur 0..1 avec v=0 CÔTÉ ROUTE d'entrée) →
# coordonnées de GRILLE continues. `d` = direction bloc→route (cf. _cote_entree).
static func _uv_grille(bb: Rect2i, d: Vector2i, u: float, v: float) -> Vector2:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var y0 := float(bb.position.y) - 0.5
	var y1 := float(bb.position.y + bb.size.y - 1) + 0.5
	if d == Vector2i(0, 1):
		return Vector2(lerpf(x0, x1, u), lerpf(y1, y0, v))
	if d == Vector2i(0, -1):
		return Vector2(lerpf(x1, x0, u), lerpf(y0, y1, v))
	if d == Vector2i(1, 0):
		return Vector2(lerpf(x1, x0, v), lerpf(y0, y1, u))
	return Vector2(lerpf(x0, x1, v), lerpf(y1, y0, u))

# Taille MONDE (sx, sz) d'un rectangle du repère (du = fraction latérale,
# dv = fraction de profondeur), selon l'axe de `d` (boîtes alignées grille).
static func _uv_taille(h, bb: Rect2i, d: Vector2i, du: float, dv: float) -> Vector2:
	var lat: float = float(bb.size.x if d.y != 0 else bb.size.y) * h.taille_cellule
	var prof: float = float(bb.size.y if d.y != 0 else bb.size.x) * h.taille_cellule
	if d.y != 0:
		return Vector2(du * lat, dv * prof)
	return Vector2(dv * prof, du * lat)

# Boîte (arêtes + faces d'occlusion) posée dans le repère orienté : centre (u,v),
# emprise (du × dv) en fractions de parcelle, hauteur monde. Renvoie [arêtes, faces].
static func _boite_uv(h, bb: Rect2i, d: Vector2i, u: float, v: float, du: float, dv: float,
		haut: float, col: Color, s: SurfaceTool, sf: SurfaceTool) -> Array:
	var g := _uv_grille(bb, d, u, v)
	var t := _uv_taille(h, bb, d, du, dv)
	var c: Vector3 = h._world(g.x, g.y, 0.0)
	var n := HoloMesh3D.box(s, c, t.x, haut, t.y, col)
	var nf := HoloMesh3D.box_faces(sf, c, t.x * 0.96, haut, t.y * 0.96)
	return [n, nf]

# Bandeau : double rail horizontal ceinturant une boîte du repère orienté.
static func _bandeau_uv(h, bb: Rect2i, d: Vector2i, u: float, v: float, du: float, dv: float,
		yb: float, yh: float, col: Color, s: SurfaceTool) -> int:
	var g := _uv_grille(bb, d, u, v)
	var t := _uv_taille(h, bb, d, du, dv)
	var c: Vector3 = h._world(g.x, g.y, 0.0)
	var hx := t.x * 0.5
	var hz := t.y * 0.5
	var n := 0
	for yy: float in [yb, yh]:
		var p0 := c + Vector3(-hx, yy, -hz); var p1 := c + Vector3(hx, yy, -hz)
		var p2 := c + Vector3(hx, yy, hz);   var p3 := c + Vector3(-hx, yy, hz)
		n += HoloMesh3D.line(s, p0, p1, col) + HoloMesh3D.line(s, p1, p2, col) \
				+ HoloMesh3D.line(s, p2, p3, col) + HoloMesh3D.line(s, p3, p0, col)
	return n

# Colonnade : `nb`+1 montants verticaux réguliers le long de la ligne v, entre u0 et u1.
static func _colonnade_uv(h, bb: Rect2i, d: Vector2i, u0: float, u1: float, v: float,
		haut: float, nb: int, col: Color, s: SurfaceTool) -> int:
	var n := 0
	for k in range(nb + 1):
		var g := _uv_grille(bb, d, lerpf(u0, u1, float(k) / float(nb)), v)
		var p: Vector3 = h._world(g.x, g.y, 0.0)
		n += HoloMesh3D.line(s, p + Vector3(0, 0.02, 0), p + Vector3(0, haut, 0), col)
	return n

# Dallage d'esplanade : fines lignes croisées sur le rectangle u∈[u0,u1] × v∈[v0,v1].
static func _esplanade_uv(h, bb: Rect2i, d: Vector2i, u0: float, u1: float, v0: float, v1: float,
		col: Color, s: SurfaceTool) -> int:
	var n := 0
	var nu := 5
	var nv := 3
	for k in range(nu + 1):
		var a := _uv_grille(bb, d, lerpf(u0, u1, float(k) / float(nu)), v0)
		var bq := _uv_grille(bb, d, lerpf(u0, u1, float(k) / float(nu)), v1)
		n += HoloMesh3D.line(s, h._world(a.x, a.y, 0.018), h._world(bq.x, bq.y, 0.018), col)
	for k in range(nv + 1):
		var a := _uv_grille(bb, d, u0, lerpf(v0, v1, float(k) / float(nv)))
		var bq := _uv_grille(bb, d, u1, lerpf(v0, v1, float(k) / float(nv)))
		n += HoloMesh3D.line(s, h._world(a.x, a.y, 0.018), h._world(bq.x, bq.y, 0.018), col)
	return n

# Disque plat (éventail de triangles, plan XZ) — nappe d'eau de bassin (couleur
# vertex blanche : c'est le shader d'eau qui colore/anime).
static func _disque_plat(s: SurfaceTool, c: Vector3, rx: float, rz: float, seg: int) -> int:
	var n := 0
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := c + Vector3(cos(a0) * rx, 0, sin(a0) * rz)
		var p1 := c + Vector3(cos(a1) * rx, 0, sin(a1) * rz)
		for v: Vector3 in [c, p0, p1]:
			s.set_color(Color.WHITE)
			s.add_vertex(v)
		n += 1
	return n

# ─── Grand parc urbain (émeraude 3FA06B) : Central Park cyberpunk ──────────
# ≠ PARC (grappe d'arbres, olive) : grand espace vert STRUCTURÉ et AMÉNAGÉ —
# pelouse émeraude vivante (même shader que les parcs, teinte dédiée), promenade
# périmétrique + allées en croix, bassin central animé, kiosques-dômes, arbres,
# lampadaires néon. PLAT (aucun volume bâti) : un lieu posé dessus reste « sans
# bâtiment ». Gradient de richesse sur les structures (h._moduler) ; la pelouse
# partage l'uniforme de son shader, comme les parcs-arbres.
static func grands_parcs(h) -> void:
	if h._excel.grands_parcs.is_empty():
		return
	var mat_pelouse := ShaderMaterial.new()
	mat_pelouse.shader = (h._mat_parc as ShaderMaterial).shader
	mat_pelouse.set_shader_parameter("parc_color", Color(0.16, 0.68, 0.34))  # émeraude vive saturée
	mat_pelouse.set_shader_parameter("emission", 0.88)   # sous le seuil de bloom (1.02)
	mat_pelouse.set_shader_parameter("fog_debut", h.brume_debut)
	mat_pelouse.set_shader_parameter("fog_fin", h.brume_fin)
	h._mats_reveal.append(mat_pelouse)   # participe à la matérialisation d'intro
	var sg := HoloMesh3D.st_tri()
	var ng := 0                          # pelouse
	var s := HoloMesh3D.st()
	var n := 0                           # structures (kiosques, mâts, arbres)
	var sc := HoloMesh3D.st()
	var nc := 0                          # allées (trait net SANS bloom)
	var sn := HoloMesh3D.st()
	var nn := 0                          # néons (têtes de lampadaires, margelles)
	var se := HoloMesh3D.st_tri()
	var ne := 0                          # bassins (nappe d'eau animée)
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x6A9D01
	var hw: float = h.taille_cellule * 0.5
	for b in h._excel.grands_parcs:
		var bb: Rect2i = b["bbox"]
		var cells: Array = b["cells"]
		var centre: Vector3 = h._centre_bbox(bb)
		var blanc: Color = h._moduler(Color(0.92, 0.88, 0.72, 0.9), centre)  # allées / kiosques
		var vert: Color = h._moduler(Color(0.36, 0.85, 0.55, 0.9), centre)   # végétation émeraude
		var ambre: Color = h._moduler(Color(1.0, 0.72, 0.30), centre)        # lampadaires
		var cyan: Color = h._moduler(Color(0.40, 0.95, 1.0), centre)         # margelle du bassin
		# 1) Pelouse pleine (une tuile par case — le shader anime touffes + pulse).
		for c: Vector2i in cells:
			var cw: Vector3 = h._world(c.x, c.y, 0.012)
			var p0 := cw + Vector3(-hw, 0, -hw)
			var p1 := cw + Vector3(hw, 0, -hw)
			var p2 := cw + Vector3(hw, 0, hw)
			var p3 := cw + Vector3(-hw, 0, hw)
			for v: Vector3 in [p0, p1, p2, p0, p2, p3]:
				sg.set_color(Color.WHITE)
				sg.add_vertex(v)
			ng += 2
		# 2) Promenade périmétrique + allées en croix (pointillés chauds).
		var x0 := float(bb.position.x)
		var x1 := float(bb.position.x + bb.size.x - 1)
		var y0 := float(bb.position.y)
		var y1 := float(bb.position.y + bb.size.y - 1)
		var da: float = h.taille_cellule * 0.42
		var ga: float = h.taille_cellule * 0.22
		var coins := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1), Vector2(x0, y0)]
		for i in 4:
			var ca := coins[i] as Vector2
			var cb := coins[i + 1] as Vector2
			nc += Geo.dashes(sc, h._world(ca.x, ca.y, 0.02), h._world(cb.x, cb.y, 0.02), blanc, da, ga)
		var cx := (x0 + x1) * 0.5
		var cyg := (y0 + y1) * 0.5
		# 3) Bassin central (parcelle ≥ 3×3) : nappe d'eau animée + margelle cyan.
		var rmin: float = minf(float(bb.size.x), float(bb.size.y))
		var brx := 0.0
		var brz := 0.0
		if rmin >= 3.0:
			brx = float(bb.size.x) * h.taille_cellule * 0.17
			brz = float(bb.size.y) * h.taille_cellule * 0.17
			ne += _disque_plat(se, centre + Vector3(0, 0.018, 0), brx, brz, 22)
			nn += HoloMesh3D.ellipse(sn, centre + Vector3(0, 0.035, 0), brx * 1.06, brz * 1.06, cyan, 26)
		# Allées traversantes en croix — COUPÉES au bord du bassin (pas de dalles sur l'eau).
		var mx: float = (brx * 1.12) / h.taille_cellule   # marge en cases (margelle comprise)
		var mz: float = (brz * 1.12) / h.taille_cellule
		if brx > 0.0:
			nc += Geo.dashes(sc, h._world(x0, cyg, 0.02), h._world(cx - mx, cyg, 0.02), blanc, da, ga)
			nc += Geo.dashes(sc, h._world(cx + mx, cyg, 0.02), h._world(x1, cyg, 0.02), blanc, da, ga)
			nc += Geo.dashes(sc, h._world(cx, y0, 0.02), h._world(cx, cyg - mz, 0.02), blanc, da, ga)
			nc += Geo.dashes(sc, h._world(cx, cyg + mz, 0.02), h._world(cx, y1, 0.02), blanc, da, ga)
		else:
			nc += Geo.dashes(sc, h._world(x0, cyg, 0.02), h._world(x1, cyg, 0.02), blanc, da, ga)
			nc += Geo.dashes(sc, h._world(cx, y0, 0.02), h._world(cx, y1, 0.02), blanc, da, ga)
		# 4) Kiosques-dômes aux quarts opposés (parcelle ≥ 4×4) + anneau lumineux.
		if rmin >= 4.0:
			for q: Vector2 in [Vector2(0.27, 0.27), Vector2(0.73, 0.73)]:
				var kg := Vector2(lerpf(x0, x1, q.x), lerpf(y0, y1, q.y))
				n += _kiosque_parc(h, kg, blanc, s)
				nn += HoloMesh3D.circle(sn, h._world(kg.x, kg.y, h.unite_maison * 0.62),
						h.taille_cellule * 0.26, cyan, 14)
		# 5) Arbres : cellules intérieures (la couronne reste promenade), hors bassin.
		for c: Vector2i in cells:
			if c.x <= bb.position.x or c.y <= bb.position.y \
					or c.x >= bb.position.x + bb.size.x - 1 or c.y >= bb.position.y + bb.size.y - 1:
				continue
			var cw: Vector3 = h._world(c.x, c.y, 0.0)
			if rmin >= 3.0 and absf(cw.x - centre.x) < brx + h.taille_cellule * 0.6 \
					and absf(cw.z - centre.z) < brz + h.taille_cellule * 0.6:
				continue   # bassin + margelle : pas d'arbre dans l'eau
			if rng.randf() > 0.60:
				continue
			var jit: Vector3 = Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5) * (h.taille_cellule * 0.3)
			n += _arbre_parc(h, s, cw + jit, h.unite_maison * rng.randf_range(0.9, 1.6),
					Color(vert, 0.9), rng.randf())
		# 6) Lampadaires néon : coins + milieux de côtés de la promenade.
		for lp: Vector2 in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
				Vector2(cx, y0), Vector2(cx, y1), Vector2(x0, cyg), Vector2(x1, cyg)]:
			var base: Vector3 = h._world(lp.x, lp.y, 0.0)
			var mh: float = h.unite_maison * 0.75
			n += HoloMesh3D.line(s, base, base + Vector3(0, mh, 0), blanc)
			nn += HoloMesh3D.diamond(sn, base + Vector3(0, mh + h.taille_cellule * 0.03, 0),
					h.taille_cellule * 0.035, h.taille_cellule * 0.05, ambre)
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "GrandsParcsPelouse", mat_pelouse)
	h._ajouter_mesh(HoloMesh3D.commit(se, ne), "GrandsParcsBassins", h._mat_eau)
	h._ajouter_mesh(HoloMesh3D.commit(sc, nc), "GrandsParcsAllees", h._mat_contour)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "GrandsParcs")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "GrandsParcsNeon", h._mat_neon)

# Kiosque de parc : 4 potelets + couronne circulaire + dôme (pavillon holo).
static func _kiosque_parc(h, g: Vector2, col: Color, s: SurfaceTool) -> int:
	var ray: float = h.taille_cellule * 0.30
	var hpot: float = h.unite_maison * 0.55
	var base: Vector3 = h._world(g.x, g.y, 0.0)
	var n := 0
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := base + Vector3(q.x * ray * 0.75, 0, q.y * ray * 0.75)
		n += HoloMesh3D.line(s, p, p + Vector3(0, hpot, 0), col)
	n += HoloMesh3D.circle(s, base + Vector3(0, hpot, 0), ray, col, 12)
	n += HoloMesh3D.dome(s, base + Vector3(0, hpot, 0), ray, ray, h.unite_maison * 0.4, col, 2, 10)
	return n

# ─── Université (bordeaux 9E3B5A) : campus académique ──────────────────────
# Corps principal en fond de parcelle + deux ailes latérales basses + AMPHI-DÔME
# sur tambour, esplanade dallée côté route avec tapis d'accès et PANNEAUX
# D'AFFICHAGE lumineux (framboise, grésillent comme des enseignes). Bandeau
# framboise en couronne + colonnade sur la façade → registre institutionnel
# étudiant. Orienté vers la route (_cote_entree). Chiffre tapé = hauteur seule.
static func universites(h) -> void:
	if h._excel.universites.is_empty():
		return
	var s := HoloMesh3D.st()
	var n := 0                           # structure
	var sf := HoloMesh3D.st_tri()
	var nf := 0                          # faces d'occlusion
	var sn := HoloMesh3D.st()
	var nn := 0                          # accents framboise (néon)
	var se := HoloMesh3D.st()
	var nse := 0                         # panneaux d'affichage (matériau enseigne)
	var sc := HoloMesh3D.st()
	var ncc := 0                         # dallage d'esplanade (net, sans bloom)
	for b in h._excel.universites:
		var bb: Rect2i = b["bbox"]
		var cells: Array = b["cells"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.40, 0.36, 0.48, 0.88), centre)   # béton académique
		var fram: Color = h._moduler(Color(0.95, 0.36, 0.55), centre)        # framboise (glow)
		var cyan: Color = h._moduler(Color(0.32, 0.95, 1.0), centre)
		var blanc: Color = h._moduler(Color(0.80, 0.78, 0.88, 0.8), centre)
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var ent := _cote_entree(h, cells)
		var d: Vector2i = ent["dir"]
		# CORPS principal (fond de parcelle) : hall académique pleine largeur.
		var r0: Array = _boite_uv(h, bb, d, 0.5, 0.76, 0.92, 0.44, haut, col, s, sf)
		n += r0[0]
		nf += r0[1]
		# Bandeau framboise en couronne + colonnade sur la façade avant du corps.
		nn += _bandeau_uv(h, bb, d, 0.5, 0.76, 0.92, 0.44, haut * 0.88, haut * 0.96, fram, sn)
		n += _colonnade_uv(h, bb, d, 0.10, 0.90, 0.54, haut * 0.80, 7, blanc, s)
		# AILES latérales basses (reliées au corps, encadrent l'esplanade).
		for uw: Vector2 in [Vector2(0.09, 0.18), Vector2(0.91, 0.18)]:
			var ra: Array = _boite_uv(h, bb, d, uw.x, 0.34, uw.y, 0.52, haut * 0.55, col, s, sf)
			n += ra[0]
			nf += ra[1]
		# AMPHI : dôme sur tambour entre l'aile gauche et le corps (landmark du campus).
		var gd := _uv_grille(bb, d, 0.24, 0.52)
		var ray: float = minf(float(bb.size.x), float(bb.size.y)) * h.taille_cellule * 0.16
		var pied: Vector3 = h._world(gd.x, gd.y, 0.0)
		var tamb: float = haut * 0.30
		n += HoloMesh3D.cylinder(s, pied, ray, ray, tamb, col, 16, 6)
		nf += HoloMesh3D.cylinder_faces(sf, pied, ray * 0.96, ray * 0.96, tamb, 16)
		var dc := pied + Vector3(0, tamb, 0)
		n += HoloMesh3D.dome(s, dc, ray, ray, ray * 0.75, col, 3, 14)
		nf += HoloMesh3D.dome_faces(sf, dc, ray * 0.96, ray * 0.96, ray * 0.73, 3, 14)
		nn += HoloMesh3D.circle(sn, dc, ray * 1.02, fram, 20)   # anneau framboise du tambour
		# ESPLANADE : dallage fin + tapis d'accès central vers la route.
		ncc += _esplanade_uv(h, bb, d, 0.10, 0.90, 0.02, 0.30, blanc, sc)
		for uu: float in [0.47, 0.53]:
			var a := _uv_grille(bb, d, uu, 0.30)
			var bpt := _uv_grille(bb, d, uu, 0.0)
			ncc += HoloMesh3D.line(sc, h._world(a.x, a.y, 0.022), h._world(bpt.x, bpt.y, 0.022), blanc)
		# PANNEAUX D'AFFICHAGE lumineux plantés sur l'esplanade (vie étudiante).
		for up: float in [0.22, 0.78]:
			nse += _panneau_campus(h, bb, d, up, 0.12, fram, cyan, se)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Universites")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "UniversitesFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "UniversitesNeon", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(se, nse), "UniversitesPanneaux", h._mat_enseigne)
	h._ajouter_mesh(HoloMesh3D.commit(sc, ncc), "UniversitesEsplanade", h._mat_contour)

# Panneau d'affichage de campus : totem sur pied (cadre lumineux face à la route
# + barres « annonces » cyan). Renvoie le nb d'arêtes.
static func _panneau_campus(h, bb: Rect2i, d: Vector2i, u: float, v: float,
		col: Color, col2: Color, s: SurfaceTool) -> int:
	var g := _uv_grille(bb, d, u, v)
	var base: Vector3 = h._world(g.x, g.y, 0.0)
	var bw: float = h.taille_cellule * 0.34
	var yb: float = h.unite_maison * 0.25
	var yh: float = yb + h.unite_maison * 0.85
	var lat := Vector3(float(d.y), 0.0, float(-d.x)) * (bw * 0.5)   # face à la route
	var n := HoloMesh3D.line(s, base, base + Vector3(0, yb, 0), col)   # pied
	var q0 := base - lat + Vector3(0, yb, 0)
	var q1 := base + lat + Vector3(0, yb, 0)
	var q2 := base + lat + Vector3(0, yh, 0)
	var q3 := base - lat + Vector3(0, yh, 0)
	n += HoloMesh3D.line(s, q0, q1, col) + HoloMesh3D.line(s, q1, q2, col) \
			+ HoloMesh3D.line(s, q2, q3, col) + HoloMesh3D.line(s, q3, q0, col)
	for m in 3:   # barres « annonces »
		var t := float(m + 1) / 4.0
		var pl := q0.lerp(q3, t)
		var pr := q1.lerp(q2, t)
		n += HoloMesh3D.line(s, pl.lerp(pr, 0.08), pr.lerp(pl, 0.08), col2)
	return n

# ─── Musée (violet-prune 6B4A8E) : institution culturelle ──────────────────
# Corps massif + VERRIÈRE en berceau sur le toit, façade MONUMENTALE côté route :
# perron étagé, colonnade + entablement + FRONTON, uplights chauds au pied des
# colonnes, parvis baigné d'une nappe de lumière et HOLOGRAMMES D'EXPOSITION
# flottants (anneau / losange sur mât, matériau enseigne → respiration/
# grésillement). Registre prestige/culture. Chiffre tapé = hauteur seule.
static func musees(h) -> void:
	if h._excel.musees.is_empty():
		return
	var s := HoloMesh3D.st()
	var n := 0
	var sf := HoloMesh3D.st_tri()
	var nf := 0
	var sn := HoloMesh3D.st()
	var nn := 0                          # néon prune + uplights chauds
	var se := HoloMesh3D.st()
	var nse := 0                         # hologrammes d'exposition (enseigne)
	var sgl := HoloMesh3D.st_tri()
	var ngl := 0                         # nappe chaude du parvis
	for b in h._excel.musees:
		var bb: Rect2i = b["bbox"]
		var cells: Array = b["cells"]
		var centre: Vector3 = h._centre_bbox(bb)
		var col: Color = h._moduler(Color(0.52, 0.48, 0.62, 0.9), centre)   # pierre claire
		var prune: Color = h._moduler(Color(0.74, 0.52, 0.98), centre)
		var chaud: Color = h._moduler(Color(1.0, 0.85, 0.55), centre)
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var ent := _cote_entree(h, cells)
		var d: Vector2i = ent["dir"]
		# CORPS massif (les 2/3 arrière de la parcelle).
		var r0: Array = _boite_uv(h, bb, d, 0.5, 0.64, 0.94, 0.62, haut, col, s, sf)
		n += r0[0]
		nf += r0[1]
		# VERRIÈRE en berceau sur le toit + faîtière prune lumineuse.
		var rv: Array = _verriere_uv(h, bb, d, 0.30, 0.70, 0.40, 0.90, haut, col, prune, s, sn)
		n += rv[0]
		nn += rv[1]
		# FAÇADE MONUMENTALE : colonnade + entablement + fronton + emblème prune.
		var uc0 := 0.16
		var uc1 := 0.84
		var vf := 0.335
		n += _colonnade_uv(h, bb, d, uc0, uc1, vf, haut * 0.78, 7, col, s)
		var ea := _uv_grille(bb, d, uc0, vf)
		var eb := _uv_grille(bb, d, uc1, vf)
		var pa: Vector3 = h._world(ea.x, ea.y, haut * 0.78)
		var pb: Vector3 = h._world(eb.x, eb.y, haut * 0.78)
		n += HoloMesh3D.line(s, pa, pb, col)   # entablement
		var apex := (pa + pb) * 0.5 + Vector3(0, haut * 0.16, 0)
		n += HoloMesh3D.line(s, pa, apex, col) + HoloMesh3D.line(s, apex, pb, col)   # fronton
		nn += HoloMesh3D.diamond(sn, (pa + pb) * 0.5 + Vector3(0, haut * 0.86, 0),
				h.taille_cellule * 0.05, h.taille_cellule * 0.07, prune)   # emblème
		# UPLIGHTS : courtes verticales chaudes au pied de chaque colonne.
		for k in range(8):
			var g := _uv_grille(bb, d, lerpf(uc0, uc1, float(k) / 7.0), vf)
			var p: Vector3 = h._world(g.x, g.y, 0.0)
			nn += HoloMesh3D.line(sn, p + Vector3(0, 0.015, 0), p + Vector3(0, haut * 0.14, 0), chaud)
		# PERRON : trois marches étagées qui descendent vers la route.
		for k in 3:
			var vm := vf - 0.055 * float(k + 1)
			var ma := _uv_grille(bb, d, 0.26, vm)
			var mb := _uv_grille(bb, d, 0.74, vm)
			var yy := 0.02 + 0.016 * float(2 - k)
			n += HoloMesh3D.line(s, h._world(ma.x, ma.y, yy), h._world(mb.x, mb.y, yy), col)
		# PARVIS : nappe de lumière chaude + hologrammes d'exposition flottants.
		var g0 := _uv_grille(bb, d, 0.08, 0.0)
		var g1 := _uv_grille(bb, d, 0.92, 0.30)
		ngl += _quad_plat(h, sgl, minf(g0.x, g1.x), minf(g0.y, g1.y),
				maxf(g0.x, g1.x), maxf(g0.y, g1.y), 0.014, Color(chaud.r, chaud.g, chaud.b, 0.10))
		nse += _hologramme_expo(h, bb, d, 0.16, 0.12, prune, true, se)
		nse += _hologramme_expo(h, bb, d, 0.84, 0.12, prune, false, se)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Musees")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "MuseesFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "MuseesNeon", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(se, nse), "MuseesHolos", h._mat_enseigne)
	h._ajouter_mesh(HoloMesh3D.commit(sgl, ngl), "MuseesAmbiance", h._mat_glow_chaud)

# Verrière en berceau : arches transversales régulières sur le toit (u0..u1 en
# largeur, v0..v1 en profondeur) + rails latéraux + FAÎTIÈRE lumineuse.
# Renvoie [arêtes structure, arêtes néon].
static func _verriere_uv(h, bb: Rect2i, d: Vector2i, u0: float, u1: float, v0: float, v1: float,
		haut: float, col: Color, neon: Color, s: SurfaceTool, sn: SurfaceTool) -> Array:
	var n := 0
	var hv: float = h.unite_maison * 0.55   # flèche de la voûte
	var arcs := 5
	var seg := 8
	for a in range(arcs + 1):
		var v := lerpf(v0, v1, float(a) / float(arcs))
		var prev := Vector3.ZERO
		for k in range(seg + 1):
			var t := float(k) / float(seg)
			var g := _uv_grille(bb, d, lerpf(u0, u1, t), v)
			var p: Vector3 = h._world(g.x, g.y, haut + sin(PI * t) * hv)
			if k > 0:
				n += HoloMesh3D.line(s, prev, p, col)
			prev = p
	for uu: float in [u0, u1]:   # rails latéraux au niveau du toit
		var ga := _uv_grille(bb, d, uu, v0)
		var gb := _uv_grille(bb, d, uu, v1)
		n += HoloMesh3D.line(s, h._world(ga.x, ga.y, haut), h._world(gb.x, gb.y, haut), col)
	var fa := _uv_grille(bb, d, (u0 + u1) * 0.5, v0)
	var fb := _uv_grille(bb, d, (u0 + u1) * 0.5, v1)
	var nn := HoloMesh3D.line(sn, h._world(fa.x, fa.y, haut + hv), h._world(fb.x, fb.y, haut + hv), neon)
	return [n, nn]

# Hologramme d'exposition : mât fin + « œuvre » flottante (anneau double OU
# losange) projetée au-dessus du parvis. Renvoie le nb d'arêtes.
static func _hologramme_expo(h, bb: Rect2i, d: Vector2i, u: float, v: float,
		col: Color, anneau: bool, s: SurfaceTool) -> int:
	var g := _uv_grille(bb, d, u, v)
	var base: Vector3 = h._world(g.x, g.y, 0.0)
	var hm: float = h.unite_maison * 0.9
	var n := HoloMesh3D.line(s, base, base + Vector3(0, hm * 0.55, 0), Color(col, 0.55))
	var c := base + Vector3(0, hm, 0)
	if anneau:
		n += HoloMesh3D.circle(s, c, h.taille_cellule * 0.16, col, 16)
		n += HoloMesh3D.circle(s, c + Vector3(0, h.taille_cellule * 0.05, 0),
				h.taille_cellule * 0.10, col, 12)
	else:
		n += HoloMesh3D.diamond(s, c, h.taille_cellule * 0.11, h.taille_cellule * 0.20, col)
	return n

# Gyrophares de toit aux angles de la façade d'entrée + voitures de patrouille
# stationnées le long de cette façade (carrosserie sombre + rampe lumineuse bleue
# clignotante sur le toit). Renvoie [arêtes structure, arêtes balise].
static func _patrouille_commissariat(h, ent: Dictionary, haut: float, col: Color, gyro: Color,
		s: SurfaceTool, sb: SurfaceTool) -> Array:
	var cmid: Vector2i = ent["cell"]
	var d: Vector2i = ent["dir"]
	var seg: Array = h._cote_cellule(cmid, d)
	var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
	var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
	var out := Vector3(float(d.x), 0.0, float(d.y))
	var lat := (b0 - a0).normalized()
	var n := 0
	var nb := 0
	# Gyrophares aux deux angles du toit, côté façade d'entrée.
	for p: Vector3 in [a0, b0]:
		var g: Vector3 = p + Vector3(0, haut + h.taille_cellule * 0.04, 0) - out * (h.taille_cellule * 0.06)
		nb += HoloMesh3D.diamond(sb, g, h.taille_cellule * 0.05, h.taille_cellule * 0.07, gyro)
	# Voitures de patrouille garées le long du trottoir devant l'entrée.
	for t: float in [0.24, 0.76]:
		var pc: Vector3 = a0.lerp(b0, t) + out * (h.taille_cellule * 0.30)
		n += _carrosserie(h, pc, lat, col, s)
		var rampe := pc + Vector3(0, h.taille_cellule * 0.11, 0)
		nb += HoloMesh3D.line(sb, rampe - lat * (h.taille_cellule * 0.05),
				rampe + lat * (h.taille_cellule * 0.05), gyro)
	return [n, nb]

# Champ de force : grille d'énergie tendue au-dessus de la cour (toutes les cases du
# bloc), à hauteur `y`. Une tuile en X par case + cadre extérieur. Renvoie le nb d'arêtes.
static func _champ_force(h, cells: Array, y: float, col: Color, s: SurfaceTool) -> int:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var hw: float = h.taille_cellule * 0.5
	for c: Vector2i in cells:
		var ctr: Vector3 = h._world(c.x, c.y, y)
		n += HoloMesh3D.line(s, ctr + Vector3(-hw, 0, -hw), ctr + Vector3(hw, 0, hw), col)
		n += HoloMesh3D.line(s, ctr + Vector3(-hw, 0, hw), ctr + Vector3(hw, 0, -hw), col)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			n += HoloMesh3D.line(s, h._world(seg[0].x, seg[0].y, y),
					h._world(seg[1].x, seg[1].y, y), col)
	return n
