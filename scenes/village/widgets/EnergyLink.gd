# ============================================================
# EnergyLink — Filament d'énergie DIFFUS et translucide reliant une entité du
# hub (ex. le cercle du Héros) à un « point d'énergie » flottant dans l'espace.
#
# Rendu volontairement ténu : plusieurs passes larges très transparentes
# (halo diffus) plutôt qu'un trait net, + un point d'énergie en dégradé doux.
# Purement décoratif : ne capte jamais la souris. Points en coordonnées LOCALES
# (le widget est dimensionné comme son parent).
# ============================================================
class_name EnergyLink extends Control

var start_point: Vector2 = Vector2.ZERO
var end_point:   Vector2 = Vector2.ZERO
var accent:      Color   = UIColors.ENERGY_ACCENT
# false : filament diffus et flottant (lien latent, non emprunté).
# true  : lien CONSISTANT (quartier établi) — trait net, ondulation calme.
var solid:       bool    = false

const SEGMENTS := 26

# Passes du halo diffus : [largeur, alpha de base]. Du plus large/faible
# (brume) au plus fin/marqué (cœur du filament) — sans jamais être opaque.
const GLOW_PASSES := [
	[9.0, 0.085],
	[5.0, 0.130],
	[2.5, 0.190],
]

var _phase: float = 0.0

# Position le long du fil au paramètre t (0 = départ, 1 = point d'énergie),
# en suivant l'arc de base (sans l'ondulation animée) pour une montée fluide.
# Utilisé par EnergySpark pour remonter le filament.
func point_at(t: float) -> Vector2:
	var delta := end_point - start_point
	var dist := delta.length()
	if dist < 1.0:
		return start_point
	var n := delta / dist
	var perp := Vector2(-n.y, n.x)
	var base := start_point.lerp(end_point, t)
	var env := sin(t * PI)
	var bend := env * dist * 0.10
	return base + perp * bend

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()

func _draw() -> void:
	var delta := end_point - start_point
	var dist := delta.length()
	if dist < 1.0:
		return
	var n    := delta / dist
	var perp := Vector2(-n.y, n.x)
	var pulse := 0.5 + 0.5 * sin(_phase * 1.2)   # respiration douce

	# Solide : ondulation calme + alpha renforcé (lien établi, net).
	var wob_amp := 1.0 if solid else 3.0
	var alpha_mult := 5.2 if solid else 1.8

	# Trajet : arc léger (s'annule aux extrémités) + ondulation animée subtile.
	var pts := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var base := start_point.lerp(end_point, t)
		var env := sin(t * PI)
		var bend := env * dist * 0.10
		var wobble := sin(t * TAU * 1.5 + _phase * 1.4) * wob_amp * env
		pts.append(base + perp * (bend + wobble))

	# Halo diffus : plusieurs passes superposées (renforcées si solide).
	for pass_def in GLOW_PASSES:
		var w: float = pass_def[0]
		var pa: float = pass_def[1] * alpha_mult * (0.55 + 0.45 * pulse)
		for i in pts.size() - 1:
			var tt := float(i) / float(pts.size() - 1)
			var seg_a: float = pa * lerp(0.30, 1.0, tt)   # plus présent près du point
			draw_line(pts[i], pts[i + 1], Color(accent.r, accent.g, accent.b, seg_a), w, true)

	# Cœur du lien : trait net en permanence pour que la route se LISE comme un
	# chemin (et pas une simple brume). Plus large/opaque une fois consistante.
	var core_a := 0.90 if solid else 0.55
	var core_w := 2.6 if solid else 1.8
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], Color(accent.r, accent.g, accent.b, core_a), core_w, true)

	# Lueur qui « remonte » doucement le filament vers le point d'énergie.
	var spark_t := fmod(_phase * 0.30, 1.0)
	var spark_pos: Vector2 = pts[clampi(int(spark_t * float(SEGMENTS)), 0, pts.size() - 1)]
	draw_circle(spark_pos, 3.5, Color(accent.r, accent.g, accent.b, 0.10 * pulse + 0.03))

	_draw_energy_point(end_point, pulse)

# Point d'énergie : halo concentrique en dégradé doux, sans cœur dur (diffus).
func _draw_energy_point(c: Vector2, pulse: float) -> void:
	var base_r: float = lerp(5.0, 8.0, pulse)
	for i in 5:
		var t := float(i) / 4.0
		var r := base_r * (1.0 + t * 2.6)
		var a: float = lerp(0.16, 0.0, t) * (0.55 + 0.45 * pulse)
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, a))
	draw_circle(c, base_r * 0.5, Color(accent.r, accent.g, accent.b, 0.16 * pulse + 0.06))
