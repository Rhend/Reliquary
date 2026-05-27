# ============================================================
# CombatCircle — Cercle de combat, DA identique au CircleRing du Village.
#
# Le RING lui-même est la jauge de PV : il se vide dans le sens
# horaire depuis le haut à mesure que les PV baissent.
# Le ghost ring (plein, 15% alpha) montre le maximum.
# La rotation s'applique uniquement au dessin (draw_set_transform),
# pas aux nœuds enfants (labels, chiffres flottants).
#
# Différenciation par type :
#   CREATURE → rotation normale, styles tier du village
#   TRAP     → rotation très lente, corona froide, lignes radiales
#   EVENT    → pas de rotation, glow externe pulsant fort
# ============================================================
class_name CombatCircle extends Control

# ─── Géométrie ───────────────────────────────────────────────
const CIRCLE_RADIUS := 115.0
const RING_WIDTH    := 14.0
const NAME_HEIGHT   := 32.0
const CTRL_PADDING  := 55.0   # marge pour corona des hauts tiers

const IDLE_PULSE_SCALE:  float = 1.08  # scale max pendant la pulsation idle
const IDLE_PULSE_PERIOD: float = 2.0   # durée d'un cycle complet (s)

enum EntityType { CREATURE, TRAP, BENEDICTION }

# ─── État entité ─────────────────────────────────────────────
var entity_name: String     = ""                  # nom affiché dans le label du haut
var current_hp:  float      = 100.0               # PV actuels, mis à jour via update_hp()
var max_hp:      float      = 100.0               # PV maximum, fixé lors du setup()
var tier:        int        = 0                   # palier 0-5 — détermine couleur et style du ring
var entity_type: EntityType = EntityType.CREATURE  # détermine le style visuel du ring
var is_hero:     bool       = false               # vrai si ce cercle représente le héro

# ─── Nœuds enfants ───────────────────────────────────────────
var _name_label:    Label   # label du nom en haut du cercle
var _hp_label:      Label   # label "HP actuels / HP max" au centre
var _dmg_layer:     Control # couche transparente pour les chiffres flottants
var _circle_center: Vector2 # position du centre géométrique du cercle dans l'espace local

# ─── Animation ───────────────────────────────────────────────
var _t:              float   = 0.0               # horloge générale — pilote shimmer, pulse et orbes
var _ring_rot:       float   = 0.0               # angle de rotation du ring (rad)
var _shake:          Vector2 = Vector2.ZERO      # offset de tremblement courant
var _shake_time:     float   = 0.0               # durée de tremblement restante (s)
var _shake_amplitude: float  = 0.0               # amplitude max du tremblement en cours (px)
var _flash_col:      Color   = Color.TRANSPARENT # couleur du flash (blanc=fort, or=crit, vert=soin)
var _flash_alpha:    float   = 0.0               # alpha du flash, décroît automatiquement dans _process()

# ─── État idle (entre deux événements) ──────────────────────
var is_idle: bool  = false  # vrai pendant l'attente entre événements
var _idle_t: float = 0.0    # horloge dédiée à la pulsation et aux motes ambiantes

# ─── Action bar (remplie par CombatScene) ────────────────────
var action_progress: float = 0.0   # 0..1 — progression de l'arc intérieur d'anticipation d'attaque

# ─── Bouclier d'urgence (Résilience Rare+) ───────────────────
var shield_hp: float = 0.0   # PV de bouclier actuels (0 = pas de bouclier)

# ═══════════════════════════════════════════════════════════
# Construit les nœuds enfants (labels, couche de dégâts) et
# calcule le centre géométrique en fonction des constantes de taille.
func _ready() -> void:
	var w := CIRCLE_RADIUS * 2.0 + CTRL_PADDING * 2.0
	var h := CIRCLE_RADIUS * 2.0 + CTRL_PADDING * 2.0 + NAME_HEIGHT
	custom_minimum_size = Vector2(w, h)
	_circle_center = Vector2(w * 0.5, NAME_HEIGHT + CTRL_PADDING + CIRCLE_RADIUS)

	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.custom_minimum_size  = Vector2(0, NAME_HEIGHT)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 17)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.custom_minimum_size = Vector2(140, 24)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = _circle_center + Vector2(-70.0, -12.0)
	add_child(_hp_label)

	_dmg_layer = Control.new()
	_dmg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dmg_layer)

	set_process(true)

# ═══════════════════════════════════════════════════════════
#  API publique
# ═══════════════════════════════════════════════════════════

# Initialise ou réinitialise le cercle pour un nouveau combattant.
# Doit être appelé avant chaque combat pour mettre à jour nom, PV, tier et type.
func setup(p_name: String, p_hp: float, p_max_hp: float,
		p_tier: int, p_type: EntityType, p_is_hero: bool = false) -> void:
	entity_name  = p_name
	current_hp   = p_hp
	max_hp       = p_max_hp
	tier         = clampi(p_tier, 0, 5)
	entity_type  = p_type
	is_hero      = p_is_hero
	modulate         = Color.WHITE
	scale            = Vector2.ONE
	_t               = 0.0
	_ring_rot        = 0.0
	_shake           = Vector2.ZERO
	_shake_time      = 0.0
	_shake_amplitude = 0.0
	_flash_alpha     = 0.0
	is_idle          = false
	_idle_t          = 0.0
	scale            = Vector2.ONE
	action_progress  = 0.0
	shield_hp        = 0.0
	_refresh_labels()
	queue_redraw()

# Met à jour les PV courants et rafraîchit le label et le ring HP.
func update_hp(new_hp: float) -> void:
	current_hp = clampf(new_hp, 0.0, max_hp)
	_refresh_labels()
	queue_redraw()

# Active la pulsation idle et les motes ambiantes.
func start_idle() -> void:
	is_idle = true
	_idle_t = 0.0

# Arrête l'état idle et remet le cercle à son scale nominal.
func stop_idle() -> void:
	is_idle = false
	scale   = Vector2.ONE

# Déclenche le feedback proportionnel au pourcentage de HP infligé.
# Catégories : faible (<10%), moyen (10-20%), fort (>20%), critique (futur).
func take_damage(amount: int, is_crit: bool) -> void:
	var dmg_pct    := float(amount) / max_hp if max_hp > 0.0 else 0.0
	var hero_deals := not is_hero

	if is_crit:
		_flash_col       = Color.WHITE
		_flash_alpha     = 0.55
		_shake_time      = 0.20
		_shake_amplitude = 10.0
		_spawn_number(str(amount), 48, Color.WHITE)
	elif dmg_pct >= 0.20:
		_flash_col       = Color.WHITE
		_flash_alpha     = 0.55
		_shake_time      = 0.15
		_shake_amplitude = 6.0
		var c := UIColors.DMG_HEAVY_HERO if hero_deals else UIColors.DMG_HEAVY_ENEMY
		_spawn_number(str(amount), 36, c)
	elif dmg_pct >= 0.10:
		_shake_time      = 0.10
		_shake_amplitude = 3.0
		_spawn_number(str(amount), 29, UIColors.FILTER_ON)
	else:
		var c := Color.WHITE if hero_deals else UIColors.LOG_DEFEAT
		_spawn_number(str(amount), 24, c)

# Affiche les dégâts de poison (Marécage Putride) : nombre vert plus petit, légèrement décalé.
func take_poison_damage(amount: int) -> void:
	_spawn_number_offset(str(amount), 18, Color.GREEN, Vector2(22.0, -18.0))

# Déclenche le flash de soin (vert) et fait apparaître le chiffre flottant "+N".
func receive_heal(amount: int) -> void:
	_flash_col   = UIColors.HEAL_COLOR
	_flash_alpha = 0.5
	_spawn_number("+" + str(amount), 24, UIColors.HEAL_COLOR)

# Met à jour les PV du bouclier et rafraîchit le label HP.
func set_shield(hp: int) -> void:
	shield_hp = maxf(float(hp), 0.0)
	_refresh_labels()
	queue_redraw()

# Affiche les dégâts absorbés par le bouclier : nombre bleu légèrement décalé.
func take_shield_damage(amount: int) -> void:
	if amount <= 0:
		return
	_flash_col   = Color(0.2, 0.5, 1.0)
	_flash_alpha = 0.3
	_spawn_number_offset(str(amount), 20, Color(0.3, 0.7, 1.0), Vector2(-22.0, -18.0))

# Affiche l'icône de proc de poison passif (Contact Venimeux) : 🐍 pop sur l'ennemi.
func show_poison_proc() -> void:
	var lbl := Label.new()
	lbl.text = "☠"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.85, 0.3))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = _circle_center + Vector2(-13.0, -CIRCLE_RADIUS - 14.0)
	_dmg_layer.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2(1.5, 1.5), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.chain().tween_callback(lbl.queue_free)

# Animation de victoire : double pulse de scale (spring-back).
func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18)
	tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.14)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.14)

# Animation de défaite : rétrécissement et fade-out simultanés.
func die() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale",      Vector2(0.0, 0.0), 0.5).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)

# ═══════════════════════════════════════════════════════════
#  Traitement frame
# ═══════════════════════════════════════════════════════════

# Avance l'horloge, fait tourner le ring, décroît le flash et applique le shake.
func _process(delta: float) -> void:
	_t += delta

	match entity_type:
		EntityType.CREATURE: _ring_rot += delta * 0.18
		EntityType.TRAP:     _ring_rot += delta * 0.04
		EntityType.BENEDICTION:    pass

	if _flash_alpha > 0.0:
		_flash_alpha = maxf(_flash_alpha - delta * 5.5, 0.0)

	if _shake_time > 0.0:
		_shake_time -= delta
		if _shake_time <= 0.0:
			_shake_time = 0.0
			_shake      = Vector2.ZERO
		else:
			_shake = Vector2(randf_range(-_shake_amplitude, _shake_amplitude),
							 randf_range(-_shake_amplitude, _shake_amplitude))
		_hp_label.position = _circle_center + Vector2(-70.0, -12.0) + _shake

	if is_idle:
		_idle_t += delta
		var s := 1.0 + (IDLE_PULSE_SCALE - 1.0) * (0.5 - 0.5 * cos(TAU * _idle_t / IDLE_PULSE_PERIOD))
		scale = Vector2(s, s)

	queue_redraw()

# ═══════════════════════════════════════════════════════════
#  Dessin
# ═══════════════════════════════════════════════════════════

# Point d'entrée du rendu custom : ghost ring, anneau HP, action bar, flash.
func _draw() -> void:
	var center := _circle_center + _shake
	var tier_color: Color = UIColors.tier_color(tier)
	var hp_pct := current_hp / max_hp if max_hp > 0.0 else 0.0

	# ── Rotation du ring (affecte uniquement le dessin) ──────
	draw_set_transform(center, _ring_rot, Vector2.ONE)

	# HP arc dans le repère rotatif.
	# a_end = haut fixe en coordonnées écran (compense la rotation).
	# a_start recule en sens anti-horaire → le vide croît dans le sens horaire.
	var a_end   := -PI * 0.5 - _ring_rot
	var a_start := a_end - TAU * hp_pct

	# Ghost ring (silhouette du max PV)
	var ghost := Color(tier_color, 0.15)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, 0.0, TAU, 96, ghost, RING_WIDTH, true)

	# Anneau HP avec effets par tier
	if hp_pct > 0.001:
		match entity_type:
			EntityType.CREATURE: _ring_creature(a_start, a_end, tier_color)
			EntityType.TRAP:     _ring_trap(a_start, a_end, tier_color)
			EntityType.BENEDICTION:    _ring_benediction(a_start, a_end, tier_color)

	# Arc bouclier — bleu dans la zone vide (au-delà du dernier HP)
	if shield_hp > 0.0 and max_hp > 0.0:
		var shield_pct := minf(shield_hp / max_hp, 1.0)
		var shield_col := Color(0.25, 0.60, 1.0, 0.85)
		# S'étend à partir de a_start (fin de l'arc HP) dans la zone vide
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS + RING_WIDTH * 0.5 + 5.0,
				a_start - TAU * shield_pct, a_start, 64, shield_col, 5.0, true)

	# Action bar — arc intérieur, sens horaire depuis le haut
	if action_progress > 0.001:
		var bar_col := tier_color.lightened(0.5)
		bar_col.a = 0.85
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS - RING_WIDTH - 6.0,
				a_end, a_end + TAU * action_progress, 64, bar_col, 3.0, true)

	# Flash dégâts / soin
	if _flash_alpha > 0.001:
		draw_circle(Vector2.ZERO, CIRCLE_RADIUS, Color(_flash_col, _flash_alpha * 0.4))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Motes ambiantes idle : 8 points orbitaux à alpha et taille pulsants
	if is_idle:
		var tc := UIColors.tier_color(tier)
		for i in 8:
			var angle := _idle_t * 0.35 + float(i) * TAU / 8.0
			var r := CIRCLE_RADIUS + RING_WIDTH + 14.0 + sin(_idle_t * 1.6 + float(i) * 0.9) * 4.0
			var pt := _circle_center + Vector2(cos(angle), sin(angle)) * r
			var a  := 0.18 + 0.12 * sin(_idle_t * 2.1 + float(i) * 1.2)
			draw_circle(pt, 1.6 + 0.6 * sin(_idle_t * 1.9 + float(i) * 0.7), Color(tc, a))

# ═══════════════════════════════════════════════════════════
#  Styles par type d'entité
# ═══════════════════════════════════════════════════════════

# Délègue au style tier correspondant (portés depuis Village.gd).
func _ring_creature(a0: float, a1: float, c: Color) -> void:
	match tier:
		0: _tier_commun(a0, a1, c)
		1: _tier_peu_commun(a0, a1, c)
		2: _tier_rare(a0, a1, c)
		3: _tier_epique(a0, a1, c)
		4: _tier_legendaire(a0, a1, c)
		5: _tier_unique(a0, a1, c)
		_: _tier_commun(a0, a1, c)

# Aspect froid/mécanique : corona fine, main sobre, lignes radiales rigides.
func _ring_trap(a0: float, a1: float, c: Color) -> void:
	var corona := Color(c, 0.06 + 0.02 * sin(_t * 0.8))
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 8.0, a0, a1, 64, corona, RING_WIDTH * 1.5, true)
	var main := Color(c, 0.60 + 0.12 * sin(_t * 1.0))
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, a0, a1, 96, main, RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	# Lignes radiales rigides (aspect engrenage)
	var num_lines := 6
	for i in num_lines:
		var angle := a0 + float(i) * (a1 - a0) / float(num_lines - 1)
		if i == 0 or i == num_lines - 1:
			continue
		var p_in  := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS - RING_WIDTH * 0.5 - 2.0)
		var p_out := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + RING_WIDTH * 0.5 + 2.0)
		var tick := Color(c.lightened(0.3), 0.45)
		draw_line(p_in, p_out, tick, 1.5, true)

# Glow externe fort pulsant + particules orbitales le long de l'arc.
func _ring_benediction(a0: float, a1: float, c: Color) -> void:
	var pulse := 0.65 + (sin(_t * 1.8) + 1.0) * 0.175
	for i in range(5, 0, -1):
		var gr := CIRCLE_RADIUS + float(i) * 7.0
		var ga := pulse * 0.10 * float(6 - i) / 5.0
		draw_arc(Vector2.ZERO, gr, a0, a1, 64, Color(c, ga), 4.0, true)
	var main := Color(c, 0.72 + 0.22 * sin(_t * 2.0))
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, a0, a1, 128, main, RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	# Particules flottantes le long de l'arc
	for i in 5:
		var frac := float(i) / 4.0
		var angle := a0 + (a1 - a0) * frac
		var alpha := 0.4 + sin(_t * 2.0 + float(i)) * 0.3
		var pt := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + RING_WIDTH * 0.5 + 8.0)
		draw_circle(pt, 2.5 + sin(_t * 3.0 + float(i)) * 1.0, Color(c, alpha))

# ═══════════════════════════════════════════════════════════
#  Styles par tier (portés depuis Village.gd, adaptés en arcs)
# ═══════════════════════════════════════════════════════════

# Tier 0 — Commun : corona subtile, anneau sobre, shimmer lent.
func _tier_commun(a0: float, a1: float, c: Color) -> void:
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 8.0,  a0, a1, 64, Color(c, 0.07 + 0.03 * sin(_t * 1.2)), RING_WIDTH * 1.6, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS,         a0, a1, 96, Color(c, 0.55 + 0.18 * sin(_t * 1.3)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	var sa := _t * 0.50
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + 0.65, 10, Color(c.lightened(0.35), 0.50), RING_WIDTH * 0.45, true)

# Tier 1 — Peu Commun : corona plus visible, shimmer plus rapide, ligne fine.
func _tier_peu_commun(a0: float, a1: float, c: Color) -> void:
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 10.0, a0, a1, 96,  Color(c, 0.12 + 0.06 * sin(_t * 1.4)), RING_WIDTH * 2.0, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS,         a0, a1, 128, Color(c, 0.72 + 0.22 * sin(_t * 1.9)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + RING_WIDTH * 0.5 - 1.0, a0, a1, 64, Color(c.lightened(0.3), 0.50), 1.0, true)
	var sa := _t * 0.75
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + 1.1, 24, Color(c.lightened(0.55), 0.75), RING_WIDTH * 0.55, true)

# Tier 2 — Rare : corona étendue, anneau intérieur, double shimmer.
func _tier_rare(a0: float, a1: float, c: Color) -> void:
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 12.0, a0, a1, 96,  Color(c, 0.14 + 0.07 * sin(_t * 1.6)), RING_WIDTH * 2.4, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS,         a0, a1, 128, Color(c, 0.75 + 0.20 * sin(_t * 2.0)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS - 22.0,  a0, a1, 64,  Color(c, 0.38 + 0.14 * sin(_t * 1.5 + 1.0)), 2.0, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + RING_WIDTH * 0.5 - 1.0, a0, a1, 64, Color(c.lightened(0.4), 0.55), 1.2, true)
	for i in 2:
		var sa := _t * (0.85 + i * 0.25) + i * PI
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + (1.1 - i * 0.3), 20, Color(c.lightened(0.45 + i * 0.1), 0.75 - i * 0.22), RING_WIDTH * (0.58 - i * 0.14), true)

# Tier 3 — Épique : double corona, triple shimmer, orbes orbitaux.
func _tier_epique(a0: float, a1: float, c: Color) -> void:
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 24.0, a0, a1, 64,  Color(c, 0.08 + 0.05 * sin(_t * 1.2)), RING_WIDTH * 3.8, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 10.0, a0, a1, 96,  Color(c, 0.18 + 0.08 * sin(_t * 1.8)), RING_WIDTH * 2.2, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS,         a0, a1, 128, Color(c, 0.78 + 0.18 * sin(_t * 2.0)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS - 22.0,  a0, a1, 64,  Color(c, 0.40 + 0.15 * sin(_t * 1.7 + 0.5)), 2.5, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + RING_WIDTH * 0.5 - 1.0, a0, a1, 64, Color(c.lightened(0.45), 0.62), 1.5, true)
	for i in 3:
		var sa := _t * (0.9 + i * 0.15) + i * TAU / 3.0
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + (1.0 - i * 0.1), 18, Color(c.lightened(0.45 + i * 0.1), 0.68 - i * 0.12), RING_WIDTH * (0.58 - i * 0.10), true)
	# Orbes orbitaux
	for i in 3:
		var angle := _t * 0.80 + i * TAU / 3.0
		var op := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + 34.0)
		draw_circle(op, 9.0, Color(c, 0.22))
		draw_circle(op, 3.5 + 1.0 * sin(_t * 2.5 + i), Color(c, 0.80 + 0.18 * sin(_t * 2.0 + i * 1.5)))

# Tier 4 — Légendaire : corona massive, rayons clignotants, orbes brillants.
func _tier_legendaire(a0: float, a1: float, c: Color) -> void:
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 40.0, a0, a1, 64, Color(c, 0.05 + 0.03 * sin(_t * 1.0)), RING_WIDTH * 5.5, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + 22.0, a0, a1, 96, Color(c, 0.12 + 0.06 * sin(_t * 1.4)), RING_WIDTH * 3.2, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS +  8.0, a0, a1, 96, Color(c, 0.22 + 0.10 * sin(_t * 1.9)), RING_WIDTH * 2.0, true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS,         a0, a1, 128, Color(c, 0.85 + 0.14 * sin(_t * 2.2)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS - 25.0, a0, a1, 64, Color(c, 0.45 + 0.18 * sin(_t * 1.8 + 0.3)), 3.0, true)
	# Rayons clignotants
	for i in 8:
		var angle := i * TAU / 8.0 + _t * 0.10
		var blink := 0.5 + 0.5 * sin(_t * 2.8 + i * 0.85)
		if blink > 0.28:
			var ray_c := Color(c.lightened(0.6), blink * 0.50)
			var p1 := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + RING_WIDTH * 0.5 + 3.0)
			var p2 := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + RING_WIDTH * 0.5 + 14.0 + blink * 10.0)
			draw_line(p1, p2, ray_c, 1.8, true)
	for i in 4:
		var sa := _t * (0.92 + i * 0.13) + i * TAU / 4.0
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + (0.9 - i * 0.08), 18, Color(c.lightened(0.38 + i * 0.08), 0.72 - i * 0.12), RING_WIDTH * (0.55 - i * 0.08), true)
	for i in 3:
		var angle := _t * 0.9 + i * TAU / 3.0
		var op := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + 36.0)
		draw_circle(op, 11.0, Color(c, 0.25))
		draw_circle(op, 4.0 + 1.2 * sin(_t * 2.5 + i), Color(c, 0.88))

# Tier 5 — Unique : golden/prismatique, corona massive multi-couches, 5 orbes.
func _tier_unique(a0: float, a1: float, c: Color) -> void:
	for i in range(6, 0, -1):
		var dist := float(i) * 10.0
		var alpha := (0.06 - i * 0.005) + 0.04 * sin(_t * (1.0 + i * 0.2))
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS + dist, a0, a1, 64, Color(c, alpha), RING_WIDTH * (6.0 - i * 0.6), true)
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, a0, a1, 128, Color(c, 0.90 + 0.10 * sin(_t * 2.5)), RING_WIDTH, true)
	_arc_borders(a0, a1, c)
	for i in 5:
		var sa := _t * (0.95 + i * 0.12) + i * TAU / 5.0
		draw_arc(Vector2.ZERO, CIRCLE_RADIUS, sa, sa + (0.85 - i * 0.06), 16, Color(c.lightened(0.4 + i * 0.06), 0.75 - i * 0.1), RING_WIDTH * (0.55 - i * 0.07), true)
	for i in 5:
		var angle := _t * (0.9 + i * 0.1) + i * TAU / 5.0
		var op := Vector2(cos(angle), sin(angle)) * (CIRCLE_RADIUS + 42.0)
		draw_circle(op, 10.0, Color(c, 0.28))
		draw_circle(op, 4.5 + 1.0 * sin(_t * 2.5 + i), Color(c, 0.92))

# ─── Utilitaires de dessin ───────────────────────────────────

# Trace les lisérés intérieur (sombre) et extérieur (clair) de l'arc HP.
func _arc_borders(a0: float, a1: float, c: Color) -> void:
	var inner := c.darkened(0.15); inner.a = 0.45
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS - RING_WIDTH * 0.5, a0, a1, 64, inner, 1.5, true)
	var outer := c.lightened(0.3); outer.a = 0.55
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS + RING_WIDTH * 0.5, a0, a1, 64, outer, 1.5, true)

# Met à jour les textes du label nom et du label PV (avec bouclier si actif).
func _refresh_labels() -> void:
	if _name_label:
		_name_label.text = entity_name
	if _hp_label:
		if shield_hp > 0.0:
			_hp_label.text = "%d (+%d🛡) / %d" % [int(current_hp), int(shield_hp), int(max_hp)]
			_hp_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
		else:
			_hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]
			_hp_label.add_theme_color_override("font_color", Color.WHITE)

# Crée un chiffre flottant animé (monte et disparaît en 0.9 s) dans _dmg_layer.
func _spawn_number(text: String, font_size: int, color: Color) -> void:
	_spawn_number_offset(text, font_size, color, Vector2.ZERO)

# Variante avec décalage local supplémentaire (utilisée pour poison, etc.).
func _spawn_number_offset(text: String, font_size: int, color: Color, offset: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sx := _circle_center.x + randf_range(-20.0, 20.0) - 22.0 + offset.x
	var sy := _circle_center.y - 14.0 + offset.y
	lbl.position = Vector2(sx, sy)
	_dmg_layer.add_child(lbl)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", sy - 65.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.30)
	tw.chain().tween_callback(lbl.queue_free)
