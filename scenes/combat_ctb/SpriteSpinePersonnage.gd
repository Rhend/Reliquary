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

static func disponible() -> bool:
	return ClassDB.class_exists("SpineSprite") \
			and ResourceLoader.exists(CHEMIN_SKEL) \
			and ResourceLoader.exists(CHEMIN_ATLAS)

# Fabrique : null si le runtime spine-godot ou les assets manquent —
# l'appelant retombe alors sur son placeholder, sans erreur.
static func creer() -> SpriteSpinePersonnage:
	if not disponible():
		return null
	var noeud := SpriteSpinePersonnage.new()
	if noeud._construire_spine():
		return noeud
	noeud.free()
	return null

func _construire_spine() -> bool:
	var skel: Resource = load(CHEMIN_SKEL)
	var atlas: Resource = load(CHEMIN_ATLAS)
	if skel == null or atlas == null:
		push_warning("SpriteSpinePersonnage : assets Spine illisibles (%s)" % CHEMIN_SKEL)
		return false
	var donnees: Resource = ClassDB.instantiate("SpineSkeletonDataResource")
	donnees.skeleton_file_res = skel
	donnees.atlas_res = atlas
	if not bool(donnees.call("is_skeleton_data_loaded")):
		push_warning("SpriteSpinePersonnage : données Spine invalides (%s)" % CHEMIN_SKEL)
		return false
	_spine = ClassDB.instantiate("SpineSprite") as Node
	_spine.set("skeleton_data_res", donnees)
	add_child(_spine)
	# Échelle : hauteur native du squelette → HAUTEUR_CIBLE_PX à l'écran.
	var hauteur := HAUTEUR_SOURCE_DEFAUT
	if donnees.has_method("get_height"):
		var h := float(donnees.call("get_height"))
		if h > 0.0:
			hauteur = h
	_spine.set("scale", Vector2.ONE * (HAUTEUR_CIBLE_PX / hauteur))
	_jouer(ANIM_IDLE, true)
	return true

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
	if _spine == null or _mort:
		return
	_mort = true
	var etat: Object = _spine.call("get_animation_state")
	etat.call("set_animation", ANIM_DEATH, false, 0)

func _one_shot_puis_idle(nom: String) -> void:
	if _spine == null or _mort:
		return
	var etat: Object = _spine.call("get_animation_state")
	etat.call("set_animation", nom, false, 0)
	etat.call("add_animation", ANIM_IDLE, 0.0, true, 0)

func _jouer(nom: String, boucle: bool) -> void:
	var etat: Object = _spine.call("get_animation_state")
	etat.call("set_animation", nom, boucle, 0)
