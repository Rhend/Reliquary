# ============================================================
# SummaryFX.gd — Couche d'effets du récap de cycle (100 % _draw).
#
# Deux modes :
#   AMBIENT — poussières lumineuses qui montent lentement derrière
#             le panneau (teintées par le résultat), pleine fenêtre.
#   BANNER  — au-dessus de la bannière : balayage de lumière
#             périodique (« shine ») + burst d'étincelles radial à
#             la révélation (fire_burst()).
#
# Purement cosmétique : MOUSE_FILTER_IGNORE, aucun état de jeu.
# ============================================================
class_name SummaryFX
extends Control

enum Mode { AMBIENT, BANNER }

var mode   : int   = Mode.AMBIENT
var accent : Color = Color.WHITE
var shine  : bool  = true   # BANNER : balayage périodique (false = burst seul)

const MOTE_COUNT   := 36
const SHINE_PERIOD := 3.6    # s entre deux balayages
const SHINE_DUR    := 0.85   # durée d'un balayage
const BURST_DUR    := 0.85   # durée du burst de révélation

var _t       := 0.0
var _burst_t := 99.0         # 99 = inactif
var _motes   : Array = []    # [xf, yf, taille, vitesse, phase, alpha_base]
var _sparks  : Array = []    # burst : [angle, vitesse, taille]
var _glow    : GradientTexture2D

func _ready() -> void:
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	clip_contents = (mode == Mode.BANNER and shine)   # le burst seul peut déborder
	_glow = UIHelpers.radial_glow_tex(64, [0.0, 0.4, 1.0], [1.0, 0.42, 0.0])
	if mode == Mode.AMBIENT:
		for i in MOTE_COUNT:
			_motes.append([
				randf(),                    # x (fraction de largeur)
				randf(),                    # y (fraction de hauteur)
				randf_range(1.0, 3.2),      # taille px
				randf_range(0.018, 0.05),   # vitesse de montée (fraction/s)
				randf() * TAU,              # phase de dérive
				randf_range(0.06, 0.20),    # alpha de base
			])

func _process(dt: float) -> void:
	_t += dt
	_burst_t += dt
	queue_redraw()

# Déclenche le burst radial (à appeler quand la bannière apparaît).
func fire_burst() -> void:
	_burst_t = 0.0
	_sparks.clear()
	for i in 26:
		_sparks.append([
			randf() * TAU,
			randf_range(55.0, 170.0),
			randf_range(1.2, 3.0),
		])

func _draw() -> void:
	match mode:
		Mode.AMBIENT:
			_draw_motes()
		Mode.BANNER:
			if shine:
				_draw_shine()
			_draw_burst()

# ── Poussières ambiantes : montée lente + dérive + scintillement ──
func _draw_motes() -> void:
	var col := accent.lightened(0.35)
	for m: Array in _motes:
		var yf := fposmod((m[1] as float) - _t * (m[3] as float), 1.0)
		var x  := (m[0] as float) * size.x + sin(_t * 0.5 + (m[4] as float)) * 18.0
		var y  := yf * size.y
		var sz := m[2] as float
		# Fondu près des bords haut/bas + scintillement individuel.
		var edge    := clampf(minf(yf, 1.0 - yf) * 6.0, 0.0, 1.0)
		var twinkle := 0.7 + 0.3 * sin(_t * 1.7 + (m[4] as float) * 3.0)
		var a       := (m[5] as float) * edge * twinkle
		if sz > 2.4:
			draw_texture_rect(_glow,
					Rect2(Vector2(x, y) - Vector2.ONE * sz * 3.0, Vector2.ONE * sz * 6.0),
					false, Color(col.r, col.g, col.b, a * 0.5))
		draw_circle(Vector2(x, y), sz * 0.55, Color(col.r, col.g, col.b, a))

# ── Shine : bande de lumière inclinée qui balaie la bannière ──
func _draw_shine() -> void:
	var ph := fmod(_t, SHINE_PERIOD)
	if ph > SHINE_DUR:
		return
	var p     := ph / SHINE_DUR
	var pe    := p * p * (3.0 - 2.0 * p)            # smoothstep
	var cx    := lerpf(-0.30, 1.30, pe) * size.x
	var slant := size.y * 0.45
	var fade  := sin(p * PI)
	# 3 bandes imbriquées : approximation d'un dégradé doux.
	for layer: Array in [[64.0, 0.05], [30.0, 0.09], [12.0, 0.16]]:
		var w := layer[0] as float
		var a := (layer[1] as float) * fade
		var pts := PackedVector2Array([
			Vector2(cx - w + slant, 0.0),
			Vector2(cx + w + slant, 0.0),
			Vector2(cx + w - slant, size.y),
			Vector2(cx - w - slant, size.y),
		])
		draw_colored_polygon(pts, Color(1.0, 0.97, 0.85, a))

# ── Burst : onde + étincelles radiales (écrasées verticalement,
#    la bannière est large et basse) ──
func _draw_burst() -> void:
	if _burst_t >= BURST_DUR:
		return
	var p  := _burst_t / BURST_DUR
	var eo := 1.0 - pow(1.0 - p, 3.0)               # ease-out cubique
	var c  := size * 0.5
	var a  := 1.0 - p
	draw_arc(c, 12.0 + eo * size.x * 0.16, 0.0, TAU, 48,
			Color(accent.lightened(0.5).r, accent.lightened(0.5).g,
					accent.lightened(0.5).b, a * 0.30), 2.0, true)
	for s: Array in _sparks:
		var ang := s[0] as float
		var pos := c + Vector2(cos(ang), sin(ang) * 0.55) * ((s[1] as float) * eo)
		var sz  := (s[2] as float) * (1.0 - p * 0.5)
		draw_circle(pos, sz * 2.2, Color(accent.r, accent.g, accent.b, a * 0.25))
		draw_circle(pos, sz, Color(1.0, 0.96, 0.80, a))
