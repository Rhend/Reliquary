# ============================================================
# HoloHud — Habillage HUD « table tactique » (Control 2D, par-dessus le rendu).
#
# Crochets d'angle aux quatre coins + ligne de scan horizontale qui balaie
# lentement l'écran + petites graduations. Mouse ignore, couleur cyan
# discrète. Dessiné en _draw, animé en _process.
#
# Chantier 11 : porte aussi la JAUGE D'ALARME de la ville (placeholder
# diégétique acté) — 6 slots, un par Lieutenant détruit
# (GameData.nb_lieutenants_vaincus), remplis en ROUGE (le danger est le
# métier de cette jauge — seule exception actée à la réserve du rouge).
# Redessinée chaque frame → toujours fidèle à l'état de partie.
# ============================================================
class_name HoloHud
extends Control

var couleur := Color(0.40, 0.85, 1.00)
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	var m := 18.0      # marge
	var L := 30.0      # longueur des branches
	var w := 2.0
	var cb := Color(couleur, 0.55)

	# Crochets d'angle (4 coins).
	_crochet(Vector2(m, m), Vector2(1, 1), L, w, cb)
	_crochet(Vector2(sz.x - m, m), Vector2(-1, 1), L, w, cb)
	_crochet(Vector2(m, sz.y - m), Vector2(1, -1), L, w, cb)
	_crochet(Vector2(sz.x - m, sz.y - m), Vector2(-1, -1), L, w, cb)

	# Ligne de scan horizontale qui descend lentement (boucle douce).
	var y := fposmod(_t * 0.045, 1.0) * sz.y
	draw_line(Vector2(m, y), Vector2(sz.x - m, y), Color(couleur, 0.10), 1.0)
	# Petit curseur sur le bord gauche au niveau du scan.
	draw_line(Vector2(m, y), Vector2(m + 8.0, y), Color(couleur, 0.5), 2.0)

	_jauge_alarme(Vector2(sz.x - m - 10.0, m + 14.0))

	# Graduations latérales discrètes (bord gauche).
	var ticks := 14
	for i in ticks + 1:
		var ty := m + L + (sz.y - 2.0 * (m + L)) * float(i) / float(ticks)
		var long := i % 5 == 0
		draw_line(Vector2(m, ty), Vector2(m + (8.0 if long else 4.0), ty),
				Color(couleur, 0.30 if long else 0.16), 1.0)

# Jauge d'Alarme (chantier 11) : 6 slots alignés à droite sous le crochet
# haut-droit, remplis selon les Lieutenants vaincus. `ancre` = coin haut-DROIT
# de la jauge. À 6/6, les slots pulsent doucement (l'alarme sonne).
func _jauge_alarme(ancre: Vector2) -> void:
	var total := GameData.NB_SLOTS_ALARME
	var remplis := GameData.nb_lieutenants_vaincus()
	var slot := Vector2(20.0, 9.0)
	var esp := 5.0
	var largeur := total * slot.x + (total - 1) * esp
	var origine := Vector2(ancre.x - largeur, ancre.y)
	var font := ThemeDB.fallback_font
	var rouge: Color = UIColors.CYBER_DANGER
	var pulse := 0.75 + 0.25 * sin(_t * 5.0) if remplis >= total else 1.0
	draw_string(font, origine + Vector2(0, -4.0),
			"%s %d/%d" % [Translations.T("alarme.jauge"), remplis, total],
			HORIZONTAL_ALIGNMENT_LEFT, largeur,
			11, Color(rouge if remplis > 0 else couleur, 0.75))
	for i in total:
		var r := Rect2(origine + Vector2(i * (slot.x + esp), 4.0), slot)
		if i < remplis:
			draw_rect(r, Color(rouge, 0.85 * pulse))
		else:
			draw_rect(r, Color(couleur, 0.30), false, 1.0)

# Crochet d'angle : deux branches partant de `coin` dans la direction `dir`.
func _crochet(coin: Vector2, dir: Vector2, L: float, w: float, col: Color) -> void:
	draw_line(coin, coin + Vector2(dir.x * L, 0), col, w)
	draw_line(coin, coin + Vector2(0, dir.y * L), col, w)
