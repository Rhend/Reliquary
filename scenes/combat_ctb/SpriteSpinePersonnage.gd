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
# Hauteur affichée à l'écran (px) — la source Spine fait ~2 800 px de haut,
# l'échelle est déduite de la hauteur réelle du squelette au chargement.
const HAUTEUR_CIBLE_PX := 240.0
const HAUTEUR_SOURCE_DEFAUT := 2770.0   # secours si l'API height est absente

var _spine: Node = null   # SpineSprite — jamais typé (extension optionnelle)
var _mort := false        # Death jouée : plus aucune autre animation
var _animations := PackedStringArray()   # ce que l'export sait vraiment jouer

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
	_spine = ClassDB.instantiate("SpineSprite") as Node
	if _spine == null:
		push_warning("SpriteSpinePersonnage : SpineSprite non instanciable")
		return false
	_spine.set("skeleton_data_res", donnees)
	add_child(_spine)
	for a in donnees.call("get_animations"):
		_animations.append(str(a.call("get_name")))
	# Apparence (skin de palier, costume, niveau d'équipement) : posée AVANT la
	# 1re animation pour que la pose de repos s'affiche d'emblée avec les bons
	# attachements.
	definir_apparence(apparence)
	# Échelle : hauteur native du squelette → hauteur_cible_px à l'écran.
	var hauteur := HAUTEUR_SOURCE_DEFAUT
	if donnees.has_method("get_height"):
		var h := float(donnees.call("get_height"))
		if h > 0.0:
			hauteur = h
	_spine.set("scale", Vector2.ONE * (hauteur_cible_px / hauteur))
	_jouer(ANIM_IDLE, true)
	return true

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
func porte_attachement(nom_slot: String, nom_attachement: String) -> bool:
	if _spine == null:
		return false
	var squelette: Object = _spine.call("get_skeleton")
	if squelette == null:
		return false
	return squelette.call("get_attachment_by_slot_name", nom_slot, nom_attachement) != null

# ─── Animations ──────────────────────────────────────────────

# L'export sait-il jouer cette animation ? (Attack_Shoot n'existe que pour
# Relic : la demander à un ennemi doit être sans effet, pas une erreur.)
func a_animation(nom: String) -> bool:
	return nom in _animations

# Attaque one-shot, retour Idle enchaîné (file d'animations Spine, piste 0).
func jouer_attaque() -> void:
	_one_shot_puis_idle(ANIM_ATTACK)

# Attaque à distance — même mécanique (ignorée si l'export ne la porte pas).
func jouer_attaque_distance() -> void:
	_one_shot_puis_idle(ANIM_ATTACK_SHOOT)

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
