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
# taille réelle du contrôle, borné par COOLDOWN_RADIUS_MAX : l'anneau
# profite un peu de la place disponible sans devenir envahissant.
const HP_RADIUS           := 64.0
const COOLDOWN_RADIUS     := 76.0
const COOLDOWN_RADIUS_MAX := 88.0   # plafond de croissance de l'anneau
const HP_WIDTH            := 8.0
const COOLDOWN_WIDTH      := 4.0
const PAD                 := 34.0   # marge pour flash + chiffres flottants

const LOW_HP_PCT := 0.30        # seuil de bascule au rouge

# ─── État ────────────────────────────────────────────────────
var camp_color: Color = Color.WHITE
var cur_hp:     float = 100.0
var max_hp:     float = 100.0
var cooldown:   float = 0.0     # 0..1, piloté par la scène

var _flash_col:   Color = Color.TRANSPARENT
var _flash_alpha: float = 0.0

# PV affichés : _disp_hp suit cur_hp en douceur (lissage exponentiel),
# _ghost_hp traîne derrière en cas de dégâts (barre fantôme façon
# jeux de combat : on LIT la perte au lieu d'un saut sec).
# La traînée TIENT GHOST_HOLD secondes avant de drainer : même une
# petite blessure (héros : −7 sur 150) reste lisible, pas seulement
# les gros coups relatifs (ennemi : −17 sur 40).
var _disp_hp:    float = 100.0
var _ghost_hp:   float = 100.0
var _ghost_hold: float = 0.0
# Symétrique pour les soins : _heal_hp reste au niveau d'avant le gain,
# le segment [_heal_hp → _disp_hp] s'affiche en vert puis se résorbe.
var _heal_hp:    float = 100.0
var _heal_hold:  float = 0.0
var _spin_t:     float = 99.0  # éclair de contour à l'entrée (99 = inactif)
const SPIN_DUR   := 0.5
const GHOST_HOLD := 0.45       # s de maintien de la traînée après une blessure/soin
const GHOST_DRAIN := 0.32      # vitesse de résorption (fraction de max_hp par s)

var _hp_label: Label
var _fx_layer: Control
var _center:   Vector2
var _punch_tw: Tween

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

# Rayon extérieur effectif : grandit avec la place disponible, borné
# entre le rayon de référence et COOLDOWN_RADIUS_MAX.
func _cooldown_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.5 - PAD,
			COOLDOWN_RADIUS, COOLDOWN_RADIUS_MAX)

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

# Snap : positionne les PV ET leur affichage (début de combat).
func set_hp(p_cur: float, p_max: float) -> void:
	max_hp    = maxf(p_max, 1.0)
	cur_hp    = clampf(p_cur, 0.0, max_hp)
	_disp_hp  = cur_hp
	_ghost_hp = cur_hp
	_heal_hp  = cur_hp
	_refresh_label()
	queue_redraw()

# Cible : _disp_hp glisse vers cur_hp dans _process (jamais de saut sec).
# Une blessure (re)arme la traînée rouge ; un soin, la traînée verte.
func update_hp(p_cur: float) -> void:
	var nv := clampf(p_cur, 0.0, max_hp)
	if nv < cur_hp:
		_ghost_hold = GHOST_HOLD
	elif nv > cur_hp:
		_heal_hold = GHOST_HOLD
	cur_hp = nv

# Entrée en scène d'un combattant : pop élastique + fondu + éclair
# de contour qui fait un tour complet de l'anneau.
func enter_combat() -> void:
	pivot_offset = size * 0.5
	modulate     = Color(1, 1, 1, 0)
	scale        = Vector2(0.55, 0.55)
	_spin_t      = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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

# Progression du cooldown extérieur (0..1). Le reset à 0 est instantané.
func set_cooldown(frac: float) -> void:
	cooldown = clampf(frac, 0.0, 1.0)
	queue_redraw()

# Chiffre flottant de dégâts. Crit → gros « ★ N » détouré qui claque
# (punch élastique), flash doré et recul marqué de l'anneau.
func damage(amount: int, is_crit: bool) -> void:
	if is_crit:
		_flash_col   = Color(1.0, 0.85, 0.20)
		_flash_alpha = 0.85
		_impact_punch(0.12)
		_spawn_number("★ %d" % amount, 54, Color(1.0, 0.88, 0.20), Vector2.ZERO, true)
	else:
		_impact_punch(0.05)
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
	pivot_offset = size * 0.5
	_flash_col   = Color(1.0, 0.85, 0.20)
	_flash_alpha = 0.55
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.20).set_ease(Tween.EASE_OUT)

# Défaite : désaturation + rétrécissement — l'adversaire « s'éteint ».
func fade_defeated() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color(0.40, 0.40, 0.40, 0.30), 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(0.86, 0.86), 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════════════════════
#  Rendu
# ═══════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(_flash_alpha - delta * 4.0, 0.0)
	_spin_t += delta

	# Lissage des PV affichés : glisse rapide vers la cible…
	_disp_hp = lerpf(_disp_hp, cur_hp, 1.0 - exp(-delta * 9.0))
	if absf(_disp_hp - cur_hp) < 0.4:
		_disp_hp = cur_hp
	# …et la barre fantôme tient un instant, puis draine lentement
	# derrière (la perte reste lisible même petite par rapport au max).
	if _ghost_hp > _disp_hp:
		if _ghost_hold > 0.0:
			_ghost_hold -= delta
		else:
			_ghost_hp = maxf(_ghost_hp - max_hp * delta * GHOST_DRAIN, _disp_hp)
	else:
		_ghost_hp = _disp_hp
	# Traînée de soin : reste au niveau d'avant le gain, puis remonte.
	if _heal_hp < _disp_hp:
		if _heal_hold > 0.0:
			_heal_hold -= delta
		else:
			_heal_hp = minf(_heal_hp + max_hp * delta * GHOST_DRAIN, _disp_hp)
	else:
		_heal_hp = _disp_hp

	_refresh_label()
	queue_redraw()

func _draw() -> void:
	var top := -PI * 0.5
	var hp_pct    := _disp_hp / max_hp if max_hp > 0.0 else 0.0
	var ghost_pct := _ghost_hp / max_hp if max_hp > 0.0 else 0.0
	var r_cd := _cooldown_radius()
	var r_hp := _hp_radius()

	# ── Anneau extérieur : cooldown ──────────────────────────
	draw_arc(_center, r_cd, 0.0, TAU, 96, Color(camp_color, 0.12), COOLDOWN_WIDTH, true)
	if cooldown > 0.001:
		var cd_ready := cooldown >= 0.999
		var cd_col := camp_color if cd_ready else UIColors.TEXT_MUTED
		draw_arc(_center, r_cd, top, top + TAU * cooldown, 96, cd_col, COOLDOWN_WIDTH, true)

	# Éclair d'entrée : arc brillant qui fait un tour complet.
	if _spin_t < SPIN_DUR:
		var sp := _spin_t / SPIN_DUR
		var se := 1.0 - pow(1.0 - sp, 2.0)
		var sa := top + TAU * se
		draw_arc(_center, r_cd, sa - 0.9, sa, 24,
				Color(camp_color.lightened(0.55), (1.0 - sp) * 0.95),
				COOLDOWN_WIDTH + 2.0, true)

	# ── Anneau intérieur : PV (se vide dans le sens horaire) ────
	draw_arc(_center, r_hp, 0.0, TAU, 96, Color(camp_color, 0.10), HP_WIDTH, true)
	# Barre fantôme : segment des PV en train d'être perdus (drain blanc-rouge).
	if ghost_pct > hp_pct + 0.002:
		draw_arc(_center, r_hp, top + TAU * (1.0 - ghost_pct), top + TAU * (1.0 - hp_pct),
				96, Color(1.0, 0.45, 0.35, 0.55), HP_WIDTH, true)
	if hp_pct > 0.001:
		# Transition douce vers le rouge sous LOW_HP_PCT (+ marge de fondu).
		var danger := clampf((hp_pct - LOW_HP_PCT) / 0.12, 0.0, 1.0)
		var hp_col := UIColors.LOG_DEFEAT.lerp(camp_color, danger)
		draw_arc(_center, r_hp, top + TAU * (1.0 - hp_pct), top + TAU, 96, hp_col, HP_WIDTH, true)

	# Traînée de soin : le segment fraîchement gagné brille en vert.
	var heal_pct := _heal_hp / max_hp if max_hp > 0.0 else 0.0
	if hp_pct > heal_pct + 0.002:
		draw_arc(_center, r_hp, top + TAU * (1.0 - hp_pct), top + TAU * (1.0 - heal_pct),
				96, Color(0.35, 1.0, 0.55, 0.60), HP_WIDTH, true)

	# ── Flash (crit doré / soin vert) ────────────────────────
	if _flash_alpha > 0.001:
		draw_circle(_center, r_hp, Color(_flash_col, _flash_alpha * 0.4))

# ═══════════════════════════════════════════════════════════
#  Interne
# ═══════════════════════════════════════════════════════════

# Affiche les PV lissés (_disp_hp) : le compteur défile avec la barre.
func _refresh_label() -> void:
	if _hp_label:
		_hp_label.text = "%d / %d" % [roundi(_disp_hp), int(max_hp)]

func _spawn_number(text: String, font_size: int, color: Color,
		offset: Vector2 = Vector2.ZERO, punch: bool = false) -> void:
	_spawn_number_at(text, font_size, color, offset, punch)

# Chiffre flottant ancré en haut de l'anneau. Délègue le mécanisme (montée +
# fondu) à UIHelpers.float_text, mutualisé avec l'XP flottante de la scène.
func _spawn_number_at(text: String, font_size: int, color: Color,
		offset: Vector2, punch: bool = false) -> void:
	var sx := _center.x + randf_range(-18.0, 18.0) - 20.0 + offset.x
	var sy := _center.y - _hp_radius() - 6.0 + offset.y
	var rise := 75.0 if punch else 60.0
	UIHelpers.float_text(_fx_layer, text, font_size, color, Vector2(sx, sy), rise, punch)
