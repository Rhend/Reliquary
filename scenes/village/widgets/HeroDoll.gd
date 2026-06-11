# ============================================================
# HeroDoll — Silhouette du héros de face + 6 emplacements
# d'équipement placés anatomiquement (haut du panneau Héros).
#
#                 (tête)
#        ⚔ main      ✦ cou       ⬡ main
#                    🛡 torse
#                    🪢 taille    💍 doigt
#
# Chaque case : bordure et icône aux couleurs du tier de l'équipement
# équipé ; case grise discrète si le slot est vide / à découvrir.
# Les détails (nom, palier, stats, lore) vivent dans le tooltip.
# ============================================================
class_name HeroDoll
extends Control

const CANVAS_H  := 180.0
const SLOT_SIZE := Vector2(34.0, 34.0)

# [clé slot, icône, id entité équipement, offset (dx depuis le centre, y)]
const SLOTS: Array = [
	["talisman", "✦",  "equipment_talisman", Vector2(  0.0,  52.0)],
	["armure",   "🛡", "equipment_armure",   Vector2(  0.0,  90.0)],
	["ceinture", "🪢", "equipment_ceinture", Vector2(  0.0, 128.0)],
	["arme",     "⚔",  "equipment_arme",     Vector2(-56.0,  90.0)],
	["bouclier", "⬡",  "equipment_bouclier", Vector2( 56.0,  90.0)],
	["anneau",   "💍", "equipment_anneau",   Vector2( 56.0, 128.0)],
]

var _tint     := Color(0.6, 0.6, 0.7)
var _glow_tex : GradientTexture2D
var _boxes    : Array = []   # [Control, offset] — repositionnés au resize

func _ready() -> void:
	custom_minimum_size = Vector2(0, CANVAS_H)
	# Le canvas ne capte pas la souris ; les cases (enfants) restent actives.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint = UIColors.tier_color(
			int(GameData.get_entity("hero").get("maitrise_actuelle", 0)))
	_glow_tex = UIHelpers.radial_glow_tex(64,
			[0.0, 0.35, 1.0], [1.0, 0.55, 0.0])
	for s in SLOTS:
		add_child(_slot_box(s[0] as String, s[1] as String,
				s[2] as String, s[3] as Vector2))
	resized.connect(_layout_slots)
	_layout_slots()

func _layout_slots() -> void:
	var cx := size.x * 0.5
	for b in _boxes:
		(b[0] as Control).position = Vector2(cx, 0.0) \
				+ (b[1] as Vector2) - SLOT_SIZE * 0.5

# ── Case d'équipement ─────────────────────────────────────────
func _slot_box(slot_key: String, icon: String, equip_id: String,
		ofs: Vector2) -> Control:
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
					0.70 if unlocked else 0.22, 1, 6))

	var lbl := Label.new()
	lbl.text = icon
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color",
			ec.lerp(Color.WHITE, 0.35) if unlocked else Color(1, 1, 1, 0.25))
	box.add_child(lbl)

	var slot_name := Translations.equip_slot_name(slot_key)
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

	_boxes.append([box, ofs])
	return box

# ── Silhouette ────────────────────────────────────────────────
func _draw() -> void:
	var cx := size.x * 0.5
	# Halo doux derrière la silhouette (couleur du tier du héros).
	draw_texture_rect(_glow_tex,
			Rect2(Vector2(cx - 95.0, -2.0), Vector2(190.0, 190.0)),
			false, Color(_tint, 0.10))

	var body := _tint.lerp(Color.WHITE, 0.10); body.a = 0.85
	# Tête
	draw_circle(Vector2(cx, 33.0), 13.0, body, true, -1.0, true)
	draw_arc(Vector2(cx, 33.0), 13.0, 0.0, TAU, 32,
			_tint.lightened(0.35), 1.5, true)
	# Cou + torse (capsule)
	draw_line(Vector2(cx, 48.0), Vector2(cx, 112.0), body, 20.0, true)
	# Bras vers les mains (slots arme / bouclier)
	draw_line(Vector2(cx - 9.0, 62.0), Vector2(cx - 42.0, 92.0), body, 7.0, true)
	draw_line(Vector2(cx + 9.0, 62.0), Vector2(cx + 42.0, 92.0), body, 7.0, true)
	# Jambes
	draw_line(Vector2(cx - 6.0, 118.0), Vector2(cx - 11.0, 166.0), body, 8.0, true)
	draw_line(Vector2(cx + 6.0, 118.0), Vector2(cx + 11.0, 166.0), body, 8.0, true)
