# ============================================================
# CombatFighter — Boule d'énergie d'un combattant (proxy remplaçable).
#
# Au centre de chaque moitié d'arène : un orbe lumineux teinté à la rareté du
# combattant (UIColors.tier_color). Il personnalise le combattant SANS asset et
# sert de proxy : quand les character designs de Christophe arriveront, le perso
# reprendra exactement ces 4 états au même emplacement — seul le rendu (_draw)
# changera, la logique de déclenchement (play_idle/attack/hit/death) reste.
#
# États :
#   • idle   : flottement vertical doux + pulsation de lueur (défaut).
#   • attack : dash vif vers l'adversaire (sens = facing_dir) + retour élastique.
#   • hit    : recul léger vers l'arrière (knockback) + retour, flash.
#   • death  : implosion + extinction.
#
# Le mouvement passe par des variables internes (_action_offset, _scale_mul)
# appliquées dans _draw : aucune dépendance au layout (la boule peut déborder de
# sa case sans être bornée par un conteneur).
# ============================================================
class_name CombatFighter extends Control

enum State { IDLE, ATTACK, HIT, DEATH }

const DASH_DIST  := 80.0   # amplitude du dash d'attaque (px)
const KNOCK_DIST := 26.0   # amplitude du recul (px)
const BOB_AMP    := 6.0    # amplitude du flottement idle (px)

# +1 = héros (dash vers la droite) · -1 = créature (dash vers la gauche).
var facing_dir: float = 1.0
var accent: Color = Color.WHITE

var _t:             float   = 0.0
var _state:         int     = State.IDLE
var _action_offset: Vector2 = Vector2.ZERO   # tweené par attack/hit
var _scale_mul:     float   = 1.0            # tweené par attack/death
var _idle_bob:      float   = 0.0            # flottement vertical (idle)
var _flash:         float   = 0.0            # éclat transitoire (hit/death)
var _alive:         bool    = true
var _action_tw:     Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

# ═══════════════════════════════════════════════════════════
#  API publique (stable — un perso dessiné l'implémentera à l'identique)
# ═══════════════════════════════════════════════════════════

# (Ré)initialise la boule à la couleur de rareté et la rend vivante (idle).
func setup(color: Color) -> void:
	accent         = color
	_alive         = true
	_state         = State.IDLE
	_action_offset = Vector2.ZERO
	_scale_mul     = 1.0
	_flash         = 0.0
	modulate       = Color.WHITE
	visible        = true
	if is_instance_valid(_action_tw):
		_action_tw.kill()
	queue_redraw()

func play_idle() -> void:
	if not _alive:
		return
	_state = State.IDLE
	if is_instance_valid(_action_tw):
		_action_tw.kill()
	_action_tw = create_tween()
	_action_tw.tween_property(self, "_action_offset", Vector2.ZERO, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Ce combattant agit : dash vers l'adversaire puis retour élastique.
func play_attack() -> void:
	if not _alive:
		return
	_state = State.ATTACK
	var dash := Vector2(facing_dir * DASH_DIST, -10.0)
	if is_instance_valid(_action_tw):
		_action_tw.kill()
	_action_tw = create_tween()
	# Élan : dash + léger grossissement.
	_action_tw.tween_property(self, "_action_offset", dash, 0.10) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_action_tw.parallel().tween_property(self, "_scale_mul", 1.16, 0.10) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Retour élastique.
	_action_tw.tween_property(self, "_action_offset", Vector2.ZERO, 0.38) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tw.parallel().tween_property(self, "_scale_mul", 1.0, 0.38) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tw.tween_callback(_back_to_idle)

# Ce combattant subit l'attaque : recul vers l'arrière puis retour + flash.
func play_hit() -> void:
	if not _alive:
		return
	_state = State.HIT
	_flash = 0.6
	var knock := Vector2(-facing_dir * KNOCK_DIST, 0.0)
	if is_instance_valid(_action_tw):
		_action_tw.kill()
	_action_tw = create_tween()
	_action_tw.tween_property(self, "_action_offset", knock, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_action_tw.tween_property(self, "_action_offset", Vector2.ZERO, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tw.tween_callback(_back_to_idle)

# Ce combattant meurt : sursaut puis implosion + extinction.
func play_death() -> void:
	if not _alive:
		return
	_alive = false
	_state = State.DEATH
	_flash = 1.0
	if is_instance_valid(_action_tw):
		_action_tw.kill()
	_action_tw = create_tween()
	_action_tw.tween_property(self, "_scale_mul", 1.30, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_action_tw.tween_property(self, "_scale_mul", 0.0, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_action_tw.parallel().tween_property(self, "modulate:a", 0.0, 0.45) \
			.set_ease(Tween.EASE_IN)

func _back_to_idle() -> void:
	if _alive:
		_state = State.IDLE

# ═══════════════════════════════════════════════════════════
#  Process + rendu
# ═══════════════════════════════════════════════════════════

func _process(dt: float) -> void:
	_t += dt
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 3.0, 0.0)
	_idle_bob = (sin(_t * 2.0) * BOB_AMP) if _alive else 0.0
	queue_redraw()

func _draw() -> void:
	if _scale_mul <= 0.001 or modulate.a <= 0.001:
		return
	var c := size * 0.5 + _action_offset + Vector2(0.0, _idle_bob)
	var rmax := minf(size.x, size.y) * 0.5 * _scale_mul
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var lift := _flash

	# Halo diffus multi-couches (s'intensifie au flash).
	var glow_r: float = rmax * (0.55 + 0.20 * pulse + 0.25 * lift)
	for i in 5:
		var t := float(i) / 4.0
		var r: float = glow_r * (0.45 + t * 1.05)
		var a: float = lerpf(0.22 + 0.22 * lift, 0.0, t)
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, a))

	# Anneau pulsant.
	var ring_r: float = rmax * (0.52 + 0.06 * sin(_t * 2.4))
	var ring_c := accent.lightened(0.45)
	ring_c.a = 0.35 + 0.35 * lift
	draw_arc(c, ring_r, 0.0, TAU, 48, ring_c, 2.0, true)

	# Cœur brillant + halo rapproché.
	var core_r: float = rmax * (0.24 + 0.04 * pulse)
	draw_circle(c, core_r * 2.0, Color(accent.r, accent.g, accent.b, 0.30 + 0.30 * lift))
	draw_circle(c, core_r, Color(1, 1, 1, clampf(0.60 + 0.40 * lift, 0.0, 1.0)))
