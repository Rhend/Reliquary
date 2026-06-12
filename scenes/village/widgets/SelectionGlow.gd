# ============================================================
# SelectionGlow — Surcouche de sélection : liseré or + luciole.
#
# Posé en ENFANT de la carte (PanelContainer) du biome sélectionné dans
# le panneau Expéditions : dessine une fine bordure dorée arrondie et
# une luciole lumineuse (cœur + halo + traîne) qui parcourt le périmètre
# de la carte en boucle. Transparent à la souris, activable via
# `visible` (AdventurePanel le bascule au fil des sélections).
#
# ⚠ Un PanelContainer replace ses enfants dans sa ZONE DE CONTENU
# (insetée par la bordure/marges du stylebox) : on ne dessine donc pas
# dans notre propre rect mais dans celui du PARENT, reconverti en
# coordonnées locales (le dessin d'un Control n'est pas clippé).
# ============================================================
class_name SelectionGlow
extends Control

const BORDER_WIDTH  := 2
const CORNER_RADIUS := 4      # = rayon des cartes UIHelpers.card_style
const FIREFLY_SPEED := 90.0   # px/s le long du périmètre
const TRAIL_COUNT   := 4      # segments de traîne derrière la luciole
const PATH_INSET    := 2.0    # la luciole circule SUR le liseré, halo contenu
const HALO_SIZE     := 14.0   # rayon du halo (réduit : pas de débordement)

var _dist     := 0.0          # distance parcourue sur le périmètre
var _border   := StyleBoxFlat.new()
var _glow_tex : GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.bg_color     = Color(0, 0, 0, 0)
	_border.border_color = Color(UIColors.SELECTION_GOLD, 0.85)
	_border.set_border_width_all(BORDER_WIDTH)
	_border.set_corner_radius_all(CORNER_RADIUS)
	_glow_tex = UIHelpers.radial_glow_tex(48, [0.0, 0.35, 1.0], [1.0, 0.45, 0.0])

# Rect de la carte parente exprimé dans NOS coordonnées locales.
func _parent_rect() -> Rect2:
	var parent := get_parent_control()
	if parent == null:
		return Rect2(Vector2.ZERO, size)
	return Rect2(-position, parent.size)

func _process(delta: float) -> void:
	if not visible:
		return
	var r := _parent_rect()
	if r.size.x <= 0.0:
		return
	_dist = fposmod(_dist + FIREFLY_SPEED * delta, 2.0 * (r.size.x + r.size.y))
	queue_redraw()

func _draw() -> void:
	var r := _parent_rect()
	_border.draw(get_canvas_item(), r)

	# Chemin de la luciole : périmètre inset pour que le halo reste
	# visuellement contenu dans la carte.
	var path := r.grow(-PATH_INSET)

	# Traîne : points décroissants derrière la luciole.
	for i in range(TRAIL_COUNT, 0, -1):
		var q := _point_at(path, _dist - float(i) * 6.0)
		draw_circle(q, 1.5 - float(i) * 0.25,
				Color(UIColors.SELECTION_GOLD, 0.40 - float(i) * 0.08),
				true, -1.0, true)

	# Luciole : halo doux + cœur brillant.
	var p := _point_at(path, _dist)
	draw_texture_rect(_glow_tex,
			Rect2(p - Vector2.ONE * HALO_SIZE * 0.5, Vector2.ONE * HALO_SIZE),
			false, Color(UIColors.SELECTION_GOLD, 0.55))
	draw_circle(p, 1.8, Color(1.0, 0.96, 0.80, 0.95), true, -1.0, true)

# Point sur le périmètre du rect à la distance d (sens horaire depuis
# le coin haut-gauche).
func _point_at(r: Rect2, d: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	d = fposmod(d, 2.0 * (w + h))
	if d < w:
		return r.position + Vector2(d, 0.0)
	d -= w
	if d < h:
		return r.position + Vector2(w, d)
	d -= h
	if d < w:
		return r.position + Vector2(w - d, h)
	d -= w
	return r.position + Vector2(0.0, h - d)
