class_name ClickOrb
extends Control

var tier_color := Color.WHITE
var callback   : Callable
var is_hovered := false
var _t         := 0.0
var _ptween    : Tween

func _ready() -> void:
	pivot_offset = size * 0.5
	mouse_entered.connect(func() -> void: is_hovered = true;  queue_redraw())
	mouse_exited.connect( func() -> void: is_hovered = false; queue_redraw())

	var ico := Label.new()
	ico.text = "✦"
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ico.add_theme_font_size_override("font_size", 28)
	ico.anchor_left   = 0.0; ico.anchor_right  = 1.0
	ico.anchor_top    = 0.0; ico.anchor_bottom = 0.0
	ico.offset_top    = 10;  ico.offset_bottom = 56
	ico.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(ico)

	var lbl := UIHelpers.label("CLIC", 9, tier_color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left   = 0.0; lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0; lbl.anchor_bottom = 0.0
	lbl.offset_top    = 52;  lbl.offset_bottom = 74
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_pulse()
		callback.call()

func _pulse() -> void:
	if _ptween: _ptween.kill()
	_ptween = create_tween().set_trans(Tween.TRANS_SINE)
	_ptween.tween_property(self, "scale", Vector2(0.82, 0.82), 0.06)
	_ptween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT)
	_ptween.tween_property(self, "scale", Vector2.ONE,         0.10)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var glow := tier_color
	glow.a = 0.08 + 0.06 * sin(_t * 2.0) + (0.10 if is_hovered else 0.0)
	draw_circle(c, r + 14.0, glow)
	var fill := tier_color.darkened(0.58); fill.a = 0.90
	draw_circle(c, r, fill)
	var border := tier_color; border.a = 0.50 + 0.25 * sin(_t * 2.0)
	draw_arc(c, r, 0.0, TAU, 64, border, 2.5, true)
	if is_hovered:
		var hov := tier_color; hov.a = 0.30
		draw_arc(c, r + 7.0, 0.0, TAU, 32, hov, 5.0, true)
