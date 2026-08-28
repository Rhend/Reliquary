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

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de
# calage du sol est volontairement en unités ABSOLUES, pas la taille réelle
# du nœud (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float, sol_x_frac: float,
		bande_vs_px: float, vue: Vector2 = Vector2(1280, 720)) -> void:
	# Décor de ville : plans PARALLAXÉS et défilants (CombatDecorCity), pas
	# un simple empilement — le découpage de Christophe est fait pour ça.
	CombatDecorCity.construire(parent, sol_y_frac, sol_x_frac, vue)

	# Ancrage adverse = miroir exact du joueur (1 - sol_x_frac, comme
	# CombatCtbUi.SOL_X_ADVERSE = 1 - SOL_X_JOUEUR) : ce fichier ne connaît
	# qu'un seul ancrage en paramètre, celui du héros.
	CombatDecorFactory.construire(parent, sol_y_frac, 1.0 - sol_x_frac, bande_vs_px, vue)

	CombatCoupureHolo.construire(parent, bande_vs_px, vue)

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
