# ============================================================
# BonusStrikeWidget.gd — Compteur de Bonus Strike (overlay combat).
#
# Cercle 80×80 affiché en overlay top-right dans CombatScene.
# Incrémenté à chaque hit du héro, brisé sur coup lourd ennemi.
#
# Paliers :
#   0       → gris (inactif)
#   1–4     → blanc  (×1.05 XP)
#   5–9     → jaune  (×1.10 XP)
#   10–19   → orange (×1.20 XP)
#   20–29   → or     (×1.35 XP)
#   30+     → légendaire (×1.50 XP)
# ============================================================
class_name BonusStrikeWidget extends Control

const SIZE:   float   = 80.0
const RADIUS: float   = 36.0
const CENTER: Vector2 = Vector2(40.0, 40.0)

var _count_label: Label = null
var _sub_label:   Label = null

var _current_strike: int     = 0
var _shake:          Vector2 = Vector2.ZERO
var _shake_time:     float   = 0.0
var _shake_amp:      float   = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter        = MOUSE_FILTER_IGNORE

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_count_label.custom_minimum_size  = Vector2(52.0, 30.0)
	_count_label.add_theme_font_size_override("font_size", 24)
	_count_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	_count_label.mouse_filter = MOUSE_FILTER_IGNORE
	_count_label.position = _label_pos()
	add_child(_count_label)

	_sub_label = Label.new()
	_sub_label.text = "STRIKE"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.custom_minimum_size  = Vector2(60.0, 14.0)
	_sub_label.add_theme_font_size_override("font_size", 9)
	_sub_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 0.70))
	_sub_label.mouse_filter = MOUSE_FILTER_IGNORE
	_sub_label.position = _sublabel_pos()
	add_child(_sub_label)

	EventBus.bonus_strike_changed.connect(_on_strike_changed)
	EventBus.bonus_strike_broken.connect(_on_strike_broken)

func _process(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time -= delta
	if _shake_time <= 0.0:
		_shake_time = 0.0
		_shake      = Vector2.ZERO
	else:
		_shake = Vector2(randf_range(-_shake_amp, _shake_amp),
						 randf_range(-_shake_amp, _shake_amp))
	_count_label.position = _label_pos()    + _shake
	_sub_label.position   = _sublabel_pos() + _shake
	queue_redraw()

func _draw() -> void:
	var center := CENTER + _shake
	var c      := _tier_color(_current_strike)
	var dim    := 0.45 if _current_strike == 0 else 1.0
	draw_circle(center, RADIUS, Color(c, 0.12 * dim))
	draw_arc(center, RADIUS, 0.0, TAU, 64, Color(c, 0.80 * dim), 2.0, true)

# ── Signaux ───────────────────────────────────────────────────

func _on_strike_changed(new_strike: int) -> void:
	var old_tier := _strike_tier(_current_strike)
	var new_tier := _strike_tier(new_strike)
	_current_strike = new_strike

	var c := _tier_color(new_strike)
	_count_label.text = str(new_strike)
	_count_label.add_theme_color_override("font_color", c)
	_sub_label.add_theme_color_override("font_color", Color(c.r, c.g, c.b, 0.65))
	queue_redraw()

	if new_strike > 0 and new_tier > old_tier:
		_play_tier_up()

func _on_strike_broken() -> void:
	_shake_time = 0.42
	_shake_amp  = 7.0
	var tw := create_tween()
	tw.tween_property(_count_label, "modulate", Color(1.2, 0.15, 0.15), 0.12)
	tw.tween_interval(0.18)
	tw.tween_property(_count_label, "modulate", Color.WHITE, 0.28)

# ── Animations ────────────────────────────────────────────────

func _play_tier_up() -> void:
	pivot_offset = Vector2(SIZE * 0.5, SIZE * 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale",    Vector2(1.28, 1.28), 0.14) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate", Color(1.5, 1.5, 1.5), 0.14)
	tw.chain()
	tw.tween_property(self, "scale",    Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate", Color.WHITE, 0.22)

# ── Helpers ───────────────────────────────────────────────────

func _label_pos() -> Vector2:
	return Vector2(CENTER.x - 26.0, CENTER.y - 22.0)

func _sublabel_pos() -> Vector2:
	return Vector2(CENTER.x - 30.0, CENTER.y + 9.0)

func _tier_color(strike: int) -> Color:
	if strike < 1:  return Color(0.50, 0.50, 0.55)
	if strike < 5:  return Color.WHITE
	if strike < 10: return UIColors.FILTER_ON
	if strike < 20: return UIColors.DMG_HEAVY_HERO
	if strike < 30: return UIColors.COMBO_COLOR
	return UIColors.TIER_LEGENDAIRE

func _strike_tier(strike: int) -> int:
	if strike < 1:  return 0
	if strike < 5:  return 1
	if strike < 10: return 2
	if strike < 20: return 3
	if strike < 30: return 4
	return 5
