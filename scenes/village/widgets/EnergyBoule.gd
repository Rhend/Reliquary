# ============================================================
# EnergyBoule — point d'énergie CLIQUABLE au bout d'un EnergyLink.
#
# Orbe lumineux pulsant + anneau, avec un retour visuel net au survol (grossit,
# s'éclaircit, l'anneau s'étend + curseur main) pour signaler clairement que
# c'est interactif. Émet `clicked` au clic gauche.
# ============================================================
class_name EnergyBoule extends Control

signal clicked

var accent: Color = Color(0.70, 0.85, 1.0)

var _t: float = 0.0
var _hovered: bool = false
var _hover: float = 0.0   # 0..1 lissé (pour des transitions douces)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	set_process(true)

func _process(dt: float) -> void:
	_t += dt
	_hover = lerpf(_hover, 1.0 if _hovered else 0.0, 1.0 - exp(-dt * 12.0))
	scale = Vector2.ONE * (1.0 + 0.14 * _hover)   # léger grossissement au survol
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		clicked.emit()

func _draw() -> void:
	var c := size * 0.5
	var rmax := minf(size.x, size.y) * 0.5
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)

	# Halo diffus (s'intensifie et grossit au survol).
	var glow_r: float = rmax * (0.55 + 0.20 * pulse + 0.30 * _hover)
	for i in 5:
		var t := float(i) / 4.0
		var r: float = glow_r * (0.45 + t * 1.05)
		var a: float = lerp(0.20 + 0.16 * _hover, 0.0, t)
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, a))

	# Anneau « cliquable » : pulse en continu, s'étend et s'éclaircit au survol.
	var ring_r: float = rmax * (0.52 + 0.06 * sin(_t * 2.4)) + _hover * rmax * 0.30
	var ring_c := accent.lightened(0.45)
	ring_c.a = 0.30 + 0.50 * _hover
	draw_arc(c, ring_r, 0.0, TAU, 48, ring_c, 1.5 + 1.5 * _hover, true)

	# Cœur brillant.
	var core_r: float = rmax * (0.22 + 0.04 * pulse + 0.06 * _hover)
	draw_circle(c, core_r * 2.0, Color(accent.r, accent.g, accent.b, 0.28 + 0.22 * _hover))
	draw_circle(c, core_r, Color(1, 1, 1, 0.55 + 0.35 * _hover))
