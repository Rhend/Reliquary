# ============================================================
# BiomeBackground — Fond animé de biome, piloté par shader.
#
# ColorRect plein écran portant biome_background.gdshader. À placer DERRIÈRE
# le contenu (premier enfant) dans le hub, la CombatScene, etc.
#
# Usage :
#   var bg := BiomeBackground.new()
#   bg.apply_preset("forest")   # ou "city"
#   bg.set_zone(Enums.Zone.ABYSSE)
#   add_child(bg)               # en premier → derrière le reste
#
# Les presets sont des palettes ; la zone module l'obscurité/brouillard pour
# rendre la descente Surface → Profondeur → Abysse de plus en plus hostile.
# ============================================================
class_name BiomeBackground
extends ColorRect

const SHADER_PATH := "res://scenes/ui/backgrounds/biome_background.gdshader"

# Palettes par biome (mode + couleurs + densité). Étendre ici pour de nouveaux biomes.
#
# Lisibilité : les silhouettes ne « ressortent » que par le CONTRASTE entre le
# ciel (clair) et les couches (sombres). Les ciels sont donc nettement plus
# lumineux que les couches, et les lueurs (lucioles, torches…) sont accentuées.
const PRESETS := {
	"forest": {   # Forêt Sombre — arbres tordus, lucioles vertes
		"u_mode":         0,
		"sky_top":        Color(0.07, 0.10, 0.16),
		"sky_bottom":     Color(0.13, 0.26, 0.21),
		"layer_far":      Color(0.06, 0.12, 0.10),
		"layer_mid":      Color(0.04, 0.08, 0.07),
		"layer_near":     Color(0.01, 0.03, 0.025),
		"fog_color":      Color(0.38, 0.58, 0.50),
		"accent":         Color(0.70, 0.95, 0.50),   # lucioles
		"fog_density":    0.45,
		"detail_density": 1.0,
		"anim_speed":     1.0,
		"glow_amount":    1.4,
	},
	"marsh": {    # Marécage Putride — palette olive/brun, brouillard épais, feux follets toxiques
		"u_mode":         0,
		"sky_top":        Color(0.09, 0.13, 0.10),
		"sky_bottom":     Color(0.18, 0.23, 0.12),
		"layer_far":      Color(0.08, 0.11, 0.07),
		"layer_mid":      Color(0.05, 0.07, 0.04),
		"layer_near":     Color(0.02, 0.03, 0.015),
		"fog_color":      Color(0.45, 0.58, 0.32),
		"accent":         Color(0.60, 0.95, 0.40),   # feux follets
		"fog_density":    0.60,
		"detail_density": 1.1,
		"anim_speed":     0.8,
		"glow_amount":    1.4,
	},
	"mountain": { # Montagne — pics rocheux bleu-gris, peu de brouillard, pas de lueurs
		"u_mode":         0,
		"sky_top":        Color(0.09, 0.12, 0.20),
		"sky_bottom":     Color(0.17, 0.21, 0.28),
		"layer_far":      Color(0.12, 0.14, 0.20),
		"layer_mid":      Color(0.07, 0.08, 0.12),
		"layer_near":     Color(0.02, 0.03, 0.05),
		"fog_color":      Color(0.55, 0.62, 0.74),
		"accent":         Color(0.80, 0.90, 1.00),
		"fog_density":    0.30,
		"detail_density": 0.40,                      # pics larges et espacés
		"anim_speed":     0.7,
		"glow_amount":    0.0,                        # ni lucioles ni fenêtres
	},
	"city": {     # Rue médiévale pavée — bâtiments bas, torches tamisées (côté Héros)
		"u_mode":         1,
		"sky_top":        Color(0.10, 0.08, 0.11),
		"sky_bottom":     Color(0.22, 0.17, 0.14),
		"layer_far":      Color(0.11, 0.09, 0.08),
		"layer_mid":      Color(0.07, 0.05, 0.05),
		"layer_near":     Color(0.03, 0.02, 0.02),
		"fog_color":      Color(0.40, 0.33, 0.27),
		"accent":         Color(1.00, 0.60, 0.25),   # torches / bougies (chaud)
		"fog_density":    0.42,
		"detail_density": 0.70,                      # bâtiments bas et larges
		"anim_speed":     0.80,
		"glow_amount":    0.75,                       # torches visibles mais tamisées
	},
}

# Mapping id de biome (.tres) → preset. Inconnu → "forest".
static func preset_for_biome(biome_id: String) -> String:
	match biome_id:
		"biome_foret":    return "forest"
		"biome_marecage": return "marsh"
		"biome_montagne": return "mountain"
		_:                return "forest"

# Couleur d'accent du biome (lucioles / feux follets / lueur des pics).
# Sert aussi à teinter le séparateur VS de la scène de combat.
static func accent_for_biome(biome_id: String) -> Color:
	return PRESETS[preset_for_biome(biome_id)]["accent"]

# État désiré, mémorisé même si le material n'existe pas encore (appels avant
# _ready, ex. quand le nœud n'est pas encore dans l'arbre). _ready() réapplique tout.
var _preset_id     := "forest"
var _split_side    := 0
var _split_band_px := 80.0   # largeur de la bande VS (pour caler la pente)
var _zone          := 0      # valeur Enums.Zone

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	material = mat
	_apply_preset_params()
	_apply_split()
	_apply_zone()
	# La pente de la découpe dépend de la largeur réelle du fond.
	resized.connect(_apply_split)

# Applique une palette de biome (clé de PRESETS). Inconnu → fallback "forest".
func apply_preset(preset_id: String) -> void:
	_preset_id = preset_id if PRESETS.has(preset_id) else "forest"
	_apply_preset_params()

func _apply_preset_params() -> void:
	if material == null:
		return
	for key in PRESETS[_preset_id]:
		material.set_shader_parameter(key, PRESETS[_preset_id][key])

# Restreint le rendu à un côté de la diagonale VS.
#   0 = plein écran ; 1 = côté héros (gauche) ; 2 = côté créature (droite).
# band_px = largeur de la bande du séparateur CombatVS : la diagonale du
# shader doit parcourir EXACTEMENT cette largeur sur toute la hauteur,
# sinon les deux fonds débordent de part et d'autre de la ligne.
func set_split(side: int, band_px: float = 80.0) -> void:
	_split_side    = side
	_split_band_px = band_px
	_apply_split()

func _apply_split() -> void:
	if material == null:
		return
	material.set_shader_parameter("split_side", _split_side)
	# Pente = bande / largeur : décalage horizontal total de la diagonale
	# (haut → bas) égal à la largeur de la bande VS, quelle que soit la
	# taille du fond (recalculé à chaque resize).
	if _split_side != 0 and size.x > 0.0:
		material.set_shader_parameter("split_tilt", _split_band_px / size.x)

# Règle l'intensité d'obscurité/brouillard selon la zone (Enums.Zone).
# Surface → clair ; Profondeur → assombri ; Abysse → très sombre + brouillard dense.
func set_zone(zone: int) -> void:
	_zone = zone
	_apply_zone()

func _apply_zone() -> void:
	if material == null:
		return
	var darken := 0.0
	match _zone:
		Enums.Zone.PROFONDEUR: darken = 0.45
		Enums.Zone.ABYSSE:     darken = 0.85
		_:                     darken = 0.0
	material.set_shader_parameter("zone_darken", darken)
