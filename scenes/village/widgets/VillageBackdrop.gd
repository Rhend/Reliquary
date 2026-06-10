# ============================================================
# VillageBackdrop — Fond d'ambiance animé du hub du Village.
#
# Deux couches dessinées DERRIÈRE tout le hub :
#   1. halo radial très sombre teinté par le palier du Village ;
#   2. « poussières d'âme » dérivant lentement vers le haut.
#
# Évolution avec le palier : le halo s'intensifie et les poussières
# deviennent plus nombreuses et plus lumineuses à mesure que le
# Village monte en Maîtrise. Appeler set_tier() à chaque rebuild.
# ============================================================
class_name VillageBackdrop
extends Control

var _tier := 0
var _tint := Color(0.38, 0.38, 0.52)
var _t    := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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

func _draw() -> void:
	var c := size * 0.5

	# ── 1. Halo radial : disques concentriques très transparents ──
	# L'alpha croît doucement avec le palier → le centre « s'éveille ».
	var base_r := minf(size.x, size.y) * 0.58
	for i in 4:
		var f := 1.0 - float(i) / 4.0
		var a := (0.016 + 0.010 * float(_tier)) * f * (1.0 + 0.15 * sin(_t * 0.8))
		draw_circle(c, base_r * (0.45 + 0.55 * f), Color(_tint, a))

	# ── 2. Poussières d'âme : montée lente + scintillement ──
	var count := 16 + _tier * 8
	for i in count:
		var fi    := float(i)
		var speed := 8.0 + 18.0 * _hash(fi * 3.7)
		var x     := _hash(fi * 1.3) * size.x + sin(_t * 0.5 + fi) * 6.0
		var y     := fposmod(_hash(fi * 2.1) * size.y - _t * speed, size.y)
		var tw    := 0.5 + 0.5 * sin(_t * (1.0 + _hash(fi)) + fi * 2.0)
		var a     := (0.08 + 0.05 * float(_tier)) * tw
		var rad   := 1.0 + 1.6 * _hash(fi * 5.3)
		draw_circle(Vector2(x, y), rad, Color(_tint.lightened(0.4), a))
