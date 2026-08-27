# ============================================================
# SpriteSpinePersonnage — sprite Spine ANIMÉ du personnage principal
# (« Relic », export WIP de Christophe) dans la scène de bataille CTB.
#
# Le runtime spine-godot est un GDExtension (bin/ à la racine, builds
# windows + linux versionnés — branche Spine 4.3, Godot 4.6.3) : ce script
# ne référence JAMAIS les classes Spine par leur type — le projet doit
# compiler et les tests headless passer même sans l'extension. Tout passe
# par ClassDB ; si l'extension ou les assets manquent, `creer()` rend null
# et l'appelant garde son placeholder (EnergyBoule).
#
# Contrat d'export Spine (assets dans assets/personnages/relic/) :
#   • animations « Idle » (boucle de repos), « Attack_CaC », « Attack_Shoot »
#     (attaque à distance, livrée 24/08/2026) et « Hit » (one-shot — retour
#     Idle enchaîné automatiquement), « Death » (one-shot, la pose finale est
#     TENUE — pas de fondu placeholder). Une animation absente est IGNORÉE
#     (les ennemis n'ont pas Attack_Shoot) ;
#   • l'origine du squelette = les PIEDS du personnage → position de ce
#     nœud = point d'appui au sol (_pieds de CombatCtbUi), comme l'ellipse.
# La 1re ligne du .atlas doit nommer le .png RÉEL du dossier (l'export de
# Christophe référençait « Test_Aniamtion.png » — corrigé à l'intégration ;
# la livraison des costumes en a 5, Relic.png … Relic_5.png).
#
# APPARENCE (Dictionary produit par SpinePersonnagesData.apparences) :
#   {"skin": String, "skins": PackedStringArray, "niveau": int}
#   • `skin` seule            → skin de palier d'un ennemi (« FlameBot_Nv3 ») ;
#   • `skins`                 → skins CUMULÉES en une skin composée (Relic :
#                               corps + équipement + accessoires) ;
#   • `niveau` > 0            → palier d'ÉQUIPEMENT de Relic. Il n'est pas
#     porté par une skin mais par des SLOTS suffixés « _Nv<n> » : la skin
#     composée est PURGÉE des slots des autres niveaux. Purger la skin plutôt
#     que vider les slots est la seule façon sûre — une animation qui pose un
#     attachement le retrouverait dans la skin et rallumerait la pièce.
# ============================================================
class_name SpriteSpinePersonnage
extends Node2D

const CHEMIN_SKEL := "res://assets/personnages/relic/Relic.skel"
const CHEMIN_ATLAS := "res://assets/personnages/relic/Relic.atlas"
const ANIM_IDLE := "Idle"
const ANIM_ATTACK := "Attack_CaC"
const ANIM_ATTACK_SHOOT := "Attack_Shoot"
const ANIM_HIT := "Hit"
const ANIM_DEATH := "Death"
# Marqueur de niveau d'équipement dans un nom de slot (cf. niveaux_du_slot).
const MARQUEUR_NIVEAU := "_Nv"
# Slots écartés de la MESURE d'échelle (cf. hors_mesure) : ils débordent le
# personnage sans lui appartenir. L'épée levée au-dessus de la tête de Relic
# occupait à elle seule la moitié du budget de hauteur, ce qui le rendait
# visiblement plus petit que des monstres au corps monobloc.
const MOTIFS_HORS_MESURE := ["Sword", "VFX"]
# Hauteur affichée à l'écran (px) — la source Spine fait ~2 800 unités de haut,
# l'échelle est déduite de la hauteur MESURÉE du squelette au chargement
# (voir _hauteur_source : la taille déclarée par l'export n'est pas fiable).
const HAUTEUR_CIBLE_PX := 276.0   # 240 + 15 % (26/08/2026 : héros et monstres jugés trop petits)
const HAUTEUR_SOURCE_DEFAUT := 2770.0   # dernier recours : ni mesure ni taille déclarée
# Fondu par défaut entre deux animations Spine consécutives (26/08/2026) :
# sans lui, l'extension enchaîne Idle→Attaque→Idle (et →Hit, →Mort) en cut
# sec (mix par défaut = 0). Une valeur courte adoucit l'ENTRÉE dans chaque
# clip livré, sans en ajouter un seul — la pose finale de Mort reste TENUE
# (aucune animation ne joue après elle : rien à en faire sortir en fondu).
const DUREE_FONDU := 0.12

var _spine: Node = null   # SpineSprite — jamais typé (extension optionnelle)
var _mort := false        # Death jouée : plus aucune autre animation
var _animations := PackedStringArray()   # ce que l'export sait vraiment jouer
var _apparence: Dictionary = {}          # dernière apparence posée (mesure d'échelle)
var _chemin_skel := ""                   # clé de la silhouette bakée

static func disponible(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS) -> bool:
	return ClassDB.class_exists("SpineSprite") \
			and ClassDB.class_exists("SpineSkeletonDataResource") \
			and ResourceLoader.exists(chemin_skel) \
			and ResourceLoader.exists(chemin_atlas)

# Fabrique : null si le runtime spine-godot ou les assets manquent —
# l'appelant retombe alors sur son placeholder, sans erreur.
#
# Les paramètres par défaut visent Relic (héros) : un appelant qui veut
# simplement « le héros tel qu'il est » n'a rien à passer.
static func creer(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS,
		apparence: Dictionary = {},
		hauteur_cible_px: float = HAUTEUR_CIBLE_PX) -> SpriteSpinePersonnage:
	if not disponible(chemin_skel, chemin_atlas):
		return null
	var noeud := SpriteSpinePersonnage.new()
	if noeud._construire_spine(chemin_skel, chemin_atlas, apparence, hauteur_cible_px):
		return noeud
	noeud.free()
	return null

# Fabrique du HÉROS pour le jeu réel. Passage OBLIGÉ par le registre : depuis
# la livraison « costumes », toutes les pièces de Relic vivent dans des skins
# nommées et sa skin « default » est VIDE — `creer()` sans apparence rendrait
# un squelette invisible.
# `niveau` = son palier d'ÉQUIPEMENT (1 = Commun, la dotation de départ du
# chantier 13). Le brancher sur l'équipement réel du joueur se fait ICI, et
# nulle part ailleurs.
static func creer_heros(niveau: int = 1,
		hauteur_cible_px: float = HAUTEUR_CIBLE_PX) -> SpriteSpinePersonnage:
	var registre := SpinePersonnagesData.charger()
	var entree: Dictionary = registre.heros() if registre != null else {}
	var apparences: Array[Dictionary] = []
	if not entree.is_empty():
		apparences = SpinePersonnagesData.apparences(entree)
	if apparences.is_empty():
		return creer(CHEMIN_SKEL, CHEMIN_ATLAS, {}, hauteur_cible_px)
	return creer(str(entree.get("skel", CHEMIN_SKEL)), str(entree.get("atlas", CHEMIN_ATLAS)),
			apparences[clampi(niveau - 1, 0, apparences.size() - 1)], hauteur_cible_px)

func _construire_spine(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS,
		apparence: Dictionary = {},
		hauteur_cible_px: float = HAUTEUR_CIBLE_PX) -> bool:
	var skel: Resource = load(chemin_skel)
	var atlas: Resource = load(chemin_atlas)
	if skel == null or atlas == null:
		push_warning("SpriteSpinePersonnage : assets Spine illisibles (%s)" % chemin_skel)
		return false
	var donnees := ClassDB.instantiate("SpineSkeletonDataResource") as Resource
	if donnees == null:
		push_warning("SpriteSpinePersonnage : SpineSkeletonDataResource introuvable (runtime incomplet)")
		return false
	donnees.skeleton_file_res = skel
	donnees.atlas_res = atlas
	if not bool(donnees.call("is_skeleton_data_loaded")):
		push_warning("SpriteSpinePersonnage : données Spine invalides (%s)" % chemin_skel)
		return false
	donnees.set("default_mix", DUREE_FONDU)
	_spine = ClassDB.instantiate("SpineSprite") as Node
	if _spine == null:
		push_warning("SpriteSpinePersonnage : SpineSprite non instanciable")
		return false
	_spine.set("skeleton_data_res", donnees)
	_chemin_skel = chemin_skel
	add_child(_spine)
	for a in donnees.call("get_animations"):
		_animations.append(str(a.call("get_name")))
	# Apparence (skin de palier, costume, niveau d'équipement) : posée AVANT la
	# 1re animation pour que la pose de repos s'affiche d'emblée avec les bons
	# attachements.
	definir_apparence(apparence)
	# Échelle : hauteur native du squelette → hauteur_cible_px à l'écran.
	_spine.set("scale", Vector2.ONE
			* (hauteur_cible_px / _hauteur_source(donnees, apparence, chemin_skel)))
	# Recentrage visuel : l'origine du squelette est entre les pieds, mais la
	# masse DESSINÉE peut pencher — Relic a un pied en avant, ce qui décale sa
	# silhouette de +17 px vers la droite à la taille de combat (mesuré). Sans
	# ça il paraît décentré sur un décor qui, lui, est centré sur l'ancrage.
	# Valeur donnée pour HAUTEUR_CIBLE_PX, remise à l'échelle demandée.
	var dx := float(apparence.get("decalage_x_px", 0.0))
	if dx != 0.0:
		_spine.set("position", Vector2(-dx * hauteur_cible_px / HAUTEUR_CIBLE_PX, 0.0))
	_jouer(ANIM_IDLE, true)
	return true

# Hauteur NATIVE du squelette (unités Spine), dont se déduit l'échelle.
# On MESURE la pose réelle (get_bounds, apparence déjà posée) plutôt que de
# croire la taille DÉCLARÉE par l'export (get_height) : cette métadonnée est
# perdue par un export mal réglé — la livraison « cheveux » du 25/08/2026
# annonçait 573 pour un Relic qui en mesure 2917, soit un héros ~5× trop grand
# devant les monstres. La mesure ne ment pas ; la métadonnée n'est plus qu'un
# secours, et la constante le dernier recours. Sans incidence sur les ennemis
# livrés : leur taille déclarée ÉGALE leur mesure (FlameBot 3028, WorkBot 2480).
#
# TROIS sources, de la plus fidèle à la plus grossière :
#
#  1. La SILHOUETTE bakée (SilhouettesData) — le nombre de pixels réellement
#     dessinés, mesuré hors ligne par tools/mesurer_silhouettes.tscn. C'est la
#     seule mesure qui corresponde à ce qu'on voit : les bornes comptent des
#     régions d'atlas transparentes (le FlameBot y gagnait ~37 % de hauteur
#     fantôme). Ignorée si elle est périmée — cf. SilhouettesData.hauteur.
#  2. Les BORNES de la pose, arme et VFX écartés (_mesurer_corps) — repli quand
#     rien n'est baké. Sinon l'épée que Relic tient au-dessus de la tête mange
#     le budget de hauteur et le rapetisse devant des monstres au corps
#     monobloc (FlameBot et WorkBot : 5 slots, aucune arme séparée).
#  3. La taille DÉCLARÉE, puis la constante — derniers recours.
func _hauteur_source(donnees: Resource, apparence: Dictionary = {},
		chemin_skel: String = "") -> float:
	var mesure := _mesurer_corps(donnees, apparence)
	if chemin_skel != "":
		var bakees := SilhouettesData.charger()
		if bakees != null:
			var silhouette := bakees.hauteur(chemin_skel, mesure)
			if silhouette > 0.0:
				return silhouette
	if mesure > 0.0:
		return mesure
	if donnees.has_method("get_height"):
		var declaree := float(donnees.call("get_height"))
		if declaree > 0.0:
			return declaree
	return HAUTEUR_SOURCE_DEFAUT

# Hauteur du CORPS (unités Spine), arme et VFX écartés. On pose une skin de
# MESURE — la même que l'apparence demandée, purgée des slots exclus —, on
# mesure, puis on remet l'apparence réelle. Rend 0.0 si la mesure est
# impossible (pas de runtime, pas de skin) : l'appelant retombe alors sur la
# taille déclarée par l'export.
#
# On passe par une skin plutôt que par un décrochage d'attachements sur le
# squelette vivant : c'est le même chemin (new_skin / add_skin /
# remove_attachment) que la purge des niveaux, déjà éprouvé ici.
func _mesurer_corps(donnees: Resource, apparence: Dictionary) -> float:
	var squelette: Object = _spine.call("get_skeleton")
	if squelette == null or not squelette.has_method("get_bounds"):
		return 0.0
	var skins := _skins_demandees(apparence)
	var mesure_posee := false
	if not skins.is_empty():
		var corps: Object = _composer_skin(skins, int(apparence.get("niveau", 0)))
		if corps != null:
			_purger_hors_mesure(corps, donnees)
			squelette.call("set_skin", corps)
			squelette.call("set_slots_to_setup_pose")
			mesure_posee = true
	var bornes := squelette.call("get_bounds") as Rect2
	if mesure_posee:
		definir_apparence(apparence)   # remet l'arme et les VFX
	return bornes.size.y

# Retire de la skin tout ce qui ne doit pas compter dans la mesure d'échelle.
func _purger_hors_mesure(skin: Object, donnees: Resource) -> void:
	var slots: Array = donnees.call("get_slots")
	for i in slots.size():
		if not hors_mesure(str((slots[i] as Object).call("get_name"))):
			continue
		for nom in skin.call("find_names_for_slot", i):
			skin.call("remove_attachment", i, str(nom))

# Ce slot compte-t-il dans la mesure d'échelle ? Test sur le NOM, insensible à
# la casse : les exports de Christophe nomment l'arme « Sword » et les effets
# « VFX » dans toutes les animations (R_H_Idle_Sword_Nv_3,
# R_H_Attack_Shoot_Sword_VFX_Light…). Les ennemis livrés n'ont aucun slot de
# ce genre (5 slots monobloc) : leur échelle est inchangée.
static func hors_mesure(nom_slot: String) -> bool:
	for motif in MOTIFS_HORS_MESURE:
		if nom_slot.findn(motif) >= 0:
			return true
	return false

# ─── Apparence ───────────────────────────────────────────────

# Pose une apparence sur un sprite déjà construit (voir l'en-tête pour la
# forme du dictionnaire). Une apparence vide laisse le squelette tel quel.
# set_skin seul ne suffit pas : les attachements doivent être re-résolus
# (set_slots_to_setup_pose), sinon la pose garde l'ancienne apparence.
func definir_apparence(apparence: Dictionary) -> void:
	if _spine == null:
		return
	var squelette: Object = _spine.call("get_skeleton")
	if squelette == null:
		return
	var skins := _skins_demandees(apparence)
	var niveau := int(apparence.get("niveau", 0))
	if skins.is_empty():
		return
	# Retenue pour que hauteur_rendue_px() sache reconstruire la skin de mesure.
	_apparence = apparence
	if skins.size() == 1 and niveau <= 0:
		squelette.call("set_skin_by_name", skins[0])
	else:
		var composee: Object = _composer_skin(skins, niveau)
		if composee == null:
			return
		squelette.call("set_skin", composee)
	squelette.call("set_slots_to_setup_pose")

static func _skins_demandees(apparence: Dictionary) -> PackedStringArray:
	var skins := apparence.get("skins", PackedStringArray()) as PackedStringArray
	if not skins.is_empty():
		return skins
	var seule := str(apparence.get("skin", ""))
	return PackedStringArray([seule]) if seule != "" else PackedStringArray()

# Fabrique une skin CUMULANT `skins`, purgée des slots d'un autre niveau
# d'équipement quand `niveau` > 0. Rend null si le runtime ne sait pas la
# construire (l'appelant garde alors la skin par défaut du squelette).
func _composer_skin(skins: PackedStringArray, niveau: int) -> Object:
	var donnees: Resource = _spine.get("skeleton_data_res")
	if donnees == null or not _spine.has_method("new_skin"):
		return null
	var composee: Object = _spine.call("new_skin", "apparence")
	if composee == null:
		return null
	for nom in skins:
		var source: Object = donnees.call("find_skin", nom)
		if source == null:
			push_warning("SpriteSpinePersonnage : skin « %s » absente de l'export" % nom)
			continue
		composee.call("add_skin", source)
	if niveau > 0:
		_purger_niveaux(composee, donnees, niveau)
	return composee

# Retire de la skin les attachements des slots qui appartiennent à un AUTRE
# niveau d'équipement. Les slots sans marqueur de niveau (corps, VFX communs)
# sont conservés tels quels.
func _purger_niveaux(skin: Object, donnees: Resource, niveau: int) -> void:
	var slots: Array = donnees.call("get_slots")
	for i in slots.size():
		var niveaux := niveaux_du_slot(str((slots[i] as Object).call("get_name")))
		if niveaux.is_empty() or niveau in niveaux:
			continue
		for nom in skin.call("find_names_for_slot", i):
			skin.call("remove_attachment", i, str(nom))

# Niveaux d'équipement portés par un nom de slot : ce qui suit le DERNIER
# « _Nv », découpé sur « / » et « _ » — Christophe mutualise une pièce entre
# plusieurs niveaux quand elle ne change pas.
#   « …_Nv3 » → [3] ; « …_Nv4/5 » → [4, 5] ; « …_Nv1_2_3 » → [1, 2, 3].
# Vide = le slot ne dépend pas du niveau (il est alors toujours affiché).
static func niveaux_du_slot(nom_slot: String) -> Array[int]:
	var sortie: Array[int] = []
	var i := nom_slot.rfind(MARQUEUR_NIVEAU)
	if i < 0:
		return sortie
	var suffixe := nom_slot.substr(i + MARQUEUR_NIVEAU.length())
	for morceau in suffixe.replace("_", "/").split("/", false):
		if morceau.is_valid_int():
			sortie.append(int(morceau))
	return sortie

# L'apparence courante fournit-elle cet attachement pour ce slot ? Seule façon
# de vérifier la purge des niveaux sans regarder l'écran : la pièce d'un autre
# niveau doit être ABSENTE de la skin, pas simplement cachée — une animation
# saurait rallumer une pièce simplement décrochée du slot.
# Oriente le personnage à l'écran. `signe` vient de
# `SpinePersonnagesData.echelle_x(entree, doit_regarder_a_droite)` : le registre
# sait vers où l'asset est exporté, l'appelant sait vers où il doit regarder.
#
# On ne touche QUE le signe de `scale.x`, jamais `scale` en entier : écraser
# l'échelle effacerait une mise à la taille éventuellement posée par
# l'appelant. Cette méthode remplace le `scale = Vector2(-1, 1)` qui était en
# dur dans la ShowRoom et retournait aveuglément TOUT ennemi — un ennemi livré
# tourné vers la gauche s'y serait retrouvé dos au héros, sans rien pour le dire.
func orienter(signe: float) -> void:
	scale.x = absf(scale.x) * (-1.0 if signe < 0.0 else 1.0)

func porte_attachement(nom_slot: String, nom_attachement: String) -> bool:
	if _spine == null:
		return false
	var squelette: Object = _spine.call("get_skeleton")
	if squelette == null:
		return false
	return squelette.call("get_attachment_by_slot_name", nom_slot, nom_attachement) != null

# Hauteur du CORPS RÉELLEMENT rendue à l'écran (px) : la pose courante mesurée,
# puis l'échelle posée au chargement. C'est le seul contrôle qui attrape un
# export qui ment sur sa taille — un héros deux fois trop grand devant les
# monstres est un bug de DONNÉE, invisible du code qui l'instancie.
# 0 sans runtime Spine.
#
# Mesure le CORPS par la MÊME source que l'échelle (_hauteur_source) : le
# garde-fou doit contrôler exactement la grandeur qu'on régule. Mesurer les
# bornes brutes le ferait virer au rouge à la prochaine épée plus longue, sans
# que le personnage ait changé de taille. Effet de bord : la pose est
# brièvement remise en setup — sans conséquence, l'animation la réécrit à la
# frame suivante.
func hauteur_rendue_px() -> float:
	if _spine == null:
		return 0.0
	var donnees: Resource = _spine.get("skeleton_data_res")
	if donnees == null:
		return 0.0
	var corps := _hauteur_source(donnees, _apparence, _chemin_skel)
	if corps <= 0.0:
		return 0.0
	var echelle: Vector2 = _spine.get("scale")
	return corps * echelle.y

# Bornes du CORPS (unités Spine), arme et VFX retirés — la grandeur que
# SilhouettesData retient comme témoin d'obsolescence. Réservé à l'outil de
# bake, qui doit écrire exactement ce que le runtime relira.
func bornes_corps() -> float:
	if _spine == null:
		return 0.0
	var donnees: Resource = _spine.get("skeleton_data_res")
	return _mesurer_corps(donnees, _apparence) if donnees != null else 0.0

# Pose la skin de MESURE (arme et VFX retirés) et l'y LAISSE. Réservé à l'outil
# de bake, seul cas où l'on veut RENDRE le corps nu ; partout ailleurs la
# mesure se fait et se défait dans _mesurer_corps. Rend false si l'apparence
# n'est pas composable (ennemi à skin unique sans skins_base, pas de runtime).
func poser_skin_mesure(apparence: Dictionary) -> bool:
	if _spine == null:
		return false
	var donnees: Resource = _spine.get("skeleton_data_res")
	var squelette: Object = _spine.call("get_skeleton")
	if donnees == null or squelette == null:
		return false
	var skins := _skins_demandees(apparence)
	if skins.is_empty():
		return false
	var corps: Object = _composer_skin(skins, int(apparence.get("niveau", 0)))
	if corps == null:
		return false
	_purger_hors_mesure(corps, donnees)
	squelette.call("set_skin", corps)
	squelette.call("set_slots_to_setup_pose")
	return true

# ─── Animations ──────────────────────────────────────────────

# L'export sait-il jouer cette animation ? (Attack_Shoot n'existe que pour
# Relic : la demander à un ennemi doit être sans effet, pas une erreur.)
func a_animation(nom: String) -> bool:
	return nom in _animations

# Attaque one-shot, retour Idle enchaîné (file d'animations Spine, piste 0).
# `a_distance` demande le geste de TIR (Attack_Shoot) : il RETOMBE sur la
# mêlée quand l'export ne le porte pas — les ennemis n'ont pas Attack_Shoot,
# et une action jouée doit toujours s'animer.
func jouer_attaque(a_distance: bool = false) -> void:
	if a_distance and a_animation(ANIM_ATTACK_SHOOT):
		_one_shot_puis_idle(ANIM_ATTACK_SHOOT)
		return
	_one_shot_puis_idle(ANIM_ATTACK)

# Coup reçu : même mécanique (ignoré si la mort est déjà jouée).
func jouer_hit() -> void:
	_one_shot_puis_idle(ANIM_HIT)

# Mort : one-shot SANS retour Idle — la pose finale est tenue, et plus
# aucune animation n'est acceptée ensuite (idempotent : rafraîchi à chaque
# _rafraichir_orbes de l'écran de combat).
func jouer_mort() -> void:
	if _mort or not a_animation(ANIM_DEATH):
		return
	var etat := _etat_animation()
	if etat == null:
		return
	_mort = true
	etat.call("set_animation", ANIM_DEATH, false, 0)

# Sort de la pose de mort et reprend le repos. RÉSERVÉ AUX OUTILS DE DEV
# (vitrine ShowRoom) : en combat, une mort est définitive.
func reprendre_repos() -> void:
	_mort = false
	_jouer(ANIM_IDLE, true)

func _one_shot_puis_idle(nom: String) -> void:
	if _mort or not a_animation(nom):
		return
	var etat := _etat_animation()
	if etat == null:
		return
	etat.call("set_animation", nom, false, 0)
	etat.call("add_animation", ANIM_IDLE, 0.0, true, 0)

func _jouer(nom: String, boucle: bool) -> void:
	if not a_animation(nom):
		return
	var etat := _etat_animation()
	if etat != null:
		etat.call("set_animation", nom, boucle, 0)

func _etat_animation() -> Object:
	if _spine == null:
		return null
	return _spine.call("get_animation_state") as Object
