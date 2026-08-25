# ============================================================
# CombatFondScinde — fond scindé en diagonale de la scène de combat CTB.
#
# Côté HÉROS : décor RÉEL de Christophe (`assets/background/city/*.png`,
# calé pour que son sol tombe sur `sol_y_frac`). Côté ADVERSE : toujours le
# placeholder procédural `BiomeBackground` (preset "forest") — le Lieu n'a
# pas encore d'art dédié, seule la ville héros a été livrée.
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

const DECOR_DIR := "res://assets/background/city/"
# Couches du décor, du plan le PLUS LOINTAIN au plus proche (les fichiers sont
# pré-calés sur un même canevas 4770×2655 : un simple empilement suffit).
const DECOR_COUCHES: Array[String] = [
	"Background_City_Plan_Fond.png",
	"Background_City_Plan_Fond_2.png",
	"Background_City_Plan_5_Immeuble_01.png",
	"Background_City_Plan_5_Immeuble_02.png",
	"Background_City_Plan_4_Immeuble_01.png",
	"Background_City_Plan_4_Immeuble_01_Neon.png",
	"Background_City_Plan_4_Immeuble_02.png",
	"Background_City_Plan_3_Immeuble_01.png",
	"Background_City_Plan_3_Immeuble_01_Neon.png",
	"Background_City_Plan_2_Sol.png",
]
# Hauteur du SOL DANS le décor city, en fraction de l'image cadrée. Mesurée
# sur la livraison de Christophe : le trottoir commence plus bas que le sol
# du combat, donc le décor est REMONTÉ pour que les pieds y posent vraiment —
# sans ça les personnages flottent. À réajuster si le décor change.
const DECOR_SOL_FRAC := 0.688

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de
# calage du sol est volontairement en unités ABSOLUES, pas la taille réelle
# du nœud (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float, bande_vs_px: float,
		vue: Vector2 = Vector2(1280, 720)) -> void:
	var fond_joueur := Control.new()
	fond_joueur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond_joueur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cale le SOL du décor sur celui du combat, sans laisser de vide au cadre.
	# Décaler seul ne suffit pas : remonter le décor découvre le bas de l'écran.
	# On cherche donc la hauteur H telle que le sol tombe sur sol_y_frac ET que
	# le rectangle déborde des deux côtés — les deux contraintes donnent
	# chacune une hauteur minimale, on garde la plus grande (le surplus est
	# rogné par STRETCH_KEEP_ASPECT_COVERED, comportement voulu pour un fond).
	var h := maxf(vue.y * sol_y_frac / DECOR_SOL_FRAC,
			vue.y * (1.0 - sol_y_frac) / (1.0 - DECOR_SOL_FRAC))
	var haut := vue.y * sol_y_frac - DECOR_SOL_FRAC * h
	fond_joueur.offset_top = haut
	fond_joueur.offset_bottom = haut + h - vue.y
	for nom in DECOR_COUCHES:
		var chemin := DECOR_DIR + nom
		if not ResourceLoader.exists(chemin):
			continue   # couche non livrée : on empile ce qui existe
		var couche := TextureRect.new()
		couche.texture = load(chemin)
		couche.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		couche.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		couche.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		couche.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fond_joueur.add_child(couche)
	parent.add_child(fond_joueur)

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

# Bande diagonale entre le décor joueur et le placeholder adverse — même
# tracé qu'avant le passage au décor réel (double liseré cyan/magenta).
static func _dessiner_diagonale(seam: Control, bande_vs_px: float) -> void:
	var w := seam.size.x
	var h := seam.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var xt := w * 0.5 + bande_vs_px * 0.5
	var xb := w * 0.5 - bande_vs_px * 0.5
	seam.draw_line(Vector2(xt, 0), Vector2(xb, h), Color(UIColors.CYBER_ACCENT, 0.55), 2.0)
	seam.draw_line(Vector2(xt + 5, 0), Vector2(xb + 5, h),
			Color(UIColors.CYBER_ACCENT_2, 0.35), 1.0)
