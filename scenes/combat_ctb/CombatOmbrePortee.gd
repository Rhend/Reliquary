# ============================================================
# CombatOmbrePortee — ombre portée sous CHAQUE combattant (29/08/2026,
# livraison Christophe : Background_{City,Factory}_Ombre[.png|_Dessus.png]).
#
# DEUX calques par ombre, dans l'ordre où Christophe les a nommés :
#   `Ombre`        — le disque plein (avec son anneau déjà peint dedans),
#                    TOUJOURS visible, posé au repos.
#   `Ombre_Dessus` — le même anneau, isolé SEUL sur calque transparent —
#                    caché au repos, réservé au tour ACTIF (voir
#                    `definir_actif`).
#
# `Background_City_Ombre*` sous les combattants du camp JOUEUR (posés sur le
# trottoir de CombatDecorCity), `Background_Factory_Ombre*` sous l'ADVERSE
# (posés sur le sol de l'Usine) — même logique que le choix de décor de
# CombatFondScinde, la ville ne change jamais de camp aujourd'hui.
#
# TAILLE PROPORTIONNELLE au personnage — corrections successives de Rhend
# après vérification en jeu :
#   1) « aucune corrélation entre la taille du sprite et l'ombre » — une
#      largeur fixe pour tout le monde faisait une ombre de hobbit sous un
#      héros et une ombre de héros sous un placeholder EnergyBoule.
#   2) « l'ombre doit englober les pieds de l'entité et dépasser un peu
#      plus » — caler sur la HAUTEUR du personnage (1er essai) indexait la
#      largeur de l'ombre sur la mauvaise dimension. `creer()` prend donc la
#      LARGEUR rendue du personnage (`SpriteSpinePersonnage.
#      largeur_rendue_px()`, ou `ORBE_TAILLE.x` en repli pour un placeholder)
#      et en dérive la largeur de l'ombre via MARGE_LARGEUR (> 1 : elle doit
#      DÉBORDER du personnage, pas s'arrêter pile à ses bords — resserrée à
#      1.1 ensuite, 1.3 débordait trop).
#
# ANNEAU ACTIF STATIQUE pour l'instant (⚠ SUPERSÉDÉ deux fois 29/08/2026) :
#   1er essai — rotation (`rotation`, l'axe Z de l'écran) : l'anneau est une
#     ELLIPSE (le disque écrasé pour la perspective au sol), la faire tourner
#     dans le plan de l'écran fait BASCULER son grand axe, illusion d'un
#     disque qui bascule en 3D au lieu de tourner à plat — casse le réalisme
#     de la scène.
#   2e essai — pulsation (échelle + alpha) à la place : Rhend préfère
#     finalement une VRAIE rotation à plat, mais le bon geste (faire tourner
#     un MOTIF sur l'anneau, pas l'ellipse elle-même) est remis à plus tard —
#     retiré ENTIÈREMENT dans l'intervalle. `definir_actif()` ne fait
#     aujourd'hui que montrer/cacher l'anneau, sans le moindre `_process`.
#
# Posée en SIBLING du sprite/orbe du combattant dans `_sol`, ajoutée AVANT
# lui (CombatCtbUi._construire) : l'ordre des enfants dans Godot EST l'ordre
# de dessin, donc l'ombre reste sous le personnage sans jouer avec le
# z-index. Repositionnée comme lui à chaque `_placer_orbes()` — mêmes pieds,
# donc hérite gratuitement du défilement du sol, du zoom-duel et du slide de
# duel puisqu'elle vit dans la même hiérarchie zoomable (`_couche_scene`).
# ============================================================
class_name CombatOmbrePortee
extends Node2D

const DIR_CITY := "res://assets/background/city/"
const DIR_FACTORY := "res://assets/background/Factory/"

# Largeur de l'ombre = largeur RENDUE du personnage × cette marge (elle doit
# déborder un peu, pas s'arrêter pile aux pieds). Le disque source fait
# 878 px de large nativement.
const MARGE_LARGEUR := 1.1

var _anneau: Sprite2D = null
var _actif := false

static func creer(camp_joueur: bool, largeur_ref_px: float) -> CombatOmbrePortee:
	var dir := DIR_CITY if camp_joueur else DIR_FACTORY
	var prefixe := "Background_City_Ombre" if camp_joueur else "Background_Factory_Ombre"
	var chemin_base := dir + prefixe + ".png"
	if not ResourceLoader.exists(chemin_base):
		return null   # dégradation propre : pas d'ombre plutôt qu'un nœud cassé
	var ombre := CombatOmbrePortee.new()
	var echelle := maxf(largeur_ref_px, 1.0) * MARGE_LARGEUR / 878.0

	var base := Sprite2D.new()
	base.texture = load(chemin_base)
	base.centered = true
	base.scale = Vector2.ONE * echelle
	ombre.add_child(base)

	var chemin_anneau := dir + prefixe + "_Dessus.png"
	if ResourceLoader.exists(chemin_anneau):
		var anneau := Sprite2D.new()
		anneau.texture = load(chemin_anneau)
		anneau.centered = true
		anneau.scale = Vector2.ONE * echelle
		anneau.visible = false
		# Additif (29/08/2026, mesuré : la teinte ville est presque la couleur
		# DU SOL LUI-MÊME — un anneau en alpha normal s'y noyait complètement,
		# invisible pile quand il doit signaler « c'est ton tour ». Même
		# raisonnement que NeonRunners/FactorySoudureVfx : ça doit se comporter
		# comme une source de lumière, pas un autocollant plat, pour rester
		# lisible quelle que soit la couleur du sol dessous).
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		anneau.material = mat
		ombre.add_child(anneau)
		ombre._anneau = anneau

	return ombre

func definir_actif(actif: bool) -> void:
	if _anneau == null:
		return
	_actif = actif
	_anneau.visible = actif
