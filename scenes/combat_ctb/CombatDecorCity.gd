# ============================================================
# CombatDecorCity — décor de ville de Christophe, en plans PARALLAXÉS.
#
# Le décor est livré découpé en plans (Fond, 5, 4, 3, Sol) précisément pour
# donner de la profondeur. Jusqu'ici ils n'étaient qu'empilés : un seul bloc,
# une seule échelle, aucun bénéfice du découpage. Ce nœud leur rend leur rôle.
#
# DEUX effets, tous deux pilotés par `PLANS` :
#
#  • PROFONDEUR — pendant le zoom-duel, `CombatCtbUi` agrandit le bloc entier
#    (`_couche_scene.scale`). Chaque plan COMPENSE ce zoom au prorata de sa
#    distance : le sol suit les personnages (profondeur 1), la skyline
#    lointaine reste presque immobile (profondeur ~0). C'est ce différentiel
#    qui fait la sensation de distance pendant le punch-in.
#      échelle voulue = 1 + (zoom − 1) × profondeur
#      échelle posée  = voulue / zoom   (le parent applique déjà `zoom`)
#    Zoom à 1 → compensation à 1 : hors duel, rien ne bouge. La ShowRoom, dont
#    le parent ne zoome jamais, n'en voit donc que le défilement.
#
#  • DÉFILEMENT — les plans d'immeubles dérivent de droite à gauche, d'autant
#    plus lentement qu'ils sont loin. Vérifié sur la livraison : les plans 4 et
#    5 ont leurs colonnes de bord entièrement transparentes, et le plan 3 a un
#    écart gauche/droite de 0.0003 — le raccord est fait pour boucler. On pose
#    donc un RUBAN de copies jointives qu'on translate, et qui se replie sur
#    lui-même (fmod) sans jamais montrer de couture.
#
# ⚠ Node2D + Sprite2D, PAS des Control/TextureRect. Godot arrondit la position
# des Control au pixel entier (`gui/common/snap_controls_to_pixels`, vrai par
# défaut) : à 3 px/s, le plan le plus lointain avançait d'un pixel toutes les
# 0,33 s — un défilement visiblement saccadé. Les Node2D gardent une position
# flottante, donc un glissement continu.
#
# Le SOL ne défile pas : les personnages y sont posés, le faire glisser sous
# leurs pieds les ferait patiner. Les fonds de ciel non plus (rien à y voir
# bouger, et ils doivent couvrir tout le cadre en permanence).
# ============================================================
class_name CombatDecorCity
extends Control

const DECOR_DIR := "res://assets/background/city/"

# Bande de SOL dans l'image, MESURÉE sur Background_City_Plan_2_Sol.png : son
# contenu opaque occupe les lignes 1854 à 2654 sur 2655, soit le tiers bas.
# Deux repères, et non un seul, parce qu'ils ne servent pas à la même chose.
const SOL_HAUT_FRAC := 0.698   # arête ARRIÈRE du trottoir = base des immeubles
const SOL_BAS_FRAC := 1.000    # bord bas de l'image

# Où tombent les PIEDS des personnages : au MILIEU de la bande, pas sur son
# arête arrière (26/08/2026). Poser les pieds sur SOL_HAUT_FRAC les mettait
# tout au fond du trottoir, comme collés au pied des immeubles.
const DECOR_SOL_FRAC := (SOL_HAUT_FRAC + SOL_BAS_FRAC) * 0.5

# ⚠ Ce choix a un COÛT, et c'est lui qui fixe SOL_Y_FRAC côté combat : sous les
# pieds il ne reste plus que la moitié BASSE de la bande (15 % de l'image) pour
# couvrir tout le bas de l'écran. Plus les personnages sont haut, plus le décor
# doit être agrandi pour y arriver (voir le `maxf` de construire) — d'où des
# immeubles démesurés si on garde les pieds trop haut. `REDUCTION_PLANS` sert à
# rattraper cet agrandissement sur les seuls plans d'immeubles, le sol et le
# ciel devant, eux, rester assez grands pour couvrir.

# Réduction des plans d'IMMEUBLES pour dégager la vue d'ensemble (26/08/2026).
const REDUCTION_PLANS := 0.62

# Les plans, du PLUS LOINTAIN au plus proche — l'ordre d'empilement.
#   profondeur : réponse au zoom (0 = fixe, 1 = comme les personnages) ;
#   vitesse    : défilement horizontal en px/s, droite → gauche (0 = fixe) ;
#   reduit     : ce plan subit REDUCTION_PLANS.
# Les calques néon partagent profondeur ET vitesse de leur immeuble : sans ça
# les enseignes se décrocheraient de leur façade.
const PLANS: Array[Dictionary] = [
	{"f": "Background_City_Plan_Fond.png",               "profondeur": 0.00, "vitesse": 0.0,  "reduit": false},
	{"f": "Background_City_Plan_Fond_2.png",             "profondeur": 0.08, "vitesse": 0.0,  "reduit": false},
	{"f": "Background_City_Plan_5_Immeuble_01.png",      "profondeur": 0.25, "vitesse": 3.0,  "reduit": true},
	{"f": "Background_City_Plan_5_Immeuble_02.png",      "profondeur": 0.25, "vitesse": 3.0,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_01.png",      "profondeur": 0.45, "vitesse": 7.0,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_01_Neon.png", "profondeur": 0.45, "vitesse": 7.0,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_02.png",      "profondeur": 0.45, "vitesse": 7.0,  "reduit": true},
	{"f": "Background_City_Plan_3_Immeuble_01.png",      "profondeur": 0.70, "vitesse": 14.0, "reduit": true},
	{"f": "Background_City_Plan_3_Immeuble_01_Neon.png", "profondeur": 0.70, "vitesse": 14.0, "reduit": true},
	{"f": "Background_City_Plan_2_Sol.png",              "profondeur": 1.00, "vitesse": 0.0,  "reduit": false},
]

# Nœud dont il faut compenser le zoom (le `_couche_scene` de CombatCtbUi).
var _noeud_zoom: Control = null
# Un élément par plan : {noeud, profondeur, vitesse, origine, boucle_px}.
var _couches: Array[Dictionary] = []
var _temps := 0.0

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de calage
# du sol est volontairement en unités ABSOLUES, pas la taille réelle du nœud
# (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		vue: Vector2 = Vector2(1280, 720)) -> CombatDecorCity:
	var decor := CombatDecorCity.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor._noeud_zoom = parent
	# Cale le SOL du décor sur celui du combat, sans laisser de vide au cadre.
	# Décaler seul ne suffit pas : remonter le décor découvre le bas de l'écran.
	# On cherche donc la hauteur H telle que le sol tombe sur sol_y_frac ET que
	# le rectangle déborde des deux côtés — les deux contraintes donnent chacune
	# une hauteur minimale, on garde la plus grande.
	var h := maxf(vue.y * sol_y_frac / DECOR_SOL_FRAC,
			vue.y * (1.0 - sol_y_frac) / (1.0 - DECOR_SOL_FRAC))
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	decor.offset_top = haut
	decor.offset_bottom = haut + h - vue.y
	decor._batir(vue.x, h, vue.x * sol_x_frac)
	parent.add_child(decor)
	return decor

func _batir(larg: float, haut: float, centre_x: float) -> void:
	for plan in PLANS:
		var chemin: String = DECOR_DIR + str(plan["f"])
		if not ResourceLoader.exists(chemin):
			continue   # couche non livrée : on empile ce qui existe
		var texture: Texture2D = load(chemin)
		if texture == null:
			continue
		var cadre := _cadre(texture.get_size(), larg, haut, bool(plan["reduit"]), centre_x)
		var vitesse := float(plan["vitesse"])
		# Assez de copies pour couvrir [0, larg] MÊME quand le ruban a glissé
		# d'une tuile entière vers la gauche — d'où le « + 1 ». Le calcul part
		# de l'origine du cadre et non de 0 : depuis le recentrage sur le camp
		# joueur, cette origine est nettement plus à gauche, et compter sur la
		# seule largeur d'écran laisserait un trou à droite. Un plan fixe n'a
		# besoin que d'une copie.
		var copies := 1
		if vitesse != 0.0 and cadre.size.x > 0.0:
			copies = maxi(int(ceil((larg - cadre.position.x) / cadre.size.x)) + 1, 2)
		var noeud := Node2D.new()
		for i in copies:
			noeud.add_child(_calque(texture, cadre.size, Vector2(cadre.size.x * i, 0.0)))
		add_child(noeud)
		_couches.append({
			"noeud": noeud,
			"profondeur": float(plan["profondeur"]),
			"vitesse": vitesse,
			"origine": cadre.position,
			# Longueur d'une boucle = la largeur d'une copie : au bout d'un
			# glissement de cette longueur, le ruban est identique à lui-même.
			"boucle_px": cadre.size.x,
		})

# Rectangle d'un plan dans les coordonnées du décor. On reproduit à la main le
# cadrage qu'aurait produit KEEP_ASPECT_COVERED — image mise à l'échelle pour
# couvrir — puis, pour un plan réduit, on le rapetisse autour de la LIGNE DE
# SOL : les immeubles gardent leur base posée au lieu de décoller.
#
# On CALCULE plutôt que de scaler le nœud : réduire l'échelle d'un TextureRect
# rétrécit aussi son rectangle, et COVERED recoupe dessus — ce qui donnait une
# arête verticale franche de chaque côté de l'écran.
#
# `centre_x` = où doit tomber le MILIEU de l'image, et non le milieu de l'écran
# (26/08/2026). Le décor est peint pour un plein cadre, mais la moitié droite
# revient au biome adverse : centrer sur l'écran mettait le héros dans le bord
# gauche de la ville. On le centre donc sur l'ancrage du camp joueur, ce qui
# place le milieu de `Plan_2_Sol` juste sous ses pieds. Tous les plans partagent
# ce centre — y compris comme pivot de réduction — sans quoi les immeubles
# glisseraient latéralement par rapport à leur sol.
static func _cadre(taille_texture: Vector2, larg: float, haut: float,
		reduit: bool, centre_x: float) -> Rect2:
	if taille_texture.x <= 0.0 or taille_texture.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(larg, haut))
	var couvre := maxf(larg / taille_texture.x, haut / taille_texture.y)
	var taille := taille_texture * couvre
	var origine := Vector2(centre_x - taille.x * 0.5, (haut - taille.y) * 0.5)
	if not reduit:
		return Rect2(origine, taille)
	# Pivot sur la BASE DES IMMEUBLES (arête arrière du trottoir), pas sur la
	# ligne des pieds : c'est là que les façades touchent le sol. Rapetissir
	# autour des pieds les ferait avancer sur le trottoir.
	var pivot := Vector2(centre_x, SOL_HAUT_FRAC * haut)
	return Rect2(pivot + (origine - pivot) * REDUCTION_PLANS, taille * REDUCTION_PLANS)

# Une copie d'un plan, posée à `decalage` dans le ruban. `centered = false` pour
# que la position soit le coin haut-gauche, comme un Rect2.
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
		# Le foyer du zoom est exprimé dans le parent ; ce nœud est plein cadre
		# mais décalé verticalement pour caler le sol — d'où le retrait.
		foyer = _noeud_zoom.pivot_offset - position
	for couche in _couches:
		var noeud: Node2D = couche["noeud"]
		var origine: Vector2 = couche["origine"]
		var vitesse: float = couche["vitesse"]
		var boucle: float = couche["boucle_px"]
		if vitesse != 0.0 and boucle > 0.0:
			origine.x -= fmod(_temps * vitesse, boucle)
		# Compensation de profondeur : ramène l'échelle EFFECTIVE du plan à
		# 1 + (zoom − 1) × profondeur, sachant que le parent applique déjà zoom.
		var echelle := (1.0 + (zoom - 1.0) * float(couche["profondeur"])) / zoom
		# Homothétie de centre `foyer` : le contenu se réduit vers le point
		# regardé, au lieu de glisser vers le coin du nœud.
		noeud.position = foyer + (origine - foyer) * echelle
		noeud.scale = Vector2.ONE * echelle
