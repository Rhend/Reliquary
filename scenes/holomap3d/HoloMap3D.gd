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
const PARC_SHADER := preload("res://scenes/holomap3d/holo_parc.gdshader")

# Modules de build extraits (refactor). Appelés en static via la const → pas de
# class_name, donc pas de régénération du cache de classes (cf. CLAUDE.md).
const Geo := preload("res://scenes/holomap3d/build/holo_geo.gd")
const Decor := preload("res://scenes/holomap3d/build/holo_decor.gd")
const Env := preload("res://scenes/holomap3d/build/holo_env.gd")
const Ville := preload("res://scenes/holomap3d/build/holo_ville.gd")
const FUMEE_SHADER := preload("res://scenes/holomap3d/holo_fumee.gdshader")
const BEAM_SHADER := preload("res://scenes/holomap3d/holo_beam.gdshader")
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
# Déplacement libre ZQSD (se balader) : on translate le centre d'orbite.
# Z/S = avant/arrière, Q/D = gauche/droite, E/A = monter/descendre. Vitesse ∝ zoom.
@export var vitesse_balade := 0.55

# ─── Échelle (référencée maison) ──────────────────────────────
@export_group("Échelle")
@export var unite_maison := 0.14    # hauteur d'un étage / maison ≈ 3 m (unité de référence)
@export var taille_cellule := 0.34  # côté d'une cellule au sol ≈ emprise d'une maison
@export var grille := 28            # nb de cellules par côté

# ─── Source : gabarit Excel (sinon ville procédurale) ─────────
@export_group("Carte Excel")
# Chemin d'un classeur .xlsx (feuilles Carte / Surélevé / Paramètres / Lieux). Vide →
# ville PROCÉDURALE (comportement historique, conservé). Renseigné → la carte est LUE
# au runtime (ZIPReader + XMLParser) : décor + lieux d'expédition découverts (pins).
@export var chemin_xlsx := ""
# Gain vertical appliqué aux hauteurs lues (en mètres) : 1 = échelle réelle (ville
# plate), >1 = relief plus lisible en holo. N'affecte PAS l'emprise au sol.
@export var exageration_hauteur := 2.5
# Densité du trafic simulé (voitures par case de route). Plus haut = plus dense
# (au-delà de ~0.45 le réseau peut s'embouteiller aux carrefours).
@export var densite_trafic := 0.30

# ─── Voirie (rendu néon des routes lues dans le gabarit) ──────
@export_group("Voirie")
@export var couleur_route := Color(0.95, 0.30, 0.66)  # magenta rosé (distinct du violet Épique)
@export var route_emission_base := 0.7  # néon de base (discret, au-dessus du décor)
@export var flux_intensite := 1.2       # surbrillance du flux qui circule
@export var flux_vitesse := 0.35        # vitesse du flux (lent)
@export var flux_frequence := 0.18      # densité de pulses le long de l'axe

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

# ─── Gradient de richesse (centre riche → périphérie à l'abandon) ──
# Module l'intensité/saturation de TOUTES les apparences selon la distance au centre
# géométrique de la grille (sans changer la nature de la zone). Centre = néons vifs,
# structures intactes ; bord = couleurs ternies, néons « morts », délabrement.
@export_group("Gradient richesse")
@export var gradient_actif := true
# Rayon du « cœur riche » (fraction du rayon de la carte) où la richesse reste à 100 %.
@export_range(0.0, 1.0) var gradient_coeur := 0.32
# Forme de la décroissance cœur→bord : <1 chute tôt, >1 garde la richesse plus loin.
@export_range(0.2, 4.0) var gradient_chute := 1.35
# Luminosité résiduelle au point le plus pauvre (0 = noir, 1 = pas d'assombrissement).
@export_range(0.0, 1.0) var gradient_pauvre_lum := 0.42
# Désaturation au point le plus pauvre (0 = couleur conservée, 1 = gris total).
@export_range(0.0, 1.0) var gradient_pauvre_desat := 0.6

# ─── Décor d'ambiance ─────────────────────────────────────────
@export_group("Décor")
@export var decor_actif := true
# Sol : nappe de terre + maillage fin (petits carrés) qui lie tout l'ensemble.
@export var sol_actif := true

# ─── Hologramme (glow + post-process) ─────────────────────────
@export_group("Hologramme")
@export var glow_intensity := 1.15
# Post-process « écran cathodique » : valeurs ACTIVES mais douces (non-épileptogène).
@export_range(0.0, 1.0) var scanline_intensity := 0.05
@export var scanline_count := 240.0
@export var scanline_speed := 0.6
@export_range(0.0, 0.5) var flicker_amplitude := 0.015
@export_range(0.0, 0.02) var distortion_amplitude := 0.0008
@export_range(0.0, 0.01) var aberration := 0.0007        # séparation chromatique (subtile)
@export_range(0.0, 1.0) var vignette_force := 0.32        # coins assombris
@export_range(0.0, 1.0) var glitch_force := 0.45          # rafales rares de tranches
@export_range(0.0, 0.1) var breathe_amplitude := 0.02     # respiration lumineuse
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
@export var vitesse_voitures := 0.08          # tours/seconde
@export var couleur_voiture_aller := Color(0.55, 0.90, 1.00)   # cyan (phares)
@export var couleur_voiture_retour := Color(1.00, 0.55, 0.25)  # ambre (feux arrière)
# Spires corpo : les plus hautes tours projettent un FAISCEAU de lumière vertical
# (+ mât d'antenne à tête pulsante) → verticalité dramatique, signal de pouvoir.
@export var spires_actif := true
@export var spires_max := 8                    # nb max de faisceaux (spires héros distinctes)
@export_range(0.0, 5.0) var beam_emission := 2.4
# Trafic AÉRIEN : couloirs de véhicules volants à plusieurs altitudes au-dessus de
# la ville (VTOL) → la mégalopole vit en 3D, pas seulement au sol.
@export var trafic_aerien_actif := true
@export var couloirs_aeriens := 9
# Brume de profondeur : les arêtes lointaines s'estompent (focus centre).
@export var brume_debut := 16.0
@export var brume_fin := 30.0

# ─── Bâti (fenêtres allumées + décor de lieu) ─────────────────
@export_group("Bâti")
# Fenêtres allumées (shader de faces) : densité + gain d'émission → ville habitée.
@export_range(0.0, 1.0) var fenetre_densite := 0.24
@export var fenetre_emission := 1.9
@export var couleur_fenetre := Color(0.98, 0.86, 0.58)  # ambre chaud
# Façades vivantes (shader de faces) : lueur de structure teintée par district +
# bandes d'étage + pulse de scan vertical → la ville respire (cf. holo_face).
@export var couleur_glow_coeur := Color(0.35, 0.95, 1.00)     # cyan chaud (centre riche)
@export var couleur_glow_peripherie := Color(0.16, 0.30, 0.52) # bleu froid (abandon)
@export_range(0.0, 2.0) var glow_facade := 0.38   # corps vitré translucide (≠ néon plein)
@export_range(0.0, 2.5) var etage_force := 1.3    # barres d'étage (crèvent le bloom)
@export_range(0.0, 2.5) var pulse_force := 1.15   # front de scan lumineux
# Skyline : les tours hautes virent au cyan-blanc (cœur corpo), les bâtis bas
# restent froids → hiérarchie de hauteur lisible (heat des arêtes).
@export var couleur_tour_haute := Color(0.55, 0.95, 1.00)
@export var hauteur_tour_ref := 1.4   # hauteur monde au-delà de laquelle le bâti « chauffe »
# Décor d'un lieu SANS bâtiment (parc-lieu) : émission du décor tier-coloré.
@export var lieu_decor_emission := 3.4

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
var _tooltip: HoloTooltip
var _hovered: HoloLocation3D
var _radar: Node3D
var _mat_motes: ShaderMaterial
var _mat_trafic: ShaderMaterial
var _mat_neon: ShaderMaterial          # accents néon (enseignes, nœuds d'intersection)
var _mat_lieu_decor: ShaderMaterial    # décor d'un lieu sans bâtiment (parc tier-coloré)
var _mat_lac: ShaderMaterial           # nappe d'eau pleine (lac satellite, hors carré)
var _mat_eau: ShaderMaterial           # eau qui s'écoule (carte Excel, shader animé)
var _mat_parc: ShaderMaterial          # sol de parc : herbe holo vivante (shader animé)
var _mat_sol: ShaderMaterial           # sol : nappe de terre + maillage fin (liant)
var _mat_horizon: ShaderMaterial       # halo d'horizon / brume (sans atténuation de brume)
var _mat_balise: ShaderMaterial        # balises rouges clignotantes (sommets de tours)
var _mat_fumee: ShaderMaterial         # fumée d'usine (vert ocre, montée animée)
var _mat_glow_chaud: ShaderMaterial    # nappes de lumière chaude (ambiance supermarché)
var _mat_beam: ShaderMaterial          # faisceaux de spires corpo (shaft vertical)
var _mat_trafic_aerien: ShaderMaterial # trafic aérien (VTOL, plus rapide/brillant)
var _discos: Array[Node3D] = []        # boules à facettes (sommets de pyramides) — tournent
var _balise_t := 0.0                   # phase de clignotement des balises
var _distance_cible := 15.0
var _intro_en_cours := false
var _mats_reveal: Array[ShaderMaterial] = []   # matériaux supportant le reveal d'intro
var _foc := 0.0                                # intensité courante du focus de survol
var _focus_tw: Tween

var _eau := {}
var _parc := {}
var _routes_set := {}    # Vector2i → true : toutes les cases ROUTE (portes face aux routes)
var _lieu_sol := {}      # Vector2i → Color : cellule de décor portée par un lieu sans bâtiment
var _lieu_arbres := {}   # Vector2i → Color : cellules CHOISIES pour un arbre coloré (plafonné)

func _ready() -> void:
	get_viewport().physics_object_picking = true
	_charger_excel()
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
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 1.02   # décor sous le seuil (pas de bloom), lieux au-dessus
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

# Crée un ShaderMaterial et applique les paramètres en bloc (clé→valeur).
func _make_mat(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

func _setup_materials() -> void:
	_mat_decor = _make_mat(LINE_SHADER, {"emission_strength": luminosite_decor, "alpha_mult": 1.0})
	_mat_ambiance = _make_mat(LINE_SHADER, {"emission_strength": luminosite_ambiance, "alpha_mult": 1.0})
	_mat_routes = _make_mat(ROUTE_SHADER, {
		"route_color": couleur_route, "emission_base": route_emission_base,
		"flux_intensite": flux_intensite, "flux_vitesse": flux_vitesse,
		"flux_frequence": flux_frequence,
	})

	# Faces sombres : dessinées AVANT les arêtes (render_priority plus bas) et
	# écrivant la profondeur → occlusion des lignes derrière. Les façades sont
	# VIVANTES : teinte de district (coeur cyan → périphérie froide), bandes
	# d'étage, pulse de scan vertical + fenêtres ambre (cf. holo_face.gdshader).
	_mat_faces = _make_mat(FACE_SHADER, {
		"face_color": couleur_faces, "opacite": opacite_faces,
		"fenetre_densite": fenetre_densite, "fenetre_emission": fenetre_emission,
		"fenetre_color": couleur_fenetre,
		"glow_coeur": couleur_glow_coeur, "glow_peripherie": couleur_glow_peripherie,
		"glow_force": glow_facade, "etage_haut": unite_maison,
		"etage_force": etage_force, "pulse_force": pulse_force,
		"rich_coeur": gradient_coeur, "rich_chute": gradient_chute,
		"rich_rmax": maxf(0.001, _cgrid() * taille_cellule),
	})
	_mat_faces.render_priority = -1

	# Poussières de données (montée animée).
	_mat_motes = _make_mat(MOTES_SHADER, {"mote_color": couleur_motes, "hauteur": motes_hauteur})

	# Trafic (traînées le long des routes).
	_mat_trafic = _make_mat(TRAFFIC_SHADER, {"vitesse": vitesse_voitures})

	# Trafic aérien : plus rapide et plus brillant (VTOL qui filent dans le ciel).
	_mat_trafic_aerien = _make_mat(TRAFFIC_SHADER, {
		"vitesse": vitesse_voitures * 1.9, "emission": 2.9,
	})

	# Accents néon (enseignes holographiques, nœuds d'intersection) — glow.
	_mat_neon = _make_mat(LINE_SHADER, {"emission_strength": 2.0, "alpha_mult": 1.0})

	# Décor d'un lieu SANS bâtiment (parc-lieu) : tier-coloré + glow marqué pour
	# que la zone ressorte comme un lieu (pas un simple décor vert).
	_mat_lieu_decor = _make_mat(LINE_SHADER, {"emission_strength": lieu_decor_emission, "alpha_mult": 1.0})

	# Lac satellite (hors carré) : nappe pleine, bleu franc et lisible.
	_mat_lac = _make_mat(LINE_SHADER, {"emission_strength": 1.3, "alpha_mult": 1.0})

	# Eau qui s'écoule (carte Excel) : bandes de courant animées par le shader.
	_mat_eau = _make_mat(WATER_SHADER, {"eau_color": couleur_eau})

	# Sol de parc : nappe verte VIVANTE (herbe holo — touffes + brins qui frémissent),
	# même esprit de surface que l'eau (motif animé en coords monde, continu).
	_mat_parc = _make_mat(PARC_SHADER, {"parc_color": couleur_parc})

	# Halo d'horizon / brume d'ambiance : émission douce, brume repoussée très loin
	# (l'horizon est volontairement distant et doit rester visible).
	_mat_horizon = _make_mat(LINE_SHADER, {
		"emission_strength": 1.0, "alpha_mult": 1.0, "fog_debut": 1.0e6, "fog_fin": 1.0e6,
	})

	# Balises rouges (sommets de tours) : clignotement via alpha_mult (cf. _process).
	_mat_balise = _make_mat(LINE_SHADER, {"emission_strength": 3.2, "alpha_mult": 1.0})

	# Fumée d'usine : vrai panache de volutes (billboards doux qui montent et gonflent).
	_mat_fumee = _make_mat(FUMEE_SHADER, {
		"fumee_color": Color(0.50, 0.58, 0.28), "hauteur": 0.95, "vitesse": 0.05, "expansion": 0.85,
	})

	# Lumière chaude (ambiance supermarché) : nappes additives ambrées, glow doux.
	_mat_glow_chaud = _make_mat(LINE_SHADER, {"emission_strength": 1.1, "alpha_mult": 1.0})

	# Faisceaux de spires corpo : shaft de lumière vertical (billboard cylindrique).
	_mat_beam = _make_mat(BEAM_SHADER, {
		"emission": beam_emission, "fog_debut": brume_debut, "fog_fin": brume_fin,
	})

	# Sol : émission faible (la luminosité réelle vient des vertex colors — nappe
	# très sombre + maillage discret) → matérialise le terrain sans écraser la ville.
	_mat_sol = _make_mat(LINE_SHADER, {"emission_strength": 0.7, "alpha_mult": 1.0})

	# Brume de profondeur : poussée sur les matériaux de lignes/routes/trafic
	# (les faces ne fadent pas → l'occlusion reste). Les lieux/faisceaux
	# utilisent les valeurs par défaut du shader (cohérentes avec ces exports).
	for m: ShaderMaterial in [_mat_decor, _mat_ambiance, _mat_lac, _mat_eau, _mat_parc, _mat_sol, _mat_routes, _mat_trafic, _mat_trafic_aerien, _mat_neon, _mat_lieu_decor, _mat_glow_chaud]:
		m.set_shader_parameter("fog_debut", brume_debut)
		m.set_shader_parameter("fog_fin", brume_fin)

	# Matériaux qui réagissent au reveal d'intro (matérialisation radiale).
	_mats_reveal = [_mat_decor, _mat_ambiance, _mat_lac, _mat_eau, _mat_parc, _mat_sol, _mat_routes, _mat_faces, _mat_trafic, _mat_trafic_aerien, _mat_neon, _mat_lieu_decor, _mat_glow_chaud]

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
	_post_mat.set_shader_parameter("aberration", aberration)
	_post_mat.set_shader_parameter("vignette_force", vignette_force)
	_post_mat.set_shader_parameter("glitch_force", glitch_force)
	_post_mat.set_shader_parameter("breathe_amp", breathe_amplitude)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _post_mat
	layer.add_child(rect)

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

	# Carte 100 % data-driven : rendue depuis le gabarit Excel. Sans gabarit
	# (fichier absent/illisible), on laisse la carte vide plutôt que d'afficher
	# un décor de secours qui ne correspondrait pas à la ville conçue.
	if _excel == null:
		push_warning("[HoloMap3D] aucun gabarit Excel chargé → carte vide.")
		return
	_build_all_excel()

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
	# Brume atmosphérique DÉSACTIVÉE (test) : poussée très loin → plus de fondu de
	# distance, les éléments lointains restent à pleine intensité (remettre 22 / 46
	# pour retrouver la brume de profondeur).
	brume_debut = 1.0e6
	brume_fin = 2.0e6
	couleur_fond = Color(0.012, 0.022, 0.045)   # bleu nuit très sombre (≠ noir total) → atmosphère
	print("[HoloMap3D] ", _excel.resume())

# Rendu de la carte Excel : décor d'apparence (eau/parc/route) + bâtiments lus,
# le tout dans la DA holo existante (socle, sol, motes, radar, intro, post-process).
# Les lieux d'expédition découverts (`lieux`, lus de la feuille « Lieux ») sont
# posés EN PLUS, en pins/zones cliquables (cf. _construire_lieux).
func _build_all_excel() -> void:
	_eau.clear()
	_parc.clear()
	_routes_set.clear()
	for c: Vector2i in _excel.routes:
		_routes_set[c] = true
	_lieu_sol.clear()
	_lieu_arbres.clear()
	_discos.clear()
	# L'eau est gérée par le shader animé (Ville.eau). On NE peuple PAS _eau
	# → Decor.decor n'ajoute pas de vaguelettes statiques par-dessus le courant.
	for c: Vector2i in _excel.parcs:
		_parc[c] = true
	Env.horizon(self)           # halo d'horizon + brume au sol (atmosphère)
	Env.skyline_lointain(self)  # silhouette de mégastructures à l'horizon (profondeur)
	if socle_actif:
		Env.socle(self)
	if sol_actif:
		Env.sol_disc(self, Vector2(_cgrid(), _cgrid()), _cgrid() * 1.28 + 2.0)
	Ville.routes(self)
	Ville.trottoirs(self)       # bordures de voirie (trottoirs)
	Ville.eclairage(self)       # lampadaires (points lumineux chauds)
	Ville.eau(self)             # eau qui s'écoule (shader animé)
	Ville.bordure_eau(self)     # liseré cyan vif → l'eau se détache de la carte
	if decor_actif:
		Decor.parcs_sol(self)       # nappe verte au sol sous les parcs (les arbres se posent dessus)
		Decor.decor(self)           # parcs (arbres) — _eau vide → pas de vaguelettes
	Decor.collines(self)        # relief de bordure (collines / désert) — cadre la ville
	Decor.terrains(self)        # terrains de sport (baseball)
	Decor.parkings(self)        # aires de stationnement (marquages au sol + lampadaires)
	Ville.batiments(self)
	if spires_actif:
		Ville.spires(self)          # faisceaux corpo + mâts d'antenne (verticalité)
	if trafic_aerien_actif:
		Ville.trafic_aerien(self)   # couloirs de VTOL au-dessus de la ville
	Decor.cimetieres(self)      # mémorial numérique (champ de stèles)
	Decor.usines(self)          # usine désaffectée (hall bas + dents de scie + cheminée)
	Decor.casses(self)          # casse auto (enclos + épaves empilées)
	Decor.supermarches(self)    # hypermarché (volume bas + enseignes néon)
	Ville.ponts(self)             # ouvrages du calque Surélevé (au-dessus de l'eau/route)
	Ville.routes_elevees(self)    # autoroutes surélevées (magenta) — vide pour l'instant
	if motes_actif:
		Env.motes(self)
	if radar_actif:
		Env.radar(self)
	_construire_lieux(lieux)    # lieux découverts (feuille « Lieux ») posés sur le décor
	if intro_actif:
		_jouer_intro()

# Portes face aux routes : pour chaque côté frontière d'un bloc directement adjacent
# à une case ROUTE, dessine une porte (deux jambages + linteau) sur la paroi, au sol.
# `dh` = hauteur de porte (monde). Renvoie le nombre d'arêtes. Appelée par les lieux
# bâtis (usine/casse/supermarché/cimetière) — PAS le sport (terrain plat, sans paroi).
func _portes_vers_routes(cells: Array, dh: float, col: Color, s: SurfaceTool) -> int:
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var n := 0
	var up := Vector3(0, dh, 0)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		for d: Vector2i in dirs:
			if setd.has(c + d) or not _routes_set.has(c + d):
				continue   # côté frontière touchant une route → porte
			var seg := _cote_cellule(c, d)
			var pa := _world(seg[0].x, seg[0].y, 0.0)
			var pb := _world(seg[1].x, seg[1].y, 0.0)
			var mid := (pa + pb) * 0.5
			var half := (pb - pa) * 0.22          # demi-largeur (~44 % du côté)
			var jl := mid - half
			var jr := mid + half
			n += HoloMesh3D.line(s, jl, jl + up, col)        # jambage gauche
			n += HoloMesh3D.line(s, jr, jr + up, col)        # jambage droit
			n += HoloMesh3D.line(s, jl + up, jr + up, col)   # linteau
	return n

# Ajoute un mesh de FACES sombres (occlusion) sous le matériau de faces partagé.
func _ajouter_faces(mesh: ArrayMesh, nom: String) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.material_override = _mat_faces
	_monde.add_child(mi)

# ─── Gradient de richesse ─────────────────────────────────────
# Richesse d'un point monde (plan XZ) : 1 dans le cœur central → 0 en périphérie.
# Le centre de la grille est l'origine monde (cf. _world soustrait _cgrid).
func _richesse(p: Vector3) -> float:
	if not gradient_actif:
		return 1.0
	var rmax := maxf(0.001, _cgrid() * taille_cellule)
	var d := Vector2(p.x, p.z).length() / rmax        # 0 au centre, ~1 au bord
	var t := clampf((d - gradient_coeur) / maxf(0.001, 1.0 - gradient_coeur), 0.0, 1.0)
	return pow(1.0 - t, gradient_chute)

# Ternit une couleur selon la richesse du lieu (centre vif → périphérie morte) :
# baisse de luminosité + désaturation + DÉRIVE FROIDE (la périphérie vire au
# bleu-cyan blafard, lumière de secours d'un quartier à l'abandon). La NATURE de
# la zone est conservée (teinte de base + alpha) ; seuls intensité, saturation et
# température chutent vers les bords.
func _moduler(col: Color, p: Vector3) -> Color:
	if not gradient_actif:
		return col
	var r := _richesse(p)
	var lum := lerpf(gradient_pauvre_lum, 1.0, r)
	var c := Color(col.r * lum, col.g * lum, col.b * lum, col.a)
	var desat := (1.0 - r) * gradient_pauvre_desat
	if desat > 0.001:
		var g := c.get_luminance()
		c = c.lerp(Color(g, g, g, c.a), desat)
		# Dérive froide : on repousse un soupçon de bleu blafard dans les gris.
		c = c.lerp(Color(g * 0.7, g * 0.92, g * 1.15, c.a), desat * 0.5)
	return c

# Teinte un bâti par sa HAUTEUR (tour haute → cyan-blanc « corpo ») puis applique
# le gradient de richesse. Donne une skyline lisible : le regard accroche les tours.
func _accent_hauteur(base: Color, h: float, p: Vector3) -> Color:
	var heat := clampf(h / maxf(0.1, hauteur_tour_ref), 0.0, 1.0)
	heat = heat * heat   # seules les vraies tours chauffent franchement
	var c := Color(base.r, base.g, base.b, base.a).lerp(
			Color(couleur_tour_haute.r, couleur_tour_haute.g, couleur_tour_haute.b, base.a),
			heat * 0.75)
	return _moduler(c, p)

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

# Hash déterministe d'une case → [0,1) (variété stable d'un build à l'autre, variée
# d'une case à l'autre). `salt` permet plusieurs tirages indépendants par case.
func _hash01(cell: Vector2i, salt: int) -> float:
	var hraw := ((cell.x + 1) * 73856093) ^ ((cell.y + 1) * 19349663) ^ (salt * 83492791)
	return float(hraw & 0xFFFF) / 65535.0

# Bâtiment générique d'UNE case : silhouette piochée dans un POOL non-cubique (selon
# la case + la hauteur) → toit en pointe, tour fuselée (biseautée), chapeau biseauté,
# ou redents (gratte-ciel étagé). Aucun toit cubique, aucun accessoire. [arêtes, faces].
func _maison_variee(cell: Vector2i, h: float, col: Color, s: SurfaceTool, sf: SurfaceTool) -> Array:
	var centre := _world(cell.x, cell.y, 0.0)
	var sz := taille_cellule * 0.8
	var ins := sz * FACE_INSET
	var floors := maxi(1, int(round(h / maxf(unite_maison, 0.001))))
	var v := _hash01(cell, 7)
	var n := 0
	var nf := 0
	# Les redents (gratte-ciel étagé) ne valent que pour les volumes assez hauts ;
	# sinon on retombe sur le chapeau biseauté → jamais de toit cubique.
	var redents := v >= 0.78 and floors >= 3
	if v < 0.33:
		# Toit en POINTE : corps droit + toiture pyramidale.
		var body := h * lerpf(0.60, 0.78, _hash01(cell, 11))
		n += HoloMesh3D.box(s, centre, sz, body, sz, col)
		nf += HoloMesh3D.box_faces(sf, centre, ins, body, ins)
		var top := centre + Vector3(0, body, 0)
		var rh := (h - body) + unite_maison * 0.5
		n += HoloMesh3D.pyramid(s, top, sz, sz, rh, col)
		nf += HoloMesh3D.pyramid_faces(sf, top, ins, ins, rh)
	elif v < 0.58:
		# Tour FUSELÉE : tronc de pyramide sur toute la hauteur (parois biseautées).
		var k := lerpf(0.55, 0.78, _hash01(cell, 13))
		n += HoloMesh3D.frustum(s, centre, sz, sz, h, k, col)
		nf += HoloMesh3D.frustum_faces(sf, centre, ins, ins, h, k)
	elif redents:
		# REDENTS : corps + volume plus petit empilé (gratte-ciel étagé).
		n += HoloMesh3D.box(s, centre, sz, h, sz, col)
		nf += HoloMesh3D.box_faces(sf, centre, ins, h, ins)
		var sz2 := sz * lerpf(0.55, 0.72, _hash01(cell, 17))
		var h2 := h * lerpf(0.20, 0.34, _hash01(cell, 19))
		var top := centre + Vector3(0, h, 0)
		n += HoloMesh3D.box(s, top, sz2, h2, sz2, col)
		nf += HoloMesh3D.box_faces(sf, top, sz2 * FACE_INSET, h2, sz2 * FACE_INSET)
	else:
		# Chapeau BISEAUTÉ : corps droit + couronne en tronc de pyramide rentré.
		var body := h * 0.80
		n += HoloMesh3D.box(s, centre, sz, body, sz, col)
		nf += HoloMesh3D.box_faces(sf, centre, ins, body, ins)
		var top := centre + Vector3(0, body, 0)
		var hc := h - body
		n += HoloMesh3D.frustum(s, top, sz, sz, hc, 0.45, col)
		nf += HoloMesh3D.frustum_faces(sf, top, ins, ins, hc, 0.45)
	return [n, nf]

# Étages (lignes de planchers) sur un BLOC plein rectangulaire et assez haut → casse la
# monotonie des grands bâtiments. Renvoie le nb d'arêtes (0 si non applicable).
func _etages_bloc(bb: Rect2i, ncells: int, h: float, col: Color, s: SurfaceTool) -> int:
	if ncells != bb.size.x * bb.size.y:
		return 0   # silhouette non rectangulaire → éviterait des lignes hors emprise
	var floors := maxi(1, int(round(h / maxf(unite_maison, 0.001))))
	if floors < 3:
		return 0
	var sx := float(bb.size.x) * taille_cellule
	var sz := float(bb.size.y) * taille_cellule
	return HoloMesh3D.etages(s, _centre_bbox(bb), sx, h, sz, col, clampi(floors - 1, 1, 6))

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
		# Le pin flotte au-dessus du toit RÉEL du décor sous la zone (jamais de bâtiment
		# ajouté : usine/cimetière/pyramide/bâtiment générique sont déjà rendus par le décor).
		loc.hauteur      = _hauteur_monde(_excel.hauteur_m_zone(l.cells))
		loc.barriere_h   = taille_cellule * 5.4   # hauteur des piliers d'énergie (3× l'ancienne)
		loc.pilier_hw    = taille_cellule * 0.22  # demi-largeur (piliers fins, distincts)
		loc.line_shader  = LINE_SHADER
		loc.position     = _centre_emprise(l.cellule.x, l.cellule.y, l.emprise)
		loc.perimetre    = _perimetre_local(l.cells, loc.position)
		loc.clique.connect(_on_lieu_clique)
		loc.survol_change.connect(_on_survol)
		_lieux_node.add_child(loc)

# Contour de périmètre d'une zone (cellules) en coords LOCALES au lieu (centré sur
# `centre`) : paires de points = arêtes de cellule donnant sur l'EXTÉRIEUR de la zone.
# Sert au contour illuminé du lieu au survol (HoloLocation3D). Vide → pas de contour
# (le nœud retombe alors sur sa boîte d'emprise).
func _perimetre_local(cells: Array, centre: Vector3) -> PackedVector3Array:
	var segs := PackedVector3Array()
	if cells.is_empty():
		return segs
	var setd := {}
	for c: Vector2i in cells:
		setd[c] = true
	var h := taille_cellule * 0.5
	for c: Vector2i in cells:
		var ctr := _world(c.x, c.y, 0.05) - centre
		if not setd.has(c + Vector2i(1, 0)):    # arête droite (+x)
			segs.append(ctr + Vector3(h, 0, -h)); segs.append(ctr + Vector3(h, 0, h))
		if not setd.has(c + Vector2i(-1, 0)):   # arête gauche (-x)
			segs.append(ctr + Vector3(-h, 0, -h)); segs.append(ctr + Vector3(-h, 0, h))
		if not setd.has(c + Vector2i(0, 1)):    # arête bas (+z)
			segs.append(ctr + Vector3(-h, 0, h)); segs.append(ctr + Vector3(h, 0, h))
		if not setd.has(c + Vector2i(0, -1)):   # arête haut (-z)
			segs.append(ctr + Vector3(-h, 0, -h)); segs.append(ctr + Vector3(h, 0, -h))
	return segs

func _on_survol(loc: HoloLocation3D, actif: bool) -> void:
	if actif:
		_hovered = loc
		# Accent du tooltip = couleur de palier du lieu.
		_tooltip.montrer(loc.lieu_nom, GameData.get_tier_name(loc.tier),
				UIColors.tier_color(loc.tier), loc.lore, UIColors.tier_color(loc.tier))
		# On n'éclaire PAS le décor au survol (pas de _focus) → le bâtiment garde son
		# aspect normal (ne devient pas blanc). Piliers + pin + tooltip suffisent.
	elif _hovered == loc:
		_hovered = null
		_tooltip.cacher()

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

# ─── Caméra orbitale (monde fixe) ─────────────────────────────
func _appliquer_camera() -> void:
	if not is_instance_valid(_rig):
		return
	plongee_deg = clampf(plongee_deg, plongee_min, plongee_max)
	distance = clampf(distance, distance_min, distance_max)
	_rig.rotation = Vector3(-deg_to_rad(plongee_deg), _yaw, 0.0)
	_cam.position = Vector3(0, 0, distance)
	_cam.fov = fov

# Déplacement libre ZQSD : translate le centre d'orbite dans le plan horizontal de
# la caméra (E/A pour l'altitude). Vitesse proportionnelle au zoom (distance).
func _deplacement_zqsd(dt: float) -> void:
	if not is_instance_valid(_cam) or not is_instance_valid(_rig):
		return
	var fwd := -_cam.global_transform.basis.z
	fwd.y = 0.0
	var right := _cam.global_transform.basis.x
	right.y = 0.0
	if fwd.length() > 0.001:
		fwd = fwd.normalized()
	if right.length() > 0.001:
		right = right.normalized()
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_Z): mv += fwd
	if Input.is_key_pressed(KEY_S): mv -= fwd
	if Input.is_key_pressed(KEY_D): mv += right
	if Input.is_key_pressed(KEY_Q): mv -= right
	if Input.is_key_pressed(KEY_E): mv += Vector3.UP
	if Input.is_key_pressed(KEY_A): mv -= Vector3.UP
	if mv.length_squared() < 0.0001:
		return
	_rig.position += mv.normalized() * (maxf(2.0, distance) * vitesse_balade * dt)

func _process(dt: float) -> void:
	if auto_rotation:
		_yaw += deg_to_rad(vitesse_rotation) * dt
	# Zoom amorti (hors intro) : la distance glisse vers sa cible.
	if zoom_amorti and not _intro_en_cours:
		distance = lerpf(distance, _distance_cible, 1.0 - exp(-12.0 * dt))
	_appliquer_camera()
	_deplacement_zqsd(dt)
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
