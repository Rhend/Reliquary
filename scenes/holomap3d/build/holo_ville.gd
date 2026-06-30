# ============================================================
# holo_ville — Tissu URBAIN extrait de HoloMap3D (refactor).
#
# La ville construite : voirie (routes, marquage, trottoirs, éclairage, trafic),
# bâtiments + spires, eau, ponts/routes surélevées, trafic aérien. Même pattern
# que holo_decor/holo_env : `static func famille(h)` où `h` = le noeud HoloMap3D
# (NON typé → pas de cycle class_name). Les helpers de base partagés (_world,
# _moduler, _bati_boite, _centre_bbox, _hauteur_monde, _accent_hauteur,
# _bati_forme, _maison_variee, _etages_bloc, _cote_cellule, _ajouter_mesh) restent
# sur HoloMap3D, appelés via h.*. Les helpers PROPRES à la voirie sont privés ici.
# Locales issues de h.* typées explicitement (inférence Variant interdite).
# Appelé via `const Ville := preload(...)` côté HoloMap3D.
# ============================================================
extends RefCounted

const Geo := preload("res://scenes/holomap3d/build/holo_geo.gd")

# ─── Routes : surface + marquage de voirie + trafic simulé ────
static func routes(h) -> void:
	# 1) Surface.
	var st := HoloMesh3D.st_tri()
	var nt := 0
	var hw: float = h.taille_cellule * 0.5
	for cell: Vector2i in h._excel.routes:
		var c: Vector3 = h._world(cell.x, cell.y, 0.02)
		var u: float = float(cell.x + cell.y) * h.taille_cellule
		var col := Color(1, 1, 1, 0.28)
		var p0 := c + Vector3(-hw, 0, -hw)
		var p1 := c + Vector3(hw, 0, -hw)
		var p2 := c + Vector3(hw, 0, hw)
		var p3 := c + Vector3(-hw, 0, hw)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.set_color(col); st.set_uv(Vector2(u, 0)); st.add_vertex(v)
		nt += 2
	var surf := HoloMesh3D.commit(st, nt)
	if surf != null:
		var mi := MeshInstance3D.new()
		mi.name = "RoutesSurfaceExcel"
		mi.mesh = surf
		mi.material_override = h._mat_routes
		h._monde.add_child(mi)
	var inter := _routes_intersections(h)   # trafic (verrou plein, sécurité)
	# 2) Marquage au sol par GRAPHE de centerline : médiane + lignes de voie qui
	#    suivent les ANGLES et s'OUVRENT aux vrais carrefours (T / croisements).
	var sm := HoloMesh3D.st()
	var nm := _marquage_voirie(h, sm)
	h._ajouter_mesh(HoloMesh3D.commit(sm, nm), "RoutesMarquage", h._mat_neon)
	# 3) Trafic SIMULÉ (HoloTraffic) : les voitures suivent les voies, tournent au
	#    bon sens aux intersections et NE SE CROISENT PAS (réservation de cases).
	if h.trafic_actif:
		var n_cars := clampi(int(h._excel.routes.size() * h.densite_trafic), 8, 220)
		var trafic := HoloTraffic.new()
		trafic.name = "TraficSim"
		h._monde.add_child(trafic)
		trafic.configurer(h._excel.routes, inter, h._cgrid(), h.taille_cellule,
				0.06, h._mat_neon, n_cars, h.seed_val ^ 0x40A05)

# Décompose les cases-route en RUNS contigus (par ligne si horizontal, sinon par
# colonne). Renvoie un Array de [ligne, début, fin] (coordonnées de grille).
static func _routes_runs(h, horizontal: bool) -> Array:
	var par_ligne := {}
	for c: Vector2i in h._excel.routes:
		var ligne: int = c.y if horizontal else c.x
		var perp: int = c.x if horizontal else c.y
		if not par_ligne.has(ligne):
			par_ligne[ligne] = []
		(par_ligne[ligne] as Array).append(perp)
	var runs: Array = []
	for ligne in par_ligne:
		var arr: Array = par_ligne[ligne]
		arr.sort()
		var debut: int = arr[0]
		var prev: int = arr[0]
		for i in range(1, arr.size()):
			if arr[i] == prev + 1:
				prev = arr[i]
			else:
				runs.append([ligne, debut, prev])
				debut = arr[i]
				prev = arr[i]
		runs.append([ligne, debut, prev])
	return runs

# Décompose la voirie en BANDES rectangulaires (rangées/colonnes contiguës de même
# emprise) → chaque bande connaît son axe (H/V) et sa largeur. On ne garde une bande
# que si sa longueur ≥ sa largeur (sinon c'est l'autre orientation qui la décrit).
static func _routes_bandes(h) -> Array:
	var bandes: Array = []
	for horiz in [true, false]:
		var par_emprise := {}
		for r in _routes_runs(h, horiz):
			var key := "%d,%d" % [r[1], r[2]]
			if not par_emprise.has(key):
				par_emprise[key] = []
			(par_emprise[key] as Array).append(int(r[0]))
		for key in par_emprise:
			var lignes: Array = par_emprise[key]
			lignes.sort()
			var bornes := (key as String).split(",")
			var e0 := int(bornes[0])
			var e1 := int(bornes[1])
			var i := 0
			while i < lignes.size():
				var j := i
				while j + 1 < lignes.size() and int(lignes[j + 1]) == int(lignes[j]) + 1:
					j += 1
				var largeur: int = int(lignes[j]) - int(lignes[i]) + 1
				if (e1 - e0 + 1) >= largeur:
					if horiz:
						bandes.append({"axe": "H", "x0": e0, "x1": e1, "y0": int(lignes[i]), "y1": int(lignes[j])})
					else:
						bandes.append({"axe": "V", "x0": int(lignes[i]), "x1": int(lignes[j]), "y0": e0, "y1": e1})
				i = j + 1
	return bandes

# Point monde d'une bande à (along, across) en coords de grille (selon l'axe).
static func _pt_bande(h, horiz: bool, av: float, wv: float, y: float) -> Vector3:
	return h._world(av, wv, y) if horiz else h._world(wv, av, y)

# Longueur du segment de route traversant `c` selon l'axe de `dir`.
static func _run_len(R: Dictionary, c: Vector2i, dir: Vector2i) -> int:
	var n := 1
	var p := c + dir
	while R.has(p):
		n += 1; p += dir
	p = c - dir
	while R.has(p):
		n += 1; p -= dir
	return n

# FRANCHISSEMENTS : cases d'EAU qui coupent une route (route de part et d'autre, H
# ou V) ET recouvertes par un PONT (calque Surélevé). La route les franchit → on les
# traite comme route pour la continuité du corridor, et le tablier porte la médiane.
static func _franchissements(h) -> Dictionary:
	var pont_cells := {}
	for p in h._excel.ponts:
		for pc: Vector2i in p["cells"]:
			pont_cells[pc] = true
	var cut := {}
	var T: Dictionary = h._excel.type_case
	for c: Vector2i in h._excel.eaux:
		if not pont_cells.has(c):
			continue
		var lr: bool = int(T.get(c + Vector2i(-1, 0), 0)) == HoloXlsxMap.Cell.ROUTE \
			and int(T.get(c + Vector2i(1, 0), 0)) == HoloXlsxMap.Cell.ROUTE
		var ud: bool = int(T.get(c + Vector2i(0, -1), 0)) == HoloXlsxMap.Cell.ROUTE \
			and int(T.get(c + Vector2i(0, 1), 0)) == HoloXlsxMap.Cell.ROUTE
		if lr or ud:
			cut[c] = true
	return cut

# Marquage de voirie par GRAPHE de centerline. Pour chaque case on déduit son AXE
# dominant (corridor H ou V) → la médiane/les voies suivent le corridor, tournent
# aux ANGLES, et s'OUVRENT aux cases « carrefour » (≥ 3 bras de corridor = T ou
# croisement). Robuste aux largeurs : une voie 2-large reste un seul corridor.
static func _marquage_voirie(h, s: SurfaceTool) -> int:
	# Franchissements (eau qui coupe une route MAIS couverte par un pont) → comptés
	# comme route pour la CONTINUITÉ du corridor : le marquage traverse au lieu de
	# « diviser » la route. La médiane VISIBLE au franchissement est portée par le
	# tablier (cf. _bati_pont) ; ici on les ajoute juste au graphe, sans tracé plat.
	var pont_cut := _franchissements(h)
	var R := {}
	for c: Vector2i in h._excel.routes:
		R[c] = true
	for c: Vector2i in pont_cut:
		R[c] = true
	var cells: Array = R.keys()
	var axis := {}
	for c: Vector2i in cells:
		axis[c] = 0 if _run_len(R, c, Vector2i(1, 0)) >= _run_len(R, c, Vector2i(0, 1)) else 1
	# Cases ouvertes (vrai T / croisement) : ≥ 3 bras SUBSTANTIELS (qui s'étendent
	# sur ≥ 2 cases). Exclut les moignons de coin ET la voie adjacente d'une route
	# large (qui ne s'étend que d'1 case en perpendiculaire) → les COINS tournent.
	var ouvert := {}
	for c: Vector2i in cells:
		var deg := 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if R.has(c + d) and R.has(c + d + d):
				deg += 1
		if deg >= 3:
			ouvert[c] = true
	# Nœud médian (centre de la coupe transversale du corridor) + largeur.
	var node := {}
	var larg := {}
	for c: Vector2i in cells:
		var ax: int = axis[c]
		if ax == 0:
			var lo := c.y; var hi := c.y
			while R.has(Vector2i(c.x, lo - 1)) and int(axis.get(Vector2i(c.x, lo - 1), -1)) == 0: lo -= 1
			while R.has(Vector2i(c.x, hi + 1)) and int(axis.get(Vector2i(c.x, hi + 1), -1)) == 0: hi += 1
			node[c] = Vector2(float(c.x), (float(lo) + float(hi)) * 0.5)
			larg[c] = hi - lo + 1
		else:
			var lo := c.x; var hi := c.x
			while R.has(Vector2i(lo - 1, c.y)) and int(axis.get(Vector2i(lo - 1, c.y), -1)) == 1: lo -= 1
			while R.has(Vector2i(hi + 1, c.y)) and int(axis.get(Vector2i(hi + 1, c.y), -1)) == 1: hi += 1
			node[c] = Vector2((float(lo) + float(hi)) * 0.5, float(c.y))
			larg[c] = hi - lo + 1
	# UNE seule médiane pointillée au centre du corridor (épuré, suit les angles).
	var col_med := Color(0.95, 0.55, 0.82)
	var n := 0
	var vus := {}
	for c: Vector2i in h._excel.routes:
		if ouvert.has(c):
			continue
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc := c + d
			if not R.has(nc) or ouvert.has(nc) or pont_cut.has(nc):
				continue
			var na: Vector2 = node[c]
			var nb: Vector2 = node[nc]
			if na.distance_to(nb) < 0.01:
				continue
			var key := "%.1f,%.1f,%.1f,%.1f" % [minf(na.x, nb.x), minf(na.y, nb.y), maxf(na.x, nb.x), maxf(na.y, nb.y)]
			if vus.has(key):
				continue
			vus[key] = true
			n += Geo.dashes(s, h._world(na.x, na.y, 0.045), h._world(nb.x, nb.y, 0.045), col_med,
					h.taille_cellule * 0.5, h.taille_cellule * 0.35)
	return n

# Cases d'INTERSECTION = couvertes par une bande horizontale ET une bande verticale.
# Pour le TRAFIC (verrou plein, sécurité) : toutes les bandes. Pour le MARQUAGE
# (`directionnel`) : seulement le croisement de deux bandes DIRECTIONNELLES (longueur
# > largeur) → les bandes « carrées » (routes 2-voies à largeur variable) ne sont
# plus prises pour des carrefours, donc les marquages ne disparaissent plus.
static func _routes_intersections(h, directionnel := false) -> Dictionary:
	var in_h := {}
	var in_v := {}
	for b in _routes_bandes(h):
		var horiz: bool = b["axe"] == "H"
		var lon: int = (int(b["x1"]) - int(b["x0"]) + 1) if horiz else (int(b["y1"]) - int(b["y0"]) + 1)
		var lar: int = (int(b["y1"]) - int(b["y0"]) + 1) if horiz else (int(b["x1"]) - int(b["x0"]) + 1)
		if directionnel and lon <= lar:
			continue
		for gx in range(int(b["x0"]), int(b["x1"]) + 1):
			for gy in range(int(b["y0"]), int(b["y1"]) + 1):
				if horiz:
					in_h[Vector2i(gx, gy)] = true
				else:
					in_v[Vector2i(gx, gy)] = true
	var inter := {}
	for c: Vector2i in in_h:
		if in_v.has(c):
			inter[c] = true
	return inter

# Trottoirs : trait clair (béton) le long de CHAQUE bord de voirie (côté d'une case
# route dont le voisin n'est pas une route) → bordure de chaussée continue.
static func trottoirs(h) -> void:
	var routes_set := {}
	for c: Vector2i in h._excel.routes:
		routes_set[c] = true
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(1.0, 0.45, 0.78)   # contour néon vif (définit la forme de la route)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in h._excel.routes:
		for d: Vector2i in dirs:
			if routes_set.has(cell + d):
				continue
			var seg: Array = h._cote_cellule(cell, d)
			n += HoloMesh3D.line(s, h._world(seg[0].x, seg[0].y, 0.03),
					h._world(seg[1].x, seg[1].y, 0.03), col)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "ContourRoutesExcel", h._mat_neon)

# Éclairage public : petits lampadaires (mât sombre + tête chaude qui glow) posés
# le long des axes de voirie, à intervalle régulier, décalés sur le trottoir.
static func eclairage(h) -> void:
	var mats := HoloMesh3D.st()       # mâts (sombres)
	var nm := 0
	var tetes := HoloMesh3D.st()      # têtes lumineuses (glow chaud)
	var nt := 0
	var col_mat := Color(0.35, 0.38, 0.42)
	var col_tete := Color(1.0, 0.82, 0.50)
	var ht: float = h.unite_maison * 1.4      # hauteur du mât
	var pas := 4                       # un lampadaire toutes les 4 cases
	# Sur les DEUX bords extérieurs de chaque bande (quelle que soit la largeur).
	for b in _routes_bandes(h):
		var horiz: bool = b["axe"] == "H"
		var a0: int = b["x0"] if horiz else b["y0"]
		var a1: int = b["x1"] if horiz else b["y1"]
		var w0: int = b["y0"] if horiz else b["x0"]
		var w1: int = b["y1"] if horiz else b["x1"]
		if a1 - a0 < 2:
			continue
		var bords := [float(w0) - 0.65, float(w1) + 0.65]
		var k := a0 + 1
		while k < a1:
			for wv: float in bords:
				var base := _pt_bande(h, horiz, float(k), wv, 0.0)
				var tete := base + Vector3(0, ht, 0)
				nm += HoloMesh3D.line(mats, base, tete, col_mat)
				nt += HoloMesh3D.diamond(tetes, tete, h.taille_cellule * 0.08, h.unite_maison * 0.18, col_tete)
			k += pas
	h._ajouter_mesh(HoloMesh3D.commit(mats, nm), "LampadairesMats", h._mat_ambiance)
	h._ajouter_mesh(HoloMesh3D.commit(tetes, nt), "LampadairesTetes", h._mat_neon)

# Boule à facettes (sommet de pyramide) : 3 grands cercles orthogonaux + rayons
# lumineux distribués sur 360° (sphère de Fibonacci). Tourne (cf. _process).
static func _disco(h, apex: Vector3, rayon_boule: float, longueur_rayons: float) -> void:
	var node := Node3D.new()
	node.name = "DiscoPyramide"
	node.position = apex
	var s := HoloMesh3D.st()
	var n := 0
	var blanc := Color(0.55, 0.78, 0.95)   # cyan doux (plus de blanc-supernova)
	n += HoloMesh3D.circle(s, Vector3.ZERO, rayon_boule, blanc, 18)   # plan XZ
	n += Geo.cercle_plan(s, rayon_boule, blanc, 18, true)               # plan XY
	n += Geo.cercle_plan(s, rayon_boule, blanc, 18, false)              # plan YZ
	var pal := [Color(0.32, 0.72, 0.90), Color(0.85, 0.34, 0.70),
			Color(0.90, 0.72, 0.42), Color(0.55, 0.85, 0.65)]
	var nb := 28
	for i in nb:
		var dir := Geo.point_sphere(i, nb)
		var c: Color = pal[i % pal.size()]
		# Rayons de longueur variée → halo organique, pas une étoile pleine.
		var lon := lerpf(rayon_boule * 1.6, longueur_rayons, h._hash01(Vector2i(i, 3), 5))
		n += HoloMesh3D.line(s, dir * rayon_boule, dir * lon, c)
	var mi := MeshInstance3D.new()
	mi.name = "DiscoMesh"
	mi.mesh = HoloMesh3D.commit(s, n)
	mi.material_override = h._mat_neon
	node.add_child(mi)
	h._monde.add_child(node)
	h._discos.append(node)

# Eau peinte → nappe pleine qui S'ÉCOULE (shader holo_water, motif animé en
# coordonnées monde → courant continu d'une case à l'autre).
static func eau(h) -> void:
	var s := HoloMesh3D.st_tri()
	var n := 0
	var y := 0.008
	var hw: float = h.taille_cellule * 0.5
	for cell: Vector2i in h._excel.eaux:
		var c: Vector3 = h._world(cell.x, cell.y, y)
		var p0 := c + Vector3(-hw, 0, -hw)
		var p1 := c + Vector3(hw, 0, -hw)
		var p2 := c + Vector3(hw, 0, hw)
		var p3 := c + Vector3(-hw, 0, hw)
		for v in [p0, p1, p2, p0, p2, p3]:
			s.set_color(Color.WHITE); s.add_vertex(v)
		n += 2
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "EauExcel", h._mat_eau)

# Bordure d'eau : fin liseré cyan vif (glow) le long de chaque bord de plan d'eau
# (côté d'une case eau dont le voisin n'est pas de l'eau) → la nappe se détache.
static func bordure_eau(h) -> void:
	var eaux := {}
	for c: Vector2i in h._excel.eaux:
		eaux[c] = true
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(0.45, 0.95, 1.0)   # cyan vif (au-dessus du seuil de glow)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in h._excel.eaux:
		for d: Vector2i in dirs:
			if eaux.has(cell + d):
				continue
			var seg: Array = h._cote_cellule(cell, d)
			n += HoloMesh3D.line(s, h._world(seg[0].x, seg[0].y, 0.014),
					h._world(seg[1].x, seg[1].y, 0.014), col)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "BordureEauExcel", h._mat_neon)

# Bâtiments lus : volumes creux (arêtes _mat_decor + faces sombres _mat_faces).
# Boîte = silhouette extrudée de l'emprise exacte ; autres formes = paramétriques
# sur la bbox du bloc. Les tours orphelines (code posé sur l'eau, ex. « 9c ») sont
# rendues comme volume compact à leur case.
static func batiments(h) -> void:
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var n := 0
	var nf := 0
	var col := Color(h.couleur_decor_bati, 0.85)
	for b in h._excel.batiments:
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		var forme: int = b["forme"]
		# Heat de skyline (tour haute → cyan-blanc) PUIS gradient de richesse :
		# la hiérarchie de hauteur se lit, la périphérie se ternit.
		var bcol: Color = h._accent_hauteur(col, haut, h._centre_bbox(b["bbox"]))
		if forme == HoloXlsxMap.Forme.BOITE:
			var cells: Array = b["cells"]
			if cells.size() > 1 and h._excel.bloc_enclos(cells):
				# Groupe ENTOURÉ d'une bordure épaisse → UN bâtiment plein (100 %).
				var r: Array = h._bati_boite(cells, haut, bcol, s, sf)
				n += r[0]; nf += r[1]
				n += h._etages_bloc(b["bbox"], cells.size(), haut, bcol, s)
			else:
				# Par défaut : chaque case = une maison à 80 %, avec une SILHOUETTE variée
				# (toit plat / toit en pointe / étages / retrait au sommet) piochée de
				# façon déterministe → la rangée de maisons n'est plus monotone. EXCEPTION :
				# un bâtiment portant des SPOTS (toit_plat) → boîte plate forcée (override
				# du pool de variété : pas de chapeau ni de biseau, cf. chantier verticalité).
				var plat: bool = b.get("toit_plat", false)
				for cell: Vector2i in cells:
					if plat:
						var ctr: Vector3 = h._world(cell.x, cell.y, 0.0)
						var sz: float = h.taille_cellule * 0.8
						n += HoloMesh3D.box(s, ctr, sz, haut, sz, bcol)
						nf += HoloMesh3D.box_faces(sf, ctr, sz * h.FACE_INSET, haut, sz * h.FACE_INSET)
					else:
						var r: Array = h._maison_variee(cell, haut, bcol, s, sf)
						n += r[0]; nf += r[1]
		else:
			var bb: Rect2i = b["bbox"]
			var sx: float = float(bb.size.x) * h.taille_cellule * h.FACE_INSET
			var sz: float = float(bb.size.y) * h.taille_cellule * h.FACE_INSET
			var centre: Vector3 = h._centre_bbox(bb)
			var r: Array = h._bati_forme(centre, sx, sz, haut, forme, bcol, s, sf)
			n += r[0]; nf += r[1]
			# Boule à facettes au sommet de la pyramide (rayons lumineux 360°).
			if forme == HoloXlsxMap.Forme.PYRAMIDE:
				_disco(h, centre + Vector3(0, haut, 0), h.taille_cellule * 0.7, h.taille_cellule * 1.7)
	for t in h._excel.tours_orphelines:
		var haut: float = h._hauteur_monde(t["hauteur_m"])
		var rect: Rect2i = t["rect"]
		# Centrée et dimensionnée sur le plan d'eau (≈ 70 % de sa plus petite dimension).
		var taille: float = float(mini(rect.size.x, rect.size.y)) * h.taille_cellule * 0.7
		var r: Array = h._bati_forme(h._centre_bbox(rect), taille, taille, haut, t["forme"],
				h._accent_hauteur(col, haut, h._centre_bbox(rect)), s, sf)
		n += r[0]; nf += r[1]
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "BatimentsExcel")
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "BatimentsExcelFaces"
		mif.mesh = fmesh
		mif.material_override = h._mat_faces
		h._monde.add_child(mif)

# ─── Spires corpo : faisceaux de lumière verticaux + mâts d'antenne ───────────
# Les plus hautes tours (vraies « corpos ») projettent un SHAFT de lumière qui
# stabe le ciel + un mât d'antenne fuselé → verticalité dramatique, signal de
# pouvoir au-dessus du tissu urbain. Limité aux `spires_max` plus hautes (clarté).
static func spires(h) -> void:
	var tours: Array = []
	for b in h._excel.batiments:
		var haut: float = h._hauteur_monde(b["hauteur_m"])
		if haut >= h.hauteur_tour_ref * 0.7:
			tours.append({"c": h._centre_bbox(b["bbox"]), "h": haut})
	for t in h._excel.tours_orphelines:
		var haut: float = h._hauteur_monde(t["hauteur_m"])
		if haut >= h.hauteur_tour_ref * 0.7:
			tours.append({"c": h._centre_bbox(t["rect"]), "h": haut})
	if tours.is_empty():
		return
	tours.sort_custom(func(a, b): return a["h"] > b["h"])
	# Espacement : on retient les plus hautes MAIS distinctes (≥ sep) → des spires
	# HÉROS réparties sur des landmarks, pas une grappe de faisceaux au même endroit.
	var sep: float = h.taille_cellule * 4.5
	var picked: Array = []
	for t in tours:
		var ok := true
		for p in picked:
			if Vector2(t["c"].x - p["c"].x, t["c"].z - p["c"].z).length() < sep:
				ok = false
				break
		if ok:
			picked.append(t)
			if picked.size() >= h.spires_max:
				break
	var smast := HoloMesh3D.st()    # mâts + têtes (lignes néon, monde absolu)
	var nmast := 0
	for t in picked:
		var c: Vector3 = t["c"]
		var haut: float = t["h"]
		var top := c + Vector3(0, haut, 0)
		var acc: Color = h._accent_hauteur(Color(h.couleur_decor_bati, 1.0), haut, c)
		# Faisceau LARGE et HAUT : plus la tour est haute, plus le shaft monte loin.
		_beam(h, top, lerpf(2.6, 4.2, clampf(haut / (h.hauteur_tour_ref * 2.0), 0.0, 1.0)) * haut,
				h.taille_cellule * 0.7, Color(acc.r, acc.g, acc.b, 0.6))
		# Mât d'antenne : segment fin + 2 haubans + tête lumineuse (nœud de données).
		var mh := haut * 0.42
		var tip := top + Vector3(0, mh, 0)
		var lc := Color(acc.r, acc.g, acc.b, 0.95)
		nmast += HoloMesh3D.line(smast, top, tip, lc)
		var hub: float = h.taille_cellule * 0.22
		nmast += HoloMesh3D.line(smast, tip, top + Vector3(hub, mh * 0.45, 0.0), lc)
		nmast += HoloMesh3D.line(smast, tip, top + Vector3(-hub, mh * 0.45, 0.0), lc)
		nmast += HoloMesh3D.diamond(smast, tip, h.taille_cellule * 0.06, h.taille_cellule * 0.10, lc)
	h._ajouter_mesh(HoloMesh3D.commit(smast, nmast), "SpiresMats", h._mat_neon)

# Faisceau vertical (billboard cylindrique) : une instance dédiée par spire — le
# shader holo_beam lit la base via MODEL_MATRIX, d'où une instance positionnée.
static func _beam(h, base: Vector3, hauteur: float, demi_l: float, col: Color) -> void:
	var s := HoloMesh3D.st_tri()
	var bl := Vector3.ZERO
	var br := Vector3.ZERO
	var tl := Vector3(0, hauteur, 0)
	var tr := Vector3(0, hauteur, 0)
	Geo.beam_vert(s, bl, 0.0, -1.0, demi_l, col)
	Geo.beam_vert(s, br, 0.0, 1.0, demi_l, col)
	Geo.beam_vert(s, tr, 1.0, 1.0, demi_l, col)
	Geo.beam_vert(s, bl, 0.0, -1.0, demi_l, col)
	Geo.beam_vert(s, tr, 1.0, 1.0, demi_l, col)
	Geo.beam_vert(s, tl, 1.0, -1.0, demi_l, col)
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = s.commit()
	mi.material_override = h._mat_beam
	mi.position = base
	h._monde.add_child(mi)

# ─── Trafic aérien : couloirs de VTOL à plusieurs altitudes au-dessus de la ville ──
# Réutilise le shader de trafic (segment translaté le long d'un trajet). Des
# traînées cyan/ambre traversent le ciel → la mégalopole circule en 3D, pas qu'au sol.
static func trafic_aerien(h) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x5A1B2C
	var s := HoloMesh3D.st()
	var total := 0
	var span: float = h._cgrid() * h.taille_cellule
	for i in maxi(0, h.couloirs_aeriens):
		var alt := lerpf(h.hauteur_tour_ref * 1.3, h.hauteur_tour_ref * 3.0, rng.randf())
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var off := perp * rng.randf_range(-span * 0.55, span * 0.55)
		var lon := span * 2.4
		var depart := -dir * (lon * 0.5) + off + Vector3(0.0, alt, 0.0)
		var couleur: Color = h.couleur_voiture_aller if rng.randf() < 0.5 else h.couleur_voiture_retour
		var nb := rng.randi_range(4, 7)
		Geo.semer_voitures(s, depart, dir * lon, h.taille_cellule * 2.4, rng, couleur, nb,
				rng.randf_range(0.7, 1.5))
		total += nb
	h._ajouter_mesh(HoloMesh3D.commit(s, total), "TraficAerien", h._mat_trafic_aerien)

# ─── Ponts (calque Surélevé) : tablier en RAMPE + structure + garde-corps + trafic ──
# Le tablier part du sol à un bout, monte (/), traverse en hauteur, redescend (\)
# au sol à l'autre bout → il « colle à la route ». Des voitures circulent dessus
# (montée, traversée, descente). L'eau/route restent visibles dessous.
static func ponts(h) -> void:
	if h._excel.ponts.is_empty():
		return
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var smed := HoloMesh3D.st()        # médiane portée par le tablier (continuité route)
	var st := SurfaceTool.new()       # trafic des ponts (réutilise holo_traffic)
	st.begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x9011D5
	var pont_cut := _franchissements(h)
	var n := 0
	var nf := 0
	var nmed := 0
	var ncar := 0
	var col := Color(0.64, 0.74, 0.86)   # acier clair (glow via _mat_decor)
	for p in h._excel.ponts:
		# Pont « routier » (franchit une coupure route/eau) → porte la médiane.
		var porte_route := false
		for pc: Vector2i in p["cells"]:
			if pont_cut.has(pc):
				porte_route = true
				break
		var r := _bati_pont(h, p, col, s, sf, smed, st, rng, porte_route)
		n += r[0]; nf += r[1]; ncar += r[2]; nmed += r[3]
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "PontsExcel")
	h._ajouter_mesh(HoloMesh3D.commit(smed, nmed), "PontsMarquage", h._mat_neon)
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "PontsExcelFaces"
		mif.mesh = fmesh
		mif.material_override = h._mat_faces
		h._monde.add_child(mif)
	if ncar > 0:
		var mit := MeshInstance3D.new()
		mit.name = "PontsTrafic"
		mit.mesh = st.commit()
		mit.material_override = h._mat_trafic
		h._monde.add_child(mit)

# Un pont en rampe : tablier (surface + bords + traverses) suivant le profil,
# garde-corps (main courante + montants) au-dessus, treillis (corde basse +
# montants + diagonales) sous la partie élevée, piliers optionnels, et trafic.
# Renvoie [nb arêtes, nb faces, nb voitures].
static func _bati_pont(h, pont: Dictionary, col: Color, s: SurfaceTool, sf: SurfaceTool,
		smed: SurfaceTool, st: SurfaceTool, rng: RandomNumberGenerator,
		porte_route: bool) -> Array:
	var bbox: Rect2i = pont["bbox"]
	var alt: float = h._hauteur_monde(pont["altitude_m"])   # hauteur du plateau
	var ep: float = h.taille_cellule * 0.14
	var rail_h: float = h.taille_cellule * 0.40
	var rf := 0.40
	var span_x := bbox.size.x >= bbox.size.y
	var long_cells: int = bbox.size.x if span_x else bbox.size.y
	var larg_cells: int = bbox.size.y if span_x else bbox.size.x
	var along := Vector3(1, 0, 0) if span_x else Vector3(0, 0, 1)
	var side := Vector3(0, 0, 1) if span_x else Vector3(1, 0, 0)
	var centre_sol: Vector3 = h._world(bbox.position.x + (bbox.size.x - 1) * 0.5,
			bbox.position.y + (bbox.size.y - 1) * 0.5, 0.0)
	var demi_long: float = float(long_cells) * h.taille_cellule * 0.5
	var demi_large: float = float(larg_cells) * h.taille_cellule * 0.47
	var end_a := centre_sol - along * demi_long
	var end_b := centre_sol + along * demi_long
	var nb := maxi(6, long_cells * 3)
	var n := 0
	var nf := 0
	var centers: Array[Vector3] = []
	for i in nb + 1:
		var t := float(i) / float(nb)
		centers.append(end_a.lerp(end_b, t) + Vector3(0, Geo.profil_pont(t, alt, rf), 0))
	# Tablier : surface (faces) + bords gauche/droite + traverses.
	for i in nb:
		var c0 := centers[i] + Vector3(0, ep, 0)
		var c1 := centers[i + 1] + Vector3(0, ep, 0)
		var l0 := c0 + side * demi_large; var r0 := c0 - side * demi_large
		var l1 := c1 + side * demi_large; var r1 := c1 - side * demi_large
		nf += HoloMesh3D._quad(sf, l0, r0, r1, l1, Vector3.UP)
		n += HoloMesh3D.line(s, l0, l1, col)
		n += HoloMesh3D.line(s, r0, r1, col)
		n += HoloMesh3D.line(s, l0, r0, col)
	var cf := centers[nb] + Vector3(0, ep, 0)
	n += HoloMesh3D.line(s, cf + side * demi_large, cf - side * demi_large, col)
	# Garde-corps + treillis le long des deux bords (suivent le profil en rampe).
	for cote: float in [-1.0, 1.0]:
		var prev_rail := Vector3.ZERO
		var prev_bot := Vector3.ZERO
		for i in nb + 1:
			var c := centers[i]
			var edge := c + side * (demi_large * cote)
			var deck := edge + Vector3(0, ep, 0)
			var rail := deck + Vector3(0, rail_h, 0)
			var bot := Vector3(edge.x, maxf(0.02, c.y - h.taille_cellule * 0.5), edge.z)
			n += HoloMesh3D.line(s, deck, rail, col)         # montant de garde-corps
			if c.y - 0.03 > bot.y:
				n += HoloMesh3D.line(s, edge, bot, col)      # montant de treillis (partie élevée)
			if i > 0:
				n += HoloMesh3D.line(s, prev_rail, rail, col)   # main courante
				n += HoloMesh3D.line(s, prev_bot, bot, col)     # corde basse
			prev_rail = rail
			prev_bot = bot
	# Piliers (si « Ouvrages d'art » le précise) : sous la partie élevée, vers le sol.
	if pont["piliers"]:
		for i in range(1, nb, 2):
			var c := centers[i]
			if c.y > alt * 0.6:
				n += HoloMesh3D.line(s, Vector3(c.x, maxf(0.02, c.y - h.taille_cellule * 0.5), c.z),
						Vector3(c.x, 0.0, c.z), col)
	# Médiane pointillée PORTÉE PAR LE TABLIER (suit la rampe) → continuité avec le
	# marquage au sol de part et d'autre : la route ne « se divise » plus au pont.
	var nmed := 0
	if porte_route:
		var deck: Array[Vector3] = []
		for c2: Vector3 in centers:
			deck.append(c2 + Vector3(0, ep + 0.02, 0))
		nmed = Geo.dashes_poly(smed, deck, Color(0.95, 0.55, 0.82),
				h.taille_cellule * 0.5, h.taille_cellule * 0.35)
	# Trafic : voitures qui montent la rampe, traversent, redescendent.
	var ncar := 0
	if h.trafic_actif:
		ncar = _semer_pont_trafic(h, st, centers, ep, rng)
	return [n, nf, ncar, nmed]

# Sème des voitures sur le pont, sur 3 tronçons (montée / plateau / descente) dans
# les deux sens → la circulation suit la rampe. Renvoie le nb de voitures.
static func _semer_pont_trafic(h, st: SurfaceTool, centers: Array, ep: float, rng: RandomNumberGenerator) -> int:
	var nb: int = centers.size() - 1
	var iu := clampi(roundi(0.4 * float(nb)), 1, nb / 2)
	var dy := Vector3(0, ep + h.taille_cellule * 0.03, 0)   # roule SUR le tablier
	var troncons := [
		[centers[0], centers[iu]], [centers[iu], centers[nb - iu]], [centers[nb - iu], centers[nb]]]
	var carlen: float = h.taille_cellule * 0.5
	var ncar := 0
	for tr: Array in troncons:
		var a: Vector3 = tr[0] + dy
		var b: Vector3 = tr[1] + dy
		if a.distance_to(b) < 0.05:
			continue
		Geo.semer_voitures(st, a, b - a, carlen, rng, h.couleur_voiture_aller, 1, 1.0)
		Geo.semer_voitures(st, b, a - b, carlen, rng, h.couleur_voiture_retour, 1, 1.0)
		ncar += 2
	return ncar

# Routes magenta surélevées (autoroutes) : tuiles néon à leur altitude. Vide pour
# l'instant (le calque ne porte que des ponts) ; code prêt si l'auteur en peint.
static func routes_elevees(h) -> void:
	if h._excel.routes_elevees.is_empty():
		return
	var s := HoloMesh3D.st_tri()
	var n := 0
	var y: float = h._hauteur_monde(8.0)   # altitude par défaut d'une autoroute surélevée
	var hw: float = h.taille_cellule * 0.5
	for cell: Vector2i in h._excel.routes_elevees:
		var c: Vector3 = h._world(cell.x, cell.y, y)
		var u: float = float(cell.x + cell.y) * h.taille_cellule
		var p0 := c + Vector3(-hw, 0, -hw)
		var p1 := c + Vector3(hw, 0, -hw)
		var p2 := c + Vector3(hw, 0, hw)
		var p3 := c + Vector3(-hw, 0, hw)
		for v in [p0, p1, p2, p0, p2, p3]:
			s.set_color(Color(1, 1, 1, 0.85)); s.set_uv(Vector2(u, 0)); s.add_vertex(v)
		n += 2
	var mesh := HoloMesh3D.commit(s, n)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "RoutesEleveesExcel"
	mi.mesh = mesh
	mi.material_override = h._mat_routes
	h._monde.add_child(mi)
