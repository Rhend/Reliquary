# ============================================================
# Village — Hub circulaire.
# Anneau coloré selon le tier du héro actif ; 4 cartes aux
# cardinalités (N/E/S/O) : Héro · Expéditions · Évolutions · Forge.
# ============================================================
extends Control

# ── Anneau personnalisé ──────────────────────────────────────
class CircleRing extends Control:
	var ring_color := Color.WHITE
	var ring_width := 14.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - ring_width * 0.5
		draw_arc(c, r, 0.0, TAU, 128, ring_color, ring_width, true)

# ── Constantes ────────────────────────────────────────────────
const RING_RADIUS := 130.0
const CARD_SIZE   := Vector2(100.0, 100.0)

# ── Initialisation ────────────────────────────────────────────

func _ready() -> void:
	SaveManager.load_save()
	_build_ui()

# ── Helpers données ───────────────────────────────────────────

func _active_creature() -> Dictionary:
	var cid: String = GameData.player.get("active_creature_id", "")
	if cid.is_empty():
		return {}
	return GameData.get_entity(cid)

# ── Construction ──────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var creature := _active_creature()
	var tier     := creature.get("current_tier", 0) as int
	var tcolor   := UIColors.tier_color(tier)
	var diam     := (RING_RADIUS + 20.0) * 2.0

	# Anneau
	var ring := CircleRing.new()
	ring.ring_color = tcolor
	ring.ring_width = 14.0
	_anchor_center(ring, Vector2.ZERO, Vector2(diam, diam))
	add_child(ring)

	# Nom du héro
	var lbl_name := Label.new()
	lbl_name.text = creature.get("name", "Héro") as String
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.add_theme_font_size_override("font_size", 17)
	lbl_name.add_theme_color_override("font_color", tcolor)
	_anchor_center(lbl_name, Vector2(0.0, -12.0), Vector2(140.0, 26.0))
	add_child(lbl_name)

	# Tier du héro
	var lbl_tier := Label.new()
	lbl_tier.text = GameData.get_tier_name(tier)
	lbl_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_tier.add_theme_font_size_override("font_size", 11)
	lbl_tier.add_theme_color_override("font_color", tcolor.lerp(Color.WHITE, 0.40))
	_anchor_center(lbl_tier, Vector2(0.0, 12.0), Vector2(130.0, 20.0))
	add_child(lbl_tier)

	# 4 cartes
	_make_card("HÉRO",        "👤", UIColors.STAT_HP,        Vector2(0.0,         -RING_RADIUS), _go_hero)
	_make_card("EXPÉDITIONS", "⚔",  UIColors.TYPE_EVENT_POS, Vector2(RING_RADIUS,  0.0        ), _go_adventure)
	_make_card("ÉVOLUTIONS",  "▲",  UIColors.FILTER_ON,      Vector2(0.0,          RING_RADIUS), _go_evolutions)
	_make_card("FORGE",       "🔨", UIColors.STAT_ATK,       Vector2(-RING_RADIUS, 0.0        ), _go_forge)

# ── Carte carrée ──────────────────────────────────────────────

func _make_card(title: String, icon: String, color: Color, center_pos: Vector2, cb: Callable) -> void:
	var btn := Button.new()
	_anchor_center(btn, center_pos, CARD_SIZE)

	var bg_hover := Color(UIColors.BG_CARD.r + 0.06, UIColors.BG_CARD.g + 0.06, UIColors.BG_CARD.b + 0.06)
	btn.add_theme_stylebox_override("normal",  _style(UIColors.BG_CARD, color.darkened(0.25), 2, 8))
	btn.add_theme_stylebox_override("hover",   _style(bg_hover,         color,                2, 8))
	btn.add_theme_stylebox_override("pressed", _style(bg_hover,         color,                2, 8))
	btn.add_theme_stylebox_override("focus",   _style(UIColors.BG_CARD, color.darkened(0.25), 2, 8))

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	btn.add_child(vb)

	var ico := Label.new()
	ico.text = icon
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.add_theme_font_size_override("font_size", 30)
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ico)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lbl)

	btn.pressed.connect(cb)
	add_child(btn)

# ── Navigations ───────────────────────────────────────────────

func _go_hero() -> void:
	get_tree().change_scene_to_file("res://scenes/village/hero.tscn")

func _go_adventure() -> void:
	get_tree().change_scene_to_file("res://scenes/village/adventure_select.tscn")

func _go_evolutions() -> void:
	get_tree().change_scene_to_file("res://scenes/village/evolution_hall.tscn")

func _go_forge() -> void:
	get_tree().change_scene_to_file("res://scenes/village/forge.tscn")

# ── Utilitaires ───────────────────────────────────────────────

func _anchor_center(ctrl: Control, center: Vector2, ctrl_size: Vector2) -> void:
	ctrl.anchor_left   = 0.5;  ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5;  ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = center.x - ctrl_size.x * 0.5
	ctrl.offset_right  = center.x + ctrl_size.x * 0.5
	ctrl.offset_top    = center.y - ctrl_size.y * 0.5
	ctrl.offset_bottom = center.y + ctrl_size.y * 0.5

func _style(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(bw)
	for prop: String in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, radius)
	return s
