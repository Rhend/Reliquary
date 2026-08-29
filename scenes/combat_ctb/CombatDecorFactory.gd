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
#  • HAUTEUR NATURELLE, pas la couverture "sans trou" de CombatDecorCity
#    (28/08/2026, signalé par Rhend : plein écran ET sans masque, on ne
#    voyait toujours pas tout le travail de Christophe). La formule de la
#    ville (h = de quoi couvrir l'écran ENTIER, pieds compris, sans jamais
#    montrer de trou) suppose implicitement que la bande de sol de l'image
#    tombe À PEU PRÈS à `sol_y_frac` — ce n'est pas le cas ici (bande mesurée
#    à 85,7 % de la hauteur du canevas contre 80,6 % voulu), et cet écart de
#    5 points oblige à grossir TOUTE l'image d'environ 35 % pour que le
#    peu de canevas sous le sol (14,3 %) couvre quand même les 19,4 %
#    d'écran requis sous les pieds — ce grossissement, uniforme, emporte
#    aussi la largeur avec lui : c'est LUI qui rognait les tours latérales,
#    pas le split. Ici `h` = la hauteur ÉCRAN telle quelle (720, aucun
#    gonflage) : l'image couvre presque toute la largeur (~99 %), et le
#    sol tombe pile où il faut (pivot exact, comme avant). Le prix : un
#    petit vide en bas (voir GAP_BAS_SECOURS) là où la fine bande sous le
#    sol de Christophe n'est plus assez étirée pour atteindre le bord de
#    l'écran — comblé par un aplat de la couleur EXACTE du bas de
#    Plan_2_Sol.png (mesurée : (38,11,12), plate, donc invisible en pratique).
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
#  • SOUDURE CHORÉGRAPHIÉE (29/08/2026, demandé par Rhend) : Soudeur_1 reste à
#    sa position D'ORIGINE (le décalage tenté puis annulé — SUPERSÉDÉ, voir
#    l'historique git si besoin de le ressortir). Le bras ANIMÉ est celui de
#    SOUDEUR_2 (confirmé par Rhend : la grue déjà bien visible, jamais
#    masquée). La Chaîne_Soudure ne défile plus en continu : un vrai CYCLE
#    (`CYCLE_PERIODE_S`, 5 s) alterne défilement et arrêt — la chaîne
#    s'immobilise avec un chariot pile sous le bras. ⚠ Le bras PIVOTE (29/08,
#    2ᵉ retour de Rhend : « la tête doit descendre selon l'axe logique avec le
#    pivot central, pas tout le sprite qui translate ») — ROTATION du sprite
#    `Soudeur_2_Bras` autour du centre mesuré de son rond d'épaule
#    (`PIVOT_LOCAL`), via le classique décalage `offset = -pivot` + repositionnement
#    (voir `_batir`) : aucun redécoupage d'asset requis, un seul calque suffit
#    tant que la base de l'épaule ne s'étend pas loin du rond. Un VFX
#    d'étincelles (`FactorySoudureVfx`) se déclenche au contact — sa position
#    locale suit AUTOMATIQUEMENT la rotation puisqu'elle est posée en ENFANT
#    du sprite, au bon décalage du pivot. Voir CHARIOT_*/BRAS_*/CYCLE_*/VFX_*
#    et `_process_bras`.
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

# Couleur EXACTE du bas de Background_Factory_Plan_2_Sol.png (mesurée, plate
# sur toute la bande basse) — comble le petit vide que laisse la hauteur
# naturelle (voir commentaire de tête). Plate → indiscernable du vrai sol.
const SOL_SECOURS_COLOR := Color8(38, 11, 12)

# Chariots de la Chaîne_Soudure : espacement et phase MESURÉS directement sur
# Background_Factory_Plan_5_Chaine_Soudure.png (canevas natif 3256 px — PAS le
# canevas 4770 px des plans Barrière/Sol). 7 chariots, ~461 px d'écart en
# moyenne (varie de 450 à 488 : l'art n'est pas une grille parfaite ; la
# moyenne suffit car le défilement avance de PILE une période par cycle, voir
# `_process`). Premier chariot centré vers x=218.
const CHARIOT_PERIODE_TEX := 461.33
const CHARIOT_PHASE_TEX := 218.5

# ─── GÉOMÉTRIE DU BRAS SOUDEUR (Soudeur_2, 29/08/2026) ──────
# Le bras est UN SEUL calque (corps+coude+avant-bras+embout fondus dans la
# même image) : Christophe n'a pas (encore) séparé l'avant-bras de l'épaule.
# Plutôt que de translater tout le sprite (1er essai, rejeté par Rhend — « la
# tête doit descendre selon l'axe logique avec le pivot central, pas tout le
# sprite ») on fait PIVOTER le sprite entier autour du rond d'épaule mesuré
# sur l'image (`PIVOT_LOCAL`) : le classique décalage `Sprite2D.offset =
# -pivot` + repositionnement (voir `_batir`) fait qu'une rotation du NŒUD
# tourne autour de ce point précis plutôt que du coin de l'image. Ça bouge
# aussi un peu la base/le coude (ils ne sont pas exactement SUR le pivot),
# mais leur bras de levier est bien plus court que celui de l'embout — visuel
# largement plus juste qu'une translation verticale pure. Si le résultat ne
# convainc toujours pas, la vraie correction est de demander à Christophe de
# séparer l'avant-bras (pivote) de l'épaule (fixe) en deux calques.
#
# Mesurés sur Background_Factory_Plan_5_Soudeur_2_Bras.png (bbox natif
# 1858-2058 × 728-984) :
#   PIVOT_LOCAL   = centre du rond d'épaule (le plus gros des deux joints).
#   BRAS_POINTE_LOCAL = extrémité de la fourche de soudure (pixel le plus à
#                   DROITE de l'image — un bras qui reproche vers le bas-
#                   droite, pas le plus BAS, qui tombe sur le pied du socle).
const PIVOT_LOCAL := Vector2(1958.0, 748.0)
const BRAS_POINTE_LOCAL := Vector2(2057.0, 830.5)

# Amplitude de la rotation à l'impact (radians). 0.5236 rad = 30° : fait
# parcourir à la pointe un arc de ~35 px NATIFS (mesuré depuis PIVOT_LOCAL et
# BRAS_POINTE_LOCAL), comparable à l'ancienne translation de 16 px écran — à
# ajuster « au feel ».
const BRAS_ANGLE_MAX := 0.5236

# Point de CONTACT du bras — PAS sa position au repos : c'est la pointe de
# l'embout une fois tournée de BRAS_ANGLE_MAX autour de PIVOT_LOCAL, calculée
# à la main (PIVOT_LOCAL + rotation(BRAS_POINTE_LOCAL - PIVOT_LOCAL,
# BRAS_ANGLE_MAX)) — c'est CE point qui doit tomber sur un chariot, pas le
# centre du sprite au repos (⚠ CORRIGÉ 29/08/2026 : le centre du bbox donnait
# un chariot visiblement décalé du bras une fois celui-ci penché).
const BRAS_CONTACT_X_TEX := 2002.4

# ─── CYCLE DE SOUDURE (29/08/2026, demandé par Rhend) ───────
# Avant : le bras battait en continu pendant que la Chaîne_Soudure défilait
# sans jamais s'arrêter — une approximation. Désormais un VRAI temps d'arrêt :
# la chaîne s'immobilise, un chariot se retrouve pile sous le bras, celui-ci
# descend le souder (étincelles), remonte, puis la chaîne repart. Un cycle
# dure CYCLE_PERIODE_S secondes : une fenêtre de DÉFILEMENT puis une fenêtre
# d'ARRÊT (somme des trois temps du bras ci-dessous) :
#     défilement → [descente → contact (VFX) → remontée] → défilement → …
# Le défilement avance de PILE UNE période de chariot (CHARIOT_PERIODE_TEX)
# par cycle, jamais plus ni moins : le chariot suivant arrive donc exactement
# là où le précédent s'est arrêté, cycle après cycle, sans dérive cumulée.
# ⚠ Simplification assumée : le cycle s'arrête sur LE chariot qui se trouve
# là au bon moment, sans distinguer les chariots « robot » des chariots
# « ferraille » du décor de Christophe — un raffinement pour plus tard si le
# feel le demande, pas un pré-requis pour un décor qui a l'air vivant.
const CYCLE_PERIODE_S := 5.0
const BRAS_DESCENTE_S := 0.3
# Durée du CONTACT — et donc du VFX d'étincelles, qui dure exactement le temps
# où le bras reste posé sur le robot. Constante SÉPARÉE de BRAS_DESCENTE_S/
# BRAS_REMONTEE_S : à ajuster seule « au feel » sans retoucher le geste du bras.
const VFX_ETINCELLES_DUREE_S := 2.0
const BRAS_REMONTEE_S := 0.3
const BRAS_ARRET_S := BRAS_DESCENTE_S + VFX_ETINCELLES_DUREE_S + BRAS_REMONTEE_S

# Plans du PLUS LOINTAIN au plus proche (ordre d'empilement). `sens` : +1 =
# droite→gauche (comme la ville), -1 = gauche→droite ; ignoré si vitesse = 0.
# `feu` : calque de flamme, flicker géré à part (voir `_feux`). `bras` : bras
# soudeur ANIMÉ — Soudeur_2_Bras — géré à part (voir `_process_bras`, pivote
# autour de `PIVOT_LOCAL`) — phase-locké sur le cycle d'arrêt de la Chaîne_
# Soudure, qui doit donc être bâtie AVANT lui (ordre du tableau). `soudure` :
# marque LE calque de la Chaîne_Soudure, dont le défilement n'est plus géré
# par `vitesse` (générique) mais par le cycle CYCLE_* — `vitesse` y reste
# purement documentaire (vitesse moyenne visuelle du convoyeur avant ce
# chantier). Soudeur_1 est resté à sa position D'ORIGINE (le décalage tenté a
# été annulé, voir l'en-tête du fichier).
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
	{"f": "Background_Factory_Plan_5_Chaine_Soudure.png",   "profondeur": 0.25, "vitesse": 80.0, "sens": 1.0,  "feu": false, "bras": false, "soudure": true},
	{"f": "Background_Factory_Plan_5_Soudeur_1.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_1_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_2.png",        "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": false},
	{"f": "Background_Factory_Plan_5_Soudeur_2_Bras.png",   "profondeur": 0.25, "vitesse": 0.0,  "sens": 1.0,  "feu": false, "bras": true},
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
var _bras_noeud: Node2D = null      # noeud du calque "bras" animé (celui qui porte "bras": true — Soudeur_2_Bras)
var _bras_sprite: Sprite2D = null   # son sprite direct — parent du VFX d'étincelles
var _temps := 0.0
var _mask_material: ShaderMaterial = null
var _split_tilt := 0.0   # copie de bande_vs_px/vue.x — réutilisée par le VFX d'étincelles
var _soudure_d0_tex := 0.0    # décalage-texture initial du cycle, voir `_calcule_d0_soudure`
var _vfx_dernier_cycle := -1  # évite de redéclencher le VFX plusieurs fois dans le même cycle
var _couvre := 1.0

static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		bande_vs_px: float, vue: Vector2 = Vector2(1280, 720)) -> CombatDecorFactory:
	var decor := CombatDecorFactory.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor._noeud_zoom = parent
	decor._mask_material = ShaderMaterial.new()
	decor._mask_material.shader = load(MASK_SHADER)
	decor._split_tilt = bande_vs_px / maxf(vue.x, 1.0)
	decor._mask_material.set_shader_parameter("split_tilt", decor._split_tilt)
	# Hauteur NATURELLE (720, pas gonflée) : voir le commentaire de tête pour
	# pourquoi la formule "couverture sans trou" de la ville ne convient pas
	# ici. Le pivot du sol (DECOR_SOL_FRAC) reste inchangé — c'est lui qui
	# garantit l'alignement avec la ville, indépendamment de `h`.
	var h := vue.y
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	decor.offset_top = haut
	decor.offset_bottom = haut + h - vue.y
	decor._batir(vue.x, h, vue.x * sol_x_frac)
	# Vide résiduel (voir commentaire de tête) : un aplat par bord concerné,
	# en LOCAL (0 = haut du cadre bâti par `_batir`, h = son bas).
	if haut > 0.0:
		decor._patch_secours(Rect2(0.0, -haut, vue.x, haut))
	var bas := vue.y - haut - h
	if bas > 0.0:
		decor._patch_secours(Rect2(0.0, h, vue.x, bas))
	parent.add_child(decor)
	return decor

# Aplat de secours masqué (même écrêtage adverse que le reste) : comble un
# vide de couverture sans jamais recouvrir le contenu réel (ajouté APRÈS
# `_batir`, donc par-dessus rien d'autre — il n'y a rien d'autre là où il est).
func _patch_secours(rect: Rect2) -> void:
	var r := ColorRect.new()
	r.color = SOL_SECOURS_COLOR
	r.position = rect.position
	r.size = rect.size
	r.material = _mask_material
	add_child(r)

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
		var est_soudure := bool(plan.get("soudure", false))
		if est_soudure:
			_soudure_d0_tex = _calcule_d0_soudure(sens)
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
		var est_bras := bool(plan["bras"])
		# Dernière copie créée : suffisant pour "bras" (toujours vitesse 0, donc
		# une SEULE copie — idx_min == idx_max == 0), pas de sens à désambiguïser.
		var derniere_copie: Sprite2D = null
		for i in range(idx_min, idx_max + 1):
			var sp := _calque(texture, cadre.size, Vector2(cadre.size.x * i, 0.0))
			if est_bras:
				# Décale le DESSIN du sprite pour que PIVOT_LOCAL tombe sur
				# l'origine du nœud, puis repousse le nœud d'autant pour que le
				# rendu reste identique à zéro rotation — c'est CE point qui
				# reste fixe quand `_process_bras` tourne le sprite (voir l'en-
				# tête du fichier, section « GÉOMÉTRIE DU BRAS SOUDEUR »).
				sp.offset = -PIVOT_LOCAL
				sp.position += PIVOT_LOCAL * sp.scale
			sp.material = _mask_material
			noeud.add_child(sp)
			derniere_copie = sp
		add_child(noeud)
		_couches.append({
			"noeud": noeud,
			"profondeur": float(plan["profondeur"]),
			"vitesse": vitesse,
			"sens": sens,
			"origine": cadre.position,
			"boucle_px": cadre.size.x,
			"soudure": est_soudure,
		})
		if bool(plan["feu"]):
			_feux.append({"noeud": noeud, "phase": float(idx_feu) * 2.39996})
			idx_feu += 1
		if est_bras:
			_bras_noeud = noeud
			_bras_sprite = derniere_copie

# Décalage-texture initial du défilement de la Chaîne_Soudure, choisi pour
# que la PREMIÈRE fenêtre de défilement (t=0) amène déjà un chariot pile sous
# le bras au premier arrêt. Toute multiple de CHARIOT_PERIODE_TEX ajoutée
# ensuite (voir `_process`) reste congrue, donc l'alignement se répète à
# chaque cycle sans dérive.
static func _calcule_d0_soudure(sens: float) -> float:
	var cible := fposmod(CHARIOT_PHASE_TEX - BRAS_CONTACT_X_TEX, CHARIOT_PERIODE_TEX)
	if sens < 0.0:
		cible = fposmod(-cible, CHARIOT_PERIODE_TEX)
	return cible

static func _cadre_couverture(taille_texture: Vector2, larg: float, haut: float, centre_x: float) -> Rect2:
	if taille_texture.x <= 0.0 or taille_texture.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(larg, haut))
	var couvre := maxf(larg / taille_texture.x, haut / taille_texture.y)
	var taille := taille_texture * couvre
	return Rect2(Vector2(centre_x - taille.x * 0.5, (haut - taille.y) * 0.5), taille)

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

	var t_defilement_s := CYCLE_PERIODE_S - BRAS_ARRET_S
	var cycle_index := floori(_temps / CYCLE_PERIODE_S)
	var t_cycle := fposmod(_temps, CYCLE_PERIODE_S)
	# Progression du défilement DANS ce cycle : 0→1 pendant la fenêtre de
	# défilement, puis PLAFONNÉE à 1 (chaîne figée) pendant l'arrêt.
	var progres := clampf(t_cycle / maxf(t_defilement_s, 0.0001), 0.0, 1.0)
	var d_soudure_tex := _soudure_d0_tex + (float(cycle_index) + progres) * CHARIOT_PERIODE_TEX

	for couche in _couches:
		var noeud: Node2D = couche["noeud"]
		var origine: Vector2 = couche["origine"]
		var boucle: float = couche["boucle_px"]
		if bool(couche.get("soudure", false)):
			# La Chaîne_Soudure ne suit plus `vitesse` : son défilement est
			# entièrement piloté par le cycle d'arrêt (voir plus haut).
			origine.x -= fmod(d_soudure_tex * _couvre, boucle) * float(couche["sens"])
		else:
			var vitesse: float = couche["vitesse"]
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

	_process_bras(t_cycle - t_defilement_s, cycle_index)

# Descente → contact (VFX d'étincelles) → remontée du bras soudeur, PENDANT
# la fenêtre d'ARRÊT du cycle seulement (`t_arret` < 0 : la chaîne défile
# encore, le bras reste au repos, angle nul). PIVOTE le SPRITE (`_bras_sprite`,
# voir `_batir`), pas le nœud de parallaxe : la rotation ne doit pas se
# mélanger avec le défilement/zoom/brume déjà posés sur `_bras_noeud`.
func _process_bras(t_arret: float, cycle_index: int) -> void:
	if not is_instance_valid(_bras_sprite):
		return
	var angle := 0.0
	var contact := false
	if t_arret >= 0.0:
		if t_arret < BRAS_DESCENTE_S:
			angle = _ease_out(t_arret / BRAS_DESCENTE_S) * BRAS_ANGLE_MAX
		elif t_arret < BRAS_DESCENTE_S + VFX_ETINCELLES_DUREE_S:
			angle = BRAS_ANGLE_MAX
			contact = true
		elif t_arret < BRAS_ARRET_S:
			var k := (t_arret - BRAS_DESCENTE_S - VFX_ETINCELLES_DUREE_S) / BRAS_REMONTEE_S
			angle = (1.0 - _ease_out(clampf(k, 0.0, 1.0))) * BRAS_ANGLE_MAX
	_bras_sprite.rotation = angle
	if contact and cycle_index != _vfx_dernier_cycle:
		_vfx_dernier_cycle = cycle_index
		_declencher_etincelles()

func _declencher_etincelles() -> void:
	if not is_instance_valid(_bras_sprite):
		return
	# Position LOCALE relative à l'origine du sprite, qui est désormais le
	# PIVOT (voir `sp.offset = -PIVOT_LOCAL` dans `_batir`) — un enfant posé au
	# décalage pivot→pointe suit donc AUTOMATIQUEMENT la rotation du bras,
	# sans recalcul : au moment du contact, `_bras_sprite.rotation` vaut déjà
	# BRAS_ANGLE_MAX, donc le VFX apparaît pile là où retombe la pointe tournée.
	FactorySoudureVfx.declencher(_bras_sprite, BRAS_POINTE_LOCAL - PIVOT_LOCAL,
			VFX_ETINCELLES_DUREE_S, _split_tilt)

# Ease-out quadratique : geste mécanique rapide au départ, adouci à l'arrivée
# — pour la descente ET la remontée (celle-ci l'utilise inversé, voir plus haut).
static func _ease_out(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)

# Flicker organique (deux sinusoïdes, pas un pouls régulier) — un flamboiement
# de fourneau, pas un néon qui clignote.
static func _flicker(t: float, phase: float) -> float:
	var s1 := 0.5 + 0.5 * sin(t * 1.7 + phase)
	var s2 := 0.5 + 0.5 * sin(t * 4.3 + phase * 1.7)
	return clampf(0.55 * s1 + 0.45 * s2, 0.0, 1.0)
