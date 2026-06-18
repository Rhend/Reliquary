# ============================================================
# CombatBar — Barre de combattant style JRPG old school.
#
# Remplace le double anneau (CombatRing) : un cadre biseauté contenant
#   • le nom du combattant (haut-gauche) + ses PV chiffrés (haut-droite),
#   • une barre de PV (ex-anneau intérieur) avec traînées de lecture
#     (perte en rouge, soin en vert) et bascule au rouge sous 30 %,
#   • une jauge d'action ATB (ex-anneau extérieur de cooldown).
#
# Conserve tout le feedback de l'anneau : flash doré sur critique, punch
# d'impact, chiffres flottants (dégâts / soin / poison), célébration et
# extinction du vaincu. La couleur suit la rareté du combattant (camp_color).
#
# L'animation de remplissage de l'ATB est pilotée par la scène (set_atb),
# exactement comme l'était set_cooldown sur l'anneau.
# ============================================================
class_name CombatBar extends Control

# ─── Géométrie interne (cadre + 2 jauges) ───────────────────
const PAD      := 8.0
const NAME_H   := 20.0
const HP_BAR_H := 18.0
const ATB_H    := 7.0
const GAP      := 5.0
const MIN_H    := PAD + NAME_H + GAP + HP_BAR_H + GAP + ATB_H + PAD

const LOW_HP_PCT  := 0.30        # bascule au rouge
const GHOST_HOLD  := 0.45        # maintien de la traînée avant résorption
const GHOST_DRAIN := 0.32        # vitesse de résorption (fraction de max/s)

# ─── État ────────────────────────────────────────────────────
var camp_color: Color = Color.WHITE
var cur_hp:     float = 100.0
var max_hp:     float = 100.0
var atb:        float = 0.0      # 0..1, piloté par la scène

# Barre miroir (créature, à droite de l'arène) : nom à droite, PV chiffrés à
# gauche, et jauges qui se remplissent depuis le bord DROIT (convention JRPG).
var mirrored: bool = false:
	set(value):
		mirrored = value
		if name_label:
			_layout()
		queue_redraw()

# PV affichés lissés + traînées (portés de CombatRing pour la lisibilité).
var _disp_hp:    float = 100.0
var _ghost_hp:   float = 100.0
var _ghost_hold: float = 0.0
var _heal_hp:    float = 100.0
var _heal_hold:  float = 0.0

var _flash_col:   Color = Color.TRANSPARENT
var _flash_alpha: float = 0.0

var name_label: Label       # public : la scène y écrit le nom et y branche le tooltip
var _hp_label:  Label
var _fx_layer:  Control
var _punch_tw:  Tween

# Les nœuds sont créés dès _init : la scène lit `name_label` au moment de
# construire la bande (avant que la barre n'entre dans l'arbre, donc avant
# _ready). Le rattachement à l'arbre se fait dans _ready.
func _init() -> void:
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_label.text = "—"
	name_label.clip_text = true

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	_hp_label.add_theme_constant_override("outline_size", 3)
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	custom_minimum_size = Vector2(0, MIN_H)
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(name_label)
	add_child(_hp_label)
	add_child(_fx_layer)
	resized.connect(_layout)
	_layout()
	set_process(true)
	_refresh_label()

func _layout() -> void:
	if not name_label:
		return
	if mirrored:
		# Nom à droite, PV chiffrés à gauche.
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_label.position = Vector2(size.x * 0.38, PAD)
		name_label.size     = Vector2(maxf(size.x * 0.62 - PAD, 10.0), NAME_H)
		_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hp_label.position  = Vector2(PAD, PAD)
		_hp_label.size      = Vector2(size.x * 0.60 - PAD, NAME_H)
	else:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.position = Vector2(PAD, PAD)
		name_label.size     = Vector2(maxf(size.x * 0.62 - PAD, 10.0), NAME_H)
		_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hp_label.position  = Vector2(size.x * 0.40, PAD)
		_hp_label.size      = Vector2(size.x * 0.60 - PAD, NAME_H)
	queue_redraw()

# ═══════════════════════════════════════════════════════════
#  API publique (miroir de CombatRing)
# ═══════════════════════════════════════════════════════════

func setup(p_color: Color) -> void:
	camp_color   = p_color
	modulate     = Color.WHITE
	scale        = Vector2.ONE
	atb          = 0.0
	_flash_alpha = 0.0
	queue_redraw()

# Snap PV + affichage (début de combat / rencontre).
func set_hp(p_cur: float, p_max: float) -> void:
	max_hp   = maxf(p_max, 1.0)
	cur_hp   = clampf(p_cur, 0.0, max_hp)
	_disp_hp = cur_hp
	_ghost_hp = cur_hp
	_heal_hp  = cur_hp
	_refresh_label()
	queue_redraw()

# Cible : _disp_hp glisse vers cur_hp dans _process (jamais de saut sec).
func update_hp(p_cur: float) -> void:
	var nv := clampf(p_cur, 0.0, max_hp)
	if nv < cur_hp:
		_ghost_hold = GHOST_HOLD
	elif nv > cur_hp:
		_heal_hold = GHOST_HOLD
	cur_hp = nv

# Remplissage de la jauge ATB (0..1). Remplace set_cooldown.
func set_atb(frac: float) -> void:
	atb = clampf(frac, 0.0, 1.0)
	queue_redraw()

# Entrée en scène : pop élastique + fondu.
func enter_combat() -> void:
	pivot_offset = size * 0.5
	modulate     = Color(1, 1, 1, 0)
	scale        = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Chiffre flottant de dégâts. Crit → gros « ★ N » détouré + flash doré.
func damage(amount: int, is_crit: bool) -> void:
	if is_crit:
		_flash_col   = Color(1.0, 0.85, 0.20)
		_flash_alpha = 0.85
		_impact_punch(0.10)
		_spawn_number("★ %d" % amount, 50, Color(1.0, 0.88, 0.20), Vector2.ZERO, true)
	else:
		_impact_punch(0.05)
		_spawn_number("-%d" % amount, 26, UIColors.LOG_DEFEAT)

func heal(amount: int) -> void:
	_flash_col   = UIColors.HEAL_COLOR
	_flash_alpha = 0.45
	_spawn_number("+%d" % amount, 24, UIColors.HEAL_COLOR)

func poison(amount: int) -> void:
	_spawn_number("%d" % amount, 18, Color(0.2, 0.85, 0.3), Vector2(24.0, 0.0))

func celebrate() -> void:
	pivot_offset = size * 0.5
	_flash_col   = Color(1.0, 0.85, 0.20)
	_flash_alpha = 0.55
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.06, 1.06), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.20).set_ease(Tween.EASE_OUT)

# Défaite : désaturation + rétrécissement — le combattant « s'éteint ».
func fade_defeated() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color(0.40, 0.40, 0.40, 0.35), 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(0.96, 0.96), 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Recul d'impact : petit squash, plus marqué sur un critique.
func _impact_punch(strength: float) -> void:
	pivot_offset = size * 0.5
	if is_instance_valid(_punch_tw):
		_punch_tw.kill()
	_punch_tw = create_tween()
	_punch_tw.tween_property(self, "scale", Vector2.ONE * (1.0 - strength), 0.06) \
			.set_ease(Tween.EASE_OUT)
	_punch_tw.tween_property(self, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════════════════════
#  Process + rendu
# ═══════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(_flash_alpha - delta * 4.0, 0.0)

	_disp_hp = lerpf(_disp_hp, cur_hp, 1.0 - exp(-delta * 9.0))
	if absf(_disp_hp - cur_hp) < 0.4:
		_disp_hp = cur_hp
	# Traînée de perte (rouge) : tient un instant, puis draine derrière.
	if _ghost_hp > _disp_hp:
		if _ghost_hold > 0.0:
			_ghost_hold -= delta
		else:
			_ghost_hp = maxf(_ghost_hp - max_hp * delta * GHOST_DRAIN, _disp_hp)
	else:
		_ghost_hp = _disp_hp
	# Traînée de soin (vert) : remonte vers le niveau gagné.
	if _heal_hp < _disp_hp:
		if _heal_hold > 0.0:
			_heal_hold -= delta
		else:
			_heal_hp = minf(_heal_hp + max_hp * delta * GHOST_DRAIN, _disp_hp)
	else:
		_heal_hp = _disp_hp

	_refresh_label()
	queue_redraw()

func _hp_track_rect() -> Rect2:
	var y := PAD + NAME_H + GAP
	return Rect2(PAD + 2.0, y, maxf(size.x - (PAD + 2.0) * 2.0, 1.0), HP_BAR_H)

func _atb_rect() -> Rect2:
	var y := PAD + NAME_H + GAP + HP_BAR_H + GAP
	return Rect2(PAD + 2.0, y, maxf(size.x - (PAD + 2.0) * 2.0, 1.0), ATB_H)

# Remplit un segment [from_f, to_f] (fractions 0..1) d'une piste. En mode
# miroir, les fractions sont mesurées depuis le bord DROIT.
func _draw_seg(track: Rect2, from_f: float, to_f: float, col: Color) -> void:
	var a := clampf(from_f, 0.0, 1.0)
	var b := clampf(to_f, 0.0, 1.0)
	if b <= a:
		return
	var w := track.size.x
	var x0: float
	if mirrored:
		x0 = track.position.x + w * (1.0 - b)
	else:
		x0 = track.position.x + w * a
	draw_rect(Rect2(Vector2(x0, track.position.y), Vector2(w * (b - a), track.size.y)), col)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# ── Plaque + cadre biseauté (old school) ──────────────────
	draw_rect(r, Color(0.05, 0.06, 0.10, 0.92))
	draw_rect(r, Color(0, 0, 0, 0.65), false, 3.0)
	var inner := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	draw_rect(inner, Color(camp_color.r, camp_color.g, camp_color.b, 0.55), false, 2.0)

	var hp_pct    := _disp_hp / max_hp if max_hp > 0.0 else 0.0
	var ghost_pct := _ghost_hp / max_hp if max_hp > 0.0 else 0.0
	var heal_pct  := _heal_hp / max_hp if max_hp > 0.0 else 0.0

	# ── Barre de PV ───────────────────────────────────────────
	var track := _hp_track_rect()
	draw_rect(track, Color(0, 0, 0, 0.55))
	# Traînée de perte (segment hp → ghost) en rouge clair.
	if ghost_pct > hp_pct + 0.002:
		_draw_seg(track, hp_pct, ghost_pct, Color(1.0, 0.45, 0.35, 0.55))
	# Remplissage principal : couleur camp, vire au rouge sous le seuil.
	if hp_pct > 0.001:
		var danger := clampf((hp_pct - LOW_HP_PCT) / 0.12, 0.0, 1.0)
		var hp_col := UIColors.LOG_DEFEAT.lerp(camp_color, danger)
		_draw_seg(track, 0.0, hp_pct, hp_col)
	# Traînée de soin (segment heal → hp) en vert.
	if hp_pct > heal_pct + 0.002:
		_draw_seg(track, heal_pct, hp_pct, Color(0.35, 1.0, 0.55, 0.60))
	draw_rect(track, Color(camp_color.r, camp_color.g, camp_color.b, 0.55), false, 1.0)

	# ── Jauge ATB ─────────────────────────────────────────────
	var ar := _atb_rect()
	draw_rect(ar, Color(0, 0, 0, 0.50))
	if atb > 0.001:
		var ready := atb >= 0.999
		var atb_col := camp_color if ready else UIColors.TEXT_MUTED
		_draw_seg(ar, 0.0, atb, atb_col)
	draw_rect(ar, Color(camp_color.r, camp_color.g, camp_color.b, 0.40), false, 1.0)

	# ── Flash (crit doré / soin vert) ─────────────────────────
	if _flash_alpha > 0.001:
		draw_rect(r, Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash_alpha * 0.30))

# ═══════════════════════════════════════════════════════════
#  Interne
# ═══════════════════════════════════════════════════════════

func _refresh_label() -> void:
	if _hp_label:
		_hp_label.text = "%d / %d" % [roundi(_disp_hp), int(max_hp)]

# Chiffre flottant ancré juste au-dessus de la barre, montée + fondu.
# Délègue à UIHelpers.float_text (mécanisme mutualisé avec l'XP de la scène).
func _spawn_number(text: String, font_size: int, color: Color,
		offset: Vector2 = Vector2.ZERO, punch: bool = false) -> void:
	var sx := size.x * 0.5 + randf_range(-18.0, 18.0) - 20.0 + offset.x
	var sy := -6.0 + offset.y
	var rise := 75.0 if punch else 60.0
	UIHelpers.float_text(_fx_layer, text, font_size, color, Vector2(sx, sy), rise, punch)
