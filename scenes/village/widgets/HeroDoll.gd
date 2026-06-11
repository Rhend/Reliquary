# ============================================================
# HeroDoll — Silhouette du héros de face + 6 emplacements
# d'équipement reliés à la partie du corps concernée (panneau Héros).
#
#   ✦ Talisman ──╮ (cou)         ╭── 🛡 Armure (torse)
#   ⚔ Arme ──────┤ (main)        ├── ⬡ Bouclier (main)
#   💍 Anneau ───╯ (doigt)       ╰── 🪢 Ceinture (taille)
#
# Trois cases par colonne, de part et d'autre de la silhouette, avec
# un fin connecteur vers le point d'ancrage anatomique : lisible, sans
# chevauchement. Détails (nom, palier, stats, lore) en tooltip.
# ============================================================
class_name HeroDoll
extends Control

const CANVAS_H  := 195.0
const SLOT_SIZE := Vector2(36.0, 36.0)
const COL_X     := 105.0   # distance des colonnes de cases au centre

# [clé, icône, id équipement, côté (-1 gauche / +1 droite),
#  y du centre de la case, ancre anatomique (dx depuis le centre, y)]
const SLOTS: Array = [
	["talisman", "✦",  "equipment_talisman", -1.0,  42.0, Vector2(  0.0,  52.0)],
	["arme",     "⚔",  "equipment_arme",     -1.0,  94.0, Vector2(-38.0, 100.0)],
	["anneau",   "💍", "equipment_anneau",   -1.0, 146.0, Vector2(-34.0, 108.0)],
	["armure",   "🛡", "equipment_armure",    1.0,  42.0, Vector2(  0.0,  82.0)],
	["bouclier", "⬡",  "equipment_bouclier",  1.0,  94.0, Vector2( 38.0, 100.0)],
	["ceinture", "🪢", "equipment_ceinture",  1.0, 146.0, Vector2(  0.0, 116.0)],
]

var _tint     := Color(0.6, 0.6, 0.7)
var _glow_tex : GradientTexture2D
# Par slot : [box, label, side, y, ancre, couleur] — pour layout + connecteurs.
var _items    : Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, CANVAS_H)
	# Le canvas ne capte pas la souris ; les cases (enfants) restent actives.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint = UIColors.tier_color(
			int(GameData.get_entity("hero").get("maitrise_actuelle", 0)))
	_glow_tex = UIHelpers.radial_glow_tex(64,
			[0.0, 0.35, 1.0], [1.0, 0.55, 0.0])
	for s in SLOTS:
		_make_slot(s[0] as String, s[1] as String, s[2] as String,
				s[3] as float, s[4] as float, s[5] as Vector2)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var cx := size.x * 0.5
	for it in _items:
		var box  := it[0] as Control
		var lbl  := it[1] as Label
		var side := it[2] as float
		var y    := it[3] as float
		var bx   := cx + side * COL_X
		box.position = Vector2(bx, y) - SLOT_SIZE * 0.5
		lbl.position = Vector2(bx - 50.0, y + SLOT_SIZE.y * 0.5 + 1.0)
	queue_redraw()

# ── Case + nom du slot ────────────────────────────────────────
func _make_slot(slot_key: String, icon: String, equip_id: String,
		side: float, y: float, anchor: Vector2) -> void:
	var equip    := GameData.get_entity(equip_id)
	var unlocked: bool = not equip.is_empty() \
			and equip.get("est_debloque", false)
	var etier := int(equip.get("maitrise_actuelle", 0)) if unlocked else 0
	var ec    := UIColors.tier_color(etier) if unlocked else UIColors.TEXT_MUTED

	var box := PanelContainer.new()
	box.custom_minimum_size = SLOT_SIZE
	box.size                = SLOT_SIZE
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.add_theme_stylebox_override("panel",
			UIHelpers.card_style(ec, 0.12 if unlocked else 0.04,
					0.70 if unlocked else 0.25, 1, 6))
	add_child(box)

	var ico := Label.new()
	ico.text = icon
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ico.add_theme_font_size_override("font_size", 15)
	ico.add_theme_color_override("font_color",
			ec.lerp(Color.WHITE, 0.35) if unlocked else Color(1, 1, 1, 0.25))
	box.add_child(ico)

	# Nom du slot sous la case : identification immédiate.
	var slot_name := Translations.equip_slot_name(slot_key)
	var name_lbl  := Label.new()
	name_lbl.text = slot_name
	name_lbl.custom_minimum_size  = Vector2(100.0, 0.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color",
			Color(ec, 0.85) if unlocked else Color(UIColors.TEXT_MUTED, 0.6))
	add_child(name_lbl)

	if unlocked:
		var tt := Translations.T("hero.equip.tt_slot") \
				% [slot_name, GameData.get_tier_name(etier)]
		var spp   := equip.get("stats_par_palier", {}) as Dictionary
		var stats := spp.get(etier, spp.get(0, {})) as Dictionary
		var line  := ForgePanel._stats_line(stats)
		if line != "":
			tt += "\n" + line
		UIHelpers.register_tooltip(box,
				equip.get("nom_affichage_fr", equip_id) as String, tt, ec,
				equip.get("lore_fr", "") as String)
		UIHelpers.add_hover_feedback(box)
	else:
		UIHelpers.register_tooltip(box, slot_name,
				Translations.T("hero.doll.empty"), UIColors.TEXT_MUTED)

	_items.append([box, name_lbl, side, y, anchor, ec])

# ── Silhouette + connecteurs ──────────────────────────────────
func _draw() -> void:
	var cx := size.x * 0.5
	# Halo doux derrière la silhouette (couleur du tier du héros).
	draw_texture_rect(_glow_tex,
			Rect2(Vector2(cx - 100.0, -5.0), Vector2(200.0, 200.0)),
			false, Color(_tint, 0.10))

	# Connecteurs case → point d'ancrage anatomique (sous la silhouette).
	for it in _items:
		var side   := it[2] as float
		var y      := it[3] as float
		var anchor := it[4] as Vector2
		var ec     := it[5] as Color
		var from   := Vector2(cx + side * (COL_X - SLOT_SIZE.x * 0.5 - 2.0), y)
		var to     := Vector2(cx + anchor.x, anchor.y)
		draw_line(from, to, Color(ec, 0.30), 1.0, true)
		draw_circle(to, 2.0, Color(ec, 0.55), true, -1.0, true)

	var body := _tint.lerp(Color.WHITE, 0.10); body.a = 0.88
	# Tête
	draw_circle(Vector2(cx, 36.0), 14.0, body, true, -1.0, true)
	draw_arc(Vector2(cx, 36.0), 14.0, 0.0, TAU, 32,
			_tint.lightened(0.35), 1.5, true)
	# Torse (capsule épaules → taille)
	draw_line(Vector2(cx, 58.0), Vector2(cx, 112.0), body, 26.0, true)
	# Bras vers les mains + mains
	draw_line(Vector2(cx - 12.0, 66.0), Vector2(cx - 36.0, 96.0), body, 8.0, true)
	draw_line(Vector2(cx + 12.0, 66.0), Vector2(cx + 36.0, 96.0), body, 8.0, true)
	draw_circle(Vector2(cx - 38.0, 100.0), 5.0, body, true, -1.0, true)
	draw_circle(Vector2(cx + 38.0, 100.0), 5.0, body, true, -1.0, true)
	# Ceinture : fine ligne sombre à la taille
	draw_line(Vector2(cx - 13.0, 116.0), Vector2(cx + 13.0, 116.0),
			Color(0, 0, 0, 0.35), 3.0, true)
	# Jambes
	draw_line(Vector2(cx - 7.0, 122.0), Vector2(cx - 10.0, 170.0), body, 9.0, true)
	draw_line(Vector2(cx + 7.0, 122.0), Vector2(cx + 10.0, 170.0), body, 9.0, true)
