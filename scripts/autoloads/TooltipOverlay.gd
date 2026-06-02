# ============================================================
# TooltipOverlay — Tooltip JRPG oldschool global.
#
# Autoload CanvasLayer (layer 20). Affiché sur hover via
# UIHelpers.register_tooltip(node, title, body, color).
# Suit la souris et se clamp aux bords du viewport.
# ============================================================
extends CanvasLayer

const MAX_WIDTH:  float = 280.0
const OFFSET:     Vector2 = Vector2(14.0, 6.0)
const MARGIN_PAD: float = 8.0

var _panel:     PanelContainer
var _title_lbl: Label
var _sep:       ColorRect
var _body_lbl:  Label
var _border_color: Color = UIColors.TEXT_MUTED

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(120, 0)
	add_child(_panel)

	var mg := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(s, 8)
	_panel.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	mg.add_child(vb)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title_lbl)

	_sep = ColorRect.new()
	_sep.custom_minimum_size = Vector2(0, 1)
	_sep.color = Color(1, 1, 1, 0.25)
	_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_sep)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 12)
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	vb.add_child(_body_lbl)

	_apply_style()

func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var mp   := _panel.get_viewport().get_mouse_position()
	var vp   := _panel.get_viewport_rect().size
	var ps   := _panel.size
	var pos  := mp + OFFSET
	pos.x = clampf(pos.x, MARGIN_PAD, vp.x - ps.x - MARGIN_PAD)
	pos.y = clampf(pos.y, MARGIN_PAD, vp.y - ps.y - MARGIN_PAD)
	_panel.global_position = pos

# Affiche le tooltip avec titre, corps et couleur d'accent.
func show_for(title: String, body: String, color: Color) -> void:
	_border_color = color
	_title_lbl.text = title
	_title_lbl.add_theme_color_override("font_color", color)
	_body_lbl.text  = body
	_body_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_sep.color = Color(color.r, color.g, color.b, 0.30)
	_apply_style()
	_panel.visible = true

# Masque le tooltip.
func hide_tooltip() -> void:
	_panel.visible = false

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(
			UIColors.BG_DARK.r, UIColors.BG_DARK.g, UIColors.BG_DARK.b, 0.95)
	s.border_color = Color(
			_border_color.r, _border_color.g, _border_color.b, 0.80)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0, 0, 0, 0.50)
	s.shadow_size  = 4
	_panel.add_theme_stylebox_override("panel", s)
