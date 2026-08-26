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
# Le SOL ne défile pas : les personnages y sont posés, le faire glisser sous
# leurs pieds les ferait patiner. Les fonds de ciel non plus (rien à y voir
# bouger, et ils doivent couvrir tout le cadre en permanence).
# ============================================================
class_name CombatDecorCity
extends Control

const DECOR_DIR := "res://assets/background/city/"

# Hauteur du SOL DANS le décor city, en fraction de l'image cadrée. Mesurée sur
# la livraison de Christophe : le trottoir commence plus bas que le sol du
# combat, donc le décor est REMONTÉ pour que les pieds y posent vraiment — sans
# ça les personnages flottent. À réajuster si le décor change.
const DECOR_SOL_FRAC := 0.688

# Réduction des plans d'IMMEUBLES pour dégager la vue d'ensemble (26/08/2026).
const REDUCTION_PLANS := 0.9

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
# Un élément par plan : {noeud, profondeur, vitesse, depart_x, boucle_px}.
var _couches: Array[Dictionary] = []
var _temps := 0.0

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de calage
# du sol est volontairement en unités ABSOLUES, pas la taille réelle du nœud
# (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float,
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
	decor._batir(vue.x, h)
	parent.add_child(decor)
	return decor

func _batir(larg: float, haut: float) -> void:
	for plan in PLANS:
		var chemin: String = DECOR_DIR + str(plan["f"])
		if not ResourceLoader.exists(chemin):
			continue   # couche non livrée : on empile ce qui existe
		var texture: Texture2D = load(chemin)
		if texture == null:
			continue
		var reduit := bool(plan["reduit"])
		var cadre := _cadre(texture.get_size(), larg, haut, reduit)
		var vitesse := float(plan["vitesse"])
		var noeud: Control = _ruban(texture, cadre, larg) if vitesse != 0.0 \
				else _calque(texture, cadre)
		add_child(noeud)
		_couches.append({
			"noeud": noeud,
			"profondeur": float(plan["profondeur"]),
			"vitesse": vitesse,
			"depart_x": cadre.position.x,
			# Longueur d'une boucle = la largeur d'une copie : au bout d'un
			# glissement de cette longueur, le ruban est identique à lui-même.
			"boucle_px": cadre.size.x,
		})

# Rectangle d'un plan dans les coordonnées du décor. On reproduit à la main le
# cadrage qu'aurait produit KEEP_ASPECT_COVERED — image mise à l'échelle pour
# couvrir, centrée — puis, pour un plan réduit, on le rapetisse autour de la
# LIGNE DE SOL : les immeubles gardent leur base posée au lieu de décoller.
#
# On CALCULE plutôt que de scaler le nœud : réduire l'échelle d'un TextureRect
# rétrécit aussi son rectangle, et COVERED recoupe dessus — ce qui donnait une
# arête verticale franche de chaque côté de l'écran.
static func _cadre(taille_texture: Vector2, larg: float, haut: float,
		reduit: bool) -> Rect2:
	if taille_texture.x <= 0.0 or taille_texture.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(larg, haut))
	var couvre := maxf(larg / taille_texture.x, haut / taille_texture.y)
	var taille := taille_texture * couvre
	var origine := Vector2((larg - taille.x) * 0.5, (haut - taille.y) * 0.5)
	if not reduit:
		return Rect2(origine, taille)
	var pivot := Vector2(larg * 0.5, DECOR_SOL_FRAC * haut)
	return Rect2(pivot + (origine - pivot) * REDUCTION_PLANS, taille * REDUCTION_PLANS)

static func _calque(texture: Texture2D, cadre: Rect2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = texture
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# STRETCH_SCALE remplit EXACTEMENT le rectangle calculé, sans jamais rogner.
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tr.position = cadre.position
	tr.size = cadre.size
	return tr

# Ruban de copies jointives, assez large pour couvrir l'écran quel que soit le
# décalage du défilement. Une copie de plus que le strict nécessaire : pendant
# qu'une sort par la gauche, la suivante doit déjà couvrir la droite.
static func _ruban(texture: Texture2D, cadre: Rect2, larg: float) -> Control:
	var ruban := Control.new()
	ruban.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ruban.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ruban.position = cadre.position
	var copies := 2 if cadre.size.x <= 0.0 else int(ceil(larg / cadre.size.x)) + 1
	for i in maxi(copies, 2):
		var tr := _calque(texture, Rect2(Vector2(cadre.size.x * i, cadre.position.y),
				cadre.size))
		# Le ruban porte déjà l'origine du cadre : les copies s'alignent en
		# local, sinon le décalage serait compté deux fois.
		tr.position.y = 0.0
		ruban.add_child(tr)
	return ruban

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
		var noeud: Control = couche["noeud"]
		var vitesse: float = couche["vitesse"]
		if vitesse != 0.0:
			var boucle: float = couche["boucle_px"]
			if boucle > 0.0:
				noeud.position.x = float(couche["depart_x"]) \
						- fmod(_temps * vitesse, boucle)
		# Compensation de profondeur : ramène l'échelle EFFECTIVE du plan à
		# 1 + (zoom − 1) × profondeur, sachant que le parent applique déjà zoom.
		var voulue := 1.0 + (zoom - 1.0) * float(couche["profondeur"])
		noeud.scale = Vector2.ONE * (voulue / zoom)
		# Le pivot est relatif au nœud : il suit donc le défilement.
		noeud.pivot_offset = foyer - noeud.position
