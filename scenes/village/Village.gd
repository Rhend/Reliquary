# ============================================================
# Village.gd — Hub circulaire JRPG style SNES.
# Tier 0  : orbe cliquable (hommage clicker) → déblocage Tier 1.
# Tier 1+ : hexagones animés débloqués progressivement.
# ============================================================
extends Control

# ─── Anneau animé ─────────────────────────────────────────────
class CircleRing extends Control:
	var ring_color    := Color.WHITE
	var ring_width    := 13.0
	var fill_fraction := 0.0   # arc de progression XP (0..1)
	var _t            := 0.0

	const _SPARK := [0.4, 1.2, 2.1, 2.9, 3.8, 4.6, 5.4]

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - ring_width * 0.5

		# Corona extérieure
		var corona := ring_color; corona.a = 0.10 + 0.06 * sin(_t * 1.4)
		draw_arc(c, r + 11.0, 0.0, TAU, 128, corona, ring_width * 2.2, true)

		# Anneau principal — respiration
		var main := ring_color; main.a = 0.72 + 0.22 * sin(_t * 1.9)
		draw_arc(c, r, 0.0, TAU, 128, main, ring_width, true)

		# Hairline intérieur
		var inner := ring_color; inner.a = 0.18
		draw_arc(c, r - ring_width * 0.65, 0.0, TAU, 64, inner, 1.5, true)

		# Arc shimmer rotatif
		var sa := _t * 0.75
		var sh  := ring_color.lightened(0.55); sh.a = 0.75
		draw_arc(c, r, sa, sa + 1.1, 24, sh, ring_width * 0.55, true)

		# Arc de progression XP (tier 0)
		if fill_fraction > 0.0:
			var prog_end := -PI * 0.5 + fill_fraction * TAU
			var prog     := ring_color.lightened(0.45); prog.a = 0.95
			draw_arc(c, r, -PI * 0.5, prog_end, 96, prog, ring_width * 1.15, true)

		# Étincelles périphériques
		for i in _SPARK.size():
			var a: float = _SPARK[i] + _t * 0.12
			var sp := c + Vector2(cos(a), sin(a)) * (r + ring_width + 7.0)
			var bl := 0.5 + 0.5 * sin(_t * 2.2 + i * 1.4)
			if bl > 0.55:
				var sc := ring_color; sc.a = (bl - 0.55) * 2.2
				draw_circle(sp, 1.5 + bl * 1.8, sc)

# ─── Orbe cliquable (tier 0) ──────────────────────────────────
class ClickOrb extends Control:
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

		var lbl := Label.new()
		lbl.text = "CLIC"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", tier_color)
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

		# Glow idle
		var glow := tier_color
		glow.a = 0.08 + 0.06 * sin(_t * 2.0) + (0.10 if is_hovered else 0.0)
		draw_circle(c, r + 14.0, glow)

		# Remplissage
		var fill := tier_color.darkened(0.58); fill.a = 0.90
		draw_circle(c, r, fill)

		# Bordure animée
		var border := tier_color
		border.a = 0.50 + 0.25 * sin(_t * 2.0)
		draw_arc(c, r, 0.0, TAU, 64, border, 2.5, true)

		if is_hovered:
			var hov := tier_color; hov.a = 0.30
			draw_arc(c, r + 7.0, 0.0, TAU, 32, hov, 5.0, true)

# ─── Hexagone interactif (tier 1+) ────────────────────────────
class HexItem extends Control:
	var icon_text  := ""
	var label_text := ""
	var tier_color := Color.WHITE
	var callback   : Callable
	var hex_radius := 38.0
	var is_hovered := false
	var _htween    : Tween

	func _ready() -> void:
		pivot_offset = size * 0.5

		var ico := Label.new()
		ico.text = icon_text
		ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		ico.add_theme_font_size_override("font_size", 24)
		ico.anchor_left   = 0.0; ico.anchor_right  = 1.0
		ico.anchor_top    = 0.0; ico.anchor_bottom = 0.0
		ico.offset_top    = 14;  ico.offset_bottom = 56
		ico.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		add_child(ico)

		var lbl := Label.new()
		lbl.text = label_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", tier_color)
		lbl.anchor_left   = 0.0; lbl.anchor_right  = 1.0
		lbl.anchor_top    = 0.0; lbl.anchor_bottom = 0.0
		lbl.offset_top    = 54;  lbl.offset_bottom = 78
		lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)

		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)

	func _on_enter() -> void:
		is_hovered = true
		_tween_scale(1.2)
		queue_redraw()

	func _on_exit() -> void:
		is_hovered = false
		_tween_scale(1.0)
		queue_redraw()

	func _tween_scale(target: float) -> void:
		if _htween: _htween.kill()
		_htween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_htween.tween_property(self, "scale", Vector2(target, target), 0.15)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			if _htween: _htween.kill()
			_htween = create_tween().set_trans(Tween.TRANS_SINE)
			_htween.tween_property(self, "scale", Vector2(0.88, 0.88), 0.07)
			_htween.tween_callback(callback)

	func _draw() -> void:
		var c   := size * 0.5
		var pts := _hex(c, hex_radius)

		var fill := tier_color.darkened(0.62); fill.a = 0.88
		draw_colored_polygon(pts, fill)

		if is_hovered:
			var corona := tier_color; corona.a = 0.18
			draw_colored_polygon(_hex(c, hex_radius + 14.0), corona)
			_draw_border(pts, tier_color, 3.0)
			var soft := tier_color; soft.a = 0.35
			_draw_border(_hex(c, hex_radius + 9.0), soft, 5.0)
		else:
			var border := tier_color.darkened(0.25); border.a = 0.50
			_draw_border(pts, border, 1.5)

	func _hex(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(c + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * r)
		return pts

	func _draw_border(pts: PackedVector2Array, col: Color, w: float) -> void:
		for i in 6:
			draw_line(pts[i], pts[(i + 1) % 6], col, w, true)

# ─── Constantes ───────────────────────────────────────────────
const RING_RADIUS  := 135.0
const HEX_SIZE     := Vector2(92.0, 92.0)
const TIER_0_COLOR := Color(0.38, 0.38, 0.52)
const XP_PER_CLICK := 20.0

# [label, icon, tier_min, callback_name]
const MENU_ITEMS: Array = [
	["HÉRO",        "👤", 1, "_go_hero"      ],
	["EXPÉDITIONS", "⚔",  1, "_go_adventure" ],
	["ÉVOLUTIONS",  "▲",  2, "_go_evolutions"],
	["FORGE",       "🔨", 3, "_go_forge"     ],
	["SANCTUAIRE",  "✦",  4, "_go_sanctuary" ],
	["RELIQUE",     "◈",  5, "_go_relic"     ],
]

# ─── Références live (tier 0) ─────────────────────────────────
var _ring      : CircleRing
var _xp_label  : Label

# ─── Init ─────────────────────────────────────────────────────
func _ready() -> void:
	SaveManager.load_save()
	_build_ui()

func _active_creature() -> Dictionary:
	var cid := GameData.player.get("active_creature_id", "") as String
	if cid.is_empty(): return {}
	return GameData.get_entity(cid)

# ─── Construction ─────────────────────────────────────────────
func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var creature := _active_creature()
	var tier     := creature.get("current_tier", 0) as int

	if tier == 0:
		_build_tier0(creature)
	else:
		_build_hub(creature, tier)

func _build_tier0(creature: Dictionary) -> void:
	var diam  := (RING_RADIUS + 24.0) * 2.0
	var xp    := creature.get("current_xp", 0.0) as float
	var xpmax := float(GameData.xp_thresholds[1])

	_ring = CircleRing.new()
	_ring.ring_color    = TIER_0_COLOR
	_ring.ring_width    = 13.0
	_ring.fill_fraction = minf(xp / xpmax, 1.0)
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	add_child(_ring)

	# Nom du héro
	var lname := Label.new()
	lname.text = creature.get("name", "Héro") as String
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 15)
	lname.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.2))
	_center(lname, Vector2(0.0, -60.0), Vector2(150.0, 22.0))
	add_child(lname)

	# Orbe cliquable
	var orb := ClickOrb.new()
	orb.tier_color   = TIER_0_COLOR
	orb.callback     = Callable(self, "_on_hero_click")
	_center(orb, Vector2(0.0, -4.0), Vector2(90.0, 90.0))
	orb.pivot_offset = Vector2(45.0, 45.0)
	add_child(orb)

	# Compteur XP
	_xp_label = Label.new()
	_xp_label.text = "%d / %d XP" % [int(xp), int(xpmax)]
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.3))
	_center(_xp_label, Vector2(0.0, 56.0), Vector2(160.0, 20.0))
	add_child(_xp_label)

func _build_hub(creature: Dictionary, tier: int) -> void:
	var tcolor := UIColors.tier_color(tier)
	var diam   := (RING_RADIUS + 24.0) * 2.0

	_ring = CircleRing.new()
	_ring.ring_color = tcolor
	_ring.ring_width = 13.0
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	add_child(_ring)

	# Nom du héro
	var lname := Label.new()
	lname.text = creature.get("name", "Héro") as String
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 17)
	lname.add_theme_color_override("font_color", tcolor)
	_center(lname, Vector2(0.0, -14.0), Vector2(150.0, 26.0))
	add_child(lname)

	# Tier label
	var ltier := Label.new()
	ltier.text = GameData.get_tier_name(tier)
	ltier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ltier.add_theme_font_size_override("font_size", 11)
	ltier.add_theme_color_override("font_color", tcolor.lerp(Color.WHITE, 0.40))
	_center(ltier, Vector2(0.0, 12.0), Vector2(130.0, 20.0))
	add_child(ltier)

	# Hexagones débloqués
	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool: return d[2] <= tier)
	var n := unlocked.size()
	for i in n:
		var ang := -PI * 0.5 + i * TAU / n
		var pos := Vector2(cos(ang), sin(ang)) * RING_RADIUS
		var d: Array = unlocked[i]
		_make_hex(d[0], d[1], tcolor, pos, Callable(self, d[3]))

# ─── Clicker mechanic ─────────────────────────────────────────
func _on_hero_click() -> void:
	var hero  := GameData.get_entity("hero")
	var xp    := hero.get("current_xp", 0.0) as float + XP_PER_CLICK
	hero["current_xp"] = xp
	var xpmax := float(GameData.xp_thresholds[1])
	_ring.fill_fraction = minf(xp / xpmax, 1.0)
	_xp_label.text      = "%d / %d XP" % [int(xp), int(xpmax)]
	EventBus.xp_gained.emit("hero", XP_PER_CLICK)
	if MasterySystem.can_evolve("hero"):
		MasterySystem.evolve_entity("hero")
		SaveManager.save()
		get_tree().reload_current_scene()

# ─── Factory hexagone ─────────────────────────────────────────
func _make_hex(lbl: String, icon: String, tcolor: Color, pos: Vector2, cb: Callable) -> void:
	var item := HexItem.new()
	item.icon_text  = icon
	item.label_text = lbl
	item.tier_color = tcolor
	item.callback   = cb
	_center(item, pos, HEX_SIZE)
	item.pivot_offset = HEX_SIZE * 0.5
	add_child(item)

# ─── Navigation ───────────────────────────────────────────────
func _go_hero()       -> void: get_tree().change_scene_to_file("res://scenes/village/hero.tscn")
func _go_adventure()  -> void: get_tree().change_scene_to_file("res://scenes/village/adventure_select.tscn")
func _go_evolutions() -> void: get_tree().change_scene_to_file("res://scenes/village/evolution_hall.tscn")
func _go_forge()      -> void: get_tree().change_scene_to_file("res://scenes/village/forge.tscn")
func _go_sanctuary()  -> void: pass  # TODO: scene sanctuaire
func _go_relic()      -> void: pass  # TODO: scene relique

# ─── Utils ────────────────────────────────────────────────────
func _center(ctrl: Control, pos: Vector2, sz: Vector2) -> void:
	ctrl.anchor_left   = 0.5; ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5; ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = pos.x - sz.x * 0.5
	ctrl.offset_right  = pos.x + sz.x * 0.5
	ctrl.offset_top    = pos.y - sz.y * 0.5
	ctrl.offset_bottom = pos.y + sz.y * 0.5
