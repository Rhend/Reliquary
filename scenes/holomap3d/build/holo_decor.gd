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
	var su := SurfaceTool.new()    # fumée (billboards de volutes, shader holo_fumee)
	su.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x05111E
	var n := 0
	var nf := 0
	var nn := 0
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
		nn += _conduits_facade(h, bb, haut, neon, sn)        # tuyauterie ceinturant le hall
		# 3 cheminées réparties sur le grand axe du hall, chacune avec son panache.
		var x0 := float(bb.position.x); var x1 := float(bb.position.x + bb.size.x - 1)
		var y0 := float(bb.position.y); var y1 := float(bb.position.y + bb.size.y - 1)
		var span_x := bb.size.x >= bb.size.y
		for f: float in [0.2, 0.5, 0.8]:
			var gx := lerpf(x0, x1, f) if span_x else lerpf(x0, x1, 0.28)
			var gy := lerpf(y0, y1, 0.28) if span_x else lerpf(y0, y1, f)
			var cbase: Vector3 = h._world(gx, gy, haut)
			nn += _cheminee_neon(h, cbase, neon, sn)
			nfu += _semer_fumee(h, su, cbase + Vector3(0, ch_h + h.unite_maison * 0.12, 0), rng)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Usines")
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "UsinesFaces")
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "UsinesNeon", h._mat_neon)
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

# Cheminée ÉMISSIVE posée en `base` (sur le toit) : fût lumineux + 2 anneaux + balise.
static func _cheminee_neon(h, base: Vector3, col: Color, s: SurfaceTool) -> int:
	var w: float = h.taille_cellule * 0.16
	var ch: float = h.unite_maison * 2.4
	var n := HoloMesh3D.box(s, base, w, ch, w, col)
	for rf: float in [0.55, 0.8]:
		n += HoloMesh3D.circle(s, base + Vector3(0, ch * rf, 0), w * 0.95, col, 10)
	n += HoloMesh3D.diamond(s, base + Vector3(0, ch + w, 0), w * 0.7, w * 0.9, Color(1.0, 0.32, 0.20))
	return n

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
		# Grue à aimant : posée sur la case la plus centrale d'un bloc assez grand.
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
		# Remplissage : grue / pile de carcasses écrasées / épave / vide (allées).
		for cell: Vector2i in cells:
			var c: Vector3 = h._world(cell.x, cell.y, 0.0)
			if cell == cell_grue:
				var rg := _grue_casse(h, c, col, neon, s, sg)
				n += rg[0]; ng += rg[1]
				continue
			var roll := rng.randf()
			if roll < 0.42:
				var rp := _pile_carcasses(h, c, col, neon, rng, s, sg)
				n += rp[0]; ng += rp[1]
			elif roll < 0.78:
				var re := _epave_voiture(h, c, col, neon, rng, s, sg)
				n += re[0]; ng += re[1]
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

# Épave de voiture : MÊME silhouette futuriste que les voitures du trafic (coque en
# goutte d'eau effilée + bulle de cockpit facettée), posée au sol, orientée le long de
# X ou Y au hasard. Phare néon à l'avant. Renvoie [arêtes, glow].
static func _epave_voiture(h, c: Vector3, col: Color, neon: Color, rng: RandomNumberGenerator, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var n := 0
	var ng := 0
	var tang := Vector3(0, 0, 1) if rng.randf() < 0.5 else Vector3(1, 0, 0)
	var perp := Vector3(-tang.z, 0.0, tang.x)
	var hl: float = h.taille_cellule * 0.22    # demi-longueur
	var hw: float = h.taille_cellule * 0.10    # demi-largeur (au maître-bau)
	var ht: float = h.taille_cellule * 0.085   # hauteur de la bulle
	var up := Vector3(0, ht, 0)
	# Empreinte au sol en goutte d'eau (identique au trafic : nez / maître-bau / poupe).
	var nez := c + tang * hl
	var ml := c + tang * (hl * 0.18) - perp * hw
	var mr := c + tang * (hl * 0.18) + perp * hw
	var pl := c - tang * hl - perp * (hw * 0.45)
	var pr := c - tang * hl + perp * (hw * 0.45)
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
	# Phare néon à l'avant (petite balise → « c'est une voiture »).
	ng += HoloMesh3D.diamond(sg, nez + Vector3(0, ht * 0.25, 0),
			h.taille_cellule * 0.04, h.taille_cellule * 0.045, neon)
	return [n, ng]

# Grue à électro-aimant : mât treillis + flèche + contrepoids + câble et aimant (glow).
# Icône immédiate de casse auto. Renvoie [arêtes, glow].
static func _grue_casse(h, base: Vector3, col: Color, neon: Color, s: SurfaceTool, sg: SurfaceTool) -> Array:
	var n := 0
	var ng := 0
	var mw: float = h.taille_cellule * 0.10
	var mh: float = h.unite_maison * 2.6
	n += HoloMesh3D.box(s, base, mw, mh, mw, col)              # mât
	var top := base + Vector3(0, mh, 0)
	var tip := top + Vector3(h.taille_cellule * 0.9, 0, 0)       # bout de flèche
	var back := top + Vector3(-h.taille_cellule * 0.32, 0, 0)    # arrière (contrepoids)
	var knee := top + Vector3(0, -mh * 0.16, 0)
	n += HoloMesh3D.line(s, back, tip, col)                    # membrure haute de la flèche
	n += HoloMesh3D.line(s, knee, tip, col)                    # treillis avant
	n += HoloMesh3D.line(s, knee, back, col)                   # treillis arrière
	n += HoloMesh3D.box(s, back + Vector3(0, -h.taille_cellule * 0.16, 0),
			h.taille_cellule * 0.16, h.taille_cellule * 0.18, h.taille_cellule * 0.16, col)  # contrepoids
	# Câble + électro-aimant pendu (glow → on lit la grue de loin).
	var hook := tip + Vector3(0, -mh * 0.5, 0)
	ng += HoloMesh3D.line(sg, tip, hook, neon)                 # câble
	ng += HoloMesh3D.box(sg, hook, h.taille_cellule * 0.20, h.taille_cellule * 0.10, h.taille_cellule * 0.20, neon)  # aimant
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
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "SupermarchesEnseignes", h._mat_neon)
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
