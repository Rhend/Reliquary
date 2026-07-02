# ============================================================
# holo_sureleve — Éléments de VERTICALITÉ du calque « Surélevé » (chantier verticalité).
#
# Rend les ouvrages en hauteur lus par HoloXlsxMap depuis la feuille « Surélevé »
# (passerelle, héliport, spots, téléphérique, antennes, enseignes) + la CROIX ROUGE
# de feedback (contrainte violée). Les ponts / autoroutes surélevées restent dans
# holo_ville (déjà existants). Même pattern que holo_ville/holo_decor : `static func
# famille(h)` où `h` = le nœud HoloMap3D (NON typé → pas de cycle class_name).
#
# Altitude TOUJOURS saisie par l'auteur (lue dans le .tres / la cellule) et convertie
# en Y monde via h._hauteur_monde. La validation croisée (bâtiment dessous, toit assez
# large, altitude = sommet…) est faite en amont par HoloXlsxMap ; ici on REND, et toute
# contrainte non satisfaite est déjà matérialisée par une croix rouge (cf. croix()).
# ============================================================
extends RefCounted

const Geo := preload("res://scenes/holomap3d/build/holo_geo.gd")

# Couleurs DA (teintes des familles du calque Surélevé).
const COL_PASSERELLE := Color(0.50, 0.86, 0.64)
const COL_HELIPORT := Color(0.95, 0.84, 0.26)
const COL_SPOTS := Color(0.78, 0.96, 1.00)
const COL_TELE := Color(0.94, 0.55, 0.27)
const COL_ANTENNE := Color(0.74, 0.62, 0.92)
const COL_ENSEIGNE := Color(0.96, 0.58, 0.85)
const COL_CROIX := Color(0.88, 0.13, 0.13)   # E02020 (réservé feedback)

# ─── CROIX ROUGE : feedback universel d'une contrainte violée ─────────────────
# Une grosse croix rouge en VOLUME (deux X dans des plans orthogonaux → lisible sous
# tout angle) à la cellule + altitude fautives. Émissive (glow) pour bien ressortir.
static func croix_rouges(h) -> void:
	if h._excel.croix_rouges.is_empty():
		return
	var s := HoloMesh3D.st()
	var n := 0
	var r: float = h.taille_cellule * 0.85
	for cx: Dictionary in h._excel.croix_rouges:
		var cell: Vector2i = cx["cell"]
		var y: float = h._hauteur_monde(cx["altitude_m"]) + r
		var c: Vector3 = h._world(cell.x, cell.y, y)
		# X dans le plan XY.
		n += HoloMesh3D.line(s, c + Vector3(-r, -r, 0), c + Vector3(r, r, 0), COL_CROIX)
		n += HoloMesh3D.line(s, c + Vector3(-r, r, 0), c + Vector3(r, -r, 0), COL_CROIX)
		# X dans le plan ZY (croix volumétrique).
		n += HoloMesh3D.line(s, c + Vector3(0, -r, -r), c + Vector3(0, r, r), COL_CROIX)
		n += HoloMesh3D.line(s, c + Vector3(0, r, -r), c + Vector3(0, -r, r), COL_CROIX)
	# _mat_balise : clignote (cf. HoloMap3D._process) → la croix « alarme » et accroche l'œil.
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "CroixRouges", h._mat_balise)

# ─── Passerelle piéton : tablier plat + garde-corps + PORTE par bâtiment relié ──
static func passerelles(h) -> void:
	if h._excel.passerelles.is_empty():
		return
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var n := 0
	var nf := 0
	var hw: float = h.taille_cellule * 0.5
	var ep: float = h.taille_cellule * 0.06
	var rail_h: float = h.taille_cellule * 0.34
	for pa: Dictionary in h._excel.passerelles:
		var alt: float = h._hauteur_monde(pa["altitude_m"])
		var setd := {}
		for c: Vector2i in pa["cells"]:
			setd[c] = true
		# Tablier : face sombre (occlusion) + contour vif sur le périmètre + traverses.
		for c: Vector2i in pa["cells"]:
			var ctr: Vector3 = h._world(c.x, c.y, alt)
			var p0 := ctr + Vector3(-hw, 0, -hw)
			var p1 := ctr + Vector3(hw, 0, -hw)
			var p2 := ctr + Vector3(hw, 0, hw)
			var p3 := ctr + Vector3(-hw, 0, hw)
			nf += HoloMesh3D._quad(sf, p0, p1, p2, p3, Vector3.UP)
			# Bords extérieurs (vers le vide) → contour + garde-corps.
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if setd.has(c + d):
					continue
				var seg: Array = h._cote_cellule(c, d)
				var a: Vector3 = h._world(seg[0].x, seg[0].y, alt)
				var b: Vector3 = h._world(seg[1].x, seg[1].y, alt)
				n += HoloMesh3D.line(s, a, b, COL_PASSERELLE)                       # bord du tablier
				var up := Vector3(0, rail_h, 0)
				n += HoloMesh3D.line(s, a, a + up, COL_PASSERELLE)                  # montant
				n += HoloMesh3D.line(s, b, b + up, COL_PASSERELLE)
				n += HoloMesh3D.line(s, a + up, b + up, COL_PASSERELLE)             # main courante
		# PORTE d'accès percée dans chaque bâtiment touché (1 par bâtiment).
		for bc: Vector2i in pa.get("portes", []):
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if setd.has(bc + d):
					n += _porte_paroi(h, bc, bc + d, alt, COL_PASSERELLE, s)
					break
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Passerelles", h._mat_neon)
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "PasserellesFaces")

# Porte (deux jambages + linteau) sur la paroi du bâtiment `bc` qui fait face à la case
# `pc` (côté de contact), seuil au niveau `alt` du tablier. Renvoie le nb d'arêtes.
static func _porte_paroi(h, bc: Vector2i, pc: Vector2i, alt: float, col: Color, s: SurfaceTool) -> int:
	var d := pc - bc
	var seg: Array = h._cote_cellule(bc, d)
	var pa: Vector3 = h._world(seg[0].x, seg[0].y, alt)
	var pb: Vector3 = h._world(seg[1].x, seg[1].y, alt)
	var mid: Vector3 = (pa + pb) * 0.5
	var half: Vector3 = (pb - pa) * 0.26
	var jl: Vector3 = mid - half
	var jr: Vector3 = mid + half
	var dh := Vector3(0, h.unite_maison * 1.5, 0)
	return HoloMesh3D.line(s, jl, jl + dh, col) + HoloMesh3D.line(s, jr, jr + dh, col) \
			+ HoloMesh3D.line(s, jl + dh, jr + dh, col)

# ─── Héliport : plateforme carrée sur toit + cercle + « H » + feux de balisage ──
static func heliports(h) -> void:
	if h._excel.heliports.is_empty():
		return
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var feux := HoloMesh3D.st()
	var n := 0
	var nf := 0
	var nfeu := 0
	var hw: float = h.taille_cellule * 0.5
	for hp: Dictionary in h._excel.heliports:
		var bb: Rect2i = hp["bbox"]
		var alt: float = h._hauteur_monde(hp["altitude_m"])
		var centre: Vector3 = h._world(bb.position.x + (bb.size.x - 1) * 0.5,
				bb.position.y + (bb.size.y - 1) * 0.5, alt)
		# Plateforme : face sombre + contour de chaque case (grille de pont d'envol).
		for c: Vector2i in hp["cells"]:
			var ctr: Vector3 = h._world(c.x, c.y, alt)
			nf += HoloMesh3D._quad(sf,
					ctr + Vector3(-hw, 0, -hw), ctr + Vector3(hw, 0, -hw),
					ctr + Vector3(hw, 0, hw), ctr + Vector3(-hw, 0, hw), Vector3.UP)
			n += Geo.carre_plat(s, ctr, hw, COL_HELIPORT)
		# Cercle réglementaire + « H » au centre.
		var ray: float = float(mini(bb.size.x, bb.size.y)) * h.taille_cellule * 0.34
		n += HoloMesh3D.circle(s, centre, ray, COL_HELIPORT, 28)
		var hx := ray * 0.42
		var hz := ray * 0.55
		n += HoloMesh3D.line(s, centre + Vector3(-hx, 0, -hz), centre + Vector3(-hx, 0, hz), COL_HELIPORT)
		n += HoloMesh3D.line(s, centre + Vector3(hx, 0, -hz), centre + Vector3(hx, 0, hz), COL_HELIPORT)
		n += HoloMesh3D.line(s, centre + Vector3(-hx, 0, 0), centre + Vector3(hx, 0, 0), COL_HELIPORT)
		# Feux de balisage clignotants aux 4 coins (sur _mat_balise).
		var bx: float = (float(bb.size.x) * 0.5 - 0.5) * h.taille_cellule
		var bz: float = (float(bb.size.y) * 0.5 - 0.5) * h.taille_cellule
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				nfeu += HoloMesh3D.diamond(feux, centre + Vector3(sx * bx, 0, sz * bz),
						h.taille_cellule * 0.07, h.taille_cellule * 0.1, COL_HELIPORT)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Heliports", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(feux, nfeu), "HeliportsFeux", h._mat_balise)
	h._ajouter_faces(HoloMesh3D.commit(sf, nf), "HeliportsFaces")

# ─── Spots lumineux : projecteurs sur toit plat + faisceau ROTATIF qui ratisse ──
# (Le toit du bâtiment dessous est forcé PLAT par la validation amont, flag toit_plat.)
# Chaque spot projette un pinceau de lumière vers le SOL, visé sur le centre du bâtiment
# porteur (= la cour pour une prison), et BALAIE un arc (oscillation, cf. HoloMap3D._process).
static func spots(h) -> void:
	if h._excel.spots.is_empty():
		return
	var idx := 0
	for c: Vector2i in h._excel.spots:
		var b: Dictionary = h._excel.bati_sous(c)
		if b.is_empty():
			continue   # sans bâtiment → croix rouge (pas de spot rendu)
		var toit: float = h._hauteur_monde(float(b["hauteur_m"]))
		var base: Vector3 = h._world(c.x, c.y, toit)
		# Visée : vers le centre du bâtiment porteur (la cour, pour un spot de coin de prison).
		var centre: Vector3 = h._centre_bbox(b["bbox"])
		var aimx: float = centre.x - base.x
		var aimz: float = centre.z - base.z
		var dist := sqrt(aimx * aimx + aimz * aimz)
		if dist < 0.001:
			# Spot pile au centre : vise une direction arbitraire, portée = demi-emprise.
			var bb: Rect2i = b["bbox"]
			aimx = 1.0; aimz = 0.0
			dist = maxf(h.taille_cellule, float(maxi(bb.size.x, bb.size.y)) * h.taille_cellule * 0.4)
		var node := _projecteur_node(h, base, dist, COL_SPOTS)
		node.set_meta("base_yaw", atan2(-aimz, aimx))   # +X local pointe vers le centre
		node.set_meta("amp", deg_to_rad(40.0))          # demi-arc de balayage
		node.set_meta("phase", float(idx) * 0.8)        # désynchronise les 4 coins
		h._monde.add_child(node)
		h._projecteurs.append(node)
		idx += 1

# Nœud d'un projecteur : MÂT vertical (pour décoller du toit bas) + tête lumineuse à son
# sommet + cône d'arêtes vers une nappe lumineuse au SOL (ellipse). Orienté local +X ;
# HoloMap3D le fait osciller autour de Y → la nappe ratisse un arc. `reach` = portée
# horizontale apex→nappe. Le mât et la tête sont sur l'axe Y → la rotation ne les bouge pas.
static func _projecteur_node(h, base: Vector3, reach: float, col: Color) -> Node3D:
	var node := Node3D.new()
	node.name = "Projecteur"
	node.position = base
	var s := HoloMesh3D.st()
	var n := 0
	# Mât : décolle la tête bien au-dessus des murs (toit de prison très bas) → faisceau
	# qui PLONGE en biais, lisible comme un projecteur de mirador.
	var post_h: float = h.taille_cellule * 2.0
	var apex := Vector3(0, post_h, 0)
	n += HoloMesh3D.line(s, Vector3.ZERO, apex, col)
	n += HoloMesh3D.diamond(s, apex, h.taille_cellule * 0.11, h.taille_cellule * 0.14, col)  # tête
	# Nappe lumineuse au sol (ellipse) + cône d'arêtes depuis la tête.
	var poolc := Vector3(reach, -base.y, 0)   # y monde = 0 → local -base.y
	var pr: float = h.taille_cellule * 0.9
	n += HoloMesh3D.circle(s, poolc, pr, col, 20)
	n += HoloMesh3D.line(s, apex, poolc, col)               # axe du faisceau
	for a: float in [0.0, 72.0, 144.0, 216.0, 288.0]:
		var rad := deg_to_rad(a)
		n += HoloMesh3D.line(s, apex, poolc + Vector3(cos(rad) * pr, 0, sin(rad) * pr), col)
	var mi := MeshInstance3D.new()
	mi.name = "FaisceauMesh"
	mi.mesh = HoloMesh3D.commit(s, n)
	mi.material_override = h._mat_neon
	node.add_child(mi)
	return node

# ─── Antennes / relais télécom : mât + paraboles + voyant clignotant ──────────
static func antennes(h) -> void:
	if h._excel.antennes.is_empty():
		return
	var s := HoloMesh3D.st()
	var voyants := HoloMesh3D.st()
	var n := 0
	var nv := 0
	for c: Vector2i in h._excel.antennes:
		var b: Dictionary = h._excel.bati_sous(c)
		if b.is_empty():
			continue   # sans bâtiment → croix rouge (pas d'antenne rendue)
		var toit: float = h._hauteur_monde(float(b["hauteur_m"]))
		var base: Vector3 = h._world(c.x, c.y, toit)
		var mh: float = h.unite_maison * 1.8 + (h._hash01(c, 3) * h.unite_maison)
		var tip := base + Vector3(0, mh, 0)
		n += HoloMesh3D.line(s, base, tip, COL_ANTENNE)             # mât
		# Haubans + petite parabole (anneau incliné) à mi-hauteur.
		var hub: float = h.taille_cellule * 0.2
		n += HoloMesh3D.line(s, tip, base + Vector3(hub, mh * 0.4, 0), COL_ANTENNE)
		n += HoloMesh3D.line(s, tip, base + Vector3(-hub, mh * 0.4, hub), COL_ANTENNE)
		n += HoloMesh3D.ellipse(s, base + Vector3(0, mh * 0.6, 0),
				h.taille_cellule * 0.16, h.taille_cellule * 0.08, COL_ANTENNE, 12)
		# Voyant clignotant rouge-cyan au sommet (_mat_balise).
		nv += HoloMesh3D.diamond(voyants, tip, h.taille_cellule * 0.05, h.taille_cellule * 0.08, COL_ANTENNE)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Antennes", h._mat_neon)
	h._ajouter_mesh(HoloMesh3D.commit(voyants, nv), "AntennesVoyants", h._mat_balise)

# ─── Téléphérique : câble tendu (léger ballant) + nacelle qui glisse, entre 2 points ──
# Les stations (blocs orange) sont appariées 2 à 2 dans l'ordre. Altitude d'extrémité =
# sommet du bâtiment dessous si présent, sinon altitude saisie (station au sol).
static func telepheriques(h) -> void:
	var stations: Array = h._excel.telepheriques
	if stations.size() < 2:
		return
	var s := HoloMesh3D.st()
	var nac := SurfaceTool.new()
	nac.begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x7E1E
	var n := 0
	var nnac := 0
	var i := 0
	while i + 1 < stations.size():
		var a := _station_point(h, stations[i])
		var b := _station_point(h, stations[i + 1])
		# Câble en léger ballant (chaînette approchée par une parabole) + pylônes courts.
		var seg := 16
		var prev := a
		var sag: float = a.distance_to(b) * 0.06
		for k in range(1, seg + 1):
			var t := float(k) / float(seg)
			var p := a.lerp(b, t)
			p.y -= sag * sin(PI * t)   # ballant max au milieu
			n += HoloMesh3D.line(s, prev, p, COL_TELE)
			prev = p
		# Mâts de station (du point haut vers le toit/sol juste dessous).
		n += HoloMesh3D.line(s, a, Vector3(a.x, maxf(0.0, a.y - h.taille_cellule * 0.6), a.z), COL_TELE)
		n += HoloMesh3D.line(s, b, Vector3(b.x, maxf(0.0, b.y - h.taille_cellule * 0.6), b.z), COL_TELE)
		# Nacelle qui glisse (shader de trafic : un segment translaté le long du câble).
		Geo.semer_voitures(nac, a, b - a, h.taille_cellule * 0.5, rng, COL_TELE, 1, 0.5)
		nnac += 1
		i += 2
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Telepheriques", h._mat_neon)
	if nnac > 0:
		var mi := MeshInstance3D.new()
		mi.name = "TelepheriquesNacelles"
		mi.mesh = nac.commit()
		mi.material_override = h._mat_trafic
		h._monde.add_child(mi)

# Point d'accroche d'une station : centre de la bbox, à l'altitude saisie — ou au sommet
# du bâtiment dessous s'il y en a un (point haut sur toit).
static func _station_point(h, st: Dictionary) -> Vector3:
	var bb: Rect2i = st["bbox"]
	var cell := Vector2i(bb.position.x + bb.size.x / 2, bb.position.y + bb.size.y / 2)
	var alt_m: float = st["altitude_m"]
	var b: Dictionary = h._excel.bati_sous(cell)
	if not b.is_empty():
		alt_m = float(b["hauteur_m"])
	return h._world(bb.position.x + (bb.size.x - 1) * 0.5,
			bb.position.y + (bb.size.y - 1) * 0.5, h._hauteur_monde(alt_m))

# ─── Enseignes holographiques : grand panneau lumineux vertical (cadre + scanlines) ──
static func enseignes(h) -> void:
	if h._excel.enseignes.is_empty():
		return
	var s := HoloMesh3D.st()
	var n := 0
	for en: Dictionary in h._excel.enseignes:
		var bb: Rect2i = en["bbox"]
		var alt: float = h._hauteur_monde(en["altitude_m"])
		# Panneau dressé dans le plan du plus grand côté de l'emprise.
		var horiz := bb.size.x >= bb.size.y
		var larg: float = float(maxi(bb.size.x, bb.size.y)) * h.taille_cellule
		var haut: float = maxf(h.unite_maison * 2.0, larg * 0.5)
		var centre: Vector3 = h._world(bb.position.x + (bb.size.x - 1) * 0.5,
				bb.position.y + (bb.size.y - 1) * 0.5, alt)
		var ax := Vector3(larg * 0.5, 0, 0) if horiz else Vector3(0, 0, larg * 0.5)
		var up := Vector3(0, haut, 0)
		var b0 := centre - ax
		var b1 := centre + ax
		# Cadre.
		n += HoloMesh3D.line(s, b0, b1, COL_ENSEIGNE)
		n += HoloMesh3D.line(s, b0 + up, b1 + up, COL_ENSEIGNE)
		n += HoloMesh3D.line(s, b0, b0 + up, COL_ENSEIGNE)
		n += HoloMesh3D.line(s, b1, b1 + up, COL_ENSEIGNE)
		# Scanlines internes (défilement holographique suggéré).
		for k in range(1, 4):
			var y := up * (float(k) / 4.0)
			n += HoloMesh3D.line(s, b0 + y, b1 + y, COL_ENSEIGNE)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Enseignes", h._mat_enseigne)
