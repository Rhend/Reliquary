# ============================================================
# CombatDecorCity — décor de ville de Christophe, en plans PARALLAXÉS.
#
# Le décor est livré découpé en plans (Fond, 5, 4, 3, Sol) précisément pour
# donner de la profondeur. Jusqu'ici ils n'étaient qu'empilés : un seul bloc,
# une seule échelle, aucun bénéfice du découpage. Ce nœud leur rend leur rôle.
#
# TROIS effets pilotés par `PLANS`, plus un quatrième porté par les enseignes
# elles-mêmes (voir tout en bas) :
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
#      Quand un même niveau de plan porte PLUSIEURS découpes (deux immeubles
#      livrés côte à côte sur le plan 5 ou le plan 4), elles défilent à des
#      vitesses légèrement différentes l'une de l'autre (26/08/2026) : à
#      vitesse identique, deux découpes du même plan glissent comme un seul
#      bloc rigide et le fond a l'air mort. L'écart (±20 % autour de la
#      vitesse du plan) reste discret — la profondeur, elle, ne change pas :
#      ce n'est qu'un signal de vie visuelle, pas un second niveau de parallax.
#      Un calque néon partage vitesse ET profondeur de SON immeuble, jamais de
#      l'autre découpe du plan, sous peine de décrocher de sa façade.
#
#  • BRUME ATMOSPHÉRIQUE — chaque plan est teinté vers `HAZE_COLOR` au
#    prorata de son ÉLOIGNEMENT (26/08/2026) : un plan lointain (profondeur
#    proche de 0) se fond un peu dans l'air entre lui et la caméra, un plan
#    proche (sol, profondeur 1) reste à sa couleur native. Perspective
#    atmosphérique classique — le même principe que les silhouettes qui
#    « perdent leurs bords » avec la distance dans `biome_background.gdshader`.
#    Un calque néon reçoit la même teinte que son immeuble (même profondeur,
#    déjà partagée pour la vitesse) : rien à faire de plus pour rester calé.
#
#  • ENSEIGNES VIVANTES (27/08/2026) — un point lumineux court le long du tube
#    de chaque enseigne, comme sur la DA du QG. Les tracés sont EXTRAITS des
#    images de Christophe et bakés hors ligne (`NeonsCiteData`,
#    `tools/bake_neons_cite.gd`) ; ici on ne fait que poser un `NeonRunners`
#    dans chaque copie du ruban. Rien d'autre n'a bougé : c'est le parentage
#    qui offre le défilement, le zoom et la brume à l'effet.
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

# ⚠ Ce choix a un COÛT : sous les pieds il ne reste plus que la moitié BASSE
# de la bande (15 % de l'image). `REDUCTION_PLANS` sert à dégager la vue
# d'ensemble sur les seuls plans d'immeubles, le sol et le ciel devant, eux,
# rester assez grands pour couvrir.

# Réduction des plans d'IMMEUBLES pour dégager la vue d'ensemble (26/08/2026).
const REDUCTION_PLANS := 0.9

# Couleur EXACTE du bas de Background_City_Plan_2_Sol.png (mesurée, plate sur
# toute la bande basse) — comble le vide que laisse la hauteur naturelle
# (voir `construire()`, même correctif que CombatDecorFactory, 28/08/2026).
# Plate → indiscernable du vrai trottoir.
const SOL_SECOURS_COLOR := Color8(54, 30, 87)

# Brume atmosphérique (26/08/2026) : teinte vers laquelle un plan lointain se
# fond, et intensité MAX (au plan le plus lointain, profondeur 0 — le sol, à
# profondeur 1, n'en reçoit aucune). Volontairement subtil : un signal de
# profondeur de plus, pas un regrading complet de la palette de Christophe.
const HAZE_COLOR := Color(0.55, 0.62, 0.74)
const HAZE_MAX := 0.30

# Les plans, du PLUS LOINTAIN au plus proche — l'ordre d'empilement.
#   profondeur : réponse au zoom (0 = fixe, 1 = comme les personnages) ;
#   vitesse    : défilement horizontal en px/s, droite → gauche (0 = fixe) ;
#   reduit     : ce plan subit REDUCTION_PLANS.
# Les calques néon partagent profondeur ET vitesse de leur immeuble : sans ça
# les enseignes se décrocheraient de leur façade.
const PLANS: Array[Dictionary] = [
	{"f": "Background_City_Plan_Fond.png",               "profondeur": 0.00, "vitesse": 0.0,  "reduit": false},
	{"f": "Background_City_Plan_Fond_2.png",             "profondeur": 0.08, "vitesse": 0.0,  "reduit": false},
	{"f": "Background_City_Plan_5_Immeuble_01.png",      "profondeur": 0.25, "vitesse": 2.4,  "reduit": true},
	{"f": "Background_City_Plan_5_Immeuble_02.png",      "profondeur": 0.25, "vitesse": 3.6,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_01.png",      "profondeur": 0.45, "vitesse": 5.6,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_01_Neon.png", "profondeur": 0.45, "vitesse": 5.6,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_01_Neon_2.png","profondeur": 0.45, "vitesse": 5.6,  "reduit": true},
	{"f": "Background_City_Plan_4_Immeuble_02.png",      "profondeur": 0.45, "vitesse": 8.4,  "reduit": true},
	{"f": "Background_City_Plan_3_Immeuble_01.png",      "profondeur": 0.70, "vitesse": 14.0, "reduit": true},
	{"f": "Background_City_Plan_3_Immeuble_01_Neon.png", "profondeur": 0.70, "vitesse": 14.0, "reduit": true},
	{"f": "Background_City_Plan_3_Immeuble_01_Neon_2.png","profondeur": 0.70, "vitesse": 14.0, "reduit": true},
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
	# Hauteur NATURELLE (28/08/2026, même correctif que CombatDecorFactory) :
	# PAS la couverture "sans trou" (l'ancien `maxf` ci-dessous, retiré) — elle
	# suppose que la bande de sol de l'image tombe à peu près à `sol_y_frac`,
	# ce qui n'est vrai qu'à 5 points près (bande mesurée à 84,9 % contre
	# 80,6 % voulu) et forçait un agrandissement uniforme d'environ 25 % —
	# donc aussi de la LARGEUR, rognant une bonne partie de la skyline pour
	# rien. `h = vue.y` couvre presque tout le canevas ; le pivot du sol
	# (DECOR_SOL_FRAC) reste inchangé, l'alignement ne bouge pas.
	var h := vue.y
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	decor.offset_top = haut
	decor.offset_bottom = haut + h - vue.y
	decor._batir(vue.x, h, vue.x * sol_x_frac)
	# Vide résiduel sous le sol (la bande y est plus fine que ce qu'il faut
	# pour atteindre le bas de l'écran) : un aplat de la couleur exacte du
	# trottoir, plate donc invisible en pratique.
	var bas := vue.y - haut - h
	if bas > 0.0:
		var secours := ColorRect.new()
		secours.color = SOL_SECOURS_COLOR
		secours.position = Vector2(0.0, h)
		secours.size = Vector2(vue.x, bas)
		decor.add_child(secours)
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
		noeud.modulate = _teinte_profondeur(float(plan["profondeur"]))
		# Échelle d'affichage de ce plan : NeonRunners s'en sert pour écarter
		# les enseignes trop petites une fois rendues pour porter un point.
		var echelle_ecran := cadre.size.x / maxf(texture.get_size().x, 1.0)
		for i in copies:
			var sp := _calque(texture, cadre.size, Vector2(cadre.size.x * i, 0.0))
			# Les points lumineux vivent DANS la copie, pas à côté : ils
			# héritent ainsi du défilement, du repli, de la compensation de
			# zoom et de la brume, sans qu'aucun des quatre soit recâblé.
			NeonRunners.poser(sp, chemin, texture.get_size(), echelle_ecran)
			noeud.add_child(sp)
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

# Teinte de brume d'un plan selon son éloignement : intensité MAX à
# profondeur 0 (le plus lointain), nulle à profondeur 1 (le sol).
static func _teinte_profondeur(profondeur: float) -> Color:
	return Color.WHITE.lerp(HAZE_COLOR, HAZE_MAX * (1.0 - clampf(profondeur, 0.0, 1.0)))

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
