# ============================================================
# VillageBackdrop — Fond d'ambiance animé du hub du Village.
#
# Deux couches dessinées DERRIÈRE tout le hub :
#   1. halo central : VRAI dégradé radial (texture GPU, aucun banding)
#      qui respire lentement et s'intensifie avec le palier ;
#   2. « poussières d'âme » : sprites radiaux doux dérivant vers le haut
#      avec parallaxe — les proches sont plus grosses, rapides et
#      lumineuses — et fondu d'entrée/sortie aux bords de l'écran
#      (aucune apparition ou téléportation visible).
#
# Appeler set_tier() à chaque rebuild du hub.
# ============================================================
class_name VillageBackdrop
extends Control

var _tier := 0
var _tint := Color(0.38, 0.38, 0.52)
var _t    := 0.0

# Sprites radiaux générés une fois : falloff long pour le halo,
# cœur serré + jupe douce pour les poussières.
var _halo_tex: GradientTexture2D
var _dust_tex: GradientTexture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo_tex = UIHelpers.radial_glow_tex(256,
			[0.0, 0.28, 0.60, 1.0], [1.0, 0.62, 0.22, 0.0])
	_dust_tex = UIHelpers.radial_glow_tex(64,
			[0.0, 0.20, 0.55, 1.0], [1.0, 0.80, 0.22, 0.0])

# Met à jour le palier et la couleur d'ambiance (couleur de tier du Village).
func set_tier(tier: int, tint: Color) -> void:
	_tier = tier
	_tint = tint
	queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

# Pseudo-aléatoire déterministe : chaque poussière garde sa trajectoire.
func _hash(n: float) -> float:
	return fposmod(sin(n * 127.1) * 43758.5453, 1.0)

# Sprite radial centré en `center`, de rayon `radius`, teinté `col`.
func _blit(tex: Texture2D, center: Vector2, radius: float, col: Color) -> void:
	draw_texture_rect(tex,
			Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
			false, col)

func _draw() -> void:
	var c := size * 0.5

	# ── 1. Halo central : dégradé radial qui « respire » ──
	# Deux couches légèrement déphasées : la respiration paraît organique.
	var breathe := 1.0 + 0.045 * sin(_t * 0.55)
	var halo_r  := minf(size.x, size.y) * 0.78 * breathe
	var halo_a  := (0.11 + 0.035 * float(_tier)) * (1.0 + 0.10 * sin(_t * 0.8))
	_blit(_halo_tex, c, halo_r, Color(_tint, halo_a))
	_blit(_halo_tex, c, halo_r * 0.42 * (2.0 - breathe),
			Color(_tint.lightened(0.12), halo_a * 0.55))

	# ── 2. Poussières d'âme : parallaxe + fondu aux bords ──
	var count := 18 + _tier * 18
	for i in count:
		var fi  := float(i)
		var h_x := _hash(fi * 1.3)   # position horizontale de base
		var h_y := _hash(fi * 2.1)   # phase verticale
		var h_d := _hash(fi * 5.3)   # profondeur → taille, vitesse, éclat

		var depth := 0.30 + 0.70 * h_d        # 0.3 = lointain · 1.0 = proche
		var speed := 7.0 + 30.0 * depth       # les proches montent plus vite
		var sway  := (5.0 + 11.0 * depth) * sin(_t * (0.35 + 0.45 * h_y) + fi * 1.7)
		var pos   := Vector2(h_x * size.x + sway,
				fposmod(h_y * size.y - _t * speed, size.y))

		# Fondu d'entrée (bas) et de sortie (haut) : le wrap est invisible.
		var yn   := pos.y / size.y
		var fade := smoothstep(0.0, 0.10, yn) * (1.0 - smoothstep(0.88, 1.0, yn))
		var tw   := 0.70 + 0.30 * sin(_t * (0.8 + 1.2 * h_d) + fi * 2.0)
		var a    := (0.30 + 0.10 * float(_tier)) * depth * tw * fade
		if a <= 0.005:
			continue

		# Jupe lumineuse douce + cœur net antialiasé.
		var rad := 1.6 + 3.2 * depth
		_blit(_dust_tex, pos, rad * 3.4, Color(_tint.lightened(0.25), a * 0.55))
		draw_circle(pos, rad * 0.55, Color(_tint.lightened(0.65), a), true, -1.0, true)
