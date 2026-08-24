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
#   • animations « Idle » (boucle de repos), « Attack_CaC » et « Hit »
#     (one-shot — retour Idle enchaîné automatiquement), « Death »
#     (one-shot, la pose finale est TENUE — pas de fondu placeholder) ;
#   • l'origine du squelette = les PIEDS du personnage → position de ce
#     nœud = point d'appui au sol (_pieds de CombatCtbUi), comme l'ellipse.
# La 1re ligne du .atlas doit nommer le .png RÉEL du dossier (l'export de
# Christophe référençait « Test_Aniamtion.png » — corrigé à l'intégration).
# ============================================================
class_name SpriteSpinePersonnage
extends Node2D

const CHEMIN_SKEL := "res://assets/personnages/relic/Relic.skel"
const CHEMIN_ATLAS := "res://assets/personnages/relic/Relic.atlas"
const ANIM_IDLE := "Idle"
const ANIM_ATTACK := "Attack_CaC"
const ANIM_HIT := "Hit"
const ANIM_DEATH := "Death"
# Hauteur affichée à l'écran (px) — la source Spine fait ~2 770 px de haut,
# l'échelle est déduite de la hauteur réelle du squelette au chargement.
const HAUTEUR_CIBLE_PX := 240.0
const HAUTEUR_SOURCE_DEFAUT := 2770.0   # secours si l'API height est absente

var _spine: Node = null   # SpineSprite — jamais typé (extension optionnelle)
var _mort := false        # Death jouée : plus aucune autre animation

static func disponible(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS) -> bool:
	return ClassDB.class_exists("SpineSprite") \
			and ClassDB.class_exists("SpineSkeletonDataResource") \
			and ResourceLoader.exists(chemin_skel) \
			and ResourceLoader.exists(chemin_atlas)

# Fabrique : null si le runtime spine-godot ou les assets manquent —
# l'appelant retombe alors sur son placeholder, sans erreur.
#
# Les paramètres par défaut visent Relic (héros) : tous les appelants
# historiques restent inchangés. Les ENNEMIS de Christophe partagent le même
# contrat d'animation (Idle/Attack_CaC/Hit/Death) mais portent leurs PALIERS
# en SKINS Spine (« FlameBot_Nv1 » … « _Nv5 ») — d'où `skin`, qui vaut ""
# pour un squelette sans variante (Relic).
static func creer(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS,
		skin: String = "",
		hauteur_cible_px: float = HAUTEUR_CIBLE_PX) -> SpriteSpinePersonnage:
	if not disponible(chemin_skel, chemin_atlas):
		return null
	var noeud := SpriteSpinePersonnage.new()
	if noeud._construire_spine(chemin_skel, chemin_atlas, skin, hauteur_cible_px):
		return noeud
	noeud.free()
	return null

func _construire_spine(chemin_skel: String = CHEMIN_SKEL,
		chemin_atlas: String = CHEMIN_ATLAS,
		skin: String = "",
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
	_spine = ClassDB.instantiate("SpineSprite") as Node
	if _spine == null:
		push_warning("SpriteSpinePersonnage : SpineSprite non instanciable")
		return false
	_spine.set("skeleton_data_res", donnees)
	add_child(_spine)
	# Skin de palier (ennemis) : posée AVANT la 1re animation pour que la
	# pose de repos s'affiche d'emblée avec les bons attachements.
	if skin != "":
		definir_skin(skin)
	# Échelle : hauteur native du squelette → hauteur_cible_px à l'écran.
	var hauteur := HAUTEUR_SOURCE_DEFAUT
	if donnees.has_method("get_height"):
		var h := float(donnees.call("get_height"))
		if h > 0.0:
			hauteur = h
	_spine.set("scale", Vector2.ONE * (hauteur_cible_px / hauteur))
	_jouer(ANIM_IDLE, true)
	return true

# Change la skin (= le palier, pour les ennemis) sur un sprite déjà construit.
# set_skin seul ne suffit pas : les attachements du squelette doivent être
# re-résolus (set_slots_to_setup_pose) sinon la pose garde l'ancienne apparence.
func definir_skin(nom: String) -> void:
	if _spine == null:
		return
	var squelette: Object = _spine.call("get_skeleton")
	if squelette == null:
		return
	squelette.call("set_skin_by_name", nom)
	squelette.call("set_slots_to_setup_pose")

# Attaque one-shot, retour Idle enchaîné (file d'animations Spine, piste 0).
func jouer_attaque() -> void:
	_one_shot_puis_idle(ANIM_ATTACK)

# Coup reçu : même mécanique (ignoré si la mort est déjà jouée).
func jouer_hit() -> void:
	_one_shot_puis_idle(ANIM_HIT)

# Mort : one-shot SANS retour Idle — la pose finale est tenue, et plus
# aucune animation n'est acceptée ensuite (idempotent : rafraîchi à chaque
# _rafraichir_orbes de l'écran de combat).
func jouer_mort() -> void:
	if _mort:
		return
	var etat := _etat_animation()
	if etat == null:
		return
	_mort = true
	etat.call("set_animation", ANIM_DEATH, false, 0)

func _one_shot_puis_idle(nom: String) -> void:
	if _mort:
		return
	var etat := _etat_animation()
	if etat == null:
		return
	etat.call("set_animation", nom, false, 0)
	etat.call("add_animation", ANIM_IDLE, 0.0, true, 0)

func _jouer(nom: String, boucle: bool) -> void:
	var etat := _etat_animation()
	if etat != null:
		etat.call("set_animation", nom, boucle, 0)

func _etat_animation() -> Object:
	if _spine == null:
		return null
	return _spine.call("get_animation_state") as Object
