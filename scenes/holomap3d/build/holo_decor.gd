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
# terrain (gazon + losange + clôture) + GRADINS en bol + PROJECTEURS + TABLEAU.
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
	var blanc := Color(0.92, 0.96, 1.0)
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
	# Clôture + warning track.
	var prev := rfp
	var prev2 := Geo.pt_ell(c, ax, az, kf * 0.93, a_rf, 0.02)
	for i in range(1, seg + 1):
		var a := lerpf(a_rf, a_lf, float(i) / float(seg))
		var cur := Geo.pt_ell(c, ax, az, kf, a, 0.02)
		var cur2 := Geo.pt_ell(c, ax, az, kf * 0.93, a, 0.02)
		n += HoloMesh3D.line(s, prev, cur, vert)
		n += HoloMesh3D.line(s, prev2, cur2, Color(vert, 0.6))
		prev = cur; prev2 = cur2
	# Lignes de faute + losange + bases + monticule.
	n += HoloMesh3D.line(s, home, rfp, blanc)
	n += HoloMesh3D.line(s, home, lfp, blanc)
	var d1 := (rfp - home).normalized()
	var d3 := (lfp - home).normalized()
	var b := minf(ax, az) * kf * 0.42
	var first := home + d1 * b
	var third := home + d3 * b
	var second := home + (d1 + d3) * b
	n += HoloMesh3D.line(s, home, first, terre)
	n += HoloMesh3D.line(s, first, second, terre)
	n += HoloMesh3D.line(s, second, third, terre)
	n += HoloMesh3D.line(s, third, home, terre)
	for base: Vector3 in [first, second, third, home]:
		n += Geo.carre_plat(s, base, h.taille_cellule * 0.06, blanc)
	n += HoloMesh3D.circle(s, home + (d1 + d3) * (b * 0.5), b * 0.13, terre, 12)
	# ── Gradins en BOL : anneaux montants de la clôture (kf) au bord (1.0) ──
	var nb_t := 4
	var hb := minf(ax, az) * 0.55
	for t in nb_t:
		var k := lerpf(kf * 1.04, 1.0, float(t) / float(nb_t - 1))
		var yy := lerpf(0.02, hb, float(t) / float(nb_t - 1))
		n += Geo.anneau_ell(s, c, ax, az, k, yy, acier, 56)
	var nb_m := 28
	for m in nb_m:
		var a := TAU * float(m) / float(nb_m)
		var pv := Geo.pt_ell(c, ax, az, kf * 1.04, a, 0.02)
		for t in range(1, nb_t):
			var k := lerpf(kf * 1.04, 1.0, float(t) / float(nb_t - 1))
			var yy := lerpf(0.02, hb, float(t) / float(nb_t - 1))
			var cur := Geo.pt_ell(c, ax, az, k, a, yy)
			n += HoloMesh3D.line(s, pv, cur, Color(acier, 0.55))
			pv = cur
	# ── Projecteurs : mâts au sommet du bol + banc lumineux (glow) ──
	for la: float in [-0.5, -1.05, -1.6, -2.1, -2.65, 0.05]:
		var basep := Geo.pt_ell(c, ax, az, 1.0, la, hb)
		var topp := basep + Vector3(0, hb * 0.55, 0)
		n += HoloMesh3D.line(s, basep, topp, acier)
		var bw := minf(ax, az) * 0.06
		nn += Geo.carre_plat(sn, topp + Vector3(0, bw, 0), bw, Color(1.0, 0.98, 0.85))
	# ── Tableau d'affichage au centre du champ (au-delà de la clôture, −Z) ──
	var sb := Geo.pt_ell(c, ax, az, kf * 1.12, -PI * 0.5, hb * 0.45)
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
	n += HoloMesh3D.line(s, sb + Vector3(-sw * 0.7, -sh, 0), sb + Vector3(-sw * 0.7, -hb * 0.45, 0), acier)
	n += HoloMesh3D.line(s, sb + Vector3(sw * 0.7, -sh, 0), sb + Vector3(sw * 0.7, -hb * 0.45, 0), acier)
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
# à électro-aimant (icône forte). Deux couches : structure sombre + accents glow (néon).
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
		var hw: float = h.unite_maison * 0.7 * fy
		# Clôture d'enceinte (poteaux + grillage) + rail néon de sécurité au sommet.
		var rc := _cloture_casse(h, b["cells"], hw, col, neon, s, sg)
		n += rc[0]; ng += rc[1]
		# Portail (entrée) face aux routes.
		ng += h._portes_vers_routes(b["cells"], hw * 1.1, neon, sg)
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
				var tang := Vector3(1, 0, 0) if cell == cell_grue else Vector3(0, 0, 1)
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
# en X discrète) + rail NÉON au sommet (lisibilité « enclos »). Renvoie [arêtes, glow].
static func _cloture_casse(h, cells: Array, hw: float, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var ng := 0
	var up := Vector3(0, hw, 0)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg: Array = h._cote_cellule(c, d)
			var a0: Vector3 = h._world(seg[0].x, seg[0].y, 0.0)
			var b0: Vector3 = h._world(seg[1].x, seg[1].y, 0.0)
			n += HoloMesh3D.line(s, a0, b0, col)             # lisse basse (sol)
			n += HoloMesh3D.line(s, a0, a0 + up, col)        # poteau A
			n += HoloMesh3D.line(s, b0, b0 + up, col)        # poteau B
			n += HoloMesh3D.line(s, a0, b0 + up, col)        # grillage (croix)
			n += HoloMesh3D.line(s, b0, a0 + up, col)
			ng += HoloMesh3D.line(sg, a0 + up, b0 + up, neon)  # rail néon de sécurité (sommet)
	return [n, ng]

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

# Grue à électro-aimant : mât treillis + flèche (orientée selon `tang`) + contrepoids
# + câble et aimant (glow). Icône immédiate de casse auto. Renvoie [arêtes, glow].
static func _grue_casse(h, base: Vector3, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool,
		tang: Vector3 = Vector3(1, 0, 0)) -> Array:
	var n := 0
	var ng := 0
	var mw: float = h.taille_cellule * 0.10
	var mh: float = h.unite_maison * 2.6
	n += HoloMesh3D.box(s, base, mw, mh, mw, col)              # mât
	var top := base + Vector3(0, mh, 0)
	var tip: Vector3 = top + tang * (h.taille_cellule * 0.9)     # bout de flèche
	var back: Vector3 = top - tang * (h.taille_cellule * 0.32)   # arrière (contrepoids)
	var knee := top + Vector3(0, -mh * 0.16, 0)
	n += HoloMesh3D.line(s, back, tip, col)                    # membrure haute de la flèche
	n += HoloMesh3D.line(s, knee, tip, col)                    # treillis avant
	n += HoloMesh3D.line(s, knee, back, col)                   # treillis arrière
	n += HoloMesh3D.box(s, back + Vector3(0, -h.taille_cellule * 0.16, 0),
			h.taille_cellule * 0.16, h.taille_cellule * 0.18, h.taille_cellule * 0.16, col)  # contrepoids
	# Câble + électro-aimant pendu (glow → on lit la grue de loin).
	var hook: Vector3 = tip + Vector3(0, -mh * 0.5, 0)
	ng += HoloMesh3D.line(sg, tip, hook, neon)                 # câble
	ng += HoloMesh3D.box(sg, hook, h.taille_cellule * 0.20, h.taille_cellule * 0.10, h.taille_cellule * 0.20, neon)  # aimant
	# Carcasse SUSPENDUE à l'aimant (elle pend dans le vide) → grue en plein travail.
	n += _carrosserie(h, hook + Vector3(0, -h.taille_cellule * 0.16, 0),
			Vector3(-tang.z, 0, tang.x), col, s)
	return [n, ng]

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
		nn += h._portes_vers_routes(b["cells"], minf(h.unite_maison * 0.75, haut * 0.85), ambre, sn)  # entrées face aux routes
		nn += _enseignes_marquee(h, bb, haut, ambre, sn)        # bandeau lumineux périmètre
		nn += _billboard_toit(h, bb, haut, ambre, cyan, sn, sc) # panneau géant + barres cyan
		ncy += _toit_skylights(h, bb, haut, cyan, sc)           # grille de verrières (toit)
		ncy += _entree_facade(h, bb, haut, cyan, sc)            # entrée illuminée
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

# Panneau publicitaire géant dressé sur le toit (plan XY, centré) : cadre ambre +
# barres horizontales cyan (le « texte » de l'enseigne) → totem visible de loin.
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
	for m in 2:   # barres « texte » cyan
		var t := float(m + 1) / 3.0
		HoloMesh3D.line(sc, c + Vector3(-bw * 0.38, y + bh * t, 0), c + Vector3(bw * 0.38, y + bh * t, 0), col2)
	return n

# Entrée illuminée en façade (+Z) : portique lumineux + auvent → point d'accès lisible.
static func _entree_facade(h, bb: Rect2i, haut: float, col: Color, s: SurfaceTool) -> int:
	var x0 := float(bb.position.x) - 0.5
	var x1 := float(bb.position.x + bb.size.x - 1) + 0.5
	var ay := float(bb.position.y + bb.size.y - 1) + 0.5
	var ex0 := lerpf(x0, x1, 0.38)
	var ex1 := lerpf(x0, x1, 0.62)
	var eh := haut * 0.62
	var n := HoloMesh3D.line(s, h._world(ex0, ay, 0.02), h._world(ex0, ay, eh), col)
	n += HoloMesh3D.line(s, h._world(ex1, ay, 0.02), h._world(ex1, ay, eh), col)
	n += HoloMesh3D.line(s, h._world(ex0, ay, eh), h._world(ex1, ay, eh), col)
	n += HoloMesh3D.line(s, h._world(ex0 - 0.35, ay, eh + 0.06), h._world(ex1 + 0.35, ay, eh + 0.06), col)  # auvent
	return n

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
	# Parc : petits « arbres » (croix verticale + houppier diamant) un peu épars.
	# Les arbres SOUS un lieu sans bâtiment passent à la couleur de palier du lieu
	# et dans un mesh à part (matériau qui glow) : la parcelle EST le lieu, elle
	# se lit comme tel. Même densité/taille que le parc normal — seule la couleur
	# (et le glow) change.
	var sl := HoloMesh3D.st()
	var nl := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x515A11
	for k in h._parc:
		var cell := k as Vector2i
		var c: Vector3 = h._world(cell.x, cell.y, 0.0)
		var ht: float = h.unite_maison * 1.2
		if h._lieu_arbres.has(cell):
			# Cellule choisie d'un parc-lieu : arbre coloré (glow).
			var lc := Color(h._lieu_arbres[cell] as Color, 0.9)
			nl += HoloMesh3D.line(sl, c, c + Vector3(0, ht, 0), lc)
			nl += HoloMesh3D.diamond(sl, c + Vector3(0, ht + ht * 0.4, 0),
					h.taille_cellule * 0.22, ht * 0.5, lc)
		elif h._lieu_sol.has(cell):
			continue   # reste du sol du lieu : laissé vide (peu d'arbres voulus)
		elif rng.randf() <= 0.55:
			# Parc ordinaire : arbres verts épars (ternis vers la périphérie).
			var tc: Color = h._moduler(cp, c)
			n += HoloMesh3D.line(s, c, c + Vector3(0, ht, 0), tc)
			n += HoloMesh3D.diamond(s, c + Vector3(0, ht + ht * 0.4, 0),
					h.taille_cellule * 0.22, ht * 0.5, tc)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Decor", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(sl, nl), "DecorLieu", h._mat_lieu_decor)

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
	return [n, ng]

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
