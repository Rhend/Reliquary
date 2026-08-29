# ============================================================
# CombatOmbrePortee — ombre portée sous CHAQUE combattant (29/08/2026,
# livraison Christophe : Background_{City,Factory}_Ombre[.png|_Dessus.png]).
#
# DEUX calques par ombre, dans l'ordre où Christophe les a nommés :
#   `Ombre`        — le disque plein (avec son anneau déjà peint dedans),
#                    TOUJOURS visible, posé au repos.
#   `Ombre_Dessus` — le même anneau, isolé SEUL sur calque transparent —
#                    caché au repos, réservé au tour ACTIF (voir
#                    `definir_actif`). Mesuré : l'anneau est une teinte
#                    PARFAITEMENT unie sur tout son pourtour (pas de dégradé
#                    directionnel), donc le faire tourner seul ne se verrait
#                    pas — on COMBINE rotation continue et pulsation
#                    (échelle + alpha, sinusoïdes déphasées comme le flicker
#                    du Fourneau) : c'est la pulsation qui porte l'essentiel
#                    du signal « c'est mon tour », la rotation reste prête à
#                    se voir si Christophe enrichit l'anneau plus tard (un
#                    repère, une graduation) sans qu'il faille retoucher ce
#                    fichier.
#
# `Background_City_Ombre*` sous les combattants du camp JOUEUR (posés sur le
# trottoir de CombatDecorCity), `Background_Factory_Ombre*` sous l'ADVERSE
# (posés sur le sol de l'Usine) — même logique que le choix de décor de
# CombatFondScinde, la ville ne change jamais de camp aujourd'hui.
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

# Largeur cible à l'écran (px), calée sur l'ancien repère placeholder qu'elle
# remplace (`_dessiner_sol` dessinait un cercle de rayon 34, soit 68 px de
# large). Le disque source fait 878 px de large nativement.
const LARGEUR_CIBLE_PX := 80.0
const ECHELLE := LARGEUR_CIBLE_PX / 878.0

const VITESSE_ROTATION := 0.9        # rad/s — lent, un repère, pas un ventilateur
const PULSE_VITESSE := 3.2
const PULSE_ECHELLE_MIN := 0.92
const PULSE_ECHELLE_MAX := 1.18
const PULSE_ALPHA_MIN := 0.55
const PULSE_ALPHA_MAX := 1.0

var _anneau: Sprite2D = null
var _actif := false
var _temps := 0.0

static func creer(camp_joueur: bool) -> CombatOmbrePortee:
	var dir := DIR_CITY if camp_joueur else DIR_FACTORY
	var prefixe := "Background_City_Ombre" if camp_joueur else "Background_Factory_Ombre"
	var chemin_base := dir + prefixe + ".png"
	if not ResourceLoader.exists(chemin_base):
		return null   # dégradation propre : pas d'ombre plutôt qu'un nœud cassé
	var ombre := CombatOmbrePortee.new()

	var base := Sprite2D.new()
	base.texture = load(chemin_base)
	base.centered = true
	base.scale = Vector2.ONE * ECHELLE
	ombre.add_child(base)

	var chemin_anneau := dir + prefixe + "_Dessus.png"
	if ResourceLoader.exists(chemin_anneau):
		var anneau := Sprite2D.new()
		anneau.texture = load(chemin_anneau)
		anneau.centered = true
		anneau.scale = Vector2.ONE * ECHELLE
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
	if _actif == actif or _anneau == null:
		return
	_actif = actif
	_anneau.visible = actif
	if not actif:
		# Repos net : le prochain tour de CE combattant reparte d'un état
		# identique, pas de la phase où le pouls s'est arrêté la fois d'avant.
		_temps = 0.0
		_anneau.rotation = 0.0
		_anneau.scale = Vector2.ONE * ECHELLE
		_anneau.modulate.a = 1.0

func _process(delta: float) -> void:
	if not _actif:
		return
	_temps += delta
	_anneau.rotation = _temps * VITESSE_ROTATION
	var p := 0.5 + 0.5 * sin(_temps * PULSE_VITESSE)
	_anneau.scale = Vector2.ONE * ECHELLE * lerpf(PULSE_ECHELLE_MIN, PULSE_ECHELLE_MAX, p)
	_anneau.modulate.a = lerpf(PULSE_ALPHA_MIN, PULSE_ALPHA_MAX, p)
