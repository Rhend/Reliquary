# ============================================================
# CombatRing — Double anneau épuré d'un combattant.
#
#   • Anneau extérieur = cooldown (trait fin 4px). Se remplit 0→100 %.
#     Muted en charge, couleur vive du camp quand prêt (100 %).
#   • Anneau intérieur = PV (trait 8px). Se vide. Rouge si PV < 30 %.
#   • Centre : "PV / max".
#
# Gère aussi les chiffres flottants (dégâts / crit / soin) et le flash
# doré sur critique. Le shake d'écran est géré par la scène.
# ============================================================
class_name CombatRing extends Control

# Rayons de RÉFÉRENCE (taille minimale garantie). Le dessin s'adapte à la
# taille réelle du contrôle : plus la zone de combat offre de hauteur, plus
# l'anneau est grand (cf. _cooldown_radius / _hp_radius).
const HP_RADIUS       := 64.0
const COOLDOWN_RADIUS := 76.0
const HP_WIDTH        := 8.0
const COOLDOWN_WIDTH  := 4.0
const PAD             := 34.0   # marge pour flash + chiffres flottants

const LOW_HP_PCT := 0.30        # seuil de bascule au rouge

# ─── État ────────────────────────────────────────────────────
var camp_color: Color = Color.WHITE
var cur_hp:     float = 100.0
var max_hp:     float = 100.0
var cooldown:   float = 0.0     # 0..1, piloté par la scène

var _flash_col:   Color = Color.TRANSPARENT
var _flash_alpha: float = 0.0

var _hp_label: Label
var _fx_layer: Control
var _center:   Vector2

func _ready() -> void:
	var d := (COOLDOWN_RADIUS + PAD) * 2.0
	custom_minimum_size = Vector2(d, d)
	_center = Vector2(d * 0.5, d * 0.5)

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 18)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.custom_minimum_size = Vector2(140, 24)
	_hp_label.position = _center + Vector2(-70.0, -12.0)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	# Le conteneur de colonne étire le widget : recentrer le dessin sur la
	# taille réelle pour que le cercle soit centré dans sa moitié d'écran.
	resized.connect(_recenter)
	_recenter()
	set_process(true)
	_refresh_label()

# Recalcule le centre géométrique d'après la taille courante du contrôle.
func _recenter() -> void:
	_center = size * 0.5
	if _hp_label:
		_hp_label.position = _center + Vector2(-70.0, -12.0)
	queue_redraw()

# Rayon extérieur effectif : grandit avec la place disponible,
# sans jamais descendre sous le rayon de référence.
func _cooldown_radius() -> float:
	return maxf(minf(size.x, size.y) * 0.5 - PAD, COOLDOWN_RADIUS)

# Rayon intérieur effectif : conserve l'écart de référence avec l'extérieur.
func _hp_radius() -> float:
	return _cooldown_radius() - (COOLDOWN_RADIUS - HP_RADIUS)

# ═══════════════════════════════════════════════════════════
#  API publique
# ═══════════════════════════════════════════════════════════

func setup(p_color: Color) -> void:
	camp_color = p_color
	modulate   = Color.WHITE
	scale      = Vector2.ONE
	cooldown   = 0.0
	_flash_alpha = 0.0
	queue_redraw()

func set_hp(p_cur: float, p_max: float) -> void:
	max_hp = maxf(p_max, 1.0)
	cur_hp = clampf(p_cur, 0.0, max_hp)
	_refresh_label()
	queue_redraw()

func update_hp(p_cur: float) -> void:
	cur_hp = clampf(p_cur, 0.0, max_hp)
	_refresh_label()
	queue_redraw()

# Progression du cooldown extérieur (0..1). Le reset à 0 est instantané.
func set_cooldown(frac: float) -> void:
	cooldown = clampf(frac, 0.0, 1.0)
	queue_redraw()

# Chiffre flottant de dégâts. Crit → jaune, +30 %, préfixe "★", flash doré.
func damage(amount: int, is_crit: bool) -> void:
	if is_crit:
		_flash_col   = Color(1.0, 0.85, 0.20)
		_flash_alpha = 0.65
		_spawn_number("★ %d" % amount, 42, Color(1.0, 0.88, 0.20))
	else:
		_spawn_number("-%d" % amount, 28, UIColors.LOG_DEFEAT)

# Chiffre flottant de soin (vert).
func heal(amount: int) -> void:
	_flash_col   = UIColors.HEAL_COLOR
	_flash_alpha = 0.45
	_spawn_number("+%d" % amount, 26, UIColors.HEAL_COLOR)

# Chiffre flottant de poison (vert plus petit, légèrement décalé).
func poison(amount: int) -> void:
	_spawn_number_at("%d" % amount, 18, Color(0.2, 0.85, 0.3), Vector2(22.0, -16.0))

func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.10, 1.10), 0.16).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.16)

func fade_defeated() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.45, 0.45, 0.45, 0.55), 0.5)

# ═══════════════════════════════════════════════════════════
#  Rendu
# ═══════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(_flash_alpha - delta * 4.0, 0.0)
		queue_redraw()

func _draw() -> void:
	var top := -PI * 0.5
	var hp_pct := cur_hp / max_hp if max_hp > 0.0 else 0.0
	var r_cd := _cooldown_radius()
	var r_hp := _hp_radius()

	# ── Anneau extérieur : cooldown ──────────────────────────
	draw_arc(_center, r_cd, 0.0, TAU, 96, Color(camp_color, 0.12), COOLDOWN_WIDTH, true)
	if cooldown > 0.001:
		var cd_ready := cooldown >= 0.999
		var cd_col := camp_color if cd_ready else UIColors.TEXT_MUTED
		draw_arc(_center, r_cd, top, top + TAU * cooldown, 96, cd_col, COOLDOWN_WIDTH, true)

	# ── Anneau intérieur : PV (se vide dans le sens horaire) ────
	draw_arc(_center, r_hp, 0.0, TAU, 96, Color(camp_color, 0.10), HP_WIDTH, true)
	if hp_pct > 0.001:
		var hp_col := UIColors.LOG_DEFEAT if hp_pct < LOW_HP_PCT else camp_color
		draw_arc(_center, r_hp, top + TAU * (1.0 - hp_pct), top + TAU, 96, hp_col, HP_WIDTH, true)

	# ── Flash (crit doré / soin vert) ────────────────────────
	if _flash_alpha > 0.001:
		draw_circle(_center, r_hp, Color(_flash_col, _flash_alpha * 0.4))

# ═══════════════════════════════════════════════════════════
#  Interne
# ═══════════════════════════════════════════════════════════

func _refresh_label() -> void:
	if _hp_label:
		_hp_label.text = "%d / %d" % [int(cur_hp), int(max_hp)]

func _spawn_number(text: String, font_size: int, color: Color) -> void:
	_spawn_number_at(text, font_size, color, Vector2.ZERO)

func _spawn_number_at(text: String, font_size: int, color: Color, offset: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sx := _center.x + randf_range(-18.0, 18.0) - 20.0 + offset.x
	var sy := _center.y - _hp_radius() - 6.0 + offset.y
	lbl.position = Vector2(sx, sy)
	_fx_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", sy - 60.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.3)
	# Suppression garantie via un SceneTreeTimer indépendant du Tween :
	# fiable même si le signal `finished` du Tween parallèle ne se déclenche pas.
	get_tree().create_timer(1.2).timeout.connect(lbl.queue_free)
