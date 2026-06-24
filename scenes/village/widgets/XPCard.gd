class_name XPCard
extends PanelContainer

# Motif de particules qui flottent dans la portion remplie de la barre d'XP.
# Un motif par grande catégorie d'entité (voir motif_for_type) :
#   BUBBLES (bulles) → Passifs   LIGHTNING (éclairs) → Pièges
#   DIAMONDS (losanges) → Biomes CROSSES (croix +) → Bénédictions
#   PAWS (empreintes) → Créatures STARS (étoiles) → Héros
enum Motif { BUBBLES, LIGHTNING, DIAMONDS, CROSSES, PAWS, STARS }

# Couleur or du segment XP gagné ce cycle (fondu vers fill_color en fin d'animation).
const GAIN_COLOR := Color(1.00, 0.88, 0.20)

var xp_fill    := 0.0
var fill_color := Color.WHITE
var motif: int = Motif.BUBBLES
var _t         := randf() * 6.0   # phase aléatoire : grésillement désynchronisé entre cartes

# Contour néon (dessiné par la carte) : rayon des coins + épaisseur du trait,
# renseignés par UIHelpers.xp_panel pour épouser exactement la carte.
var corner_rad := 4.0
var border_w   := 1.0

# Segment XP gagné :
#   gain_start ≥ 0  → fraction où commence le segment or (= avant_frac du cycle)
#   gain_start = -1 → pas de segment (rendu normal monochrome)
#   gain_t ∈ [0, 1] → 0 = couleur tier, 1 = GAIN_COLOR (lerp)
var gain_start : float = -1.0
var gain_t     : float = 0.0
# Étincelles one-shot (récap de cycle) : jaillissent du segment gagné quand
# la barre finit de se remplir. [x, y, vx, vy, taille, âge, vie] — en px.
var _sparks    : Array = []
# Particules générées une seule fois pour cette carte : [ [xf, taille, vitesse, phase], … ].
# Tirage propre à chaque carte (aléatoire contrôlé) → deux barres du même motif
# ne s'animent jamais à l'identique, même multipliées à l'écran.
var _particles : Array = []

# ─── Réglages de génération (aléatoire contrôlé) ────────────
const _COUNT_MIN    := 7     # nb min de particules par carte
const _COUNT_MAX    := 12    # nb max de particules par carte
const _SIZE_JITTER  := 0.30  # variation de taille par particule : ±30 %
const _SPEED_JITTER := 0.25  # variation de vitesse par particule : ±25 %

# Taille caractéristique de chaque motif (avant variation ±30 %).
const _BASE_SIZE: Dictionary = {
	Motif.BUBBLES:   2.4,
	Motif.LIGHTNING: 4.4,
	Motif.DIAMONDS:  3.3,
	Motif.CROSSES:   3.3,
	Motif.PAWS:      4.7,
	Motif.STARS:     5.0,
}

# Vitesse de montée caractéristique de chaque motif (préserve le « feel » :
# éclairs rapides, étoiles lentes…) avant variation ±25 %.
const _BASE_SPEED: Dictionary = {
	Motif.BUBBLES:   0.65,
	Motif.LIGHTNING: 0.95,
	Motif.DIAMONDS:  0.50,
	Motif.CROSSES:   0.52,
	Motif.PAWS:      0.58,
	Motif.STARS:     0.44,
}

# Motif associé au type d'entité d'une barre d'XP (source de vérité du mapping).
static func motif_for_type(entity_type: String) -> int:
	match entity_type:
		Enums.EntityType.TRAP:                                   return Motif.LIGHTNING
		Enums.EntityType.BIOME:                                  return Motif.DIAMONDS
		Enums.EntityType.EQUIPMENT:                              return Motif.DIAMONDS
		Enums.EntityType.BENEDICTION:                            return Motif.CROSSES
		Enums.EntityType.CREATURE:                               return Motif.PAWS
		Enums.EntityType.HERO:                                   return Motif.STARS
		Enums.EntityType.PASSIVE, Enums.EntityType.PASSIF_UNIQUE: return Motif.BUBBLES
		_:                                                       return Motif.BUBBLES

# Génère le set de particules unique de cette carte (aléatoire contrôlé) :
#   • 7 à 12 éléments,
#   • chacun de taille  = base ± 30 % (aucune particule de la même taille),
#   • chacun de vitesse = base ± 25 %, position et phase aléatoires.
# Le tirage est propre à chaque carte (RNG global, indépendant d'une carte à
# l'autre) → pas d'homogénéité quand plusieurs barres du même motif coexistent.
func _generate_particles() -> void:
	_particles.clear()
	var base_size  : float = _BASE_SIZE.get(motif, 2.4)
	var base_speed : float = _BASE_SPEED.get(motif, 0.55)
	var count := randi_range(_COUNT_MIN, _COUNT_MAX)
	for i in count:
		_particles.append([
			randf_range(0.05, 0.95),                                            # position x (fraction)
			base_size  * randf_range(1.0 - _SIZE_JITTER,  1.0 + _SIZE_JITTER),  # taille ± 30 %
			base_speed * randf_range(1.0 - _SPEED_JITTER, 1.0 + _SPEED_JITTER), # vitesse ± 25 %
			randf(),                                                            # phase
		])

# Gerbe d'étincelles dorées montant du segment gagné — appelée par le
# récap de cycle quand l'animation de remplissage se termine.
func spawn_completion_sparks() -> void:
	var x0 := size.x * clampf(maxf(gain_start, 0.0), 0.0, 1.0)
	var x1 := size.x * clampf(xp_fill, 0.0, 1.0)
	if x1 <= x0:
		x0 = 0.0
	for i in randi_range(10, 14):
		_sparks.append([
			randf_range(x0, maxf(x1, x0 + 1.0)),   # x de départ
			size.y,                                # part du bas de la barre
			randf_range(-14.0, 14.0),              # dérive horizontale
			randf_range(-78.0, -34.0),             # vitesse de montée
			randf_range(1.2, 2.6),                 # taille
			0.0,                                   # âge
			randf_range(0.45, 0.85),               # durée de vie
		])

func _process(delta: float) -> void:
	# Toujours animer : le contour néon (pulsation + grésillement) vit en permanence,
	# indépendamment du remplissage de la barre.
	_t += delta
	if not _sparks.is_empty():
		for s: Array in _sparks:
			s[0] += (s[2] as float) * delta
			s[1] += (s[3] as float) * delta
			s[3] = (s[3] as float) + 30.0 * delta   # décélération de la montée
			s[5] = (s[5] as float) + delta
		_sparks = _sparks.filter(func(s: Array) -> bool: return (s[5] as float) < (s[6] as float))
	queue_redraw()

func _draw() -> void:
	_draw_sparks()
	_draw_fill()
	_draw_neon_contour()

# Remplissage interne (barre + motif de particules) — INCHANGÉ, indépendant du contour.
func _draw_fill() -> void:
	if xp_fill <= 0.0: return
	if _particles.is_empty():
		_generate_particles()

	var w := size.x * xp_fill
	var h := size.y

	# Pulsation quand barre pleine
	var fill_alpha := 0.35
	if xp_fill >= 1.0:
		fill_alpha = 0.38 + 0.18 * sin(_t * 2.8)
		# Halo externe
		var glow_a := 0.18 + 0.10 * sin(_t * 2.8)
		draw_rect(Rect2(Vector2(-3, -3), Vector2(size.x + 6, h + 6)),
				Color(fill_color.r, fill_color.g, fill_color.b, glow_a))

	# Rendu en deux segments quand un segment or est actif, sinon monochrome.
	var has_gain := gain_start >= 0.0 and gain_t > 0.0 and xp_fill > gain_start
	if has_gain:
		if gain_start > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * gain_start, h)),
					Color(fill_color.r, fill_color.g, fill_color.b, fill_alpha))
		var gc := fill_color.lerp(GAIN_COLOR, gain_t)
		draw_rect(Rect2(Vector2(size.x * gain_start, 0.0), Vector2(size.x * (xp_fill - gain_start), h)),
				Color(gc.r, gc.g, gc.b, fill_alpha))
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)),
				Color(fill_color.r, fill_color.g, fill_color.b, fill_alpha))

	for p in _particles:
		var xf : float = p[0]
		var r  : float = p[1]
		var sp : float = p[2]
		var ph : float = p[3]

		if xf * w < r: continue

		var bx := clampf(xf * w + sin(_t * sp * 3.0 + ph * TAU) * r * 0.6, r, w - r)
		var progress := fmod(_t * sp + ph, 1.0)
		var by       := h + r - progress * (h + r * 2.0)

		var fade  := r * 3.0
		var alpha := clampf(minf((h - by) / fade, by / fade), 0.0, 1.0) * 0.55

		if alpha <= 0.01: continue

		match motif:
			Motif.LIGHTNING: _draw_lightning(Vector2(bx, by), r, alpha)
			Motif.DIAMONDS:  _draw_diamond(Vector2(bx, by), r, alpha)
			Motif.CROSSES:   _draw_cross(Vector2(bx, by), r, alpha)
			Motif.PAWS:      _draw_paw(Vector2(bx, by), r, alpha)
			Motif.STARS:     _draw_star(Vector2(bx, by), r, alpha)
			_:               _draw_bubble(Vector2(bx, by), r, alpha)

# ─── Contour néon (DA cyberpunk, couleur du palier = fill_color) ─────────────
# Glow diffus + trait net avivé, à coins arrondis, pulsé et grésillant. Ne touche
# QUE le contour : le remplissage (fond + motif) reste géré par _draw_fill.
func _draw_neon_contour() -> void:
	# Pulsation douce SEULEMENT (pas de grésillement : réservé au contour des panels,
	# sinon trop de bruit visuel quand plusieurs cartes coexistent).
	var energy := 0.80 + 0.20 * sin(_t * 2.2)
	# Rentré d'1 px pour que le trait net reste dans la carte.
	var pts := _rounded_rect(Rect2(Vector2.ONE, size - Vector2(2.0, 2.0)), maxf(corner_rad, 3.0))
	for g: Array in [[9.0, 0.08], [5.0, 0.14], [2.5, 0.22]]:
		var gc := fill_color; gc.a = (g[1] as float) * energy
		draw_polyline(pts, gc, g[0] as float, true)
	var core := fill_color.lerp(Color.WHITE, 0.55); core.a = 0.95
	draw_polyline(pts, core, maxf(border_w, 1.5), true)

func _rounded_rect(rect: Rect2, rad: float, seg: int = 5) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	rad = minf(rad, minf(s.x, s.y) * 0.5)
	var pts := PackedVector2Array()
	_arc(pts, p + Vector2(rad, rad),             rad, PI,       PI * 1.5, seg)
	_arc(pts, p + Vector2(s.x - rad, rad),       rad, PI * 1.5, TAU,      seg)
	_arc(pts, p + Vector2(s.x - rad, s.y - rad), rad, 0.0,      PI * 0.5, seg)
	_arc(pts, p + Vector2(rad, s.y - rad),       rad, PI * 0.5, PI,       seg)
	pts.append(pts[0])
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, rad: float,
		a0: float, a1: float, seg: int) -> void:
	for i in seg + 1:
		var a: float = lerpf(a0, a1, float(i) / float(seg))
		pts.append(center + Vector2(cos(a), sin(a)) * rad)

# Étincelles de fin de remplissage : cœur clair + halo or, fondu sur la vie.
func _draw_sparks() -> void:
	for s: Array in _sparks:
		var a := 1.0 - (s[5] as float) / (s[6] as float)
		var pos := Vector2(s[0] as float, s[1] as float)
		var sz  := s[4] as float
		draw_circle(pos, sz * 2.0, Color(GAIN_COLOR.r, GAIN_COLOR.g, GAIN_COLOR.b, a * 0.28))
		draw_circle(pos, sz, Color(1.0, 0.97, 0.82, a))

# ─── Formes par motif ───────────────────────────────────────

# Bulle (Passifs) : disque translucide + cerne + reflet.
func _draw_bubble(p: Vector2, r: float, a: float) -> void:
	var c := fill_color
	draw_circle(p, r, Color(c.r, c.g, c.b, a * 0.45))
	draw_arc(p, r, 0.0, TAU, 16, Color(c.r, c.g, c.b, a), 1.2)
	draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(c.r, c.g, c.b, a * 0.8))

# Éclair (Pièges) : zigzag à 4 points.
func _draw_lightning(p: Vector2, r: float, a: float) -> void:
	var c := Color(fill_color.r, fill_color.g, fill_color.b, a)
	var pts := PackedVector2Array([
		p + Vector2(-r * 0.45, -r),
		p + Vector2( r * 0.20, -r * 0.25),
		p + Vector2(-r * 0.25,  r * 0.10),
		p + Vector2( r * 0.45,  r),
	])
	draw_polyline(pts, c, maxf(r * 0.35, 1.2), true)

# Losange (Biomes) : rhombe plein + contour.
func _draw_diamond(p: Vector2, r: float, a: float) -> void:
	var c := fill_color
	var pts := PackedVector2Array([
		p + Vector2(0.0, -r),
		p + Vector2(r * 0.7, 0.0),
		p + Vector2(0.0, r),
		p + Vector2(-r * 0.7, 0.0),
	])
	draw_colored_polygon(pts, Color(c.r, c.g, c.b, a * 0.45))
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color(c.r, c.g, c.b, a), 1.2, true)

# Croix « + » (Bénédictions) : deux traits perpendiculaires.
func _draw_cross(p: Vector2, r: float, a: float) -> void:
	var c := Color(fill_color.r, fill_color.g, fill_color.b, a)
	var th := maxf(r * 0.45, 1.4)
	draw_line(p + Vector2(0.0, -r), p + Vector2(0.0, r), c, th, true)
	draw_line(p + Vector2(-r, 0.0), p + Vector2(r, 0.0), c, th, true)

# Empreinte de patte (Créatures) : un coussinet + trois orteils au-dessus.
func _draw_paw(p: Vector2, r: float, a: float) -> void:
	var c := fill_color
	var pad := Color(c.r, c.g, c.b, a * 0.5)
	var toe := Color(c.r, c.g, c.b, a * 0.62)
	draw_circle(p + Vector2(0.0, r * 0.45), r * 0.6, pad)          # coussinet
	draw_circle(p + Vector2(-r * 0.5, -r * 0.25), r * 0.26, toe)   # orteil gauche
	draw_circle(p + Vector2(0.0,      -r * 0.55), r * 0.26, toe)   # orteil central
	draw_circle(p + Vector2( r * 0.5, -r * 0.25), r * 0.26, toe)   # orteil droit

# Étoile / éclat (Héros) : étoile à 4 branches + cœur brillant.
func _draw_star(p: Vector2, r: float, a: float) -> void:
	var c := fill_color
	var inner := r * 0.42
	var pts := PackedVector2Array()
	for i in 8:
		var ang := -PI * 0.5 + i * PI * 0.25
		var rad := r if i % 2 == 0 else inner
		pts.append(p + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, Color(c.r, c.g, c.b, a * 0.55))
	draw_circle(p, r * 0.16, Color(c.r, c.g, c.b, a * 0.9))
