# ============================================================
# HoloTraffic — Simulation d'agents (voitures) sur la voirie de la carte Excel.
#
# Remplace le « trafic shader qui glisse tout droit » par de vraies voitures qui :
#   • suivent les voies (décalées à DROITE du sens de marche → conduite à droite),
#   • TOURNENT aux intersections (tout droit / gauche / droite, jamais de demi-tour),
#   • ne SE CROISENT JAMAIS, garanti par un système de RÉSERVATION de cases :
#       - case d'intersection (deux routes se croisent) = VERROU PLEIN : une seule
#         voiture à la fois → aucun croisement possible ;
#       - case de tronçon droit = créneau PAR SENS → les sens opposés coexistent
#         (décalés de part et d'autre), mais deux voitures du même sens gardent
#         l'écart d'une case (file indienne, pas de chevauchement).
#
# Chaque voiture détient en permanence la réservation de la case qu'elle occupe ;
# elle n'avance dans la suivante que si le créneau requis est libre, sinon attend.
# Rendu par ImmediateMesh régénéré chaque frame (petits segments émissifs).
# ============================================================
class_name HoloTraffic
extends Node3D

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _road := {}          # Vector2i → true
var _road_list: Array = []
var _inter := {}         # Vector2i → true (vraie intersection : verrou plein)
var _occ := {}           # clé de créneau → id voiture
var _cars: Array = []
# Feux tricolores (#1) : carrefours (cases d'intersection connexes) → phase H/V.
var _jid := {}                 # case d'intersection → id de carrefour
var _junction_ctrl: Array = [] # carrefour contrôlé par des feux ?
var _junction_off: Array = []  # déphasage (variété)
var _lights: Array = []        # feux à dessiner : {a, b, jid, axe}
var _t_global := 0.0
var _cgrid := 0.0
var _cell := 0.34
var _y := 0.06
var _col_av := Color(0.55, 0.90, 1.00)   # sens « + » (cyan)
var _col_ret := Color(1.00, 0.62, 0.30)  # sens « − » (ambre)
var _im: ImmediateMesh
var _rng := RandomNumberGenerator.new()

func configurer(routes: Array, inter: Dictionary, cgrid: float, cell: float,
		hauteur: float, mat: ShaderMaterial, nb_voitures: int, graine: int) -> void:
	_cgrid = cgrid
	_cell = cell
	_y = hauteur
	_inter = inter
	_rng.seed = graine
	_road.clear()
	_road_list.clear()
	for c: Vector2i in routes:
		_road[c] = true
		_road_list.append(c)
	_calc_feux()
	_im = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "VoituresMesh"
	mi.mesh = _im
	mi.material_override = mat
	add_child(mi)
	_spawn(nb_voitures)
	set_process(not _cars.is_empty())

# Carrefours = composantes connexes de cases d'intersection. Un carrefour est
# « contrôlé » (feux) s'il a des approches sur les DEUX axes et ≥ 3 côtés (vrai
# croisement / T) — pas un simple virage. Pose un feu par approche.
func _axe(dir: Vector2i) -> int:
	return 0 if dir.x != 0 else 1   # 0 = horizontal, 1 = vertical

func _calc_feux() -> void:
	var seen := {}
	for c0: Vector2i in _inter:
		if seen.has(c0):
			continue
		var jid := _junction_ctrl.size()
		var blob: Array = []
		var stack: Array = [c0]
		while not stack.is_empty():
			var x: Vector2i = stack.pop_back()
			if seen.has(x) or not _inter.has(x):
				continue
			seen[x] = true
			blob.append(x)
			_jid[x] = jid
			for d: Vector2i in DIRS:
				if _inter.has(x + d):
					stack.append(x + d)
		var ad := {}
		for x: Vector2i in blob:
			for d: Vector2i in DIRS:
				if _road.has(x + d) and not _inter.has(x + d):
					ad[d] = true
		var has_h: bool = ad.has(Vector2i(1, 0)) or ad.has(Vector2i(-1, 0))
		var has_v: bool = ad.has(Vector2i(0, 1)) or ad.has(Vector2i(0, -1))
		var ctrl: bool = has_h and has_v and ad.size() >= 3
		_junction_ctrl.append(ctrl)
		_junction_off.append(_rng.randf() * 9.0)
		if ctrl:
			for x: Vector2i in blob:
				for d: Vector2i in DIRS:
					if _road.has(x + d) and not _inter.has(x + d):
						var centre := (_world(x.x, x.y) + _world(x.x + d.x, x.y + d.y)) * 0.5
						var across := Vector3(float(d.y), 0.0, -float(d.x)) * (_cell * 0.34)
						var up := Vector3(0, _cell * 0.12, 0)
						_lights.append({"a": centre + across + up, "b": centre - across + up,
								"jid": jid, "axe": _axe(d)})

# Phase d'un carrefour : 0 = axe H au vert, 1 = axe V au vert, -1 = tout rouge (jaune).
func _phase(jid: int) -> int:
	var periode := 9.0
	var jaune := 1.2
	var local := fmod(_t_global + _junction_off[jid], periode)
	if local < periode * 0.5 - jaune:
		return 0
	if local < periode * 0.5:
		return -1
	if local < periode - jaune:
		return 1
	return -1

# Le feu interdit-il d'entrer dans le carrefour `ncell` en venant de `arrived` ?
func _feu_rouge(arrived: Vector2i, ncell: Vector2i, ndir: Vector2i) -> bool:
	if _inter.get(arrived, false):
		return false   # déjà engagé dans le carrefour → on dégage
	if not _inter.get(ncell, false):
		return false
	var jid: int = _jid.get(ncell, -1)
	if jid < 0 or not _junction_ctrl[jid]:
		return false
	var ph := _phase(jid)
	return ph != _axe(ndir)   # rouge si pas le bon axe (ou tout-rouge ph=-1)

# ─── Géométrie ────────────────────────────────────────────────
func _world(gx: float, gy: float) -> Vector3:
	return Vector3((gx - _cgrid) * _cell, _y, (gy - _cgrid) * _cell)

# Décalage perpendiculaire À DROITE du sens de marche (conduite à droite).
func _perp(dir: Vector2i) -> Vector3:
	return Vector3(float(dir.y), 0.0, -float(dir.x)) * (_cell * 0.20)

# Point de voie : centre de la case décalé du côté du sens.
func _lane_pt(cell: Vector2i, dir: Vector2i) -> Vector3:
	return _world(cell.x, cell.y) + _perp(dir)

# ─── Réservation ──────────────────────────────────────────────
func _slot_key(cell: Vector2i, dir: Vector2i) -> String:
	if _inter.get(cell, false):
		return "%d_%d" % [cell.x, cell.y]                       # verrou plein
	return "%d_%d_%d_%d" % [cell.x, cell.y, dir.x, dir.y]       # créneau par sens

func _libre(cell: Vector2i, dir: Vector2i, id: int) -> bool:
	var k := _slot_key(cell, dir)
	return not _occ.has(k) or _occ[k] == id

# ─── Spawn ────────────────────────────────────────────────────
func _spawn(n: int) -> void:
	if _road_list.is_empty():
		return
	for id in n:
		for _essai in 12:
			var cell: Vector2i = _road_list[_rng.randi() % _road_list.size()]
			var dirs_ok: Array = []
			for d: Vector2i in DIRS:
				if _road.has(cell + d):
					dirs_ok.append(d)
			if dirs_ok.is_empty():
				continue
			var dir: Vector2i = dirs_ok[_rng.randi() % dirs_ok.size()]
			var k := _slot_key(cell, dir)
			if _occ.has(k):
				continue
			_occ[k] = id
			var p := _lane_pt(cell, dir)
			_cars.append({
				"tgt": cell, "tdir": dir,
				"from": p, "ctrl": p, "to": p,
				"t": 1.0, "len": 1.0, "key": k, "prev_key": "",
				"speed": _cell * _rng.randf_range(1.1, 1.7),
			})
			break

# ─── Choix du prochain mouvement ──────────────────────────────
# Tout droit sur un tronçon ; aux intersections, on choisit un mouvement RÉSERVABLE
# (pas de demi-tour), pour éviter de bloquer le carrefour.
func _choisir(cell: Vector2i, dir: Vector2i, id: int) -> Vector2i:
	var opts: Array = []
	for d: Vector2i in DIRS:
		if d == -dir:
			continue
		if _road.has(cell + d):
			opts.append(d)
	if opts.is_empty():
		return -dir if _road.has(cell - dir) else Vector2i.ZERO   # cul-de-sac : demi-tour
	if not _inter.get(cell, false):
		return dir if opts.has(dir) else opts[0]                  # tronçon : tout droit / virage forcé
	# Intersection : tout droit en priorité, sinon un virage réservable.
	if opts.has(dir) and _libre(cell + dir, dir, id):
		return dir
	opts.shuffle()
	for d: Vector2i in opts:
		if _libre(cell + d, d, id):
			return d
	return Vector2i.ZERO   # tout bloqué → attendre

# ─── Boucle ───────────────────────────────────────────────────
func _process(dt: float) -> void:
	_t_global += dt
	for id in _cars.size():
		_avancer(id, dt)
	_dessiner()

func _avancer(id: int, dt: float) -> void:
	var car: Dictionary = _cars[id]
	car["t"] += car["speed"] * dt / maxf(0.01, car["len"])
	if car["t"] < 1.0:
		return
	car["t"] = 1.0
	# Arrivé : on libère ENFIN la case quittée (tenue pendant tout le trajet → écart
	# garanti d'au moins une case avec la voiture qui suit).
	var pk: String = car["prev_key"]
	if pk != "" and _occ.get(pk, -1) == id:
		_occ.erase(pk)
	car["prev_key"] = ""
	var arrived: Vector2i = car["tgt"]
	var adir: Vector2i = car["tdir"]
	var ndir := _choisir(arrived, adir, id)
	if ndir == Vector2i.ZERO:
		return   # attend (ne tient plus que sa case courante)
	var ncell: Vector2i = arrived + ndir
	if _feu_rouge(arrived, ncell, ndir):
		return   # feu rouge → attend à la ligne d'arrêt
	if not _libre(ncell, ndir, id):
		return   # case suivante occupée → attend (file / cède le passage)
	# Engage le mouvement : réserve la suivante en GARDANT la courante.
	var nkey := _slot_key(ncell, ndir)
	_occ[nkey] = id
	car["prev_key"] = car["key"]
	car["key"] = nkey
	var depart: Vector3 = car["to"]
	var arrivee := _lane_pt(ncell, ndir)
	car["from"] = depart
	car["to"] = arrivee
	car["ctrl"] = (depart + arrivee) * 0.5 if ndir == adir else _world(arrived.x, arrived.y)
	car["len"] = maxf(0.02, arrivee.distance_to(depart))
	car["t"] = 0.0
	car["tgt"] = ncell
	car["tdir"] = ndir

func _seg(a: Vector3, b: Vector3, col: Color) -> void:
	_im.surface_set_color(col); _im.surface_add_vertex(a)
	_im.surface_set_color(col); _im.surface_add_vertex(b)

func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u) + b * (2.0 * u * t) + c * (t * t)

# Position monde courante de chaque voiture (test / debug).
func positions() -> Array:
	var out: Array = []
	for car: Dictionary in _cars:
		out.append(_bezier(car["from"], car["ctrl"], car["to"], car["t"]))
	return out

# Avance la simulation d'un pas SANS rendu (test headless).
func pas_sim(dt: float) -> void:
	_t_global += dt
	for id in _cars.size():
		_avancer(id, dt)

func _dessiner() -> void:
	_im.clear_surfaces()
	if _cars.is_empty() and _lights.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	# Feux tricolores : barre verte (passant) / rouge (arrêt) / ambre (transition).
	for lt: Dictionary in _lights:
		var ph := _phase(lt["jid"])
		var col := Color(1.0, 0.70, 0.15)
		if ph >= 0:
			col = Color(0.30, 1.0, 0.40) if ph == int(lt["axe"]) else Color(1.0, 0.20, 0.18)
		_im.surface_set_color(col); _im.surface_add_vertex(lt["a"])
		_im.surface_set_color(col); _im.surface_add_vertex(lt["b"])
	# Silhouette futuriste (vue de dessus en relief) : coque en goutte d'eau effilée
	# (nez pointu, flancs galbés, poupe resserrée) + bulle de cockpit basse et facettée.
	# Tout en arêtes lumineuses → speeder / pod plutôt que berline.
	var hl := _cell * 0.20    # demi-longueur (axe de marche)
	var hw := _cell * 0.08    # demi-largeur (au maître-bau)
	var ht := _cell * 0.075   # hauteur de la bulle (basse → profil aérodynamique)
	for car: Dictionary in _cars:
		var t: float = car["t"]
		var cf: Vector3 = car["from"]
		var cc: Vector3 = car["ctrl"]
		var ct: Vector3 = car["to"]
		var p := _bezier(cf, cc, ct, t)
		var tang := (cc - cf) * (2.0 * (1.0 - t)) + (ct - cc) * (2.0 * t)
		if tang.length() < 0.0001:
			tang = ct - cf
		tang = tang.normalized()
		var perp := Vector3(-tang.z, 0.0, tang.x)   # côté (gauche/droite) dans le plan
		var up := Vector3(0, ht, 0)
		var tdir: Vector2i = car["tdir"]
		var col := _col_av if (tdir.x + tdir.y > 0) else _col_ret
		# Empreinte au sol en goutte d'eau : nez (pointe avant), maître-bau (galbe,
		# légèrement avancé), poupe (resserrée). Arête de proue effilée.
		var nez := p + tang * hl
		var ml := p + tang * (hl * 0.18) - perp * hw
		var mr := p + tang * (hl * 0.18) + perp * hw
		var pl := p - tang * hl - perp * (hw * 0.45)
		var pr := p - tang * hl + perp * (hw * 0.45)
		_seg(nez, mr, col); _seg(mr, pr, col); _seg(pr, pl, col); _seg(pl, ml, col); _seg(ml, nez, col)
		# Bulle de cockpit : apex bas, légèrement reculé → facettes vers nez/flancs/poupe.
		var apex := p - tang * (hl * 0.08) + up
		var poupe := (pl + pr) * 0.5
		_seg(apex, nez, col)                       # pare-brise effilé
		_seg(apex, ml, col); _seg(apex, mr, col)   # montants latéraux (galbe)
		_seg(apex, poupe, col)                      # carène arrière
	_im.surface_end()
