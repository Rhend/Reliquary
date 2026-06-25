# ============================================================
# HoloMap3D — Carte holographique en VRAIE 3D : ville À PLAT (Godot 4.6).
#
# Node3D racine autonome et lançable. Géométrie en volume (MeshInstance3D en
# PRIMITIVE_LINES, wireframe émissif). Plus de relief naturel : sol urbain plan,
# tissu dense d'îlots séparés par une vraie voirie (grands axes 2×2 voies +
# rues secondaires), décor d'ambiance inerte (fleuve / lac / parc).
#
# CAMÉRA ORBITALE, MONDE FIXE : on orbite autour de l'axe vertical ; les lieux
# ne bougent jamais → raycast de clic cohérent pendant/après rotation.
#
# COULEURS = DA du projet (UIColors) : lieux colorés par UIColors.tier_color
# (trait plein + glow marqué, ils ressortent) ; tissu de remplissage en
# bleu-gris désaturé atténué (faible glow, fond neutre) ; décor en teintes
# propres discrètes. Le contraste lieu/décor passe par luminosité + glow.
#
# Échelle référencée maison : `unite_maison` = hauteur d'un étage ; les gabarits
# se définissent en multiples (emprise en cellules, hauteur en étages).
#
# Glow via WorldEnvironment. Scanlines/flicker/distorsion en post-process (à 0
# par défaut). Tout procédural — aucun asset externe.
# Hors portée (assets futurs, NON simulés) : nuages volumétriques, micro-détails
# texturés, DOF cinématographique.
# ============================================================
class_name HoloMap3D
extends Node3D

signal lieu_selectionne(id: String)

const LINE_SHADER := preload("res://scenes/holomap3d/holo_line.gdshader")
const POST_SHADER := preload("res://scenes/holomap3d/holo_post.gdshader")
const ROUTE_SHADER := preload("res://scenes/holomap3d/holo_route.gdshader")
const FACE_SHADER := preload("res://scenes/holomap3d/holo_face.gdshader")
const FACE_INSET := 0.96   # faces légèrement insérées → les arêtes ne sont pas avalées

@export var seed_val := 1337

# ─── Caméra / rotation ────────────────────────────────────────
@export_group("Caméra")
@export_range(15.0, 85.0) var plongee_deg := 55.0
@export var plongee_min := 25.0
@export var plongee_max := 80.0
@export var distance := 15.0
@export var distance_min := 8.0
@export var distance_max := 32.0
@export var fov := 50.0
@export_enum("Libre", "Paliers") var mode_rotation := 0
@export var palier_deg := 45.0
@export var vitesse_rotation := 18.0
@export var auto_rotation := false

# ─── Échelle (référencée maison) ──────────────────────────────
@export_group("Échelle")
@export var unite_maison := 0.14    # hauteur d'un étage / maison ≈ 3 m (unité de référence)
@export var taille_cellule := 0.34  # côté d'une cellule au sol ≈ emprise d'une maison
@export var grille := 28            # nb de cellules par côté

# ─── Voirie / densité ─────────────────────────────────────────
@export_group("Voirie")
@export var taille_ilot := 5            # cellules par îlot (entre deux rues)
@export var rue_secondaire := 1         # largeur des rues secondaires (cellules)
@export var avenue_largeur := 2         # largeur des grands axes 2×2 voies (cellules)
@export var avenue_tous_les := 3        # un axe sur N est un grand axe
@export_range(0.0, 1.0) var densite := 0.85  # remplissage des îlots
# Routes-néon (seul calque de lignes au sol ; remplace grille + circuits).
@export var couleur_route := Color(0.95, 0.30, 0.66)  # magenta rosé (distinct du violet Épique)
@export var route_emission_base := 0.7  # néon de base (discret, au-dessus du décor)
@export var route_intensite_avenue := 1.0
@export var route_intensite_rue := 0.6
@export var flux_intensite := 1.2       # surbrillance du flux qui circule
@export var flux_vitesse := 0.35        # vitesse du flux (lent)
@export var flux_frequence := 0.18      # densité de pulses le long de l'axe

# ─── Gabarits de bâtiments (tissu urbain) ─────────────────────
@export_group("Gabarits")
@export var gabarits: Array[HoloGabarit] = []

# ─── Palette (DA UIColors) ────────────────────────────────────
@export_group("Palette")
@export var couleur_decor_bati := Color(0.34, 0.40, 0.52)  # bleu-gris désaturé (remplissage)
# Faces sombres semi-transparentes (occlusion douce). Opacité réglable :
# 0 = quasi transparent (très holo) → 1 = bien masquant.
@export var couleur_faces := Color(0.02, 0.03, 0.06)
@export_range(0.0, 1.0) var opacite_faces := 0.5
@export var couleur_eau := Color(0.16, 0.42, 0.62)
@export var couleur_parc := Color(0.22, 0.52, 0.30)
# Luminosité des ARÊTES du tissu bâti : remontée pour rester visibles PAR-DESSUS
# leurs faces sombres (wireframe holo), mais sous le seuil de glow (1.05) → le
# décor ne bloome pas, il reste en retrait des lieux.
@export var luminosite_decor := 1.3
# Luminosité du décor d'AMBIANCE (eau / parc) — distincte, inchangée (la grappe
# verte du parc reste telle quelle, non affectée par l'éclaircissement du bâti).
@export var luminosite_ambiance := 0.5
# Fond : quasi noir teinté, mais décollé du noir TOTAL (ambiance globale d'un cran).
@export var couleur_fond := Color(0.020, 0.026, 0.044)

# ─── Décor d'ambiance ─────────────────────────────────────────
@export_group("Décor")
@export var decor_actif := true

# ─── Hologramme (glow + post-process) ─────────────────────────
@export_group("Hologramme")
@export var glow_intensity := 1.0
@export_range(0.0, 1.0) var scanline_intensity := 0.0
@export var scanline_count := 240.0
@export var scanline_speed := 0.6
@export_range(0.0, 0.5) var flicker_amplitude := 0.0
@export_range(0.0, 0.02) var distortion_amplitude := 0.0
@export var post_process_interne := true

# ─── Lieux ────────────────────────────────────────────────────
@export_group("Lieux")
@export var lieux: Array[HoloLieuData] = []

var _rig: Node3D
var _cam: Camera3D
var _monde: Node3D
var _lieux_node: Node3D
var _mat_decor: ShaderMaterial       # arêtes du tissu bâti (éclaircies)
var _mat_ambiance: ShaderMaterial    # eau / parc (inchangé)
var _mat_routes: ShaderMaterial
var _mat_faces: ShaderMaterial
var _post_mat: ShaderMaterial

var _yaw := 0.0
var _dragging := false
var _debug_label: Label
var _tooltip: HoloTooltip
var _hovered: HoloLocation3D

var _cols_route := {}
var _rows_route := {}
var _bloque := {}        # Vector2i → true : cellules interdites au remplissage (décor + lieux)
var _eau := {}
var _parc := {}

func _ready() -> void:
	get_viewport().physics_object_picking = true
	if lieux.is_empty():
		lieux = _lieux_placeholder()
	if gabarits.is_empty():
		gabarits = _gabarits_defaut()
	_setup_environment()
	_setup_camera()
	_setup_materials()
	if post_process_interne:
		_setup_post()
	_setup_debug()
	_setup_tooltip()
	_build_all()

# ─── Setup ────────────────────────────────────────────────────
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = couleur_fond   # décollé du noir total (fond reste très sombre)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.12, 0.18)
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.05   # décor sous le seuil (pas de bloom), lieux au-dessus
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

func _setup_camera() -> void:
	_rig = Node3D.new()
	_rig.name = "CameraRig"
	add_child(_rig)
	_cam = Camera3D.new()
	_cam.fov = fov
	_cam.near = 0.1
	_cam.far = 300.0
	_rig.add_child(_cam)
	_appliquer_camera()

func _setup_materials() -> void:
	_mat_decor = ShaderMaterial.new()
	_mat_decor.shader = LINE_SHADER
	_mat_decor.set_shader_parameter("emission_strength", luminosite_decor)
	_mat_decor.set_shader_parameter("alpha_mult", 1.0)

	_mat_ambiance = ShaderMaterial.new()
	_mat_ambiance.shader = LINE_SHADER
	_mat_ambiance.set_shader_parameter("emission_strength", luminosite_ambiance)
	_mat_ambiance.set_shader_parameter("alpha_mult", 1.0)

	_mat_routes = ShaderMaterial.new()
	_mat_routes.shader = ROUTE_SHADER
	_mat_routes.set_shader_parameter("route_color", couleur_route)
	_mat_routes.set_shader_parameter("emission_base", route_emission_base)
	_mat_routes.set_shader_parameter("flux_intensite", flux_intensite)
	_mat_routes.set_shader_parameter("flux_vitesse", flux_vitesse)
	_mat_routes.set_shader_parameter("flux_frequence", flux_frequence)

	# Faces sombres : dessinées AVANT les arêtes (render_priority plus bas) et
	# écrivant la profondeur → occlusion des lignes derrière.
	_mat_faces = ShaderMaterial.new()
	_mat_faces.shader = FACE_SHADER
	_mat_faces.set_shader_parameter("face_color", couleur_faces)
	_mat_faces.set_shader_parameter("opacite", opacite_faces)
	_mat_faces.render_priority = -1

func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	_post_mat.set_shader_parameter("scanline_intensity", scanline_intensity)
	_post_mat.set_shader_parameter("scanline_count", scanline_count)
	_post_mat.set_shader_parameter("scanline_speed", scanline_speed)
	_post_mat.set_shader_parameter("flicker_amplitude", flicker_amplitude)
	_post_mat.set_shader_parameter("distortion_amplitude", distortion_amplitude)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _post_mat
	layer.add_child(rect)

func _setup_debug() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var lbl := Label.new()
	lbl.name = "DebugLabel"
	lbl.position = Vector2(14, 690)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0, 0.9))
	lbl.text = "HoloMap3D — glisser pour orbiter · molette = zoom · clic sur un lieu"
	layer.add_child(lbl)
	_debug_label = lbl

func _setup_tooltip() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_tooltip = HoloTooltip.new()
	layer.add_child(_tooltip)

# ─── Projection (ville à plat : y=0) ──────────────────────────
func _cgrid() -> float:
	return float(grille - 1) * 0.5

func _world(gx: float, gy: float, y: float) -> Vector3:
	return Vector3((gx - _cgrid()) * taille_cellule, y, (gy - _cgrid()) * taille_cellule)

# Centre monde d'un bâtiment d'emprise N×M dont la cellule d'origine est (i,j).
func _centre_emprise(i: int, j: int, emp: Vector2i) -> Vector3:
	return _world(i + (emp.x - 1) * 0.5, j + (emp.y - 1) * 0.5, 0.0)

# ─── Construction ─────────────────────────────────────────────
func _build_all() -> void:
	if not is_instance_valid(_monde):
		_monde = Node3D.new()
		_monde.name = "Monde"
		add_child(_monde)
	for c in _monde.get_children():
		c.queue_free()

	_calc_routes()
	_calc_decor()
	_bloque.clear()
	for k in _eau:
		_bloque[k] = true
	for k in _parc:
		_bloque[k] = true
	_reserver_lieux()       # interdit le remplissage sous les lieux

	_build_routes_neon()
	if decor_actif:
		_build_decor()
	_build_ville()
	_construire_lieux(lieux)

func _ajouter_mesh(mesh: ArrayMesh, nom: String, mat: Material = null) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _mat_decor
	_monde.add_child(mi)

# ─── Voirie ───────────────────────────────────────────────────
func _calc_routes() -> void:
	_cols_route.clear()
	_rows_route.clear()
	_marquer_routes(_cols_route)
	_marquer_routes(_rows_route)

func _marquer_routes(dest: Dictionary) -> void:
	var p := taille_ilot
	var idx := 0
	while p < grille:
		var est_avenue := idx % maxi(1, avenue_tous_les) == 0
		var w := avenue_largeur if est_avenue else rue_secondaire
		for k in w:
			if p + k < grille:
				dest[p + k] = est_avenue   # valeur = grand axe ? (hiérarchie néon)
		p += w + taille_ilot
		idx += 1

func _est_route(x: int, y: int) -> bool:
	return _cols_route.has(x) or _rows_route.has(y)

# ─── Décor d'ambiance (placeholder : lac + fleuve + parc) ─────
func _calc_decor() -> void:
	_eau.clear()
	_parc.clear()
	if not decor_actif:
		return
	var g := float(grille)
	# Lac (ellipse).
	var lc := Vector2(g * 0.74, g * 0.24)
	var lrx := g * 0.14
	var lry := g * 0.10
	# Parc (rectangle).
	var px0 := int(g * 0.08); var px1 := int(g * 0.30)
	var py0 := int(g * 0.62); var py1 := int(g * 0.84)
	for x in grille:
		for y in grille:
			var fx := float(x); var fy := float(y)
			# Fleuve : bande diagonale traversante.
			var d_fleuve: float = abs(fy - (0.50 * g + 0.16 * fx))
			if d_fleuve < 1.3:
				_eau[Vector2i(x, y)] = true
			elif pow((fx - lc.x) / lrx, 2.0) + pow((fy - lc.y) / lry, 2.0) <= 1.0:
				_eau[Vector2i(x, y)] = true
			elif x >= px0 and x <= px1 and y >= py0 and y <= py1:
				_parc[Vector2i(x, y)] = true

func _build_decor() -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var ce := Color(couleur_eau, 0.7)
	var cp := Color(couleur_parc, 0.7)
	# Eau : courtes vaguelettes horizontales.
	for k in _eau:
		var cell := k as Vector2i
		var c := _world(cell.x, cell.y, 0.012)
		var hw := taille_cellule * 0.4
		n += HoloMesh3D.line(s, c + Vector3(-hw, 0, -0.05 * taille_cellule),
				c + Vector3(hw, 0, -0.05 * taille_cellule), ce)
		n += HoloMesh3D.line(s, c + Vector3(-hw, 0, 0.18 * taille_cellule),
				c + Vector3(hw, 0, 0.18 * taille_cellule), ce)
	# Parc : petits « arbres » (croix verticale + houppier diamant) un peu épars.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x515A11
	for k in _parc:
		if rng.randf() > 0.55:
			continue
		var cell := k as Vector2i
		var c := _world(cell.x, cell.y, 0.0)
		var ht := unite_maison * 1.2
		n += HoloMesh3D.line(s, c, c + Vector3(0, ht, 0), cp)
		n += HoloMesh3D.diamond(s, c + Vector3(0, ht + ht * 0.4, 0),
				taille_cellule * 0.22, ht * 0.5, cp)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Decor", _mat_ambiance)

# ─── Routes-néon (seul calque de lignes au sol) ───────────────
# Trace la voirie (déjà calculée pour les îlots) en néon magenta fin, avec
# hiérarchie grand axe / rue. Le flux lumineux est animé par le shader.
func _build_routes_neon() -> void:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	var n := 0
	var L := float(grille - 1) * taille_cellule
	var y := 0.015
	for col in _cols_route:
		var i_col := route_intensite_avenue if _cols_route[col] else route_intensite_rue
		n += _route_line(s, _world(col, 0, y), _world(col, grille - 1, y), i_col, L)
	for row in _rows_route:
		var i_row := route_intensite_avenue if _rows_route[row] else route_intensite_rue
		n += _route_line(s, _world(0, row, y), _world(grille - 1, row, y), i_row, L)
	if n <= 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Routes"
	mi.mesh = s.commit()
	mi.material_override = _mat_routes
	_monde.add_child(mi)

# Segment de route : UV.x = distance le long du tracé (pour le flux animé),
# COLOR.a = intensité (hiérarchie avenue / rue).
func _route_line(s: SurfaceTool, a: Vector3, b: Vector3, inten: float, L: float) -> int:
	s.set_color(Color(1, 1, 1, inten)); s.set_uv(Vector2(0, 0)); s.add_vertex(a)
	s.set_color(Color(1, 1, 1, inten)); s.set_uv(Vector2(L, 0)); s.add_vertex(b)
	return 1

# ─── Tissu urbain (remplissage par gabarits) ──────────────────
func _build_ville() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var occ := {}
	var s := HoloMesh3D.st()           # arêtes lumineuses
	var sf := HoloMesh3D.st_tri()      # faces sombres semi-opaques
	var n := 0
	var nf := 0
	var col := Color(couleur_decor_bati, 0.85)
	for x in grille:
		for y in grille:
			var cell := Vector2i(x, y)
			if occ.has(cell) or _bloque.has(cell) or _est_route(x, y):
				continue
			if rng.randf() > densite:
				occ[cell] = true       # placette / espace laissé vide
				continue
			var g := _gabarit_rentre(x, y, occ, rng)
			if g == null:
				occ[cell] = true
				continue
			for di in g.emprise.x:
				for dj in g.emprise.y:
					occ[Vector2i(x + di, y + dj)] = true
			var sx := float(g.emprise.x) * taille_cellule * 0.86
			var sz := float(g.emprise.y) * taille_cellule * 0.86
			var et := g.etages + (0 if g.creux else rng.randi_range(0, 2))
			var sy := float(et) * unite_maison
			var centre := _centre_emprise(x, y, g.emprise)
			# Contour creux UNIQUEMENT (12 arêtes) — aucun quadrillage interne.
			n += HoloMesh3D.box(s, centre, sx, sy, sz, col)
			# Faces sombres légèrement insérées (occlusion douce).
			nf += HoloMesh3D.box_faces(sf, centre, sx * FACE_INSET, sy * FACE_INSET, sz * FACE_INSET)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Ville")
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "VilleFaces"
		mif.mesh = fmesh
		mif.material_override = _mat_faces
		_monde.add_child(mif)

# Premier gabarit (ordre aléatoire) dont l'emprise tient ici (pas de route /
# décor / occupé / hors-grille sous l'empreinte).
func _gabarit_rentre(x: int, y: int, occ: Dictionary, rng: RandomNumberGenerator) -> HoloGabarit:
	var ordre := gabarits.duplicate()
	ordre.shuffle()
	for g: HoloGabarit in ordre:
		if rng.randf() > g.poids:
			continue
		if _emprise_libre(x, y, g.emprise, occ):
			return g
	# Repli : un gabarit 1×1 s'il en existe un.
	for g: HoloGabarit in gabarits:
		if g.emprise == Vector2i(1, 1) and _emprise_libre(x, y, g.emprise, occ):
			return g
	return null

func _emprise_libre(x: int, y: int, emp: Vector2i, occ: Dictionary) -> bool:
	for di in emp.x:
		for dj in emp.y:
			var cx := x + di
			var cy := y + dj
			if cx >= grille or cy >= grille:
				return false
			var c := Vector2i(cx, cy)
			if occ.has(c) or _bloque.has(c) or _est_route(cx, cy):
				return false
	return true

func _gabarits_defaut() -> Array[HoloGabarit]:
	# [nom, emprise, étages, creux, poids]
	var defs := [
		["maison",      Vector2i(1, 1), 1, false, 1.0],
		["maison_r1",   Vector2i(1, 1), 2, false, 0.9],
		["duplex",      Vector2i(2, 1), 2, false, 0.7],
		["immeuble",    Vector2i(2, 2), 6, false, 0.6],
		["immeuble_l",  Vector2i(3, 2), 4, false, 0.5],
		["bloc",        Vector2i(3, 3), 3, false, 0.4],
		["tour",        Vector2i(2, 2), 12, false, 0.35],
		["entrepot",    Vector2i(4, 3), 2, true,  0.3],
		["decharge",    Vector2i(5, 5), 1, true,  0.18],
	]
	var out: Array[HoloGabarit] = []
	for d in defs:
		var g := HoloGabarit.new()
		g.nom = d[0]; g.emprise = d[1]; g.etages = d[2]; g.creux = d[3]; g.poids = d[4]
		out.append(g)
	return out

# ─── Lieux (bâtiments-lieux tier-colorés, découverts only) ────
func _reserver_lieux() -> void:
	for l in lieux:
		if not l.decouvert:
			continue
		for di in l.emprise.x:
			for dj in l.emprise.y:
				_bloque[Vector2i(l.cellule.x + di, l.cellule.y + dj)] = true

func _construire_lieux(liste: Array) -> void:
	_hovered = null
	if is_instance_valid(_tooltip):
		_tooltip.cacher()
	if not is_instance_valid(_lieux_node):
		_lieux_node = Node3D.new()
		_lieux_node.name = "Lieux"
		add_child(_lieux_node)
	for c in _lieux_node.get_children():
		_lieux_node.remove_child(c)
		c.queue_free()

	for l in liste:
		if not l.decouvert:
			continue  # règle stricte : absent (bâtiment + pin + anneau + collision)
		var loc := HoloLocation3D.new()
		loc.lieu_id      = l.id
		loc.lieu_nom     = l.nom_affichage_fr
		loc.tier         = l.tier
		loc.lore         = l.lore_fr
		loc.col          = UIColors.tier_color(l.tier)   # DA : couleur de palier
		loc.taille_x     = float(l.emprise.x) * taille_cellule * 0.9
		loc.taille_z     = float(l.emprise.y) * taille_cellule * 0.9
		loc.hauteur      = float(l.etages) * unite_maison
		loc.etages       = l.etages
		loc.ring_radius  = maxf(l.emprise.x, l.emprise.y) * taille_cellule * 0.7
		loc.sans_batiment = l.sans_batiment
		loc.line_shader  = LINE_SHADER
		loc.face_material = _mat_faces
		loc.face_inset   = FACE_INSET
		loc.position     = _centre_emprise(l.cellule.x, l.cellule.y, l.emprise)
		loc.clique.connect(_on_lieu_clique)
		loc.survol_change.connect(_on_survol)
		_lieux_node.add_child(loc)

func _on_survol(loc: HoloLocation3D, actif: bool) -> void:
	if actif:
		_hovered = loc
		# Accent du tooltip = couleur de palier du lieu.
		_tooltip.montrer(loc.lieu_nom, GameData.get_tier_name(loc.tier),
				UIColors.tier_color(loc.tier), loc.lore, UIColors.tier_color(loc.tier))
	elif _hovered == loc:
		_hovered = null
		_tooltip.cacher()

func _on_lieu_clique(id: String) -> void:
	lieu_selectionne.emit(id)
	var nom := id
	for l in lieux:
		if l.id == id:
			nom = l.nom_affichage_fr
			break
	print("[HoloMap3D] lieu sélectionné : %s (%s)" % [id, nom])
	if is_instance_valid(_debug_label):
		_debug_label.text = "Lieu sélectionné : %s" % nom

# ─── Caméra orbitale (monde fixe) ─────────────────────────────
func _appliquer_camera() -> void:
	if not is_instance_valid(_rig):
		return
	plongee_deg = clampf(plongee_deg, plongee_min, plongee_max)
	distance = clampf(distance, distance_min, distance_max)
	_rig.rotation = Vector3(-deg_to_rad(plongee_deg), _yaw, 0.0)
	_cam.position = Vector3(0, 0, distance)
	_cam.fov = fov

func _process(dt: float) -> void:
	if auto_rotation:
		_yaw += deg_to_rad(vitesse_rotation) * dt
		_appliquer_camera()
	_maj_tooltip()

func _maj_tooltip() -> void:
	if not is_instance_valid(_tooltip):
		return
	if _hovered == null or not is_instance_valid(_hovered):
		return
	var wp := _hovered.ancre_globale()
	_tooltip.positionner(_cam.unproject_position(wp), not _cam.is_position_behind(wp))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance -= 1.2
			_appliquer_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance += 1.2
			_appliquer_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and mode_rotation == 0
	elif event is InputEventMouseMotion and _dragging:
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * 0.01
		plongee_deg = clampf(plongee_deg + rel.y * 0.3, plongee_min, plongee_max)
		_appliquer_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed and mode_rotation == 1:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT:
			tourner(-deg_to_rad(palier_deg))
		elif k == KEY_RIGHT:
			tourner(deg_to_rad(palier_deg))

func tourner(d_yaw: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_yaw, _yaw, _yaw + d_yaw, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_yaw(v: float) -> void:
	_yaw = v
	_appliquer_camera()

# ─── API publique ─────────────────────────────────────────────
func peupler_lieux(nouvelle_liste: Array[HoloLieuData]) -> void:
	lieux = nouvelle_liste
	_build_all()

func _lieux_placeholder() -> Array[HoloLieuData]:
	# [id, nom, tier, lore, cellule, emprise, etages]
	var defs := [
		["q_nexus", "Nexus Central", 4,
			"Cœur de données de la mégapole, scellé depuis le Grand Crash.",
			Vector2i(12, 12), Vector2i(3, 3), 14],
		["q_fonderie", "Fonderie Néon", 2,
			"Les forges automatisées tournent encore, sans personne aux commandes.",
			Vector2i(2, 8), Vector2i(3, 2), 5],
		["q_archives", "Archives Spectrales", 3,
			"Des téraoctets de souvenirs volés y dérivent comme des fantômes.",
			Vector2i(20, 3), Vector2i(2, 2), 9],
		["q_dock", "Docks Orbitaux", 1,
			"Rampes de lancement rouillées pointant vers un ciel mort.",
			Vector2i(19, 19), Vector2i(4, 3), 3],
		["q_secret", "Secteur Verrouillé", 5,
			"Inaccessible. Aucune trace dans les registres.",
			Vector2i(7, 20), Vector2i(2, 2), 11, false],
	]
	var out: Array[HoloLieuData] = []
	for d in defs:
		var l := HoloLieuData.new()
		l.id = d[0]
		l.nom_affichage_fr = d[1]
		l.tier = d[2]
		l.lore_fr = d[3]
		l.cellule = d[4]
		l.emprise = d[5]
		l.etages = d[6]
		l.decouvert = d[7] if d.size() > 7 else true
		out.append(l)
	return out
