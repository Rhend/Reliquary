# ============================================================
# EnergySpark — petite étincelle d'énergie qui remonte un EnergyLink.
#
# Boule jaune lumineuse (halo diffus + cœur brillant) déplacée par tween le long
# du filament au clic de la boule : quand elle atteint la boule, le quartier
# éclot. Purement décorative — ne capte jamais la souris.
# ============================================================
class_name EnergySpark extends Control

var accent: Color = Color(1.0, 0.92, 0.45)   # jaune chaud d'énergie

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	set_process(true)

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var rmax := minf(size.x, size.y) * 0.5
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)

	# Halo diffus (dégradé concentrique doux).
	for i in 5:
		var t := float(i) / 4.0
		var r: float = rmax * (0.32 + t * 1.0)
		var a: float = lerp(0.34, 0.0, t) * (0.7 + 0.3 * pulse)
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, a))

	# Cœur brillant.
	draw_circle(c, rmax * (0.30 + 0.05 * pulse), Color(accent.r, accent.g, accent.b, 0.92))
	draw_circle(c, rmax * 0.16, Color(1.0, 1.0, 1.0, 0.95))
