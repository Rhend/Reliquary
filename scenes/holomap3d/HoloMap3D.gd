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
const MOTES_SHADER := preload("res://scenes/holomap3d/holo_motes.gdshader")
const TRAFFIC_SHADER := preload("res://scenes/holomap3d/holo_traffic.gdshader")
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
# Fond : noir.
@export var couleur_fond := Color(0.0, 0.0, 0.0)

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

# ─── Effets / Juice ───────────────────────────────────────────
@export_group("Effets")
@export var intro_actif := true               # matérialisation : la ville monte du sol à l'ouverture
@export var socle_actif := true               # anneau-socle « table tactique »
@export var radar_actif := true               # balayage radar lent au sol
@export var radar_vitesse := 22.0             # °/s du balayage
@export var couleur_socle := Color(0.30, 0.85, 1.00)  # cyan holographique (cadre/HUD au sol)
@export var zoom_amorti := true               # zoom molette lissé
@export var hud_actif := true                 # habillage HUD 2D (crochets + ligne de scan)
@export var motes_actif := true               # poussières de données qui montent
@export var motes_count := 80
@export var motes_hauteur := 3.5              # hauteur de montée des poussières
@export var couleur_motes := Color(0.40, 0.85, 1.00)
# Trafic : traînées lumineuses qui circulent sur les routes.
@export var trafic_actif := true
@export var voitures_par_voie := 2            # nb de véhicules par sens et par route
@export var vitesse_voitures := 0.08          # tours/seconde
@export var couleur_voiture_aller := Color(0.55, 0.90, 1.00)   # cyan (phares)
@export var couleur_voiture_retour := Color(1.00, 0.55, 0.25)  # ambre (feux arrière)
# Brume de profondeur : les arêtes lointaines s'estompent (focus centre).
@export var brume_debut := 16.0
@export var brume_fin := 30.0

# ─── Urbanisme (Wave 4) ───────────────────────────────────────
@export_group("Urbanisme")
@export var skyline_radiale := true           # tours hautes au centre, bas aux bords
@export var skyline_centre := 2.2             # facteur de hauteur au centre (downtown)
@export var skyline_bord := 0.40              # facteur de hauteur aux bords
@export var zonage_actif := true              # quartiers : tours centre / entrepôts périphérie
# Îlots à fronts de rue : les cellules en bordure de rue se bâtissent presque
# toujours (front continu), le cœur d'îlot reste creux (courettes) → la ville se
# lit en blocs et non en bâtiments éparpillés.
@export var ilots_fronts := true
@export_range(0.0, 1.0) var coeur_ilot_densite := 0.30  # densité au cœur d'un îlot
# Teinte des arêtes par quartier (downtown cyan, périphérie ambre) → quartiers lisibles.
@export var teinte_quartiers := true
@export var teinte_downtown := Color(0.40, 0.78, 1.00)   # accent froid du centre
@export var teinte_peripherie := Color(1.00, 0.62, 0.34) # accent chaud des faubourgs
@export var toits_detail_actif := true        # antennes / citernes sur les toits
@export var enseignes_actif := true           # bannières holographiques sur quelques tours
@export var monument_actif := true            # place + flèche-repère au centre
@export var noeuds_actif := true              # glow aux GRANDS croisements (avenue × avenue)
@export var autoroute_actif := true           # autoroute surélevée + piliers + trafic
@export var autoroute_hauteur := 2.6
@export var couleur_neon := Color(0.30, 0.85, 1.00)  # base émissive des accents néon
# Fenêtres allumées (shader de faces) : densité + gain d'émission → ville habitée.
@export_range(0.0, 1.0) var fenetre_densite := 0.24
@export var fenetre_emission := 1.9
@export var couleur_fenetre := Color(0.98, 0.86, 0.58)  # ambre chaud
# Décor d'un lieu SANS bâtiment (parc-lieu) : émission du décor tier-coloré.
@export var lieu_decor_emission := 3.4

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
var _radar: Node3D
var _mat_motes: ShaderMaterial
var _mat_trafic: ShaderMaterial
var _mat_neon: ShaderMaterial          # accents néon (enseignes, nœuds d'intersection)
var _mat_lieu_decor: ShaderMaterial    # décor d'un lieu sans bâtiment (parc tier-coloré)
var _distance_cible := 15.0
var _intro_en_cours := false
var _mats_reveal: Array[ShaderMaterial] = []   # matériaux supportant le reveal d'intro
var _foc := 0.0                                # intensité courante du focus de survol
var _focus_tw: Tween

var _cols_route := {}
var _rows_route := {}
var _bloque := {}        # Vector2i → true : cellules interdites au remplissage (décor + lieux)
var _eau := {}
var _parc := {}
var _lieu_sol := {}      # Vector2i → Color : cellule de décor portée par un lieu sans bâtiment

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
	if hud_actif:
		_setup_hud()
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
	_distance_cible = distance
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
	_mat_faces.set_shader_parameter("fenetre_densite", fenetre_densite)
	_mat_faces.set_shader_parameter("fenetre_emission", fenetre_emission)
	_mat_faces.set_shader_parameter("fenetre_color", couleur_fenetre)
	_mat_faces.render_priority = -1

	# Poussières de données (montée animée).
	_mat_motes = ShaderMaterial.new()
	_mat_motes.shader = MOTES_SHADER
	_mat_motes.set_shader_parameter("mote_color", couleur_motes)
	_mat_motes.set_shader_parameter("hauteur", motes_hauteur)

	# Trafic (traînées le long des routes).
	_mat_trafic = ShaderMaterial.new()
	_mat_trafic.shader = TRAFFIC_SHADER
	_mat_trafic.set_shader_parameter("vitesse", vitesse_voitures)

	# Accents néon (enseignes holographiques, nœuds d'intersection) — glow.
	_mat_neon = ShaderMaterial.new()
	_mat_neon.shader = LINE_SHADER
	_mat_neon.set_shader_parameter("emission_strength", 2.0)
	_mat_neon.set_shader_parameter("alpha_mult", 1.0)

	# Décor d'un lieu SANS bâtiment (parc-lieu) : tier-coloré + glow marqué pour
	# que la zone ressorte comme un lieu (pas un simple décor vert).
	_mat_lieu_decor = ShaderMaterial.new()
	_mat_lieu_decor.shader = LINE_SHADER
	_mat_lieu_decor.set_shader_parameter("emission_strength", lieu_decor_emission)
	_mat_lieu_decor.set_shader_parameter("alpha_mult", 1.0)

	# Brume de profondeur : poussée sur les matériaux de lignes/routes/trafic
	# (les faces ne fadent pas → l'occlusion reste). Les lieux/faisceaux
	# utilisent les valeurs par défaut du shader (cohérentes avec ces exports).
	for m: ShaderMaterial in [_mat_decor, _mat_ambiance, _mat_routes, _mat_trafic, _mat_neon, _mat_lieu_decor]:
		m.set_shader_parameter("fog_debut", brume_debut)
		m.set_shader_parameter("fog_fin", brume_fin)

	# Matériaux qui réagissent au reveal d'intro (matérialisation radiale).
	_mats_reveal = [_mat_decor, _mat_ambiance, _mat_routes, _mat_faces, _mat_trafic, _mat_neon, _mat_lieu_decor]

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

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var hud := HoloHud.new()
	hud.couleur = couleur_socle
	layer.add_child(hud)

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
	_calc_lieu_sol()        # cellules de décor portées par un lieu sans bâtiment
	_bloque.clear()
	for k in _eau:
		_bloque[k] = true
	for k in _parc:
		_bloque[k] = true
	_reserver_lieux()       # interdit le remplissage sous les lieux
	if monument_actif:
		for c in _cellules_monument():
			_bloque[c] = true   # place centrale (pas de bâtiment de remplissage)

	if socle_actif:
		_build_socle()
	_build_routes_neon()
	if noeuds_actif:
		_build_noeuds()
	if decor_actif:
		_build_decor()
	_build_ville()
	if monument_actif:
		_build_monument()
	if autoroute_actif:
		_build_autoroute()
	_construire_lieux(lieux)
	if trafic_actif:
		_build_trafic()
	if motes_actif:
		_build_motes()
	if radar_actif:
		_build_radar()
	if intro_actif:
		_jouer_intro()

# ─── Trafic : traînées lumineuses qui circulent sur les routes ─
func _build_trafic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xCA4F1C
	var y := 0.03
	var carlen := taille_cellule * 0.55
	var lz := Vector3(0, 0, float(grille - 1) * taille_cellule)   # trajet le long de Z
	var lx := Vector3(float(grille - 1) * taille_cellule, 0, 0)   # trajet le long de X
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	# Trafic hiérarchisé : grands axes plus chargés (×2) et plus rapides (×1.4).
	for col in _cols_route:
		var av: bool = _cols_route[col]
		var nb := voitures_par_voie * (2 if av else 1)
		var spd := 1.4 if av else 1.0
		_semer_voitures(s, _world(col, 0, y), lz, carlen, rng, couleur_voiture_aller, nb, spd)
		_semer_voitures(s, _world(col, grille - 1, y), -lz, carlen, rng, couleur_voiture_retour, nb, spd)
	for row in _rows_route:
		var av2: bool = _rows_route[row]
		var nb2 := voitures_par_voie * (2 if av2 else 1)
		var spd2 := 1.4 if av2 else 1.0
		_semer_voitures(s, _world(0, row, y), lx, carlen, rng, couleur_voiture_aller, nb2, spd2)
		_semer_voitures(s, _world(grille - 1, row, y), -lx, carlen, rng, couleur_voiture_retour, nb2, spd2)
	var mi := MeshInstance3D.new()
	mi.name = "Trafic"
	mi.mesh = s.commit()
	mi.material_override = _mat_trafic
	_monde.add_child(mi)

# Sème `nb` segments sur une route : base = départ, UV2 = vecteur de trajet
# complet, COLOR.a = multiplicateur de vitesse (le shader translate selon UV.x).
func _semer_voitures(s: SurfaceTool, depart: Vector3, trajet: Vector3, carlen: float,
		rng: RandomNumberGenerator, couleur: Color, nb: int, vit_mult: float) -> void:
	var dirn := trajet.normalized()
	var uv2 := Vector2(trajet.x, trajet.z)
	var c := Color(couleur.r, couleur.g, couleur.b, vit_mult)
	for _v in maxi(0, nb):
		var ph := rng.randf()
		var p0 := depart
		var p1 := depart + dirn * carlen
		s.set_color(c); s.set_uv(Vector2(ph, 0)); s.set_uv2(uv2); s.add_vertex(p0)
		s.set_color(c); s.set_uv(Vector2(ph, 0)); s.set_uv2(uv2); s.add_vertex(p1)

# ─── Poussières de données (montée animée par shader) ─────────
func _build_motes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x310C0DE
	var r := (_cgrid() + 1.0) * taille_cellule
	var seg := 0.12
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_LINES)
	for _i in maxi(0, motes_count):
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
	mi.material_override = _mat_motes
	_monde.add_child(mi)

# ─── Socle « table tactique » (anneau + ticks au sol) ─────────
func _build_socle() -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var r := (_cgrid() + 1.0) * taille_cellule * 1.10
	n += HoloMesh3D.circle(s, Vector3.ZERO, r, Color(couleur_socle, 0.55), 96)
	n += HoloMesh3D.circle(s, Vector3.ZERO, r * 0.965, Color(couleur_socle, 0.22), 96)
	# Ticks radiaux (graduations) — plus longs tous les 1/8 de tour.
	var ticks := 48
	for i in ticks:
		var a := TAU * float(i) / float(ticks)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var long := i % 6 == 0
		var ext := taille_cellule * (0.65 if long else 0.3)
		n += HoloMesh3D.line(s, dir * r, dir * (r + ext),
				Color(couleur_socle, 0.5 if long else 0.28))
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Socle")   # _mat_decor → léger glow cyan

# ─── Balayage radar (sweep en éventail, tourne lentement) ─────
func _build_radar() -> void:
	var r := (_cgrid() + 1.0) * taille_cellule * 1.06
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
		s.set_color(Color(couleur_socle, 0.10)); s.add_vertex(Vector3(0, y, 0))
		s.set_color(Color(couleur_socle, al0)); s.add_vertex(p0)
		s.set_color(Color(couleur_socle, al1)); s.add_vertex(p1)
	_radar = Node3D.new()
	_radar.name = "Radar"
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	mi.material_override = _mat_ambiance   # additif, émission faible → discret
	_radar.add_child(mi)
	_monde.add_child(_radar)

# ─── Intro : MATÉRIALISATION RADIALE (la carte se peint du centre) + caméra ─
# Un front lumineux s'étend du centre vers les bords ; au-delà du rayon courant,
# la géométrie est masquée (discard shader) → la ville se dessine. La caméra
# s'approche de loin en parallèle.
func _jouer_intro() -> void:
	_intro_en_cours = true
	var max_r := _cgrid() * taille_cellule * 1.6 + 2.0
	_set_reveal(0.0)
	var d0 := _distance_cible * 1.7
	distance = d0
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_reveal, 0.0, max_r, 1.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(_set_distance, d0, _distance_cible, 1.1) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.finished.connect(func() -> void:
		_intro_en_cours = false
		_distance_cible = distance
		_set_reveal(100000.0))   # désactive le clip une fois la carte peinte

func _set_distance(v: float) -> void:
	distance = v

# Pousse le rayon de matérialisation sur tous les matériaux + les lieux.
func _set_reveal(r: float) -> void:
	for m in _mats_reveal:
		if m != null:
			m.set_shader_parameter("reveal_r", r)
	if is_instance_valid(_lieux_node):
		for c in _lieux_node.get_children():
			if c is HoloLocation3D:
				(c as HoloLocation3D).set_reveal(r)

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

# Cellules de décor portées par un lieu SANS bâtiment → couleur de palier du lieu.
# (Ex. Marécage Putride posé sur le parc : ses arbres prennent sa couleur.)
func _calc_lieu_sol() -> void:
	_lieu_sol.clear()
	for l in lieux:
		if not l.decouvert or not l.sans_batiment:
			continue
		var c := UIColors.tier_color(l.tier)
		for di in l.emprise.x:
			for dj in l.emprise.y:
				_lieu_sol[Vector2i(l.cellule.x + di, l.cellule.y + dj)] = c

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
	# Les arbres SOUS un lieu sans bâtiment passent à la couleur de palier du lieu
	# et dans un mesh à part (matériau qui glow) : la parcelle EST le lieu, elle
	# se lit comme tel. Ces arbres-là sont denses (jamais omis) et un peu plus
	# hauts pour remplir et marquer la zone.
	var sl := HoloMesh3D.st()
	var nl := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x515A11
	for k in _parc:
		var cell := k as Vector2i
		var est_lieu: bool = _lieu_sol.has(cell)
		if not est_lieu and rng.randf() > 0.55:
			continue
		var c := _world(cell.x, cell.y, 0.0)
		var ht := unite_maison * (1.7 if est_lieu else 1.2)
		if est_lieu:
			var lc := Color(_lieu_sol[cell] as Color, 0.9)
			nl += HoloMesh3D.line(sl, c, c + Vector3(0, ht, 0), lc)
			nl += HoloMesh3D.diamond(sl, c + Vector3(0, ht + ht * 0.4, 0),
					taille_cellule * 0.26, ht * 0.5, lc)
		else:
			n += HoloMesh3D.line(s, c, c + Vector3(0, ht, 0), cp)
			n += HoloMesh3D.diamond(s, c + Vector3(0, ht + ht * 0.4, 0),
					taille_cellule * 0.22, ht * 0.5, cp)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Decor", _mat_ambiance)
	_ajouter_mesh(HoloMesh3D.commit(sl, nl), "DecorLieu", _mat_lieu_decor)

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
	var ss := HoloMesh3D.st()          # enseignes holographiques (néon)
	var ns := 0
	for x in grille:
		for y in grille:
			var cell := Vector2i(x, y)
			if occ.has(cell) or _bloque.has(cell) or _est_route(x, y):
				continue
			# Front de rue dense, cœur d'îlot creux (courettes).
			var seuil := densite
			if ilots_fronts and not _front_de_rue(x, y):
				seuil = densite * coeur_ilot_densite
			if rng.randf() > seuil:
				occ[cell] = true       # placette / espace laissé vide
				continue
			var zone := _zone(x, y)
			var col := Color(_teinte_quartier(zone, couleur_decor_bati), 0.85)
			var g := _gabarit_rentre(x, y, occ, rng, zone)
			if g == null:
				occ[cell] = true
				continue
			for di in g.emprise.x:
				for dj in g.emprise.y:
					occ[Vector2i(x + di, y + dj)] = true
			var sx := float(g.emprise.x) * taille_cellule * 0.86
			var sz := float(g.emprise.y) * taille_cellule * 0.86
			var et := g.etages + (0 if g.creux else rng.randi_range(0, 2))
			var cx := x + (g.emprise.x - 1) * 0.5
			var cy := y + (g.emprise.y - 1) * 0.5
			# Skyline radiale : tours hautes au centre, bas aux bords (pas le creux).
			if skyline_radiale and not g.creux:
				et = maxi(1, roundi(float(et) * _facteur_hauteur(cx, cy)))
			var sy := float(et) * unite_maison
			var centre := _centre_emprise(x, y, g.emprise)
			# Contour creux UNIQUEMENT (12 arêtes) — aucun quadrillage interne.
			n += HoloMesh3D.box(s, centre, sx, sy, sz, col)
			# Faces sombres légèrement insérées (occlusion douce).
			nf += HoloMesh3D.box_faces(sf, centre, sx * FACE_INSET, sy * FACE_INSET, sz * FACE_INSET)
			# Détails de toit (antennes / citernes).
			if toits_detail_actif:
				n += _detail_toit(s, centre, sx, sy, sz, et, col, rng)
			# Enseignes holographiques (rares, sur les hautes structures).
			if enseignes_actif and et >= 6 and rng.randf() < 0.18:
				ns += _enseigne(ss, centre, sx, sy, sz, rng)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Ville")
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "VilleFaces"
		mif.mesh = fmesh
		mif.material_override = _mat_faces
		_monde.add_child(mif)
	if ns > 0:
		_ajouter_mesh(HoloMesh3D.commit(ss, ns), "Enseignes", _mat_neon)

# Premier gabarit (ordre aléatoire) dont l'emprise tient ici (pas de route /
# décor / occupé / hors-grille sous l'empreinte).
func _gabarit_rentre(x: int, y: int, occ: Dictionary, rng: RandomNumberGenerator, zone: int) -> HoloGabarit:
	var ordre := gabarits.duplicate()
	ordre.shuffle()
	# 1re passe : gabarits adaptés à la zone (downtown=tours, périph=entrepôts).
	if zonage_actif:
		for g: HoloGabarit in ordre:
			if _zone_gabarit(g) != zone:
				continue
			if rng.randf() > g.poids:
				continue
			if _emprise_libre(x, y, g.emprise, occ):
				return g
	# 2e passe : n'importe quel gabarit qui rentre.
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

# Zone d'un gabarit : 0 = downtown (tours), 1 = résidentiel (petit),
# 2 = industriel/périphérie (large ou creux).
func _zone_gabarit(g: HoloGabarit) -> int:
	if g.etages >= 8:
		return 0
	if g.creux or g.emprise.x * g.emprise.y >= 12:
		return 2
	return 1

# Zone d'une cellule selon la distance au centre (0 centre → 2 périphérie).
func _zone(cx: int, cy: int) -> int:
	var d := Vector2(float(cx) - _cgrid(), float(cy) - _cgrid()).length() / maxf(1.0, _cgrid())
	if d < 0.34:
		return 0
	if d < 0.66:
		return 1
	return 2

# Facteur de hauteur radial (downtown haut → bords bas).
func _facteur_hauteur(cx: float, cy: float) -> float:
	var d := clampf(Vector2(cx - _cgrid(), cy - _cgrid()).length() / maxf(1.0, _cgrid()), 0.0, 1.0)
	return lerpf(skyline_centre, skyline_bord, d)

# Cellule en bordure de rue (front de bloc) : un 4-voisin est une route, OU c'est
# le pourtour de la grille (façade donnant sur le vide).
func _front_de_rue(x: int, y: int) -> bool:
	if x == 0 or y == 0 or x == grille - 1 or y == grille - 1:
		return true
	return _est_route(x - 1, y) or _est_route(x + 1, y) \
			or _est_route(x, y - 1) or _est_route(x, y + 1)

# Teinte d'arête selon le quartier : centre froid (cyan), faubourgs chauds (ambre),
# zone médiane inchangée. Mélange léger → reste cohérent avec la DA bleu-gris.
func _teinte_quartier(zone: int, base: Color) -> Color:
	if not teinte_quartiers:
		return base
	match zone:
		0: return base.lerp(teinte_downtown, 0.45)
		2: return base.lerp(teinte_peripherie, 0.32)
		_: return base

# Détail de toit : antenne+balise (tours) ou citerne (autres). Renvoie le nb de segments.
func _detail_toit(s: SurfaceTool, centre: Vector3, sx: float, sy: float, sz: float,
		et: int, col: Color, rng: RandomNumberGenerator) -> int:
	var top := centre + Vector3(0, sy, 0)
	var n := 0
	var r := rng.randf()
	if et >= 6 and r < 0.6:
		var h := unite_maison * rng.randf_range(1.2, 2.6)
		var tip := top + Vector3(0, h, 0)
		n += HoloMesh3D.line(s, top, tip, col)
		var cw := taille_cellule * 0.12
		n += HoloMesh3D.line(s, tip + Vector3(-cw, 0, 0), tip + Vector3(cw, 0, 0), col)
		n += HoloMesh3D.line(s, tip + Vector3(0, 0, -cw), tip + Vector3(0, 0, cw), col)
	elif r < 0.4:
		var tw := taille_cellule * 0.22
		var th := unite_maison * 0.8
		var off := Vector3((sx * 0.5 - tw * 0.6), sy, (sz * 0.5 - tw * 0.6))
		n += HoloMesh3D.box(s, centre + off, tw, th, tw, col)
	return n

# Enseigne holographique : bannière verticale (grille) plaquée sur une façade.
func _enseigne(ss: SurfaceTool, centre: Vector3, sx: float, sy: float, sz: float,
		rng: RandomNumberGenerator) -> int:
	var pal := [Color(0.30, 0.85, 1.00), Color(1.00, 0.30, 0.66), Color(1.00, 0.70, 0.25)]
	var cc: Color = pal[rng.randi() % pal.size()]
	var y0 := sy * 0.45
	var y1 := sy * 0.92
	var z0 := -sz * 0.18
	var z1 := sz * 0.18
	var bx := centre.x + sx * 0.51   # juste devant la face +X
	var n := 0
	n += HoloMesh3D.line(ss, Vector3(bx, centre.y + y0, centre.z + z0), Vector3(bx, centre.y + y1, centre.z + z0), cc)
	n += HoloMesh3D.line(ss, Vector3(bx, centre.y + y0, centre.z + z1), Vector3(bx, centre.y + y1, centre.z + z1), cc)
	for i in 4:
		var yy := lerpf(y0, y1, float(i) / 3.0)
		n += HoloMesh3D.line(ss, Vector3(bx, centre.y + yy, centre.z + z0),
				Vector3(bx, centre.y + yy, centre.z + z1), Color(cc, 0.55))
	return n

# ─── Monument central (place + flèche-repère) ─────────────────
func _cellules_monument() -> Array:
	var ci := int(floor(_cgrid()))
	return [Vector2i(ci, ci), Vector2i(ci + 1, ci), Vector2i(ci, ci + 1), Vector2i(ci + 1, ci + 1)]

func _build_monument() -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var c := Color(couleur_socle, 0.9)
	var base := taille_cellule * 0.9
	var h := unite_maison * 30.0   # flèche-repère, plus haute que les tours
	var apex := Vector3(0, h, 0)
	var corners := [
		Vector3(base, 0, 0), Vector3(0, 0, base), Vector3(-base, 0, 0), Vector3(0, 0, -base)]
	for i in 4:
		n += HoloMesh3D.line(s, corners[i], corners[(i + 1) % 4], c)
		n += HoloMesh3D.line(s, corners[i], apex, c)
	for k in 3:
		var t := float(k + 1) / 4.0
		n += HoloMesh3D.circle(s, Vector3(0, h * t, 0), base * (1.0 - t), Color(couleur_socle, 0.45), 16)
	n += HoloMesh3D.diamond(s, apex, base * 0.12, unite_maison * 0.6, c)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Monument")

# ─── Autoroute surélevée (au-dessus d'un grand axe) + trafic ──
func _avenue_centrale() -> int:
	var best := -1
	var bestd := 1.0e9
	for col in _cols_route:
		if _cols_route[col]:
			var d: float = abs(float(col) - _cgrid())
			if d < bestd:
				bestd = d
				best = col
	return best

func _build_autoroute() -> void:
	var col := _avenue_centrale()
	if col < 0:
		col = int(_cgrid())
	var xw := _world(col, 0, 0).x
	var hh := autoroute_hauteur
	var lane := taille_cellule * 0.45
	var z0 := _world(col, 0, 0).z
	var z1 := _world(col, grille - 1, 0).z
	var s := HoloMesh3D.st()
	var n := 0
	var c := Color(couleur_socle, 0.8)
	var rail := Color(couleur_socle, 0.35)
	# Deux voies + glissières.
	n += HoloMesh3D.line(s, Vector3(xw - lane, hh, z0), Vector3(xw - lane, hh, z1), c)
	n += HoloMesh3D.line(s, Vector3(xw + lane, hh, z0), Vector3(xw + lane, hh, z1), c)
	n += HoloMesh3D.line(s, Vector3(xw - lane, hh + 0.06, z0), Vector3(xw - lane, hh + 0.06, z1), rail)
	n += HoloMesh3D.line(s, Vector3(xw + lane, hh + 0.06, z0), Vector3(xw + lane, hh + 0.06, z1), rail)
	# Traverses + piliers vers le sol (dans le boulevard).
	var zc := 0
	while zc < grille:
		var z := _world(col, zc, 0).z
		n += HoloMesh3D.line(s, Vector3(xw - lane, hh, z), Vector3(xw + lane, hh, z), c)
		n += HoloMesh3D.line(s, Vector3(xw, hh, z), Vector3(xw, 0.0, z), Color(couleur_socle, 0.7))
		zc += maxi(2, taille_ilot)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Autoroute")
	# Trafic surélevé (réutilise le shader trafic).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xA07
	var carlen := taille_cellule * 0.6
	var trav := Vector3(0, 0, z1 - z0)
	_semer_voitures(st, Vector3(xw - lane, hh, z0), trav, carlen, rng, couleur_voiture_aller, voitures_par_voie * 2, 1.8)
	_semer_voitures(st, Vector3(xw + lane, hh, z1), -trav, carlen, rng, couleur_voiture_retour, voitures_par_voie * 2, 1.8)
	var mi := MeshInstance3D.new()
	mi.name = "AutorouteTrafic"
	mi.mesh = st.commit()
	mi.material_override = _mat_trafic
	_monde.add_child(mi)

# ─── Nœuds d'intersection (glints néon aux GRANDS croisements) ─
# Seules les intersections avenue × avenue portent un glint (les croisements de
# rues secondaires restaient un damier de losanges qui noyait la ville). Plus
# petits et plus discrets.
func _build_noeuds() -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var c := Color(couleur_route, 0.7)
	var rr := taille_cellule * 0.2
	for col in _cols_route:
		if not _cols_route[col]:
			continue
		for row in _rows_route:
			if not _rows_route[row]:
				continue
			n += HoloMesh3D.diamond(s, _world(col, row, 0.04), rr, taille_cellule * 0.10, c)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Noeuds", _mat_neon)

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
	if is_instance_valid(_focus_tw):
		_focus_tw.kill()
	_set_focus_amount(0.0)
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
		_focus(loc.global_position, true)
	elif _hovered == loc:
		_hovered = null
		_tooltip.cacher()
		_focus(Vector3.ZERO, false)

# Focus cinématographique : le quartier autour du lieu survolé s'intensifie
# (halo dans holo_line) pendant que le trafic ralentit et s'atténue.
func _focus(pos: Vector3, actif: bool) -> void:
	if is_instance_valid(_focus_tw):
		_focus_tw.kill()
	if actif:
		_mat_decor.set_shader_parameter("focus_pos", Vector2(pos.x, pos.z))
	_focus_tw = create_tween()
	_focus_tw.tween_method(_set_focus_amount, _foc, 1.0 if actif else 0.0, 0.3) \
			.set_ease(Tween.EASE_OUT)

func _set_focus_amount(v: float) -> void:
	_foc = v
	if _mat_decor != null:
		_mat_decor.set_shader_parameter("focus_force", v)
	if _mat_trafic != null:
		_mat_trafic.set_shader_parameter("emission", lerpf(2.2, 0.7, v))
		_mat_trafic.set_shader_parameter("vitesse", lerpf(vitesse_voitures, 0.03, v))

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
	# Zoom amorti (hors intro) : la distance glisse vers sa cible.
	if zoom_amorti and not _intro_en_cours:
		distance = lerpf(distance, _distance_cible, 1.0 - exp(-12.0 * dt))
	_appliquer_camera()
	if is_instance_valid(_radar):
		_radar.rotation.y += deg_to_rad(radar_vitesse) * dt
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
			_distance_cible = clampf(_distance_cible - 1.2, distance_min, distance_max)
			if not zoom_amorti:
				distance = _distance_cible
				_appliquer_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance_cible = clampf(_distance_cible + 1.2, distance_min, distance_max)
			if not zoom_amorti:
				distance = _distance_cible
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
