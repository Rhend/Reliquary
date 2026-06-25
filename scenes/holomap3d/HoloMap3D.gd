# ============================================================
# HoloMap3D — Carte holographique cyberpunk en VRAIE 3D (Godot 4.6).
#
# Node3D racine autonome et lançable. Géométrie en volume (MeshInstance3D en
# PRIMITIVE_LINES, wireframe émissif) : cœur urbain de bâtiments + reliefs
# procéduraux périphériques (heightmap bruit) + circuits néon au sol + grille
# de sol. Double palette cyan/magenta. Marqueurs-pins 3D sur lieux découverts.
#
# CAMÉRA ORBITALE, MONDE FIXE (choix imposé) : on tourne autour de l'axe
# vertical en orbitant la caméra ; les lieux ne bougent jamais → le raycast de
# clic (picking physique) reste cohérent pendant et après rotation.
#
# Glow via WorldEnvironment (HDR 3D). Scanlines/flicker/distorsion en
# post-process plein écran (CanvasLayer + holo_post.gdshader) pour couvrir
# l'image finale de façon homogène, rotation comprise.
#
# Intégration : connecter `lieu_selectionne(id)` à un contrôleur externe.
# Repeupler : `peupler_lieux(liste)`.
#
# Tout est procédural — aucun asset externe requis.
# Hors portée (assets futurs, NON simulés) : nuages volumétriques, micro-détails
# texturés des bâtiments, DOF cinématographique.
# ============================================================
class_name HoloMap3D
extends Node3D

signal lieu_selectionne(id: String)

const LINE_SHADER := preload("res://scenes/holomap3d/holo_line.gdshader")
const POST_SHADER := preload("res://scenes/holomap3d/holo_post.gdshader")

@export var seed_val := 1337

# ─── Caméra / rotation ────────────────────────────────────────
@export_group("Caméra")
@export_range(15.0, 85.0) var plongee_deg := 55.0     # angle aérien
@export var plongee_min := 25.0
@export var plongee_max := 80.0
@export var distance := 14.0                          # distance caméra→centre
@export var distance_min := 7.0
@export var distance_max := 26.0
@export var fov := 50.0
@export_enum("Libre", "Paliers") var mode_rotation := 0
@export var palier_deg := 45.0                        # pas en mode Paliers
@export var vitesse_rotation := 18.0                  # °/s (auto-rotation)
@export var auto_rotation := false

# ─── Maillage / Cœur urbain ───────────────────────────────────
@export_group("Maillage / Ville")
@export var grille := 16                        # nb de cellules par côté (fin = net)
@export var taille_cellule := 0.45              # taille monde d'une cellule (petit = fin)
@export var bloc_cellules := 2                  # côté d'un bâtiment, en cellules
@export var rue_cellules := 1                   # largeur de rue entre blocs (cellules)
@export_range(0.0, 1.0) var densite := 0.62     # proportion de blocs bâtis (espacement prime)
@export var hauteur_min := 0.5
@export var hauteur_max := 2.6
@export var rayon_urbain := 7.0                 # rayon du cœur plat (cellules)

# ─── Reliefs périphériques ────────────────────────────────────
@export_group("Reliefs")
@export var relief_marge := 8
@export_range(1, 3) var relief_subdiv := 1
@export var relief_hauteur := 2.2
@export var relief_echelle := 0.12
@export var relief_transition := 3.0

# ─── Circuits néon ────────────────────────────────────────────
@export_group("Circuits")
@export var circuits_count := 6

# ─── Palette ──────────────────────────────────────────────────
@export_group("Palette")
@export var couleur_cyan := Color(0.30, 0.85, 1.00)
@export var couleur_magenta := Color(1.00, 0.25, 0.78)
# Finesse du trait : émission HDR des lignes. En GL Compatibility le cœur de
# ligne fait 1 px ; l'épaisseur PERÇUE vient du glow → baisser pour un trait
# plus fin/net, monter pour des lignes plus grasses.
@export var luminosite_lignes := 1.5

# ─── Hologramme (glow + post-process) ─────────────────────────
@export_group("Hologramme")
@export var glow_intensity := 1.0
@export_range(0.0, 1.0) var scanline_intensity := 0.28
@export var scanline_count := 240.0
@export var scanline_speed := 0.6
@export_range(0.0, 0.5) var flicker_amplitude := 0.04
@export_range(0.0, 0.02) var distortion_amplitude := 0.0035
# Post-process interne (scanlines/flicker/distorsion sur un CanvasLayer). À
# DÉSACTIVER quand la scène est embarquée dans un SubViewport : le post est
# alors porté par le SubViewportContainer (cf. HoloMap3DOverlay).
@export var post_process_interne := true

# ─── Lieux ────────────────────────────────────────────────────
@export_group("Lieux")
@export var lieux: Array[HoloLieuData] = []

var _rig: Node3D
var _cam: Camera3D
var _monde: Node3D
var _lieux_node: Node3D
var _mat_lignes: ShaderMaterial
var _post_mat: ShaderMaterial
var _noise: FastNoiseLite

var _yaw := 0.0
var _dragging := false
var _debug_label: Label
var _tooltip: HoloTooltip
var _hovered: HoloLocation3D

func _ready() -> void:
	get_viewport().physics_object_picking = true   # picking 3D (Area3D)
	if lieux.is_empty():
		lieux = _lieux_placeholder()
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
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.12, 0.18)
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_bloom = 0.12          # halo plus serré → trait plus net
	env.glow_hdr_threshold = 1.05  # seuil relevé → moins de bouillie lumineuse
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
	_cam.far = 200.0
	_rig.add_child(_cam)
	_appliquer_camera()

func _setup_materials() -> void:
	_mat_lignes = ShaderMaterial.new()
	_mat_lignes.shader = LINE_SHADER
	_mat_lignes.set_shader_parameter("emission_strength", luminosite_lignes)
	_mat_lignes.set_shader_parameter("alpha_mult", 1.0)

func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	_appliquer_post_uniforms()
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ne bloque pas le picking 3D
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
	lbl.text = "HoloMap3D — glisser pour orbiter · molette = zoom · clic sur un pin"
	layer.add_child(lbl)
	_debug_label = lbl

# Tooltip de lieu (au-dessus du post-process interne : layer 3 > layer 1).
func _setup_tooltip() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_tooltip = HoloTooltip.new()
	layer.add_child(_tooltip)

func _appliquer_post_uniforms() -> void:
	_post_mat.set_shader_parameter("scanline_intensity", scanline_intensity)
	_post_mat.set_shader_parameter("scanline_count", scanline_count)
	_post_mat.set_shader_parameter("scanline_speed", scanline_speed)
	_post_mat.set_shader_parameter("flicker_amplitude", flicker_amplitude)
	_post_mat.set_shader_parameter("distortion_amplitude", distortion_amplitude)

# ─── Projection / heightmap ───────────────────────────────────
func _cgrid() -> float:
	return float(grille - 1) * 0.5

func _world(gx: float, gy: float, y: float) -> Vector3:
	return Vector3((gx - _cgrid()) * taille_cellule, y, (gy - _cgrid()) * taille_cellule)

func _relief_weight(gx: float, gy: float) -> float:
	var d := Vector2(gx - _cgrid(), gy - _cgrid()).length()
	var rise := smoothstep(rayon_urbain, rayon_urbain + relief_transition, d)
	var outer := _cgrid() + float(relief_marge)
	var fall := 1.0 - smoothstep(outer * 0.8, outer, d)
	return clampf(rise * fall, 0.0, 1.0)

func _relief_h(gx: float, gy: float) -> float:
	var w := _relief_weight(gx, gy)
	if w <= 0.0:
		return 0.0
	var n01 := _noise.get_noise_2d(gx, gy) * 0.5 + 0.5
	return relief_hauteur * w * n01

# ─── Construction du monde ────────────────────────────────────
func _build_all() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed_val
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = relief_echelle

	if not is_instance_valid(_monde):
		_monde = Node3D.new()
		_monde.name = "Monde"
		add_child(_monde)
	for c in _monde.get_children():
		c.queue_free()

	_build_grille_sol()
	_build_reliefs()
	_build_ville()
	_build_circuits()
	_construire_lieux(lieux)

func _ajouter_mesh(parent: Node3D, mesh: ArrayMesh, nom: String) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.material_override = _mat_lignes
	parent.add_child(mi)

func _build_grille_sol() -> void:
	var s := HoloMesh3D.st()
	var col := Color(couleur_cyan, 0.30)
	var n := 0
	for i in grille:
		HoloMesh3D.line(s, _world(i, 0, 0.0), _world(i, grille - 1, 0.0), col); n += 1
		HoloMesh3D.line(s, _world(0, i, 0.0), _world(grille - 1, i, 0.0), col); n += 1
	_ajouter_mesh(_monde, HoloMesh3D.commit(s, n), "GrilleSol")

func _build_reliefs() -> void:
	var gmin := -float(relief_marge)
	var gmax := float(grille - 1 + relief_marge)
	var step := 1.0 / float(relief_subdiv)
	var cols := int(round((gmax - gmin) / step)) + 1

	var pts: Array = []
	var ws: Array = []
	for a in cols:
		var gx := gmin + a * step
		var rp: Array = []
		var rw := PackedFloat32Array()
		for b in cols:
			var gy := gmin + b * step
			rp.append(_world(gx, gy, _relief_h(gx, gy)))
			rw.append(_relief_weight(gx, gy))
		pts.append(rp)
		ws.append(rw)

	var s := HoloMesh3D.st()
	var n := 0
	for a in cols:
		for b in cols:
			if a + 1 < cols:
				n += _arete(s, pts[a][b], pts[a + 1][b], ws[a][b], ws[a + 1][b])
			if b + 1 < cols:
				n += _arete(s, pts[a][b], pts[a][b + 1], ws[a][b], ws[a][b + 1])
	_ajouter_mesh(_monde, HoloMesh3D.commit(s, n), "Reliefs")

# Arête de relief : sautée si plate (cœur urbain), teintée cyan→magenta.
func _arete(s: SurfaceTool, p1: Vector3, p2: Vector3, w1: float, w2: float) -> int:
	var w := maxf(w1, w2)
	if w < 0.05:
		return 0
	var col := couleur_cyan.lerp(couleur_magenta, clampf(w * 0.45, 0.0, 0.4))
	HoloMesh3D.line(s, p1, p2, Color(col, 0.30 + 0.5 * w))
	return 1

# Ville par BLOCS : un bâtiment occupe `bloc_cellules`² cellules, séparé du
# voisin par `rue_cellules` cellules de rue (espacement → arêtes non partagées,
# lecture « circuit imprimé »). Densité = proportion de blocs bâtis.
func _build_ville() -> void:
	var reserved := {}
	for l in lieux:
		if l.decouvert:
			reserved[l.cellule] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(couleur_cyan, 0.9)
	var pitch := bloc_cellules + rue_cellules
	var fp := float(bloc_cellules) * taille_cellule * 0.82  # inset → rues visibles
	var bi := 0
	while bi < grille:
		var bj := 0
		while bj < grille:
			var cx := bi + (bloc_cellules - 1) * 0.5
			var cy := bj + (bloc_cellules - 1) * 0.5
			if Vector2(cx - _cgrid(), cy - _cgrid()).length() <= rayon_urbain \
					and not _bloc_reserve(reserved, bi, bj) \
					and rng.randf() <= densite:
				var h := rng.randf_range(hauteur_min, hauteur_max)
				HoloMesh3D.box(s, _world(cx, cy, 0.0), fp, h, fp, col)
				n += 12
			bj += pitch
		bi += pitch
	_ajouter_mesh(_monde, HoloMesh3D.commit(s, n), "Ville")

# Vrai si une cellule réservée à un lieu tombe dans l'empreinte du bloc.
func _bloc_reserve(reserved: Dictionary, bi: int, bj: int) -> bool:
	for di in bloc_cellules:
		for dj in bloc_cellules:
			if reserved.has(Vector2i(bi + di, bj + dj)):
				return true
	return false

func _build_circuits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x9E3779B9
	var s := HoloMesh3D.st()
	var n := 0
	for c in circuits_count:
		var col := couleur_cyan if c % 3 == 0 else couleur_magenta
		var cur := Vector2(rng.randi_range(0, grille - 1), rng.randi_range(0, grille - 1))
		for _k in rng.randi_range(3, 5):
			var target := Vector2(rng.randi_range(0, grille - 1), rng.randi_range(0, grille - 1))
			var mid := Vector2(target.x, cur.y) if rng.randf() < 0.5 else Vector2(cur.x, target.y)
			HoloMesh3D.line(s, _world(cur.x, cur.y, 0.04), _world(mid.x, mid.y, 0.04),
					Color(col, 0.85)); n += 1
			HoloMesh3D.line(s, _world(mid.x, mid.y, 0.04), _world(target.x, target.y, 0.04),
					Color(col, 0.85)); n += 1
			cur = target
	_ajouter_mesh(_monde, HoloMesh3D.commit(s, n), "Circuits")

# ─── Lieux (pins + anneaux + collisions, découverts only) ─────
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

	var fp := float(bloc_cellules) * taille_cellule
	for l in liste:
		if not l.decouvert:
			continue  # règle stricte : absent (pin + anneau + collision)
		var loc := HoloLocation3D.new()
		loc.lieu_id      = l.id
		loc.lieu_nom     = l.nom_affichage_fr
		loc.tier         = l.tier
		loc.lore         = l.lore_fr
		loc.accent_color = couleur_magenta
		loc.base_color   = couleur_cyan
		loc.footprint    = fp * 0.7
		loc.base_y       = _relief_h(l.cellule.x, l.cellule.y)
		loc.ring_radius  = fp * 0.95
		loc.line_shader  = LINE_SHADER
		loc.position     = _world(l.cellule.x, l.cellule.y, 0.0)
		loc.clique.connect(_on_lieu_clique)
		loc.survol_change.connect(_on_survol)
		_lieux_node.add_child(loc)

func _on_survol(loc: HoloLocation3D, actif: bool) -> void:
	if actif:
		_hovered = loc
		_tooltip.montrer(loc.lieu_nom, GameData.get_tier_name(loc.tier),
				UIColors.tier_color(loc.tier), loc.lore, couleur_magenta)
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

# Reprojette l'ancre 3D du pin survolé vers l'écran chaque frame → la ligne de
# rappel et le cadre suivent le pin pendant/aprés la rotation.
func _maj_tooltip() -> void:
	if not is_instance_valid(_tooltip):
		return
	if _hovered == null or not is_instance_valid(_hovered):
		return
	var wp := _hovered.ancre_globale()
	var a_lecran := not _cam.is_position_behind(wp)
	_tooltip.positionner(_cam.unproject_position(wp), a_lecran)

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
			_dragging = mb.pressed and mode_rotation == 0  # drag = orbite (mode Libre)
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

# API publique : rotation (utilisée par le mode Paliers ; tweenée).
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
	# [id, nom_affichage_fr, tier, lore_fr, cellule, decouvert]
	var defs := [
		["q_nexus", "Nexus Central", 4,
			"Cœur de données de la mégapole, scellé depuis le Grand Crash.",
			Vector2i(8, 8), true],
		["q_fonderie", "Fonderie Néon", 2,
			"Les forges automatisées tournent encore, sans personne aux commandes.",
			Vector2i(3, 11), true],
		["q_archives", "Archives Spectrales", 3,
			"Des téraoctets de souvenirs volés y dérivent comme des fantômes.",
			Vector2i(12, 4), true],
		["q_dock", "Docks Orbitaux", 1,
			"Rampes de lancement rouillées pointant vers un ciel mort.",
			Vector2i(11, 12), true],
		["q_secret", "Secteur Verrouillé", 5,
			"Inaccessible. Aucune trace dans les registres.",
			Vector2i(4, 3), false], # non découvert : absent
	]
	var out: Array[HoloLieuData] = []
	for d in defs:
		var l := HoloLieuData.new()
		l.id = d[0]
		l.nom_affichage_fr = d[1]
		l.tier = d[2]
		l.lore_fr = d[3]
		l.cellule = d[4]
		l.decouvert = d[5]
		out.append(l)
	return out
