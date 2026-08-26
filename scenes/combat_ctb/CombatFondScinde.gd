# ============================================================
# CombatFondScinde — fond scindé en diagonale de la scène de combat CTB.
#
# Côté HÉROS : décor RÉEL de Christophe, monté par `CombatDecorCity` — plans
# parallaxés et défilants, calé pour que son sol tombe sur `sol_y_frac`.
# Côté ADVERSE : toujours le placeholder procédural `BiomeBackground` (preset
# "forest") — le Lieu n'a pas encore d'art dédié, seule la ville héros a été
# livrée. Ce fichier ne fait plus que COMPOSER les deux moitiés et leur
# couture ; tout ce qui touche aux plans de la ville vit dans CombatDecorCity.
#
# class_name statique (pattern Balance/ExpeStyle, PAS un autoload) : PARTAGÉ
# entre l'écran de combat réel (CombatCtbUi) et la vitrine (ShowRoom) pour
# que les deux restent identiques à l'octet près — une seule source, jamais
# deux copies qui pourraient diverger.
#
# Pas de clip explicite du décor joueur : le shader de `fond_adverse` se
# découpe déjà tout seul sur la diagonale (alpha nul côté héros), donc le
# décor raster — ajouté avant lui, en dessous — n'apparaît que là où le
# placeholder adverse le laisse transparaître. Le liseré `seam` par-dessus
# dessine la même double ligne diagonale que l'écran de combat.
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

	var fond_adverse := BiomeBackground.new()
	fond_adverse.apply_preset("forest")
	fond_adverse.set_split(2, bande_vs_px)
	parent.add_child(fond_adverse)

	var seam := Control.new()
	seam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seam.draw.connect(_dessiner_diagonale.bind(seam, bande_vs_px))
	seam.resized.connect(seam.queue_redraw)
	parent.add_child(seam)

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

# Bande diagonale entre le décor joueur et le placeholder adverse — même
# tracé qu'avant le passage au décor réel (double liseré cyan/magenta).
static func _dessiner_diagonale(seam: Control, bande_vs_px: float) -> void:
	var w := seam.size.x
	var h := seam.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var xt := x_frontiere(0.0, h, w, bande_vs_px)
	var xb := x_frontiere(h, h, w, bande_vs_px)
	seam.draw_line(Vector2(xt, 0), Vector2(xb, h), Color(UIColors.CYBER_ACCENT, 0.55), 2.0)
	seam.draw_line(Vector2(xt + 5, 0), Vector2(xb + 5, h),
			Color(UIColors.CYBER_ACCENT_2, 0.35), 1.0)
