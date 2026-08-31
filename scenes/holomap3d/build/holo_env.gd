# ============================================================
# holo_env — Cadre d'ENVIRONNEMENT extrait de HoloMap3D (refactor).
#
# Tout ce qui entoure et soutient la ville sans en faire partie : halo d'horizon,
# brume, skyline lointain, socle « table tactique », nappe de sol, balayage radar,
# poussières de données. Même pattern que holo_decor : `static func famille(h)` où
# `h` = le noeud HoloMap3D (NON typé → pas de cycle class_name). Helpers de base
# partagés et propriétés accédés via `h.*` ; locales issues de `h.*` typées
# explicitement (inférence Variant interdite). Appelé via `const Env := preload(...)`.
# ============================================================
extends RefCounted

# ─── Horizon : halo cylindrique + brume au sol (atmosphère) ───
static func horizon(h) -> void:
	var rv: float = (h._cgrid() + 1.0) * h.taille_cellule
	var rh := rv * 1.7
	var hh := rv * 0.6
	var seg := 72
	var c_bas := Color(0.10, 0.28, 0.48, 0.42)
	var c_haut := Color(0.10, 0.28, 0.48, 0.0)
	var sc := HoloMesh3D.st_tri()
	var nc := 0
	var prev := Vector2(rh, 0.0)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := Vector2(cos(a) * rh, sin(a) * rh)
		var b0 := Vector3(prev.x, 0.0, prev.y)
		var b1 := Vector3(cur.x, 0.0, cur.y)
		var t0 := Vector3(prev.x, hh, prev.y)
		var t1 := Vector3(cur.x, hh, cur.y)
		sc.set_color(c_bas); sc.add_vertex(b0)
		sc.set_color(c_bas); sc.add_vertex(b1)
		sc.set_color(c_haut); sc.add_vertex(t1)
		sc.set_color(c_bas); sc.add_vertex(b0)
		sc.set_color(c_haut); sc.add_vertex(t1)
		sc.set_color(c_haut); sc.add_vertex(t0)
		nc += 2
		prev = cur
	h._ajouter_mesh(HoloMesh3D.commit(sc, nc), "Horizon", h._mat_horizon)
	# Brume au sol : éventail centre (transparent) → bord (faible lueur).
	var sd := HoloMesh3D.st_tri()
	var nd := 0
	var c_centre := Color(0.06, 0.16, 0.30, 0.0)
	var c_bord := Color(0.10, 0.26, 0.44, 0.28)
	var y := -0.006
	var prevp := Vector3(rh, y, 0.0)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := Vector3(cos(a) * rh, y, sin(a) * rh)
		sd.set_color(c_centre); sd.add_vertex(Vector3(0, y, 0))
		sd.set_color(c_bord); sd.add_vertex(prevp)
		sd.set_color(c_bord); sd.add_vertex(cur)
		nd += 1
		prevp = cur
	h._ajouter_mesh(HoloMesh3D.commit(sd, nd), "BrumeSol", h._mat_horizon)

# ─── Skyline lointain : silhouette de mégastructures à l'horizon ──────────────
# Un anneau de tours sombres jaillit AU-DELÀ des collines → la ville n'est plus une
# île posée sur une table, elle est un fragment d'une mégalopole sans fin. Tours
# fines, hauteurs irrégulières (jagged), teinte froide qui recule ; quelques têtes
# néon (enseignes lointaines) ponctuent la ligne d'horizon.
static func skyline_lointain(h) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x5C1701
	var rv: float = (h._cgrid() + 1.0) * h.taille_cellule
	var s := HoloMesh3D.st()       # tours sombres (froides, reculées)
	var n := 0
	var sn := HoloMesh3D.st()      # têtes néon (enseignes lointaines) — glow
	var nn := 0
	var nb := 150
	var froid := Color(0.16, 0.30, 0.50)
	for i in nb:
		var a := TAU * float(i) / float(nb) + rng.randf_range(-0.02, 0.02)
		var rad := rv * rng.randf_range(1.28, 1.62)
		var c := Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var hh := rng.randf_range(rv * 0.16, rv * 0.52)   # hauteurs irrégulières
		var w: float = h.taille_cellule * rng.randf_range(0.25, 0.6)
		var col := froid * rng.randf_range(0.5, 1.0)
		col.a = 0.9
		n += HoloMesh3D.box(s, c, w, hh, w, col)
		# ~1 sur 7 : tête néon (enseigne/balise lointaine), teinte chaude ou magenta.
		if rng.randf() < 0.14:
			var tete := c + Vector3(0.0, hh, 0.0)
			var nc: Color = h.couleur_route if rng.randf() < 0.5 else h.couleur_fenetre
			nc = Color(nc.r, nc.g, nc.b, 0.85)
			nn += HoloMesh3D.line(sn, tete, tete + Vector3(0.0, h.taille_cellule * 0.25, 0.0), nc)
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "SkylineLointain", h._mat_horizon)
	h._ajouter_mesh(HoloMesh3D.commit(sn, nn), "SkylineEnseignes", h._mat_enseigne)

# ─── Poussières de données (montée animée par shader) ─────────
static func motes(h) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x310C0DE
	var r: float = (h._cgrid() + 1.0) * h.taille_cellule
	var seg := 0.12
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	for _i in maxi(0, h.motes_count):
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * r        # disque uniforme
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var ph := rng.randf()                    # phase de montée
		var a := 0.35 + 0.45 * rng.randf()
		s.set_color(Color(1, 1, 1, a)); s.set_uv(Vector2(ph, 0)); s.add_vertex(Vector3(x, 0, z))
		s.set_color(Color(1, 1, 1, a)); s.set_uv(Vector2(ph, 0)); s.add_vertex(Vector3(x, seg, z))
	var mi := MeshInstance3D.new()
	mi.name = "Motes"
	mi.mesh = s.commit()
	mi.material_override = h._mat_motes
	h._monde.add_child(mi)

# ─── Socle « table tactique » (anneau + ticks au sol) ─────────
static func socle(h) -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var r: float = (h._cgrid() + 1.0) * h.taille_cellule * 1.10
	n += HoloMesh3D.circle(s, Vector3.ZERO, r, Color(h.couleur_socle, 0.55), 96)
	n += HoloMesh3D.circle(s, Vector3.ZERO, r * 0.965, Color(h.couleur_socle, 0.22), 96)
	# Ticks radiaux (graduations) — plus longs tous les 1/8 de tour.
	var ticks := 48
	for i in ticks:
		var a := TAU * float(i) / float(ticks)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var long := i % 6 == 0
		var ext: float = h.taille_cellule * (0.65 if long else 0.3)
		n += HoloMesh3D.line(s, dir * r, dir * (r + ext),
				Color(h.couleur_socle, 0.5 if long else 0.28))
	h._ajouter_mesh(HoloMesh3D.commit(s, n), "Socle")   # _mat_decor → léger glow cyan

# ─── Sol : nappe de terre + maillage fin (liant visuel sous tout) ──
# Un grand disque sombre (la « matière » du terrain) + un quadrillage fin de
# tout petits carrés posés dessus, le tout clippé au disque (pas de bord carré).
# Couvre la ville, le lac, les collines et les faubourgs proches → tout est
# rattaché à un même sol. Centre décalé vers le lac pour englober l'ensemble.
# Disque-terrain + maillage fin, centré sur `sc` (cellules), rayon `R` (cellules).
static func sol_disc(h, sc: Vector2, R: float) -> void:
	# 1) Nappe de terre pleine (disque sombre) — additif → léger relief de fond.
	var sp := HoloMesh3D.st_tri()
	var npq := 0
	var c_terre := Color(0.05, 0.07, 0.10, 1.0)
	var cw: Vector3 = h._world(sc.x, sc.y, -0.004)
	var seg := 96
	var prev: Vector3 = h._world(sc.x + R, sc.y, -0.004)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur: Vector3 = h._world(sc.x + cos(a) * R, sc.y + sin(a) * R, -0.004)
		sp.set_color(c_terre); sp.add_vertex(cw)
		sp.set_color(c_terre); sp.add_vertex(prev)
		sp.set_color(c_terre); sp.add_vertex(cur)
		npq += 1
		prev = cur
	h._ajouter_mesh(HoloMesh3D.commit(sp, npq), "SolTerre", h._mat_sol)
	# 2) Maillage fin (petits carrés) clippé au disque (chordes dans le cercle).
	var sg := HoloMesh3D.st()
	var ng := 0
	var c_grille := Color(0.16, 0.22, 0.30, 0.42)
	var pas := 0.5                  # demi-cellule → tout petits carrés
	var yg := -0.003
	var k := -R
	while k <= R + 0.001:
		var half := sqrt(maxf(0.0, R * R - k * k))
		if half > 0.05:
			ng += HoloMesh3D.line(sg, h._world(sc.x + k, sc.y - half, yg), h._world(sc.x + k, sc.y + half, yg), c_grille)
			ng += HoloMesh3D.line(sg, h._world(sc.x - half, sc.y + k, yg), h._world(sc.x + half, sc.y + k, yg), c_grille)
		k += pas
	h._ajouter_mesh(HoloMesh3D.commit(sg, ng), "SolGrille", h._mat_sol)

# ─── Drones : petite vie ambiante au-dessus de la ville ───────
# Quelques patrouilles lentes, chacune en orbite libre autour d'un centre tiré au
# hasard (≠ couloirs aériens rectilignes de Ville.trafic_aerien) — la carte ne
# semble plus figée même loin de tout Lieu. Un diamant miniature par drone (même
# forme que le pin d'un Lieu, en plus petit) ; les métadonnées de trajectoire sont
# lues et animées par HoloMap3D._maj_drones (réutilise l'horloge _proj_t).
static func drones(h) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_val ^ 0x0D20E5
	var rv: float = h._cgrid() * h.taille_cellule
	var nb := 7
	var pal := [Color(0.45, 0.90, 1.00), Color(1.00, 0.62, 0.30), Color(0.75, 0.95, 0.55)]
	for i in nb:
		var node := Node3D.new()
		node.name = "Drone%d" % i
		var s := HoloMesh3D.st()
		var col: Color = pal[i % pal.size()]
		var n := HoloMesh3D.diamond(s, Vector3.ZERO, h.taille_cellule * 0.16, h.taille_cellule * 0.22, col)
		var mi := MeshInstance3D.new()
		mi.name = "DroneMesh"
		mi.mesh = HoloMesh3D.commit(s, n)
		mi.material_override = h._mat_prop   # néon doux, sans cœur blanc → discret
		node.add_child(mi)
		var centre := Vector3(rng.randf_range(-rv * 0.7, rv * 0.7), 0.0, rng.randf_range(-rv * 0.7, rv * 0.7))
		node.set_meta("centre", centre)
		node.set_meta("rayon", rv * rng.randf_range(0.10, 0.30))
		node.set_meta("hauteur", h.unite_maison * rng.randf_range(3.0, 7.0))
		node.set_meta("vitesse", rng.randf_range(0.10, 0.22) * (1.0 if i % 2 == 0 else -1.0))
		node.set_meta("phase", rng.randf() * TAU)
		h._monde.add_child(node)
		h._drones.append(node)

# ─── Balayage radar (sweep en éventail, tourne lentement) ─────
static func radar(h) -> void:
	var r: float = (h._cgrid() + 1.0) * h.taille_cellule * 1.06
	var seg := 12
	var span := deg_to_rad(28.0)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.02
	for i in seg:
		var a0 := -span * 0.5 + span * float(i) / float(seg)
		var a1 := -span * 0.5 + span * float(i + 1) / float(seg)
		# Alpha croît vers le bord d'attaque (a = +span/2) : effet comète.
		var al0 := 0.32 * (a0 + span * 0.5) / span
		var al1 := 0.32 * (a1 + span * 0.5) / span
		var p0 := Vector3(cos(a0), 0, sin(a0)) * r + Vector3(0, y, 0)
		var p1 := Vector3(cos(a1), 0, sin(a1)) * r + Vector3(0, y, 0)
		s.set_color(Color(h.couleur_socle, 0.10)); s.add_vertex(Vector3(0, y, 0))
		s.set_color(Color(h.couleur_socle, al0)); s.add_vertex(p0)
		s.set_color(Color(h.couleur_socle, al1)); s.add_vertex(p1)
	h._radar = Node3D.new()
	h._radar.name = "Radar"
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	mi.material_override = h._mat_ambiance   # additif, émission faible → discret
	h._radar.add_child(mi)
	h._monde.add_child(h._radar)
