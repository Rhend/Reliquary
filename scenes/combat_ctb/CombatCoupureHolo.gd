# ============================================================
# CombatCoupureHolo — coupure holographique du split de combat.
#
# Remplace l'ancienne ligne de séparation (2 traits pleins, avant 08/2026) :
# chaque zone de combat s'arrête un peu avant l'axe de split, et tout le
# rendu holographique (glow, scanlines, sweep, bordures) vit exclusivement
# dans le vide entre les deux — jamais en surimpression sur les décors. Un
# seul shader (`combat_coupure_holo.gdshader`) porte toute l'animation
# (flicker, sweep, pulse, flux animé des bordures) : rien à piloter depuis
# `_process`, `TIME` suffit.
#
# class_name statique (comme CombatFondScinde/BiomeBackground) : un ColorRect
# plein cadre posé AU-DESSUS des deux décors, qui reprend l'AXE DE SPLIT
# EXISTANT (même formule que `CombatFondScinde.x_frontiere`, même
# `bande_vs_px`) — géométrie inchangée, seul le traitement visuel change.
# ============================================================
class_name CombatCoupureHolo
extends ColorRect

const SHADER_PATH := "res://scenes/combat_ctb/combat_coupure_holo.gdshader"

# Demi-largeur du vide, en fraction de la largeur d'écran (~0,9 % par côté,
# ~1,8 % au total — point de départ à ajuster à l'œil en jeu, cf. spec).
const GAP_FRAC := 0.009

static func construire(parent: Control, bande_vs_px: float,
		vue: Vector2 = Vector2(1280, 720)) -> CombatCoupureHolo:
	var n := CombatCoupureHolo.new()
	n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("rect_size", vue)
	mat.set_shader_parameter("bande_vs_px", bande_vs_px)
	mat.set_shader_parameter("gap_frac", GAP_FRAC)
	n.material = mat
	# La pente de l'axe dépend de la largeur réelle du nœud, connue seulement
	# après le premier layout — même pattern que BiomeBackground._apply_split.
	n.resized.connect(func() -> void:
		mat.set_shader_parameter("rect_size", n.size))
	parent.add_child(n)
	return n
