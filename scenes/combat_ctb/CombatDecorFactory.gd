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
#    cadrage — pas de `REDUCTION_PLANS`/pivot à gérer. MÊME formule de calage
#    du sol que la ville (`DECOR_SOL_FRAC`, milieu de bande, sans réduction) :
#    c'est la ville qui fait AUTORITÉ sur la hauteur du sol (28/08/2026,
#    signalé par Rhend) — dévier de cette recette (testé : dézoomer pour
#    élargir le champ) décale le sol par rapport à elle, même en pivotant
#    pile sur le point d'ancrage. Le crop est donc serré (une seule des trois
#    tours du fourneau visible à la fois) — c'est le prix de l'alignement.
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
# des lignes 1895 à 2655 sur 2655). MÊME convention que CombatDecorCity : les
# pieds tombent au MILIEU de cette bande, pas sur son arête — c'est cette
# convention, identique des deux côtés, qui garantit que le sol des deux
# décors tombe à la MÊME hauteur écran (la ville fait autorité, 28/08/2026,
# signalé par Rhend). Ne pas dévier de ce point d'ancrage : tout élargissement
# du champ (REDUCTION ci-dessous) doit pivoter EXACTEMENT dessus, sinon le
# sol se décale.
const SOL_HAUT_FRAC := 0.7137
const SOL_BAS_FRAC := 1.0
const DECOR_SOL_FRAC := (SOL_HAUT_FRAC + SOL_BAS_FRAC) * 0.5

const HAZE_COLOR := Color(0.55, 0.62, 0.74)
const HAZE_MAX := 0.30

const FEU_ALPHA_MIN := 0.55
const FEU_ALPHA_MAX := 1.0
const FEU_ECLAT_MAX := 0.35   # boost RGB au pic, pour un flamboiement plus chaud qu'un simple fondu

# Chariots de la Chaîne_Soudure : espacement MESURÉ (7 chariots sur le
# canevas, ~670 px d'écart en moyenne, le premier centré vers x=315) — sert à
# synchroniser le bras soudeur (voir BRAS_* et `_bras` plus bas). Approximatif
# par nature (l'espacement réel varie de 660 à 710 px) : suffisant pour un
# geste qui a l'air synchronisé, pas pour un pixel-perfect — à peaufiner.
const CHARIOT_PERIODE_TEX := 670.0
const CHARIOT_PHASE_TEX := 315.0
# Point de contact du bras = centre mesuré de Plan_5_Soudeur_1_Bras.png.
const BRAS_CONTACT_X_TEX := 789.5
const BRAS_AMPLITUDE_PX := 16.0   # descente du bras à l'impact, en pixels écran
const BRAS_LARGEUR_S := 0.12      # largeur du geste (gaussienne), en secondes

# Plans du PLUS LOINTAIN au plus proche (ordre d'empilement). `sens` : +1 =
# droite→gauche (comme la ville), -1 = gauche→droite ; ignoré si vitesse = 0.
# `feu` : calque de flamme, flicker géré à part (voir `_feux`). `bras` : bras
# soudeur, geste vertical géré à part (voir `_bras`) — synchronisé sur le
# défilement de la Chaîne_Soudure, qui doit donc être bâtie AVANT lui (ordre
# du tableau : Chaîne_Soudure précède Soudeur_1_Bras).
#
# LOGIQUE DE DÉFILEMENT (28/08/2026, harmonisée à la demande de Rhend) : les
# TROIS plans de la chaîne de production ROBOTS (5 → 4 → 3, les plus
# lisibles de la scène) alternent > < > pour lire comme une vraie chaîne de
# montage en zigzag. Le Fourneau (même profondeur que la Chaîne_Robotique du
# plan 3) suit la MÊME direction que son voisin de plan, mais plus lentement
# (parallaxe à deux vitesses sur une même profondeur, déjà le principe des
# calques néon de la ville) — ses 3 foyers le SUIVENT à l'identique pour
# rester calés sur les fenêtres du fourneau. Les autres calques (Barrière,
# Sol, Armature, Soudeurs, Chaîne_Soudure) n'ont pas cette contrainte de
# cohérence : Chaîne_Soudure défile pour elle-même (le convoyeur qui amène
# les chariots au bras soudeur).
const PLANS: Array[Dictionary] = [
	{"f": "Background_Factory_Plan_Fond.png",               "profondeur": 0.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Chaine_Soudure.png",   "profondeur": 0.25, "vitesse": 80.0, "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_1.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_1_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": true},
	{"f": "Background_Factory_Plan_5_Soudeur_2.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_2_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Chaine_Robotique.png", "profondeur": 0.25, "vitesse": 4.0,  "sens": -1.0, "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_4_Armature.png",         "profondeur": 0.45, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_4_Chaine_Robotique.png", "profondeur": 0.45, "vitesse": 7.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_3_Chaine_Robotique.png", "profondeur": 0.70, "vitesse": 12.0, "sens": -1.0, "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_3_Fourneau.png",         "profondeur": 0.70, "vitesse": 3.0,  "sens": -1.0, "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_1.png",   "profondeur": 0.70, "vitesse": 3.0,  "sens": -1.0, "feu": true,  "bras": false},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_2.png",   "profondeur": 0.70, "vitesse": 3.0,  "sens": -1.0, "feu": true,  "bras": false},
	{"f": "Background_Factory_Plan_3_Fourneau_Feu_3.png",   "profondeur": 0.70, "vitesse": 3.0,  "sens": -1.0, "feu": true,  "bras": false},
	{"f": "Background_Factory_Plan_2_Barriere.png",         "profondeur": 1.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_2_Sol.png",              "profondeur": 1.00, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
]

var _noeud_zoom: Control = null
var _couches: Array[Dictionary] = []
var _feux: Array[Dictionary] = []   # {noeud, phase} — sous-ensemble de _couches
var _bras: Array[Dictionary] = []   # {noeud, t0, periode} — sous-ensemble de _couches
var _temps := 0.0
var _mask_material: ShaderMaterial = null
var _soudure_vitesse := 0.0   # captées en bâtissant Chaîne_Soudure, réutilisées pour le bras
var _soudure_sens := 1.0
var _couvre := 1.0

static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		bande_vs_px: float, vue: Vector2 = Vector2(1280, 720)) -> CombatDecorFactory:
	var decor := CombatDecorFactory.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor._noeud_zoom = parent
	decor._mask_material = ShaderMaterial.new()
	decor._mask_material.shader = load(MASK_SHADER)
	decor._mask_material.set_shader_parameter("split_tilt", bande_vs_px / maxf(vue.x, 1.0))
	# Même formule que CombatDecorCity, avec DECOR_SOL_FRAC (milieu de bande) :
	# c'est CE calcul, identique des deux côtés, qui garantit que le sol tombe
	# à la même hauteur écran que la ville.
	var h := maxf(vue.y * sol_y_frac / DECOR_SOL_FRAC,
			vue.y * (1.0 - sol_y_frac) / (1.0 - DECOR_SOL_FRAC))
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	decor.offset_top = haut
	decor.offset_bottom = haut + h - vue.y
	decor._batir(vue.x, h, vue.x * sol_x_frac)
	parent.add_child(decor)
	return decor

func _batir(larg: float, haut: float, centre_x: float) -> void:
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
			_couvre = cadre.size.x / maxf(texture.get_size().x, 1.0)
		var vitesse := float(plan["vitesse"])
		var sens := float(plan["sens"])
		if str(plan["f"]) == "Background_Factory_Plan_5_Chaine_Soudure.png":
			_soudure_vitesse = vitesse
			_soudure_sens = sens
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
		if bool(plan["bras"]):
			_bras.append(_bras_synchro(noeud))

static func _cadre_couverture(taille_texture: Vector2, larg: float, haut: float, centre_x: float) -> Rect2:
	if taille_texture.x <= 0.0 or taille_texture.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(larg, haut))
	var couvre := maxf(larg / taille_texture.x, haut / taille_texture.y)
	var taille := taille_texture * couvre
	return Rect2(Vector2(centre_x - taille.x * 0.5, (haut - taille.y) * 0.5), taille)

# Calcule à quel instant (dans le repère de _temps) un chariot de la
# Chaîne_Soudure passe sous le point de contact du bras, et à quel intervalle
# ça se reproduit — dérivé du sens/vitesse de la Chaîne_Soudure (captés
# pendant sa construction, forcément AVANT le bras dans `PLANS`) convertis en
# pixels TEXTURE (divisés par `_couvre`) pour raisonner dans le référentiel où
# CHARIOT_PERIODE_TEX/CHARIOT_PHASE_TEX ont été mesurés.
func _bras_synchro(noeud: Node2D) -> Dictionary:
	var vitesse_tex := _soudure_vitesse / maxf(_couvre, 0.0001)
	if vitesse_tex <= 0.0:
		return {"noeud": noeud, "t0": 0.0, "periode": 1.0e9}   # pas de défilement : jamais de geste
	var cible := fposmod(CHARIOT_PHASE_TEX - BRAS_CONTACT_X_TEX, CHARIOT_PERIODE_TEX)
	if _soudure_sens < 0.0:
		cible = fposmod(-cible, CHARIOT_PERIODE_TEX)
	var periode := CHARIOT_PERIODE_TEX / vitesse_tex
	return {"noeud": noeud, "t0": cible / vitesse_tex, "periode": periode}

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
	for b in _bras:
		var noeud: Node2D = b["noeud"]
		var periode: float = b["periode"]
		var phase := fposmod(_temps - float(b["t0"]), periode)
		if phase > periode * 0.5:
			phase -= periode
		var frappe := exp(-pow(phase / BRAS_LARGEUR_S, 2.0))
		noeud.position.y += frappe * BRAS_AMPLITUDE_PX

# Flicker organique (deux sinusoïdes, pas un pouls régulier) — un flamboiement
# de fourneau, pas un néon qui clignote.
static func _flicker(t: float, phase: float) -> float:
	var s1 := 0.5 + 0.5 * sin(t * 1.7 + phase)
	var s2 := 0.5 + 0.5 * sin(t * 4.3 + phase * 1.7)
	return clampf(0.55 * s1 + 0.45 * s2, 0.0, 1.0)
