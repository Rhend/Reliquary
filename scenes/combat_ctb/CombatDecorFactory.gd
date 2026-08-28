# ============================================================
# CombatDecorFactory — décor RÉEL de l'Usine (Christophe, 28/08/2026), côté
# ADVERSE de la scène de combat CTB. Remplace le placeholder procédural
# `BiomeBackground("forest")` : même canevas 4770×2655 que la ville
# (`CombatDecorCity`), mêmes techniques (plans parallaxés compensant le zoom-
# duel, ruban de copies pour le défilement horizontal en boucle) — voir les
# commentaires de CombatDecorCity pour le détail de ces deux effets, non
# répétés ici.
#
# Différences avec CombatDecorCity :
#  • Un seul cadre de couverture (`_cadre`), calculé UNE fois : chaque .png
#    livré est le canevas COMPLET de la scène (pas une découpe d'immeuble à
#    part), donc tous les plans se superposent avec exactement le même
#    cadrage — pas de `REDUCTION_PLANS`/pivot à gérer.
#  • ÉCRÊTAGE à la moitié adverse : ce décor est ajouté PAR-DESSUS le décor
#    héros (CombatDecorCity, dessiné en dessous par CombatFondScinde), donc
#    chaque sprite porte `raster_split_mask.gdshader` (alpha nul côté héros)
#    pour laisser transparaître la ville à gauche de la diagonale VS.
#  • DÉFILEMENT BIDIRECTIONNEL : `sens` (+1 droite→gauche comme la ville,
#    -1 gauche→droite) inverse simplement le signe du décalage. Une copie de
#    ruban SUPPLÉMENTAIRE est posée à gauche de la première (`idx_min = -1`)
#    pour ne jamais découvrir de bord côté gauche quand `sens = -1` fait
#    croître `origine.x` au lieu de décroître.
#  • FEU DU FOURNEAU : Christophe a isolé 3 foyers dans des .png séparés
#    (mêmes coordonnées que `Plan_3_Fourneau`, transparents ailleurs). Chacun
#    est son propre calque (même profondeur, vitesse 0) mais reçoit en plus
#    un flicker (alpha + éclat) piloté par `_process`, phase propre par foyer
#    pour ne pas pulser en bloc — l'usine doit paraître VIVANTE, pas
#    métronomique (même souci que le cycle des enseignes de CombatDecorCity).
# ============================================================
class_name CombatDecorFactory
extends Control

const DECOR_DIR := "res://assets/background/Factory/"
const MASK_SHADER := "res://scenes/combat_ctb/raster_split_mask.gdshader"

# Bande de SOL, MESURÉE sur Background_Factory_Plan_2_Sol.png (contenu opaque
# des lignes 1895 à 2655 sur 2655).
const SOL_HAUT_FRAC := 0.7137
const SOL_BAS_FRAC := 1.0
const DECOR_SOL_FRAC := (SOL_HAUT_FRAC + SOL_BAS_FRAC) * 0.5

const HAZE_COLOR := Color(0.55, 0.62, 0.74)
const HAZE_MAX := 0.30

const FEU_ALPHA_MIN := 0.55
const FEU_ALPHA_MAX := 1.0
const FEU_ECLAT_MAX := 0.35   # boost RGB au pic, pour un flamboiement plus chaud qu'un simple fondu

# Zoom arrière (28/08/2026, signalé par Rhend : "on ne voit pas toute la
# scène"). La couverture stricte (cadrage qui garantit zéro trou, dérivée de
# SOL_Y_FRAC/DECOR_SOL_FRAC comme pour la ville) cadre si serré qu'on ne voit
# plus qu'UNE tour du fourneau central sur les trois que Christophe a peintes
# côte à côte : contrairement aux immeubles de la ville (motif répété, un
# crop serré ou large se ressemble), l'Usine est UNE composition large avec
# des pièces maîtresses espacées — le crop serré en isole une seule.
# On réduit donc l'image, pivotée sur la ligne de sol (même recette que
# `REDUCTION_PLANS` de CombatDecorCity, poussée plus loin) pour élargir le
# champ. Ça découvre un vide au-dessus (le pivot est près du bas du cadre) :
# `_fond_secours` le comble d'une teinte proche du noir dominant de la scène
# (usine de nuit, silhouettes sombres) — invisible en pratique.
const REDUCTION := 0.55
const FOND_SECOURS := Color(0.035, 0.02, 0.018)

# Plans du PLUS LOINTAIN au plus proche (ordre d'empilement). `sens` : +1 =
# droite→gauche (comme la ville), -1 = gauche→droite ; ignoré si vitesse = 0.
# `feu` : calque de flamme, flicker géré à part (voir `_feux`).
const PLANS: Array[Dictionary] = [
	{"f": "Background_Factory_Plan_Fond.png",               "profondeur": 0.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Chaine_Soudure.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Soudeur_1.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Soudeur_1_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Soudeur_2.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Soudeur_2_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_5_Chaine_Robotique.png", "profondeur": 0.25, "vitesse": 4.0,  "sens": -1.0, "feu": false},
	{"f": "Background_Factory_Plan_4_Armature.png",         "profondeur": 0.45, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_4_Chaine_Robotique.png", "profondeur": 0.45, "vitesse": 7.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_3_Chaine_Robotique.png", "profondeur": 0.70, "vitesse": 12.0, "sens": -1.0, "feu": false},
	{"f": "Background_Factory_Plan_3_Fourneau.png",         "profondeur": 0.70, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_1.png",   "profondeur": 0.70, "vitesse": 0.0,  "sens": 1.0,  "feu": true},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_2.png",   "profondeur": 0.70, "vitesse": 0.0,  "sens": 1.0,  "feu": true},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_3.png",   "profondeur": 0.70, "vitesse": 0.0,  "sens": 1.0,  "feu": true},
	{"f": "Background_Factory_Plan_2_Barriere.png",         "profondeur": 1.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_2_Sol.png",              "profondeur": 1.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
	{"f": "Background_Factory_Plan_1_Barriere.png",         "profondeur": 1.15, "vitesse": 0.0,  "sens": 1.0,  "feu": false},
]

var _noeud_zoom: Control = null
var _couches: Array[Dictionary] = []
var _feux: Array[Dictionary] = []   # {noeud, phase} — sous-ensemble de _couches
var _temps := 0.0
var _mask_material: ShaderMaterial = null

static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		bande_vs_px: float, vue: Vector2 = Vector2(1280, 720)) -> CombatDecorFactory:
	var decor := CombatDecorFactory.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor._noeud_zoom = parent
	decor._mask_material = ShaderMaterial.new()
	decor._mask_material.shader = load(MASK_SHADER)
	decor._mask_material.set_shader_parameter("split_tilt", bande_vs_px / maxf(vue.x, 1.0))
	var h := maxf(vue.y * sol_y_frac / DECOR_SOL_FRAC,
			vue.y * (1.0 - sol_y_frac) / (1.0 - DECOR_SOL_FRAC))
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	decor.offset_top = haut
	decor.offset_bottom = haut + h - vue.y
	decor._batir(vue.x, h, vue.x * sol_x_frac)
	parent.add_child(decor)
	return decor

func _batir(larg: float, haut: float, centre_x: float) -> void:
	# Fond de secours : le zoom arrière (REDUCTION) laisse un vide au-dessus
	# de l'image réduite (pivot près du bas) — un rectangle plein comble ce
	# vide plutôt que de laisser transparaître le gris du nœud hôte.
	var secours := ColorRect.new()
	secours.color = FOND_SECOURS
	secours.position = Vector2.ZERO
	secours.size = Vector2(larg, haut)
	secours.material = _mask_material
	add_child(secours)

	# Un seul cadre de couverture : chaque .png EST le canevas complet de la
	# scène, donc tous les plans partagent le même cadrage (pas de "reduit").
	var cadre := Rect2()
	var cadre_pret := false
	var idx_feu := 0
	for plan in PLANS:
		var chemin: String = DECOR_DIR + str(plan["f"])
		if not ResourceLoader.exists(chemin):
			continue
		var texture: Texture2D = load(chemin)
		if texture == null:
			continue
		if not cadre_pret:
			cadre = _cadre_couverture(texture.get_size(), larg, haut, centre_x)
			cadre_pret = true
		var vitesse := float(plan["vitesse"])
		var sens := float(plan["sens"])
		var idx_min := 0
		var idx_max := 0
		if vitesse != 0.0 and cadre.size.x > 0.0:
			# Copie(s) vers la droite pour couvrir l'écran + 1 copie vers la
			# GAUCHE en réserve : le défilement peut faire croître OU décroître
			# `origine.x` selon `sens`, donc les deux bords doivent avoir une
			# marge, pas seulement celui que suit le défilement par défaut.
			idx_min = -1
			idx_max = maxi(int(ceil((larg - cadre.position.x) / cadre.size.x)), 1)
		var noeud := Node2D.new()
		noeud.modulate = _teinte_profondeur(float(plan["profondeur"]))
		for i in range(idx_min, idx_max + 1):
			var sp := _calque(texture, cadre.size, Vector2(cadre.size.x * i, 0.0))
			sp.material = _mask_material
			noeud.add_child(sp)
		add_child(noeud)
		_couches.append({
			"noeud": noeud,
			"profondeur": float(plan["profondeur"]),
			"vitesse": vitesse,
			"sens": sens,
			"origine": cadre.position,
			"boucle_px": cadre.size.x,
		})
		if bool(plan["feu"]):
			_feux.append({"noeud": noeud, "phase": float(idx_feu) * 2.39996})
			idx_feu += 1

static func _cadre_couverture(taille_texture: Vector2, larg: float, haut: float, centre_x: float) -> Rect2:
	if taille_texture.x <= 0.0 or taille_texture.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(larg, haut))
	var couvre := maxf(larg / taille_texture.x, haut / taille_texture.y)
	var taille := taille_texture * couvre
	var origine := Vector2(centre_x - taille.x * 0.5, (haut - taille.y) * 0.5)
	# Zoom arrière pivoté sur la ligne de sol : ce point-là doit rester à sa
	# place (c'est lui qui cale `haut`/`offset_top` à la construction), tout
	# le reste se réduit autour.
	var pivot := Vector2(centre_x, SOL_HAUT_FRAC * haut)
	return Rect2(pivot + (origine - pivot) * REDUCTION, taille * REDUCTION)

static func _teinte_profondeur(profondeur: float) -> Color:
	return Color.WHITE.lerp(HAZE_COLOR, HAZE_MAX * (1.0 - clampf(profondeur, 0.0, 1.0)))

static func _calque(texture: Texture2D, taille: Vector2, decalage: Vector2) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = texture
	sp.centered = false
	sp.position = decalage
	var source := texture.get_size()
	if source.x > 0.0 and source.y > 0.0:
		sp.scale = taille / source
	return sp

func _process(delta: float) -> void:
	_temps += delta
	var zoom := 1.0
	var foyer := Vector2.ZERO
	if is_instance_valid(_noeud_zoom):
		zoom = maxf(_noeud_zoom.scale.y, 0.001)
		foyer = _noeud_zoom.pivot_offset - position
	for couche in _couches:
		var noeud: Node2D = couche["noeud"]
		var origine: Vector2 = couche["origine"]
		var vitesse: float = couche["vitesse"]
		var boucle: float = couche["boucle_px"]
		if vitesse != 0.0 and boucle > 0.0:
			origine.x -= fmod(_temps * vitesse, boucle) * float(couche["sens"])
		var echelle := (1.0 + (zoom - 1.0) * float(couche["profondeur"])) / zoom
		noeud.position = foyer + (origine - foyer) * echelle
		noeud.scale = Vector2.ONE * echelle
	for feu in _feux:
		var noeud: Node2D = feu["noeud"]
		var intens := _flicker(_temps, float(feu["phase"]))
		var base: Color = _teinte_profondeur(0.70)
		var eclat := 1.0 + FEU_ECLAT_MAX * intens
		var alpha := FEU_ALPHA_MIN + (FEU_ALPHA_MAX - FEU_ALPHA_MIN) * intens
		noeud.modulate = Color(base.r * eclat, base.g * eclat, base.b * eclat, alpha)

# Flicker organique (deux sinusoïdes, pas un pouls régulier) — un flamboiement
# de fourneau, pas un néon qui clignote.
static func _flicker(t: float, phase: float) -> float:
	var s1 := 0.5 + 0.5 * sin(t * 1.7 + phase)
	var s2 := 0.5 + 0.5 * sin(t * 4.3 + phase * 1.7)
	return clampf(0.55 * s1 + 0.45 * s2, 0.0, 1.0)
