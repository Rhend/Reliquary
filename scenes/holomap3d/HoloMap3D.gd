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
const WATER_SHADER := preload("res://scenes/holomap3d/holo_water.gdshader")
const FACE_INSET := 0.96   # faces légèrement insérées → les arêtes ne sont pas avalées
const TAILLE_MONDE_CIBLE := 13.0   # largeur monde visée pour la grille Excel (cadrage caméra)
const CHEMIN_GABARIT_DEFAUT := "res://Carte Holo/carte_holomap.xlsx"   # gabarit de carte par défaut

@export var seed_val := 1337

# ─── Caméra / rotation ────────────────────────────────────────
@export_group("Caméra")
@export_range(15.0, 85.0) var plongee_deg := 55.0
@export var plongee_min := 25.0
@export var plongee_max := 80.0
@export var distance := 15.0
@export var distance_min := 5.6   # 2 crans de molette plus près qu'avant (8.0)
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

# ─── Source : gabarit Excel (sinon ville procédurale) ─────────
@export_group("Carte Excel")
# Chemin d'un classeur .xlsx (feuilles Carte / Surélevé / Paramètres). Vide → ville
# PROCÉDURALE (comportement historique, conservé). Renseigné → la carte est LUE au
# runtime (ZIPReader + XMLParser) et reproduite (décor seul, aucun lieu cliquable).
@export var chemin_xlsx := ""
# Gain vertical appliqué aux hauteurs lues (en mètres) : 1 = échelle réelle (ville
# plate), >1 = relief plus lisible en holo. N'affecte PAS l'emprise au sol.
@export var exageration_hauteur := 2.5
# Densité du trafic simulé (voitures par case de route). Plus haut = plus dense
# (au-delà de ~0.45 le réseau peut s'embouteiller aux carrefours).
@export var densite_trafic := 0.30

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
# Faubourgs/routes/lac GREFFÉS autour du carré (asymétriques, hors grille) :
# cassent la symétrie du carré sans rien chevaucher du tissu existant.
@export var exterieur_actif := true
# Sol : nappe de terre + maillage fin (petits carrés) qui lie tout l'ensemble.
@export var sol_actif := true

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
# Nb MAX d'arbres colorés posés sur un parc-lieu (les arbres glow, peu suffisent).
@export var lieu_arbres_max := 6

# ─── Lieux ────────────────────────────────────────────────────
@export_group("Lieux")
@export var lieux: Array[HoloLieuData] = []

var _excel: HoloXlsxMap   # modèle lu depuis le gabarit Excel (null = ville procédurale)
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
var _mat_lac: ShaderMaterial           # nappe d'eau pleine (lac satellite, hors carré)
var _mat_eau: ShaderMaterial           # eau qui s'écoule (carte Excel, shader animé)
var _mat_sol: ShaderMaterial           # sol : nappe de terre + maillage fin (liant)
var _mat_horizon: ShaderMaterial       # halo d'horizon / brume (sans atténuation de brume)
var _mat_balise: ShaderMaterial        # balises rouges clignotantes (sommets de tours)
var _discos: Array[Node3D] = []        # boules à facettes (sommets de pyramides) — tournent
var _balise_t := 0.0                   # phase de clignotement des balises
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
var _lieu_arbres := {}   # Vector2i → Color : cellules CHOISIES pour un arbre coloré (plafonné)

func _ready() -> void:
	get_viewport().physics_object_picking = true
	_charger_excel()
	# Mode Excel = décor seul : aucun lieu placeholder (les lieux sont hors périmètre).
	if _excel == null and lieux.is_empty():
		lieux = _lieux_placeholder()
	if gabarits.is_empty():
		gabarits = _gabarits_defaut()
	_setup_environment()
	_setup_camera()
	_setup_materials()
	if post_process_interne:
		_setup_post()
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

	# Lac satellite (hors carré) : nappe pleine, bleu franc et lisible.
	_mat_lac = ShaderMaterial.new()
	_mat_lac.shader = LINE_SHADER
	_mat_lac.set_shader_parameter("emission_strength", 1.3)
	_mat_lac.set_shader_parameter("alpha_mult", 1.0)

	# Eau qui s'écoule (carte Excel) : bandes de courant animées par le shader.
	_mat_eau = ShaderMaterial.new()
	_mat_eau.shader = WATER_SHADER
	_mat_eau.set_shader_parameter("eau_color", couleur_eau)

	# Halo d'horizon / brume d'ambiance : émission douce, brume repoussée très loin
	# (l'horizon est volontairement distant et doit rester visible).
	_mat_horizon = ShaderMaterial.new()
	_mat_horizon.shader = LINE_SHADER
	_mat_horizon.set_shader_parameter("emission_strength", 1.0)
	_mat_horizon.set_shader_parameter("alpha_mult", 1.0)
	_mat_horizon.set_shader_parameter("fog_debut", 1.0e6)
	_mat_horizon.set_shader_parameter("fog_fin", 1.0e6)

	# Balises rouges (sommets de tours) : clignotement via alpha_mult (cf. _process).
	_mat_balise = ShaderMaterial.new()
	_mat_balise.shader = LINE_SHADER
	_mat_balise.set_shader_parameter("emission_strength", 3.2)
	_mat_balise.set_shader_parameter("alpha_mult", 1.0)

	# Sol : émission faible (la luminosité réelle vient des vertex colors — nappe
	# très sombre + maillage discret) → matérialise le terrain sans écraser la ville.
	_mat_sol = ShaderMaterial.new()
	_mat_sol.shader = LINE_SHADER
	_mat_sol.set_shader_parameter("emission_strength", 0.7)
	_mat_sol.set_shader_parameter("alpha_mult", 1.0)

	# Brume de profondeur : poussée sur les matériaux de lignes/routes/trafic
	# (les faces ne fadent pas → l'occlusion reste). Les lieux/faisceaux
	# utilisent les valeurs par défaut du shader (cohérentes avec ces exports).
	for m: ShaderMaterial in [_mat_decor, _mat_ambiance, _mat_lac, _mat_eau, _mat_sol, _mat_routes, _mat_trafic, _mat_neon, _mat_lieu_decor]:
		m.set_shader_parameter("fog_debut", brume_debut)
		m.set_shader_parameter("fog_fin", brume_fin)

	# Matériaux qui réagissent au reveal d'intro (matérialisation radiale).
	_mats_reveal = [_mat_decor, _mat_ambiance, _mat_lac, _mat_eau, _mat_sol, _mat_routes, _mat_faces, _mat_trafic, _mat_neon, _mat_lieu_decor]

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

	# Carte lue depuis le gabarit Excel → rendu data-driven (décor seul).
	if _excel != null:
		_build_all_excel()
		return

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
	if sol_actif:
		_build_sol()        # nappe de terre + maillage fin : liant visuel sous tout
	_build_routes_neon()
	if noeuds_actif:
		_build_noeuds()
	if decor_actif:
		_build_decor()
	_build_ville()
	if exterieur_actif:
		_build_exterieur()   # faubourgs / routes / lac GREFFÉS autour du carré
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

# ─── Carte Excel : lecture + rendu data-driven ────────────────
# Charge le gabarit ; en cas de succès, cale la grille et l'échelle sur le fichier.
func _charger_excel() -> void:
	# `_excel` peut être pré-injecté (preview/test) → on ne recharge pas le fichier.
	if _excel == null:
		if chemin_xlsx.strip_edges() == "":
			return
		var m := HoloXlsxMap.new()
		if not m.charger(chemin_xlsx):
			push_warning("[HoloMap3D] gabarit illisible (%s) → ville procédurale" % chemin_xlsx)
			return
		_excel = m
	grille = _excel.grille
	taille_cellule = TAILLE_MONDE_CIBLE / float(maxi(1, grille))
	# Réglages spécifiques carte Excel (décor dense au sol, pas de gratte-ciels) :
	# cadrage plus serré, bâti plus clair/lisible, routes moins envahissantes,
	# brume repoussée (la carte tient dans le champ proche).
	distance = TAILLE_MONDE_CIBLE * 0.98
	plongee_deg = 50.0
	couleur_decor_bati = Color(0.46, 0.56, 0.74)
	luminosite_decor = 2.2
	route_emission_base = 0.45
	brume_debut = 22.0
	brume_fin = 46.0
	couleur_fond = Color(0.012, 0.022, 0.045)   # bleu nuit très sombre (≠ noir total) → atmosphère
	print("[HoloMap3D] ", _excel.resume())

# Rendu de la carte Excel : décor d'apparence (eau/parc/route) + bâtiments lus,
# le tout dans la DA holo existante (socle, sol, motes, radar, intro, post-process).
# AUCUN lieu cliquable (chantier : décor seul).
func _build_all_excel() -> void:
	_eau.clear()
	_parc.clear()
	_bloque.clear()
	_lieu_sol.clear()
	_lieu_arbres.clear()
	_discos.clear()
	# L'eau est gérée par le shader animé (_build_eau_excel). On NE peuple PAS _eau
	# → _build_decor n'ajoute pas de vaguelettes statiques par-dessus le courant.
	for c: Vector2i in _excel.parcs:
		_parc[c] = true
	_build_horizon_excel()      # halo d'horizon + brume au sol (atmosphère)
	if socle_actif:
		_build_socle()
	if sol_actif:
		_build_sol_disc(Vector2(_cgrid(), _cgrid()), _cgrid() * 1.28 + 2.0)
	_build_routes_excel()
	_build_trottoirs_excel()    # bordures de voirie (trottoirs)
	_build_eclairage_excel()    # lampadaires (points lumineux chauds)
	_build_eau_excel()          # eau qui s'écoule (shader animé)
	_build_bordure_eau_excel()  # liseré cyan vif → l'eau se détache de la carte
	if decor_actif:
		_build_decor()          # parcs (arbres) — _eau vide → pas de vaguelettes
	_build_terrains_excel()     # terrains de sport (baseball)
	_build_batiments_excel()
	_build_ponts_excel()          # ouvrages du calque Surélevé (au-dessus de l'eau/route)
	_build_routes_elevees_excel() # autoroutes surélevées (magenta) — vide pour l'instant
	if motes_actif:
		_build_motes()
	if radar_actif:
		_build_radar()
	_construire_lieux([])       # aucun lieu : décor seul
	if intro_actif:
		_jouer_intro()

# Routes peintes → voirie TYPÉE par largeur (départementale 1 / nationale 2 /
# autoroute 4 cases) :
#   1) surface = tuiles magenta discrètes (corps de la chaussée),
#   2) marquage = médiane (sépare les 2 sens) + lignes de voie pointillées,
#   3) trafic DIRECTIONNEL par voie (aller cyan / retour ambre) → sens lisible.
func _build_routes_excel() -> void:
	# 1) Surface.
	var st := HoloMesh3D.st_tri()
	var nt := 0
	var hw := taille_cellule * 0.5
	for cell: Vector2i in _excel.routes:
		var c := _world(cell.x, cell.y, 0.02)
		var u := float(cell.x + cell.y) * taille_cellule
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
		mi.material_override = _mat_routes
		_monde.add_child(mi)
	# 2) Marquage au sol : médiane (sépare les sens) + lignes de voie pointillées.
	var sm := HoloMesh3D.st()
	var nm := 0
	for b in _routes_bandes():
		nm += _bande_marquage(b, sm)
	_ajouter_mesh(HoloMesh3D.commit(sm, nm), "RoutesMarquage", _mat_neon)
	# 3) Trafic SIMULÉ (HoloTraffic) : les voitures suivent les voies, tournent au
	#    bon sens aux intersections et NE SE CROISENT PAS (réservation de cases).
	if trafic_actif:
		var n_cars := clampi(int(_excel.routes.size() * densite_trafic), 8, 220)
		var trafic := HoloTraffic.new()
		trafic.name = "TraficSim"
		_monde.add_child(trafic)
		trafic.configurer(_excel.routes, _routes_intersections(), _cgrid(), taille_cellule,
				0.06, _mat_neon, n_cars, seed_val ^ 0x40A05)

# Décompose les cases-route en RUNS contigus (par ligne si horizontal, sinon par
# colonne). Renvoie un Array de [ligne, début, fin] (coordonnées de grille).
func _routes_runs(horizontal: bool) -> Array:
	var par_ligne := {}
	for c: Vector2i in _excel.routes:
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

# Nb de voies PAR SENS selon la largeur (cases) : départementale 1×1 (1 voie),
# nationale 2×2 (2 voies), autoroute 3×3 (3 voies) — cf. demande auteur.
func _n_voies(largeur: int) -> int:
	if largeur <= 1:
		return 1
	if largeur <= 3:
		return 2
	return 3

# Décompose la voirie en BANDES rectangulaires (rangées/colonnes contiguës de même
# emprise) → chaque bande connaît son axe (H/V) et sa largeur. On ne garde une bande
# que si sa longueur ≥ sa largeur (sinon c'est l'autre orientation qui la décrit).
func _routes_bandes() -> Array:
	var bandes: Array = []
	for horiz in [true, false]:
		var par_emprise := {}
		for r in _routes_runs(horiz):
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
func _pt_bande(horiz: bool, av: float, wv: float, y: float) -> Vector3:
	return _world(av, wv, y) if horiz else _world(wv, av, y)

# Marquage au sol d'une bande : médiane vive (double trait) séparant les deux sens
# + lignes de voie pointillées (nb selon le type). Renvoie le nb d'arêtes.
func _bande_marquage(b: Dictionary, s: SurfaceTool) -> int:
	var horiz: bool = b["axe"] == "H"
	var a0: int = b["x0"] if horiz else b["y0"]
	var a1: int = b["x1"] if horiz else b["y1"]
	var w0: int = b["y0"] if horiz else b["x0"]
	var w1: int = b["y1"] if horiz else b["x1"]
	var as0 := float(a0) - 0.5
	var as1 := float(a1) + 0.5
	var wa := float(w0) - 0.5
	var wb := float(w1) + 0.5
	var wmid := (float(w0) + float(w1)) * 0.5
	var nl := _n_voies(w1 - w0 + 1)
	var y := 0.045
	var n := 0
	var col_med := Color(1.0, 0.45, 0.78)    # médiane vive
	var col_voie := Color(0.85, 0.28, 0.58)  # lignes de voie (plus discrètes)
	n += HoloMesh3D.line(s, _pt_bande(horiz, as0, wmid - 0.05, y), _pt_bande(horiz, as1, wmid - 0.05, y), col_med)
	n += HoloMesh3D.line(s, _pt_bande(horiz, as0, wmid + 0.05, y), _pt_bande(horiz, as1, wmid + 0.05, y), col_med)
	for ch: Array in [[wa, wmid], [wmid, wb]]:
		for k in range(1, nl):
			var wv := lerpf(ch[0], ch[1], float(k) / float(nl))
			n += _dashes(s, _pt_bande(horiz, as0, wv, y), _pt_bande(horiz, as1, wv, y), col_voie,
					taille_cellule * 0.4, taille_cellule * 0.3)
	return n

# Cases d'INTERSECTION = couvertes par une bande horizontale ET une bande verticale
# (deux routes se croisent / un virage). Servent de « verrou plein » au trafic
# simulé : une seule voiture à la fois → pas de croisement.
func _routes_intersections() -> Dictionary:
	var in_h := {}
	var in_v := {}
	for b in _routes_bandes():
		var horiz: bool = b["axe"] == "H"
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

# Ligne pointillée a→b (segments `dash`, trous `gap`). Renvoie le nb de segments.
func _dashes(s: SurfaceTool, a: Vector3, b: Vector3, col: Color, dash: float, gap: float) -> int:
	var L := a.distance_to(b)
	if L < 0.001:
		return 0
	var dir := (b - a) / L
	var n := 0
	var d := 0.0
	while d < L:
		n += HoloMesh3D.line(s, a + dir * d, a + dir * minf(d + dash, L), col)
		d += dash + gap
	return n

# Trottoirs : trait clair (béton) le long de CHAQUE bord de voirie (côté d'une case
# route dont le voisin n'est pas une route) → bordure de chaussée continue.
func _build_trottoirs_excel() -> void:
	var routes := {}
	for c: Vector2i in _excel.routes:
		routes[c] = true
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(0.55, 0.60, 0.66)   # béton clair, discret
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in _excel.routes:
		for d: Vector2i in dirs:
			if routes.has(cell + d):
				continue
			var seg := _cote_cellule(cell, d)
			n += HoloMesh3D.line(s, _world(seg[0].x, seg[0].y, 0.025),
					_world(seg[1].x, seg[1].y, 0.025), col)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "TrottoirsExcel", _mat_ambiance)

# Éclairage public : petits lampadaires (mât sombre + tête chaude qui glow) posés
# le long des axes de voirie, à intervalle régulier, décalés sur le trottoir.
func _build_eclairage_excel() -> void:
	var mats := HoloMesh3D.st()       # mâts (sombres)
	var nm := 0
	var tetes := HoloMesh3D.st()      # têtes lumineuses (glow chaud)
	var nt := 0
	var col_mat := Color(0.35, 0.38, 0.42)
	var col_tete := Color(1.0, 0.82, 0.50)
	var ht := unite_maison * 1.4      # hauteur du mât
	var pas := 4                       # un lampadaire toutes les 4 cases
	# Sur les DEUX bords extérieurs de chaque bande (quelle que soit la largeur).
	for b in _routes_bandes():
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
				var base := _pt_bande(horiz, float(k), wv, 0.0)
				var tete := base + Vector3(0, ht, 0)
				nm += HoloMesh3D.line(mats, base, tete, col_mat)
				nt += HoloMesh3D.diamond(tetes, tete, taille_cellule * 0.08, unite_maison * 0.18, col_tete)
			k += pas
	_ajouter_mesh(HoloMesh3D.commit(mats, nm), "LampadairesMats", _mat_ambiance)
	_ajouter_mesh(HoloMesh3D.commit(tetes, nt), "LampadairesTetes", _mat_neon)

# Boule à facettes (sommet de pyramide) : 3 grands cercles orthogonaux + rayons
# lumineux distribués sur 360° (sphère de Fibonacci). Tourne (cf. _process).
func _build_disco(apex: Vector3, rayon_boule: float, longueur_rayons: float) -> void:
	var node := Node3D.new()
	node.name = "DiscoPyramide"
	node.position = apex
	var s := HoloMesh3D.st()
	var n := 0
	var blanc := Color(0.90, 0.96, 1.0)
	n += HoloMesh3D.circle(s, Vector3.ZERO, rayon_boule, blanc, 18)   # plan XZ
	n += _cercle_plan(s, rayon_boule, blanc, 18, true)               # plan XY
	n += _cercle_plan(s, rayon_boule, blanc, 18, false)              # plan YZ
	var pal := [Color(0.40, 0.90, 1.0), Color(1.0, 0.40, 0.80),
			Color(1.0, 0.85, 0.50), Color(0.70, 1.0, 0.75)]
	var nb := 44
	for i in nb:
		var dir := _point_sphere(i, nb)
		var c: Color = pal[i % pal.size()]
		n += HoloMesh3D.line(s, dir * rayon_boule, dir * longueur_rayons, c)
	var mi := MeshInstance3D.new()
	mi.name = "DiscoMesh"
	mi.mesh = HoloMesh3D.commit(s, n)
	mi.material_override = _mat_neon
	node.add_child(mi)
	_monde.add_child(node)
	_discos.append(node)

# Cercle vertical (plan XY si `xy`, sinon YZ), centré à l'origine.
func _cercle_plan(s: SurfaceTool, r: float, col: Color, seg: int, xy: bool) -> int:
	var prev := Vector3(r, 0, 0) if xy else Vector3(0, r, 0)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := Vector3(cos(a) * r, sin(a) * r, 0) if xy else Vector3(0, cos(a) * r, sin(a) * r)
		n += HoloMesh3D.line(s, prev, cur, col)
		prev = cur
	return n

# i-ème direction d'une distribution sphérique régulière (spirale de Fibonacci).
func _point_sphere(i: int, n: int) -> Vector3:
	var phi := PI * (3.0 - sqrt(5.0))
	var y := 1.0 - (float(i) / float(maxi(1, n - 1))) * 2.0
	var rad := sqrt(maxf(0.0, 1.0 - y * y))
	var th := phi * float(i)
	return Vector3(cos(th) * rad, y, sin(th) * rad)

# Eau peinte → nappe pleine qui S'ÉCOULE (shader holo_water, motif animé en
# coordonnées monde → courant continu d'une case à l'autre).
func _build_eau_excel() -> void:
	var s := HoloMesh3D.st_tri()
	var n := 0
	var y := 0.008
	var hw := taille_cellule * 0.5
	for cell: Vector2i in _excel.eaux:
		var c := _world(cell.x, cell.y, y)
		var p0 := c + Vector3(-hw, 0, -hw)
		var p1 := c + Vector3(hw, 0, -hw)
		var p2 := c + Vector3(hw, 0, hw)
		var p3 := c + Vector3(-hw, 0, hw)
		for v in [p0, p1, p2, p0, p2, p3]:
			s.set_color(Color.WHITE); s.add_vertex(v)
		n += 2
	_ajouter_mesh(HoloMesh3D.commit(s, n), "EauExcel", _mat_eau)

# Bordure d'eau : fin liseré cyan vif (glow) le long de chaque bord de plan d'eau
# (côté d'une case eau dont le voisin n'est pas de l'eau) → la nappe se détache.
func _build_bordure_eau_excel() -> void:
	var eaux := {}
	for c: Vector2i in _excel.eaux:
		eaux[c] = true
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(0.45, 0.95, 1.0)   # cyan vif (au-dessus du seuil de glow)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in _excel.eaux:
		for d: Vector2i in dirs:
			if eaux.has(cell + d):
				continue
			var seg := _cote_cellule(cell, d)
			n += HoloMesh3D.line(s, _world(seg[0].x, seg[0].y, 0.014),
					_world(seg[1].x, seg[1].y, 0.014), col)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "BordureEauExcel", _mat_neon)

# Bâtiments lus : volumes creux (arêtes _mat_decor + faces sombres _mat_faces).
# Boîte = silhouette extrudée de l'emprise exacte ; autres formes = paramétriques
# sur la bbox du bloc. Les tours orphelines (code posé sur l'eau, ex. « 9c ») sont
# rendues comme volume compact à leur case.
func _build_batiments_excel() -> void:
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var sb := HoloMesh3D.st()    # balises rouges (clignotantes)
	var sban := HoloMesh3D.st()  # enseignes holographiques
	var n := 0
	var nf := 0
	var nb := 0
	var nban := 0
	var col := Color(couleur_decor_bati, 0.85)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x70175
	for b in _excel.batiments:
		var h := _hauteur_monde(b["hauteur_m"])
		var forme: int = b["forme"]
		if forme == HoloXlsxMap.Forme.BOITE:
			var r := _bati_boite(b["cells"], h, col, s, sf)
			n += r[0]; nf += r[1]
			# Détails de toit (#3) : antenne/citerne + balise + enseigne.
			var rd := _toit_details_excel(b["bbox"], h, col, s, sb, sban, rng)
			n += rd[0]; nb += rd[1]; nban += rd[2]
		else:
			var bb: Rect2i = b["bbox"]
			var sx := float(bb.size.x) * taille_cellule * FACE_INSET
			var sz := float(bb.size.y) * taille_cellule * FACE_INSET
			var centre := _centre_bbox(bb)
			var r := _bati_forme(centre, sx, sz, h, forme, col, s, sf)
			n += r[0]; nf += r[1]
			# Boule à facettes au sommet de la pyramide (rayons lumineux 360°).
			if forme == HoloXlsxMap.Forme.PYRAMIDE:
				_build_disco(centre + Vector3(0, h, 0), taille_cellule * 0.85, taille_cellule * 3.2)
	for t in _excel.tours_orphelines:
		var h := _hauteur_monde(t["hauteur_m"])
		var rect: Rect2i = t["rect"]
		# Centrée et dimensionnée sur le plan d'eau (≈ 70 % de sa plus petite dimension).
		var taille := float(mini(rect.size.x, rect.size.y)) * taille_cellule * 0.7
		var r := _bati_forme(_centre_bbox(rect), taille, taille, h, t["forme"], col, s, sf)
		n += r[0]; nf += r[1]
	_ajouter_mesh(HoloMesh3D.commit(s, n), "BatimentsExcel")
	_ajouter_mesh(HoloMesh3D.commit(sb, nb), "Balises", _mat_balise)
	_ajouter_mesh(HoloMesh3D.commit(sban, nban), "Enseignes", _mat_neon)
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "BatimentsExcelFaces"
		mif.mesh = fmesh
		mif.material_override = _mat_faces
		_monde.add_child(mif)

# Détails de toit (#3) sur un bâtiment BOÎTE : antenne ou citerne (la plupart),
# balise rouge clignotante au sommet des HAUTES tours, et enseigne holographique
# sur quelques façades. Renvoie [nb arêtes, nb balises, nb enseignes].
func _toit_details_excel(bbox: Rect2i, h: float, col: Color, s: SurfaceTool,
		sb: SurfaceTool, sban: SurfaceTool, rng: RandomNumberGenerator) -> Array:
	var sx := float(bbox.size.x) * taille_cellule * 0.86
	var sz := float(bbox.size.y) * taille_cellule * 0.86
	var toit := _centre_bbox(bbox) + Vector3(0, h, 0)
	var n := 0
	var nb := 0
	var nban := 0
	var grand := bbox.size.x * bbox.size.y >= 9
	var haut := h >= _hauteur_monde(7.0)
	var roll := rng.randf()
	# Antenne (tours hautes/grandes) ou citerne (autres) — la plupart en ont une.
	if haut or grand or roll < 0.55:
		if haut or roll < 0.3:
			var tip := toit + Vector3(0, maxf(unite_maison * 1.4, h * 0.4), 0)
			n += HoloMesh3D.line(s, toit, tip, col)
			var cw := taille_cellule * 0.1
			n += HoloMesh3D.line(s, tip + Vector3(-cw, 0, 0), tip + Vector3(cw, 0, 0), col)
			n += HoloMesh3D.line(s, tip + Vector3(0, 0, -cw), tip + Vector3(0, 0, cw), col)
			# Balise rouge clignotante à la pointe (tours hautes / grandes).
			if haut or grand:
				nb += HoloMesh3D.diamond(sb, tip + Vector3(0, taille_cellule * 0.06, 0),
						taille_cellule * 0.05, taille_cellule * 0.08, Color(1.0, 0.15, 0.12))
		else:
			var tw := taille_cellule * 0.2
			var off := Vector3(sx * 0.5 - tw * 0.6, 0, sz * 0.5 - tw * 0.6)
			n += HoloMesh3D.box(s, toit + off, tw, unite_maison * 0.7, tw, col)
	# Enseigne holographique : bannière verticale sur une façade (grandes tours).
	if (haut or grand) and rng.randf() < 0.5:
		var pal := [Color(0.30, 0.85, 1.0), Color(1.0, 0.30, 0.66), Color(1.0, 0.70, 0.25)]
		var cc: Color = pal[rng.randi() % pal.size()]
		var bx := toit.x + sx * 0.5
		var y0 := toit.y - h * 0.5
		var y1 := toit.y - h * 0.08
		var z0 := toit.z - sz * 0.22
		var z1 := toit.z + sz * 0.22
		nban += HoloMesh3D.line(sban, Vector3(bx, y0, z0), Vector3(bx, y1, z0), cc)
		nban += HoloMesh3D.line(sban, Vector3(bx, y0, z1), Vector3(bx, y1, z1), cc)
		for i in 4:
			var yy := lerpf(y0, y1, float(i) / 3.0)
			nban += HoloMesh3D.line(sban, Vector3(bx, yy, z0), Vector3(bx, yy, z1), Color(cc, 0.55))
	return [n, nb, nban]

# ─── Ponts (calque Surélevé) : tablier en RAMPE + structure + garde-corps + trafic ──
# Le tablier part du sol à un bout, monte (/), traverse en hauteur, redescend (\)
# au sol à l'autre bout → il « colle à la route ». Des voitures circulent dessus
# (montée, traversée, descente). L'eau/route restent visibles dessous.
func _build_ponts_excel() -> void:
	if _excel.ponts.is_empty():
		return
	var s := HoloMesh3D.st()
	var sf := HoloMesh3D.st_tri()
	var st := SurfaceTool.new()       # trafic des ponts (réutilise holo_traffic)
	st.begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x9011D5
	var n := 0
	var nf := 0
	var ncar := 0
	var col := Color(0.64, 0.74, 0.86)   # acier clair (glow via _mat_decor)
	for p in _excel.ponts:
		var r := _bati_pont(p, col, s, sf, st, rng)
		n += r[0]; nf += r[1]; ncar += r[2]
	_ajouter_mesh(HoloMesh3D.commit(s, n), "PontsExcel")
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "PontsExcelFaces"
		mif.mesh = fmesh
		mif.material_override = _mat_faces
		_monde.add_child(mif)
	if ncar > 0:
		var mit := MeshInstance3D.new()
		mit.name = "PontsTrafic"
		mit.mesh = st.commit()
		mit.material_override = _mat_trafic
		_monde.add_child(mit)

# Profil du tablier le long de la travée (t∈[0,1]) : rampe / sur les `rf` premiers,
# plateau au milieu, rampe \ sur les `rf` derniers. `alt` = hauteur du plateau.
func _profil_pont(t: float, alt: float, rf: float) -> float:
	if t < rf:
		return alt * (t / rf)
	if t > 1.0 - rf:
		return alt * ((1.0 - t) / rf)
	return alt

# Un pont en rampe : tablier (surface + bords + traverses) suivant le profil,
# garde-corps (main courante + montants) au-dessus, treillis (corde basse +
# montants + diagonales) sous la partie élevée, piliers optionnels, et trafic.
# Renvoie [nb arêtes, nb faces, nb voitures].
func _bati_pont(pont: Dictionary, col: Color, s: SurfaceTool, sf: SurfaceTool,
		st: SurfaceTool, rng: RandomNumberGenerator) -> Array:
	var bbox: Rect2i = pont["bbox"]
	var alt := _hauteur_monde(pont["altitude_m"])   # hauteur du plateau
	var ep := taille_cellule * 0.14
	var rail_h := taille_cellule * 0.40
	var rf := 0.40
	var span_x := bbox.size.x >= bbox.size.y
	var long_cells: int = bbox.size.x if span_x else bbox.size.y
	var larg_cells: int = bbox.size.y if span_x else bbox.size.x
	var along := Vector3(1, 0, 0) if span_x else Vector3(0, 0, 1)
	var side := Vector3(0, 0, 1) if span_x else Vector3(1, 0, 0)
	var centre_sol := _world(bbox.position.x + (bbox.size.x - 1) * 0.5,
			bbox.position.y + (bbox.size.y - 1) * 0.5, 0.0)
	var demi_long := float(long_cells) * taille_cellule * 0.5
	var demi_large := float(larg_cells) * taille_cellule * 0.47
	var end_a := centre_sol - along * demi_long
	var end_b := centre_sol + along * demi_long
	var nb := maxi(6, long_cells * 3)
	var n := 0
	var nf := 0
	var centers: Array[Vector3] = []
	for i in nb + 1:
		var t := float(i) / float(nb)
		centers.append(end_a.lerp(end_b, t) + Vector3(0, _profil_pont(t, alt, rf), 0))
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
			var bot := Vector3(edge.x, maxf(0.02, c.y - taille_cellule * 0.5), edge.z)
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
				n += HoloMesh3D.line(s, Vector3(c.x, maxf(0.02, c.y - taille_cellule * 0.5), c.z),
						Vector3(c.x, 0.0, c.z), col)
	# Trafic : voitures qui montent la rampe, traversent, redescendent.
	var ncar := 0
	if trafic_actif:
		ncar = _semer_pont_trafic(st, centers, ep, rng)
	return [n, nf, ncar]

# Sème des voitures sur le pont, sur 3 tronçons (montée / plateau / descente) dans
# les deux sens → la circulation suit la rampe. Renvoie le nb de voitures.
func _semer_pont_trafic(st: SurfaceTool, centers: Array, ep: float, rng: RandomNumberGenerator) -> int:
	var nb: int = centers.size() - 1
	var iu := clampi(roundi(0.4 * float(nb)), 1, nb / 2)
	var dy := Vector3(0, ep + taille_cellule * 0.03, 0)   # roule SUR le tablier
	var troncons := [
		[centers[0], centers[iu]], [centers[iu], centers[nb - iu]], [centers[nb - iu], centers[nb]]]
	var carlen := taille_cellule * 0.5
	var ncar := 0
	for tr: Array in troncons:
		var a: Vector3 = tr[0] + dy
		var b: Vector3 = tr[1] + dy
		if a.distance_to(b) < 0.05:
			continue
		_semer_voitures(st, a, b - a, carlen, rng, couleur_voiture_aller, 1, 1.0)
		_semer_voitures(st, b, a - b, carlen, rng, couleur_voiture_retour, 1, 1.0)
		ncar += 2
	return ncar

# Routes magenta surélevées (autoroutes) : tuiles néon à leur altitude. Vide pour
# l'instant (le calque ne porte que des ponts) ; code prêt si l'auteur en peint.
func _build_routes_elevees_excel() -> void:
	if _excel.routes_elevees.is_empty():
		return
	var s := HoloMesh3D.st_tri()
	var n := 0
	var y := _hauteur_monde(8.0)   # altitude par défaut d'une autoroute surélevée
	var hw := taille_cellule * 0.5
	for cell: Vector2i in _excel.routes_elevees:
		var c := _world(cell.x, cell.y, y)
		var u := float(cell.x + cell.y) * taille_cellule
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
	mi.material_override = _mat_routes
	_monde.add_child(mi)

# ─── Terrain de baseball (apparence sable/tan) ────────────────
# Vu de dessus, DA holo : gazon (éventail) + arc du champ extérieur + lignes de
# faute + losange intérieur (bases) + monticule. Le marbre est posé à un coin du
# bloc, le champ s'ouvre vers l'opposé.
func _build_terrains_excel() -> void:
	if _excel.terrains.is_empty():
		return
	var sg := HoloMesh3D.st_tri()   # gazon
	var ng := 0
	var s := HoloMesh3D.st()        # structure (terre / lignes / gradins)
	var n := 0
	var sn := HoloMesh3D.st()       # éléments lumineux (projecteurs, écran)
	var nn := 0
	for t in _excel.terrains:
		var r := _stade_baseball(t["bbox"], sg, s, sn)
		ng += r[0]; n += r[1]; nn += r[2]
	_ajouter_mesh(HoloMesh3D.commit(sg, ng), "StadeGazon", _mat_ambiance)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "StadeStructure", _mat_decor)
	_ajouter_mesh(HoloMesh3D.commit(sn, nn), "StadeLumieres", _mat_neon)

# Point sur une ellipse ajustée à la bbox (k = fraction du demi-axe), à hauteur y.
func _pt_ell(c: Vector3, ax: float, az: float, k: float, a: float, y: float) -> Vector3:
	return c + Vector3(cos(a) * ax * k, y, sin(a) * az * k)

# Anneau elliptique (échelle k, hauteur y). Renvoie le nb d'arêtes.
func _anneau_ell(s: SurfaceTool, c: Vector3, ax: float, az: float, k: float, y: float, col: Color, seg: int) -> int:
	var prev := _pt_ell(c, ax, az, k, 0.0, y)
	var n := 0
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := _pt_ell(c, ax, az, k, a, y)
		n += HoloMesh3D.line(s, prev, cur, col)
		prev = cur
	return n

# Stade de baseball complet, ajusté à la bbox (ellipses → tout ratio remplit) :
# terrain (gazon + losange + clôture) + GRADINS en bol + PROJECTEURS + TABLEAU.
func _stade_baseball(bbox: Rect2i, sg: SurfaceTool, s: SurfaceTool, sn: SurfaceTool) -> Array:
	var cx := bbox.position.x + (bbox.size.x - 1) * 0.5
	var cy := bbox.position.y + (bbox.size.y - 1) * 0.5
	var ax := float(bbox.size.x) * taille_cellule * 0.5
	var az := float(bbox.size.y) * taille_cellule * 0.5
	var c := _world(cx, cy, 0.0)
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
	var rfp := _pt_ell(c, ax, az, kf, a_rf, 0.02)
	var lfp := _pt_ell(c, ax, az, kf, a_lf, 0.02)
	var seg := 30
	# Gazon (territoire bon) : éventail du marbre vers l'arc de clôture.
	var prevg := rfp
	for i in range(1, seg + 1):
		var a := lerpf(a_rf, a_lf, float(i) / float(seg))
		var cur := _pt_ell(c, ax, az, kf, a, 0.02)
		sg.set_color(vert_a); sg.add_vertex(home)
		sg.set_color(vert_a); sg.add_vertex(prevg)
		sg.set_color(vert_a); sg.add_vertex(cur)
		ng += 1
		prevg = cur
	# Clôture + warning track.
	var prev := rfp
	var prev2 := _pt_ell(c, ax, az, kf * 0.93, a_rf, 0.02)
	for i in range(1, seg + 1):
		var a := lerpf(a_rf, a_lf, float(i) / float(seg))
		var cur := _pt_ell(c, ax, az, kf, a, 0.02)
		var cur2 := _pt_ell(c, ax, az, kf * 0.93, a, 0.02)
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
		n += _carre_plat(s, base, taille_cellule * 0.06, blanc)
	n += HoloMesh3D.circle(s, home + (d1 + d3) * (b * 0.5), b * 0.13, terre, 12)
	# ── Gradins en BOL : anneaux montants de la clôture (kf) au bord (1.0) ──
	var nb_t := 4
	var hb := minf(ax, az) * 0.55
	for t in nb_t:
		var k := lerpf(kf * 1.04, 1.0, float(t) / float(nb_t - 1))
		var yy := lerpf(0.02, hb, float(t) / float(nb_t - 1))
		n += _anneau_ell(s, c, ax, az, k, yy, acier, 56)
	var nb_m := 28
	for m in nb_m:
		var a := TAU * float(m) / float(nb_m)
		var pv := _pt_ell(c, ax, az, kf * 1.04, a, 0.02)
		for t in range(1, nb_t):
			var k := lerpf(kf * 1.04, 1.0, float(t) / float(nb_t - 1))
			var yy := lerpf(0.02, hb, float(t) / float(nb_t - 1))
			var cur := _pt_ell(c, ax, az, k, a, yy)
			n += HoloMesh3D.line(s, pv, cur, Color(acier, 0.55))
			pv = cur
	# ── Projecteurs : mâts au sommet du bol + banc lumineux (glow) ──
	for la: float in [-0.5, -1.05, -1.6, -2.1, -2.65, 0.05]:
		var basep := _pt_ell(c, ax, az, 1.0, la, hb)
		var topp := basep + Vector3(0, hb * 0.55, 0)
		n += HoloMesh3D.line(s, basep, topp, acier)
		var bw := minf(ax, az) * 0.06
		nn += _carre_plat(sn, topp + Vector3(0, bw, 0), bw, Color(1.0, 0.98, 0.85))
	# ── Tableau d'affichage au centre du champ (au-delà de la clôture, −Z) ──
	var sb := _pt_ell(c, ax, az, kf * 1.12, -PI * 0.5, hb * 0.45)
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

# ─── Halo d'horizon + brume au sol (#6) ───────────────────────
# Une « jupe » cylindrique à dégradé vertical autour de la ville (bleu-cyan en bas,
# transparent en haut) + une nappe de brume au sol qui s'éclaire vers l'horizon →
# la ville se décolle du noir et gagne en profondeur.
func _build_horizon_excel() -> void:
	var rv := (_cgrid() + 1.0) * taille_cellule
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
	_ajouter_mesh(HoloMesh3D.commit(sc, nc), "Horizon", _mat_horizon)
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
	_ajouter_mesh(HoloMesh3D.commit(sd, nd), "BrumeSol", _mat_horizon)

# Petit carré plat (plan XZ) centré en `c`, demi-côté `r`.
func _carre_plat(s: SurfaceTool, c: Vector3, r: float, col: Color) -> int:
	var a := c + Vector3(-r, 0, -r)
	var b := c + Vector3(r, 0, -r)
	var d := c + Vector3(r, 0, r)
	var e := c + Vector3(-r, 0, r)
	return HoloMesh3D.line(s, a, b, col) + HoloMesh3D.line(s, b, d, col) \
			+ HoloMesh3D.line(s, d, e, col) + HoloMesh3D.line(s, e, a, col)

# Hauteur en mètres → hauteur monde (1 hauteur-défaut = 1 unité-maison × exagération).
func _hauteur_monde(h_m: float) -> float:
	var par_metre := unite_maison / maxf(0.5, _excel.hauteur_defaut_m)
	return h_m * par_metre * exageration_hauteur

func _centre_bbox(bb: Rect2i) -> Vector3:
	return _world(bb.position.x + (bb.size.x - 1) * 0.5, bb.position.y + (bb.size.y - 1) * 0.5, 0.0)

# Bloc-bâtiment BOÎTE : silhouette extrudée de l'emprise exacte (arbitraire).
# Arêtes = contour bas + contour haut (côtés frontière) + verticales aux SEULS coins
# de silhouette. Faces = parois (poussées vers l'intérieur) + toit par case (sous le
# niveau des arêtes) → occlusion sans avaler les arêtes. Renvoie [nb arêtes, nb faces].
func _bati_boite(cells: Array, h: float, col: Color, s: SurfaceTool, sf: SurfaceTool) -> Array:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var nf := 0
	var eps := taille_cellule * 0.06
	var hwf := taille_cellule * 0.5
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
	for c: Vector2i in cells:
		minx = mini(minx, c.x); miny = mini(miny, c.y)
		maxx = maxi(maxx, c.x); maxy = maxi(maxy, c.y)
		# Frontières : côtés dont le voisin n'est pas dans le bloc.
		for d: Vector2i in dirs:
			if setd.has(c + d):
				continue
			var seg := _cote_cellule(c, d)
			var a0 := _world(seg[0].x, seg[0].y, 0.0)
			var b0 := _world(seg[1].x, seg[1].y, 0.0)
			var a1 := a0 + Vector3(0, h, 0)
			var b1 := b0 + Vector3(0, h, 0)
			n += HoloMesh3D.line(s, a0, b0, col)   # bas
			n += HoloMesh3D.line(s, a1, b1, col)   # haut
			var inward := Vector3(-float(d.x), 0, -float(d.y)) * eps
			nf += HoloMesh3D._quad(sf, a0 + inward, b0 + inward, b1 + inward, a1 + inward,
					Vector3(float(d.x), 0, float(d.y)))
		# Toit de la case (légèrement sous le sommet → les arêtes hautes ressortent).
		var rc := _world(c.x, c.y, h - eps)
		var r0 := rc + Vector3(-hwf, 0, -hwf)
		var r1 := rc + Vector3(hwf, 0, -hwf)
		var r2 := rc + Vector3(hwf, 0, hwf)
		var r3 := rc + Vector3(-hwf, 0, hwf)
		nf += HoloMesh3D._quad(sf, r0, r1, r2, r3, Vector3(0, 1, 0))
	# Verticales aux coins de silhouette uniquement (boîte = 4 coins, L = 6, etc.).
	for vi in range(minx, maxx + 2):
		for vj in range(miny, maxy + 2):
			if _est_coin(setd, vi, vj):
				var pv := _world(float(vi) - 0.5, float(vj) - 0.5, 0.0)
				n += HoloMesh3D.line(s, pv, pv + Vector3(0, h, 0), col)
	return [n, nf]

# Côté `d` de la case `c` → [coin a, coin b] en coordonnées de grille (demi-entiers).
func _cote_cellule(c: Vector2i, d: Vector2i) -> Array:
	var x := float(c.x)
	var y := float(c.y)
	match d:
		Vector2i(1, 0):  return [Vector2(x + 0.5, y - 0.5), Vector2(x + 0.5, y + 0.5)]
		Vector2i(-1, 0): return [Vector2(x - 0.5, y + 0.5), Vector2(x - 0.5, y - 0.5)]
		Vector2i(0, 1):  return [Vector2(x + 0.5, y + 0.5), Vector2(x - 0.5, y + 0.5)]
		_:               return [Vector2(x - 0.5, y - 0.5), Vector2(x + 0.5, y - 0.5)]

# Le sommet de grille (vi,vj) est-il un coin de silhouette du bloc ? (cases autour :
# 1 ou 3 dans le bloc = coin franc ; 2 en diagonale = coin de pincement.)
func _est_coin(setd: Dictionary, vi: int, vj: int) -> bool:
	var a := setd.has(Vector2i(vi - 1, vj - 1))
	var b := setd.has(Vector2i(vi, vj - 1))
	var c := setd.has(Vector2i(vi - 1, vj))
	var d := setd.has(Vector2i(vi, vj))
	var k := int(a) + int(b) + int(c) + int(d)
	if k == 1 or k == 3:
		return true
	if k == 2:
		return (a and d) or (b and c)
	return false

# Volume paramétrique (Pyramide / Cylindre / Dôme / Gradins) centré sur `centre`,
# emprise sx×sz, hauteur h. Renvoie [nb arêtes, nb faces].
func _bati_forme(centre: Vector3, sx: float, sz: float, h: float, forme: int, col: Color,
		s: SurfaceTool, sf: SurfaceTool) -> Array:
	var n := 0
	var nf := 0
	match forme:
		HoloXlsxMap.Forme.PYRAMIDE:
			n += HoloMesh3D.pyramid(s, centre, sx, sz, h, col)
			nf += HoloMesh3D.pyramid_faces(sf, centre, sx * FACE_INSET, sz * FACE_INSET, h * FACE_INSET)
		HoloXlsxMap.Forme.CYLINDRE:
			n += HoloMesh3D.cylinder(s, centre, sx * 0.5, sz * 0.5, h, col)
			nf += HoloMesh3D.cylinder_faces(sf, centre, sx * 0.5 * FACE_INSET, sz * 0.5 * FACE_INSET, h * FACE_INSET)
		HoloXlsxMap.Forme.DOME:
			n += HoloMesh3D.dome(s, centre, sx * 0.5, sz * 0.5, h, col)
		HoloXlsxMap.Forme.GRADINS:
			var paliers := clampi(roundi(h / maxf(0.05, unite_maison * 0.8)), 2, 5)
			for k in paliers:
				var t0 := h * float(k) / float(paliers)
				var t1 := h * float(k + 1) / float(paliers)
				var shrink := lerpf(1.0, 0.34, float(k) / float(paliers))
				var bx := sx * shrink
				var bz := sz * shrink
				var base := Vector3(centre.x, centre.y + t0, centre.z)
				n += HoloMesh3D.box(s, base, bx, t1 - t0, bz, col)
				nf += HoloMesh3D.box_faces(sf, base, bx * FACE_INSET, (t1 - t0), bz * FACE_INSET)
		_:
			n += HoloMesh3D.box(s, centre, sx, h, sz, col)
			nf += HoloMesh3D.box_faces(sf, centre, sx * FACE_INSET, h * FACE_INSET, sz * FACE_INSET)
	return [n, nf]

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

# ─── Sol : nappe de terre + maillage fin (liant visuel sous tout) ──
# Un grand disque sombre (la « matière » du terrain) + un quadrillage fin de
# tout petits carrés posés dessus, le tout clippé au disque (pas de bord carré).
# Couvre la ville, le lac, les collines et les faubourgs proches → tout est
# rattaché à un même sol. Centre décalé vers le lac pour englober l'ensemble.
func _build_sol() -> void:
	_build_sol_disc(Vector2(6.0, 22.0), 34.0)   # centre entre ville et lac (procédural)

# Disque-terrain + maillage fin, centré sur `sc` (cellules), rayon `R` (cellules).
func _build_sol_disc(sc: Vector2, R: float) -> void:
	# 1) Nappe de terre pleine (disque sombre) — additif → léger relief de fond.
	var sp := HoloMesh3D.st_tri()
	var npq := 0
	var c_terre := Color(0.05, 0.07, 0.10, 1.0)
	var cw := _world(sc.x, sc.y, -0.004)
	var seg := 96
	var prev := _world(sc.x + R, sc.y, -0.004)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := _world(sc.x + cos(a) * R, sc.y + sin(a) * R, -0.004)
		sp.set_color(c_terre); sp.add_vertex(cw)
		sp.set_color(c_terre); sp.add_vertex(prev)
		sp.set_color(c_terre); sp.add_vertex(cur)
		npq += 1
		prev = cur
	_ajouter_mesh(HoloMesh3D.commit(sp, npq), "SolTerre", _mat_sol)
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
			ng += HoloMesh3D.line(sg, _world(sc.x + k, sc.y - half, yg), _world(sc.x + k, sc.y + half, yg), c_grille)
			ng += HoloMesh3D.line(sg, _world(sc.x - half, sc.y + k, yg), _world(sc.x + half, sc.y + k, yg), c_grille)
		k += pas
	_ajouter_mesh(HoloMesh3D.commit(sg, ng), "SolGrille", _mat_sol)

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
# (Ex. Marécage Putride posé sur le parc : quelques arbres prennent sa couleur.)
# `_lieu_sol` = toute l'emprise (sol du lieu, laissé vide d'arbres) ; `_lieu_arbres`
# = un petit nombre de cellules CHOISIES (plafond `lieu_arbres_max`) qui porteront
# un arbre coloré — les arbres glow, 5-6 suffisent à marquer la parcelle.
func _calc_lieu_sol() -> void:
	_lieu_sol.clear()
	_lieu_arbres.clear()
	for l in lieux:
		if not l.decouvert or not l.sans_batiment:
			continue
		var c := UIColors.tier_color(l.tier)
		var libres: Array = []
		for di in l.emprise.x:
			for dj in l.emprise.y:
				var cell := Vector2i(l.cellule.x + di, l.cellule.y + dj)
				_lieu_sol[cell] = c
				if _parc.has(cell):
					libres.append(cell)
		# Tirage déterministe (graine = id du lieu) de quelques cellules à arbre.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(l.id)
		for k in range(libres.size() - 1, 0, -1):
			var r := rng.randi_range(0, k)
			var tmp: Variant = libres[k]; libres[k] = libres[r]; libres[r] = tmp
		for i in mini(lieu_arbres_max, libres.size()):
			_lieu_arbres[libres[i]] = c

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
	# se lit comme tel. Même densité/taille que le parc normal — seule la couleur
	# (et le glow) change.
	var sl := HoloMesh3D.st()
	var nl := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x515A11
	for k in _parc:
		var cell := k as Vector2i
		var c := _world(cell.x, cell.y, 0.0)
		var ht := unite_maison * 1.2
		if _lieu_arbres.has(cell):
			# Cellule choisie d'un parc-lieu : arbre coloré (glow).
			var lc := Color(_lieu_arbres[cell] as Color, 0.9)
			nl += HoloMesh3D.line(sl, c, c + Vector3(0, ht, 0), lc)
			nl += HoloMesh3D.diamond(sl, c + Vector3(0, ht + ht * 0.4, 0),
					taille_cellule * 0.22, ht * 0.5, lc)
		elif _lieu_sol.has(cell):
			continue   # reste du sol du lieu : laissé vide (peu d'arbres voulus)
		elif rng.randf() <= 0.55:
			# Parc ordinaire : arbres verts épars.
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

# ─── Extérieur : faubourgs / routes / lac greffés AUTOUR du carré ──
# Tout est posé HORS de la grille [0,grille)² (aucun chevauchement avec le tissu
# existant) et réparti de façon volontairement asymétrique : faubourg dense à
# l'est, quartier-satellite détaché au nord-est, hameau au bout d'une route au
# nord, lac au coin sud-ouest — le côté ouest reste nu. Casse la symétrie du carré.
func _build_exterieur() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x0FA0B0
	var s := HoloMesh3D.st()        # arêtes des faubourgs
	var sf := HoloMesh3D.st_tri()   # faces sombres (occlusion)
	var na := 0
	var nf := 0
	# Faubourgs : rect en cellules HORS grille (x ≥ grille, ou y < 0).
	# [rect, densité, étages max] — tailles/positions inégales → asymétrie.
	var quartiers := [
		[Rect2(grille + 1, 6, 7, 15), 0.62, 4],   # est : faubourg dense, décalé sud
		[Rect2(grille + 3, -9, 6, 6), 0.55, 3],   # nord-est : satellite détaché
		[Rect2(7, -12, 8, 4), 0.50, 2],           # nord : hameau au bout de la route
	]
	for q in quartiers:
		var r := _poser_quartier(s, sf, q[0], q[1], q[2], rng)
		na += r[0]
		nf += r[1]
	_ajouter_mesh(HoloMesh3D.commit(s, na), "Faubourgs")
	var fmesh := HoloMesh3D.commit(sf, nf)
	if fmesh != null:
		var mif := MeshInstance3D.new()
		mif.name = "FaubourgsFaces"
		mif.mesh = fmesh
		mif.material_override = _mat_faces
		_monde.add_child(mif)
	# Routes de liaison : polylignes coudées partant du bord du carré vers les
	# faubourgs (coudes = symétrie cassée). UV = flux animé du shader de route.
	var sr := SurfaceTool.new()
	sr.begin(Mesh.PRIMITIVE_LINES)
	var nr := 0
	var ed := float(grille - 1)   # ligne de bord du carré (point d'accroche)
	nr += _route_ext(sr, [Vector2(ed, 9), Vector2(grille + 2, 9), Vector2(grille + 6, 10)], route_intensite_avenue)
	nr += _route_ext(sr, [Vector2(ed, 17), Vector2(grille + 3, 18), Vector2(grille + 7, 18)], route_intensite_rue)
	nr += _route_ext(sr, [Vector2(ed, 5), Vector2(grille + 2, 0), Vector2(grille + 5, -5)], route_intensite_rue)
	nr += _route_ext(sr, [Vector2(10, 0), Vector2(10.5, -5), Vector2(11, -11)], route_intensite_rue)
	# Route jusqu'au lac : sort du coin sud-ouest de la ville et rejoint la rive.
	nr += _route_ext(sr, [Vector2(2, ed), Vector2(-0.5, ed + 1.0), Vector2(-1.7, 28.6)], route_intensite_avenue)
	if nr > 0:
		var mir := MeshInstance3D.new()
		mir.name = "RoutesExt"
		mir.mesh = sr.commit()
		mir.material_override = _mat_routes
		_monde.add_child(mir)
	# Lac au coin sud-ouest (nappe pleine bleue, calée contre le coin mais
	# entièrement hors du carré → la ville borde l'eau sans la chevaucher).
	var lac_centre := Vector2(-5.0, grille + 4.5)
	var lac_rx := 6.0
	var lac_ry := 5.0
	_build_lac_ext(lac_centre, lac_rx, lac_ry)
	# Collines tout autour du lac (dômes wireframe), sauf là où elles mordraient
	# la ville (côté ville culé).
	_build_collines(lac_centre, lac_rx, lac_ry, rng)

# Remplit un rect (cellules) de petits bâtiments épars (faubourg). Renvoie
# [nb arêtes, nb faces] pour que l'appelant sache si les meshes sont non vides.
func _poser_quartier(s: SurfaceTool, sf: SurfaceTool, rect: Rect2, dens: float,
		et_max: int, rng: RandomNumberGenerator) -> Array:
	var na := 0
	var nf := 0
	var occ := {}
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var w := int(rect.size.x)
	var h := int(rect.size.y)
	var col := Color(couleur_decor_bati, 0.85)
	for ix in w:
		for iy in h:
			var gx := x0 + ix
			var gy := y0 + iy
			var cell := Vector2i(gx, gy)
			if occ.has(cell):
				continue
			if rng.randf() > dens:
				continue
			# Emprise 1×1, 2×1 ou 1×2 (reste dans le rect).
			var ex := 1
			var ey := 1
			var roll := rng.randf()
			if roll < 0.28 and ix + 1 < w:
				ex = 2
			elif roll < 0.5 and iy + 1 < h:
				ey = 2
			for dx in ex:
				for dy in ey:
					occ[Vector2i(gx + dx, gy + dy)] = true
			var et := rng.randi_range(1, maxi(1, et_max))
			var sx := float(ex) * taille_cellule * 0.82
			var sz := float(ey) * taille_cellule * 0.82
			var sy := float(et) * unite_maison
			var centre := _world(gx + (ex - 1) * 0.5, gy + (ey - 1) * 0.5, 0.0)
			na += HoloMesh3D.box(s, centre, sx, sy, sz, col)
			nf += HoloMesh3D.box_faces(sf, centre, sx * FACE_INSET, sy * FACE_INSET, sz * FACE_INSET)
	return [na, nf]

# Polyligne de route extérieure (UV.x = distance cumulée → flux animé du shader).
func _route_ext(sr: SurfaceTool, pts_cellules: Array, inten: float) -> int:
	var n := 0
	var acc := 0.0
	var y := 0.02
	for i in range(pts_cellules.size() - 1):
		var a := _world(pts_cellules[i].x, pts_cellules[i].y, y)
		var b := _world(pts_cellules[i + 1].x, pts_cellules[i + 1].y, y)
		var L := a.distance_to(b)
		sr.set_color(Color(1, 1, 1, inten)); sr.set_uv(Vector2(acc, 0)); sr.add_vertex(a)
		sr.set_color(Color(1, 1, 1, inten)); sr.set_uv(Vector2(acc + L, 0)); sr.add_vertex(b)
		acc += L
		n += 1
	return n

# Lac satellite : nappe d'eau PLEINE (éventail d'ellipse au sol), tout en bleu.
func _build_lac_ext(centre_cell: Vector2, rx: float, ry: float) -> void:
	var se := HoloMesh3D.st_tri()
	var ne := 0
	var ce := Color(couleur_eau, 0.92)
	var y := 0.012
	var c := _world(centre_cell.x, centre_cell.y, y)
	var seg := 64
	var prev := _world(centre_cell.x + rx, centre_cell.y, y)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / float(seg)
		var cur := _world(centre_cell.x + cos(a) * rx, centre_cell.y + sin(a) * ry, y)
		se.set_color(ce); se.add_vertex(c)
		se.set_color(ce); se.add_vertex(prev)
		se.set_color(ce); se.add_vertex(cur)
		ne += 1
		prev = cur
	_ajouter_mesh(HoloMesh3D.commit(se, ne), "LacExt", _mat_lac)

# Collines : dômes wireframe disposés en couronne AUTOUR du lac (sur la rive),
# avec culling de tout dôme qui mordrait la ville carrée → reliefs uniquement
# sur les rives extérieures du lac (le côté ville reste sans collines).
func _build_collines(lac_centre: Vector2, lac_rx: float, lac_ry: float, rng: RandomNumberGenerator) -> void:
	var s := HoloMesh3D.st()
	var n := 0
	var col := Color(0.30, 0.52, 0.40)   # teinte terrain (vert sourd, distinct du bâti)
	var nb := 16
	for i in nb:
		var a := TAU * float(i) / float(nb) + rng.randf_range(-0.14, 0.14)
		var rh := rng.randf_range(1.4, 2.9)             # rayon de colline (cellules)
		# Anneau elliptique calé sur la rive (juste au-delà du bord du lac).
		var hx := lac_centre.x + cos(a) * (lac_rx + rh * 0.8)
		var hy := lac_centre.y + sin(a) * (lac_ry + rh * 0.8)
		if _chevauche_ville(hx, hy, rh + 0.6):
			continue   # collerait à la ville → on saute (côté ville sans relief)
		var centre := _world(hx, hy, 0.0)
		var ht := unite_maison * rng.randf_range(2.0, 4.5)
		n += _dome(s, centre, rh * taille_cellule, ht, col, 2, 6)
	_ajouter_mesh(HoloMesh3D.commit(s, n), "Collines", _mat_ambiance)

# Dôme wireframe (colline) : `anneaux` cercles de latitude (profil hémisphérique)
# + cercle de base + `meridiens` arcs verticaux jusqu'au sommet. Renvoie le nb d'arêtes.
func _dome(s: SurfaceTool, c: Vector3, r: float, h: float, col: Color, anneaux: int, meridiens: int) -> int:
	var n := 0
	n += HoloMesh3D.circle(s, c, r, col, 24)
	for k in range(1, anneaux + 1):
		var t := float(k) / float(anneaux + 1)
		n += HoloMesh3D.circle(s, c + Vector3(0, h * t, 0), r * sqrt(maxf(0.0, 1.0 - t * t)), col, 20)
	for m in meridiens:
		var ang := TAU * float(m) / float(meridiens)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var prev := c + dir * r
		var pas := 6
		for i in range(1, pas + 1):
			var t := float(i) / float(pas)
			var cur := c + dir * (r * sqrt(maxf(0.0, 1.0 - t * t))) + Vector3(0, h * t, 0)
			n += HoloMesh3D.line(s, prev, cur, col)
			prev = cur
	return n

# Un disque (centre cellule cx,cy ; rayon r en cellules) mord-il la ville carrée
# [−0.5, grille−0.5]² (emprise des bâtiments) ?
func _chevauche_ville(cx: float, cy: float, r: float) -> bool:
	var nx := clampf(cx, -0.5, float(grille) - 0.5)
	var ny := clampf(cy, -0.5, float(grille) - 0.5)
	return Vector2(cx - nx, cy - ny).length() < r

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
	# Boules à facettes : rotation lente → balayage des rayons lumineux.
	for d in _discos:
		if is_instance_valid(d):
			d.rotation.y += dt * 0.9
	# Balises rouges de sommet : clignotement (allumées ~40 % du temps).
	if _mat_balise != null:
		_balise_t += dt
		_mat_balise.set_shader_parameter("alpha_mult", 1.0 if fposmod(_balise_t, 1.6) < 0.6 else 0.06)
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
