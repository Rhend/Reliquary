# ============================================================
# HoloTooltip — Cadre d'info déporté + ligne de rappel (style HUD technique).
#
# Control 2D (sur un CanvasLayer au-dessus du rendu 3D). HoloMap3D le pilote :
# à chaque frame il projette la position monde du pin survolé vers l'écran
# (Camera3D.unproject_position) et appelle `set_ancre()` ; la ligne de rappel
# (segment horizontal « ----- » qui casse « \ » vers le cadre) et le cadre
# suivent donc le pin pendant la rotation.
#
# Contenu : nom (bleu muted, registre « nom » du journal), palier (couleur du
# tier, NOM seul jamais de numéro), lore. Couleurs via UIColors — rien en dur.
# ============================================================
class_name HoloTooltip
extends Control

const MARGE_ECRAN := 12.0
const JAMBE := 46.0          # longueur du segment horizontal qui part du pin
const ECART_CADRE := 12.0    # gap entre le coude et le cadre

var _ancre := Vector2.ZERO   # point écran du pin (départ de la ligne)
var _coude := Vector2.ZERO
var _bord_cadre := Vector2.ZERO
var _accent := Color(1.0, 0.25, 0.78)
var _actif := false       # contenu défini (entre montrer/cacher)
var _a_lecran := false    # pin visible (devant la caméra) cette frame

var _frame: PanelContainer
var _lbl_nom: Label
var _lbl_palier: Label
var _lbl_lore: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_frame = PanelContainer.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	var m := UIHelpers.margin_of(8)
	_frame.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	m.add_child(vb)

	_lbl_nom = UIHelpers.label("", 15, UIColors.LOG_IGNORED)     # registre « nom » = bleu muted
	vb.add_child(_lbl_nom)
	_lbl_palier = UIHelpers.label("", 12, UIColors.TEXT_MUTED)   # couleur posée au survol (tier)
	vb.add_child(_lbl_palier)
	_lbl_lore = UIHelpers.label("", 11, UIColors.TEXT_MUTED)
	_lbl_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_lore.custom_minimum_size = Vector2(230, 0)
	vb.add_child(_lbl_lore)

# Affiche le tooltip avec son contenu. `palier_nom` = NOM du palier (pas de numéro).
func montrer(nom: String, palier_nom: String, tier_color: Color, lore: String, accent: Color) -> void:
	_accent = accent
	_lbl_nom.text = nom
	_lbl_palier.text = palier_nom
	_lbl_palier.add_theme_color_override("font_color", tier_color)
	_lbl_lore.text = lore
	_lbl_lore.visible = lore != ""
	_frame.add_theme_stylebox_override("panel",
			UIHelpers.card_style(accent, 0.16, 0.9, 2, 6))
	_actif = true   # la visibilité réelle est posée par positionner() (dépend de la caméra)

func cacher() -> void:
	_actif = false
	_a_lecran = false
	_frame.visible = false
	queue_redraw()

# Reprojection par frame : `p` = position écran du pin, `a_lecran` = pin devant
# la caméra. Recalcule le placement du cadre (côté opposé au bord proche).
func positionner(p: Vector2, a_lecran: bool) -> void:
	_ancre = p
	_a_lecran = a_lecran and _actif
	_frame.visible = _a_lecran
	if not _a_lecran:
		queue_redraw()
		return
	var ecran := get_viewport_rect().size
	var fsize := _frame.size
	# Côté : cadre à droite du pin sauf si le pin est trop à droite.
	var cote := 1.0 if _ancre.x < ecran.x * 0.6 else -1.0
	_coude = _ancre + Vector2(cote * JAMBE, 0.0)

	var fx: float
	if cote > 0.0:
		fx = _coude.x + ECART_CADRE
	else:
		fx = _coude.x - ECART_CADRE - fsize.x
	var fy := _ancre.y - fsize.y * 0.5
	fx = clampf(fx, MARGE_ECRAN, ecran.x - fsize.x - MARGE_ECRAN)
	fy = clampf(fy, MARGE_ECRAN, ecran.y - fsize.y - MARGE_ECRAN)
	_frame.position = Vector2(fx, fy)

	# Bord du cadre vers lequel pointe la ligne (milieu de l'arête la plus proche).
	var bord_x := fx if cote > 0.0 else fx + fsize.x
	_bord_cadre = Vector2(bord_x, clampf(_ancre.y, fy + 6.0, fy + fsize.y - 6.0))
	queue_redraw()

func _draw() -> void:
	if not (_actif and _a_lecran):
		return
	var col := Color(_accent, 0.9)
	# Pastille au point d'ancrage (le pin).
	draw_circle(_ancre, 3.0, col)
	# Segment horizontal « ----- » (pointillé) partant du pin.
	_pointille(_ancre, _coude, col, 2.0)
	# Cassure « \ » vers le cadre.
	draw_line(_coude, _bord_cadre, col, 2.0, true)

func _pointille(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var segs := 6
	for i in segs:
		if i % 2 == 1:
			continue
		draw_line(a.lerp(b, float(i) / segs), a.lerp(b, float(i + 1) / segs), col, w, true)
