# ============================================================
# GodRays.gd — Rayons de lumière rotatifs + onde de choc (100 % _draw).
#
# Utilisé par le rituel d'évolution : des rayons divins émanent du
# centre (+ center_offset), tournent lentement et respirent.
# `intensity` (0 → 1) pilote l'alpha global — tweenable.
# fire_shockwave() déclenche une double onde circulaire one-shot.
#
# Purement cosmétique : MOUSE_FILTER_IGNORE, aucun état de jeu.
# ============================================================
class_name GodRays
extends Control

const RAY_COUNT := 14
const RAY_LEN   := 950.0
const WAVE_DUR  := 0.75

var color         := Color.WHITE
var intensity     := 0.0           # 0 = invisible, 1 = plein
var center_offset := Vector2.ZERO  # décalage du foyer (suit la carte)

var _t      := 0.0
var _wave_t := 99.0                # 99 = inactif
var _glow   : GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = UIHelpers.radial_glow_tex(128, [0.0, 0.45, 1.0], [0.9, 0.30, 0.0])

func _process(dt: float) -> void:
	_t += dt
	_wave_t += dt
	if intensity > 0.005 or _wave_t < WAVE_DUR:
		queue_redraw()

func fire_shockwave() -> void:
	_wave_t = 0.0

func _draw() -> void:
	var c := size * 0.5 + center_offset

	if intensity > 0.005:
		# Halo central doux
		var bloom_r := 220.0 + 26.0 * sin(_t * 1.1)
		draw_texture_rect(_glow,
				Rect2(c - Vector2.ONE * bloom_r, Vector2.ONE * bloom_r * 2.0),
				false, Color(color.r, color.g, color.b, intensity * 0.40))

		# Rayons : largeur/alpha alternés, longueur qui respire, rotation lente.
		for i in RAY_COUNT:
			var ang  := _t * 0.22 + float(i) * TAU / RAY_COUNT
			var wide := i % 2 == 0
			var half := deg_to_rad(5.0 if wide else 2.4)
			var ray_len := RAY_LEN * (0.80 + 0.20 * sin(_t * 0.7 + float(i) * 1.7))
			var a    := intensity * (0.085 if wide else 0.045) \
					* (0.75 + 0.25 * sin(_t * 1.3 + float(i) * 2.3))
			var pts := PackedVector2Array([
				c,
				c + Vector2(cos(ang - half), sin(ang - half)) * ray_len,
				c + Vector2(cos(ang + half), sin(ang + half)) * ray_len,
			])
			draw_colored_polygon(pts, Color(color.r, color.g, color.b, a))

	# Double onde de choc one-shot (révélation du palier).
	if _wave_t < WAVE_DUR:
		var p  := _wave_t / WAVE_DUR
		var eo := 1.0 - pow(1.0 - p, 3.0)
		var lc := color.lightened(0.45)
		draw_arc(c, 30.0 + eo * 430.0, 0.0, TAU, 64,
				Color(lc.r, lc.g, lc.b, (1.0 - p) * 0.55), 3.0 + 5.0 * (1.0 - p), true)
		draw_arc(c, 30.0 + eo * 300.0, 0.0, TAU, 64,
				Color(lc.r, lc.g, lc.b, (1.0 - p) * 0.30), 2.0 + 3.0 * (1.0 - p), true)
