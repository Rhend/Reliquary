# ============================================================
# CombatFondScinde — fond scindé en diagonale de la scène de combat CTB.
#
# Côté HÉROS : décor RÉEL de Christophe, monté par `CombatDecorCity` — plans
# parallaxés et défilants, calé pour que son sol tombe sur `sol_y_frac`.
# Côté ADVERSE : décor RÉEL de l'Usine (Christophe, 28/08/2026), monté par
# `CombatDecorFactory` — même technique, écrêté à la moitié droite par
# `raster_split_mask.gdshader` (voir ce fichier). ⚠ Pas encore DYNAMIQUE selon
# le Lieu de l'expédition (un seul décor adverse livré à ce jour) : l'Usine
# s'affiche pour TOUS les combats, comme le faisait le placeholder "forest"
# avant elle — c'est le sélecteur par Lieu qui reste à écrire, pas ce fichier.
# Ce fichier ne fait plus que COMPOSER les deux moitiés et leur couture ; tout
# ce qui touche aux plans de chaque décor vit dans son propre CombatDecor*.
#
# class_name statique (pattern Balance/ExpeStyle, PAS un autoload) : PARTAGÉ
# entre l'écran de combat réel (CombatCtbUi) et la vitrine (ShowRoom) pour
# que les deux restent identiques à l'octet près — une seule source, jamais
# deux copies qui pourraient diverger.
#
# Pas de clip explicite du décor joueur : chaque sprite du décor adverse porte
# déjà son écrêtage (alpha nul côté héros), donc le décor raster héros —
# ajouté avant lui, en dessous — n'apparaît que là où l'adverse le laisse
# transparaître. `CombatCoupureHolo`, posé par-dessus, peint la coupure
# holographique (vide + bordures animées) — opaque sur toute sa largeur, elle
# masque le mince fondu résiduel des deux décors autour de l'axe sans qu'il
# faille toucher à leur découpe.
# ============================================================
class_name CombatFondScinde

# Perf (24/09/2026, retour Rhend : combat plafonné à ~20 fps) : Ville+Usine à
# elles deux sont ~45 sprites plein cadre alpha-blendés empilés (overdraw, pas
# un souci de shader — testé : regrouper le masque de l'Usine dans un seul
# CanvasGroup n'a RIEN gagné). Le vrai levier est le nombre de PIXELS à
# calculer par calque, donc on rend Ville+Usine dans un SubViewport plus petit
# puis on le réagrandit (`SubViewportContainer` mis à l'échelle, filtrage
# linéaire natif) — un fond lointain n'a pas besoin du piqué natif qu'on vient de
# donner aux sprites Spine au premier plan. `CombatCoupureHolo` (la coupure
# holographique, fine et scrutée au centre de l'écran) reste EN DEHORS, à la
# résolution native, pour ne pas la rendre floue.
#
# ⚠ INCOMPATIBLE avec le zoom-duel tel quel : un SubViewport a une taille FIXE
# et DÉCOUPE tout ce qui dépasse — or les sprites de décor sont volontairement
# plus grands que le cadre nominal (1280×720) pour avoir de la marge quand le
# zoom (`DuelZoomFx`, jusqu'à ×1,55) révèle plus de cadre autour d'un pivot qui
# n'est PAS fixe (il suit le point de contact attaquant/cible). Les enfermer
# dans ce SubViewport perdait cette marge → bandeau gris visible en haut de
# l'écran pendant le zoom (constaté, comparé à l'ancien code). Solution
# retenue (pas de marge de sécurité, jugée trop fragile vu le pivot mobile) :
# `sortir_zoom`/`entrer_zoom` déplacent Ville+Usine HORS du SubViewport (retour
# plein-res, comme avant ce fix) pendant la brève fenêtre de zoom SEULEMENT,
# appelés par `CombatCtbUi._duel_attaque`/`_duel_interrompre`. Le combat passe
# l'essentiel de son temps au repos (zoom=1), c'est LÀ que le downscale compte.
#
# Retour Rhend (02/10/2026, après le fix du zoom ×4 ci-dessous) : "c'est tout
# pixelisé, flou mal venu" — le ×2 (640×360, un quart des pixels) rendait le
# fin détail du décor (néons, rivets) visiblement plus flou que les sprites
# Spine au premier plan (ceux-ci en résolution native depuis le fix fullscreen
# du 24/09/2026). Choix tranché par Rhend : un compromis plutôt que l'un des
# deux extrêmes (retour natif = perd le gain FPS ; garder ×2 = flou gênant).
# ×1,35 (≈55 % des pixels, contre 25 % à ×2) — RATIO FRACTIONNAIRE, donc piloté
# à la main : `SubViewportContainer.stretch_shrink` est un `int`, aucune valeur
# entre ×1 (natif) et ×2 n'est exprimable via cette seule propriété.
const RESOLUTION_DECOR_SHRINK := 1.35
const NOM_CONTENEUR_REDUIT := "DecorReduit"

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de
# calage du sol est volontairement en unités ABSOLUES, pas la taille réelle
# du nœud (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		bande_vs_px: float, vue: Vector2 = Vector2(1280, 720)) -> void:
	# Décor de ville : plans PARALLAXÉS et défilants (CombatDecorCity), pas
	# un simple empilement — le découpage de Christophe est fait pour ça.
	var city := CombatDecorCity.construire(parent, sol_y_frac, sol_x_frac, vue)

	# Ancrage adverse = miroir exact du joueur (1 - sol_x_frac, comme
	# CombatCtbUi.SOL_X_ADVERSE = 1 - SOL_X_JOUEUR) : ce fichier ne connaît
	# qu'un seul ancrage en paramètre, celui du héros.
	var factory := CombatDecorFactory.construire(parent, sol_y_frac, 1.0 - sol_x_frac, bande_vs_px, vue)

	# Ville + Usine construits normalement CI-DESSUS (donc `_noeud_zoom` des
	# deux pointe déjà vers `parent`, le vrai nœud zoomé pendant le duel) puis
	# DÉPLACÉS dans le SubViewport réduit — un simple changement de PARENT,
	# aucune des deux classes n'a besoin de savoir qu'elle est downscalée.
	var conteneur := SubViewportContainer.new()
	conteneur.name = NOM_CONTENEUR_REDUIT
	conteneur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	conteneur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conteneur.stretch = false
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Le layout des CanvasItem à l'intérieur (Ville/Usine, math en pixels
	# ABSOLUS pour `vue` = 1280×720) doit rester calé sur `vue` quel que soit
	# le buffer de rendu réellement alloué (`vp.size`, réduit juste en
	# dessous) — sans ça, le contenu composé pour 1280×720 déborde du buffer
	# réduit, et seul son coin haut-gauche s'y trouve, réétiré sur tout
	# l'écran par le conteneur : zoom ×4 constaté (régression du 24/09/2026,
	# repérée aux captures ScreenshotTool le 02/10/2026). `size_2d_override`
	# fixe cet espace logique à `vue` indépendamment de `vp.size` : le rendu
	# logique reste 1280×720 (la math existante retombe juste), seul le
	# nombre de pixels RASTÉRISÉS diminue — le downscale visé.
	vp.size_2d_override_stretch = true
	vp.size_2d_override = vue
	conteneur.add_child(vp)
	parent.add_child(conteneur)
	# `stretch = false` : le conteneur dessine alors le buffer du SubViewport
	# TEL QUEL (taille native, aucun réétirement auto) — c'est ce qui laisse
	# `vp.size` réglable à la main (avec `stretch = true`, Godot REFUSE
	# silencieusement tout changement manuel : "Can't change the size of a
	# SubViewport with a SubViewportContainer parent that has stretch
	# enabled", constaté aux captures du 02/10/2026 — `stretch_shrink` est un
	# `int`, aucune valeur entre ×1 et ×2 n'est exprimable par CETTE
	# propriété). Sans réétirement auto, un ratio fractionnaire doit donc
	# réétirer lui-même le conteneur ENTIER (texture comprise) via `scale` —
	# pivot par défaut (0,0) = coin haut-gauche, déjà calé sur `parent`.
	vp.size = Vector2i(roundi(vue.x / RESOLUTION_DECOR_SHRINK), roundi(vue.y / RESOLUTION_DECOR_SHRINK))
	conteneur.scale = Vector2(vue.x / vp.size.x, vue.y / vp.size.y)
	var interieur := Control.new()
	interieur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(interieur)
	if city != null:
		city.reparent(interieur, false)
	if factory != null:
		factory.reparent(interieur, false)

	CombatCoupureHolo.construire(parent, bande_vs_px, vue)

# Sort Ville+Usine du SubViewport réduit vers `parent` en PLEIN-RES — à
# appeler juste AVANT `DuelZoomFx.jouer` (le zoom aurait sinon un bandeau gris
# en bord de cadre, voir le commentaire de tête). Idempotent : ne fait rien si
# déjà sorti (duel qui s'enchaîne sans repasser par `entrer_zoom`).
static func sortir_zoom(parent: Control) -> void:
	var interieur := _interieur(parent)
	if interieur == null:
		return
	# Index CROISSANT (0, 1…) : préserve l'ordre Ville PUIS Usine (celui de
	# `construire()`) et les place tous les deux AVANT `CombatCoupureHolo` —
	# `reparent` sans ça les empilerait en dernier, par-dessus la coupure.
	var i := 0
	for c in interieur.get_children().duplicate():
		if c is CombatDecorCity or c is CombatDecorFactory:
			c.reparent(parent, false)
			parent.move_child(c, i)
			i += 1

# Symétrique de `sortir_zoom` : remet Ville+Usine dans le SubViewport réduit —
# à appeler à la fin du zoom (callback `fin` de `DuelZoomFx.jouer`) ET au
# début de `_duel_interrompre` (un duel tué via `Tween.kill()` n'émet JAMAIS
# `finished`, donc pas d'appel naturel — sans ce filet, le décor resterait
# bloqué en plein-res, perte de perf silencieuse mais pas de bug visuel).
# Idempotent : ne fait rien si déjà dedans.
static func entrer_zoom(parent: Control) -> void:
	var interieur := _interieur(parent)
	if interieur == null:
		return
	for c in parent.get_children().duplicate():
		if c is CombatDecorCity or c is CombatDecorFactory:
			c.reparent(interieur, false)

static func _interieur(parent: Control) -> Control:
	var conteneur := parent.get_node_or_null(NOM_CONTENEUR_REDUIT) as SubViewportContainer
	if conteneur == null or conteneur.get_child_count() == 0:
		return null
	var vp := conteneur.get_child(0) as SubViewport
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Control

# Position X de la diagonale (côté héros) à une hauteur `y` donnée (0 = haut,
# h = bas) — SOURCE UNIQUE de cette frontière. `CombatCtbUi._dessiner_sol` et
# `ShowRoom._dessiner_sol_combat` s'en servent pour ne JAMAIS peindre leur
# chrome de sol (ligne d'horizon + bande dégradée) au-delà, dans le biome
# adverse : dessiné plein cadre, ce chrome empiétait sur le biome de droite
# et donnait l'impression que son sol traversait la couture (26/08/2026,
# signalé par Rhend).
static func x_frontiere(y: float, h: float, w: float, bande_vs_px: float) -> float:
	if h <= 0.0:
		return w * 0.5
	return w * 0.5 + bande_vs_px * (0.5 - y / h)
