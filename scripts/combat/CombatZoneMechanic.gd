# ============================================================
# CombatZoneMechanic.gd — Bandeaux d'info en haut de l'arène (extrait de CombatScene).
#
# Deux indicateurs permanents posés en haut de la zone de combat :
#   • Strate (Surface / Profondeur / Abysse) : petit panneau centré sur la barre
#     VS, teinté à la couleur de la zone.
#   • Mécanique forte du biome (embuscade / poison / endurcissement) : badge en
#     haut-droite, masqué tant qu'aucune mécanique n'est active.
#
# Le host (CombatScene) parente les nœuds et pilote le contenu (update_zone /
# show_mechanic / hide_mechanic). Aucune connexion de signal.
# ============================================================
class_name CombatZoneMechanic
extends RefCounted

var _host: Control
var _zone_panel: PanelContainer = null
var _zone_label: Label = null
var _mech_label: Label = null

func _init(host: Control) -> void:
	_host = host

# Crée les deux bandeaux et les ajoute à l'arbre du host.
func build() -> void:
	# Panneau de strate centré en haut de l'arène, par-dessus la barre oblique VS.
	# Auto-dimensionné à son texte (grow symétrique autour du centre). Le style
	# (teinte de bordure) est posé par update_zone.
	_zone_panel = PanelContainer.new()
	_zone_panel.anchor_left = 0.5; _zone_panel.anchor_right = 0.5
	_zone_panel.anchor_top  = 0.0; _zone_panel.anchor_bottom = 0.0
	_zone_panel.offset_top  = 8
	_zone_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_zone_panel.grow_vertical   = Control.GROW_DIRECTION_END
	_zone_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	_zone_label = Label.new()
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.add_theme_constant_override("outline_size", 3)
	_zone_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_panel.add_child(_zone_label)
	_host.add_child(_zone_panel)

	_mech_label = Label.new()
	_mech_label.anchor_left  = 1.0; _mech_label.anchor_right  = 1.0
	_mech_label.anchor_top   = 0.0; _mech_label.anchor_bottom = 0.0
	_mech_label.offset_left  = -170; _mech_label.offset_right = -6
	_mech_label.offset_top   = 6;    _mech_label.offset_bottom = 30
	_mech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mech_label.add_theme_font_size_override("font_size", 13)
	_mech_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_mech_label.visible = false
	_host.add_child(_mech_label)

func update_zone(zone: Enums.Zone) -> void:
	if not _zone_label or not _zone_panel:
		return
	var idx   := clampi(int(zone), 0, 2)
	var color := UIColors.zone_color(idx)
	_zone_label.text = "◆ " + Translations.zone_name(idx)
	_zone_label.add_theme_color_override("font_color", color)

	# Panneau sombre à bordure teintée strate, avec un peu d'air autour du texte.
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(UIColors.BG_DARK.r, UIColors.BG_DARK.g, UIColors.BG_DARK.b, 0.88)
	s.border_color = Color(color.r, color.g, color.b, 0.85)
	s.set_border_width_all(1)
	s.set_corner_radius_all(7)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 3;   s.content_margin_bottom = 3
	_zone_panel.add_theme_stylebox_override("panel", s)

	UIHelpers.register_tooltip(_zone_panel, Translations.zone_name(idx),
			Translations.zone_tooltip(idx), color)

func hide_mechanic() -> void:
	if _mech_label:
		_mech_label.visible = false

# Affiche le badge de mécanique : texte + couleur + tooltip (titre/corps).
func show_mechanic(text: String, color: Color, tt_title: String, tt_body: String) -> void:
	if not _mech_label:
		return
	_mech_label.text = text
	_mech_label.add_theme_color_override("font_color", color)
	_mech_label.visible = true
	UIHelpers.register_tooltip(_mech_label, tt_title, tt_body, color)
