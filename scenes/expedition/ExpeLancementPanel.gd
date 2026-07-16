# ============================================================
# ExpeLancementPanel — Panneau de LANCEMENT d'expédition (Rework Combat,
# chantier 8). Ouvert PAR-DESSUS la HoloMap quand le joueur clique un Lieu :
# c'est sur la carte que se choisissent destination et lancement (flux acté
# 06/07/2026). Placeholder DA (100 % code, règle projet).
#
# Contenu : destination (le Lieu cliqué — nom/palier via l'entité GameData),
# choix du PALIER DE PROFONDEUR (Périphérie / Enceinte / Noyau — rappel :
# aucun effet mécanique, le paramètre circule), puis PARTIR ou Annuler.
# Le panneau ne lance rien lui-même : il émet `lancer(palier)` / `annule`,
# le Village orchestre (fermeture de la carte, écran d'expédition).
# ============================================================
class_name ExpeLancementPanel
extends Control

signal lancer(palier: PalierProfondeurData)
signal annule

const PALIERS: Array[PalierProfondeurData] = [
	preload("res://data/expedition/palier_peripherie.tres"),
	preload("res://data/expedition/palier_enceinte.tres"),
	preload("res://data/expedition/palier_noyau.tres"),
]

# Défini AVANT add_child par l'appelant : id d'entité du Lieu cliqué.
var lieu_id := ""

var _palier_idx := 0
var _boutons_palier: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # modal : bloque la carte dessous

	var voile := ColorRect.new()
	voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voile.color = Color(0.0, 0.0, 0.0, 0.55)
	voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(voile)

	var lieu := GameData.get_entity(lieu_id)
	var tier := int(lieu.get("maitrise_actuelle", 0))
	var tcolor := UIColors.tier_color(tier)

	var boite := PanelContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.custom_minimum_size = Vector2(440, 0)
	boite.add_theme_stylebox_override("panel", UIHelpers.card_style(tcolor, 0.92, 1.0, 2, 10))
	boite.resized.connect(func() -> void:
		boite.position = (size - boite.size) * 0.5)
	add_child(boite)

	var m := UIHelpers.margin_of(18)
	boite.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)

	var titre := UIHelpers.label(Translations.T("expe.lancement_titre"), 20, tcolor.lightened(0.3))
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(titre)

	var dest := UIHelpers.label(Translations.T("expe.destination")
			% Translations.entity_name(lieu, lieu_id), 14, Color(0.85, 0.88, 0.95))
	dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dest)

	vb.add_child(HSeparator.new())

	var lbl_palier := UIHelpers.label(Translations.T("expe.palier_titre"), 12, UIColors.TEXT_MUTED)
	lbl_palier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_palier)

	# Choix du palier : 3 boutons radio (groupe), Périphérie présélectionnée.
	var rangee := HBoxContainer.new()
	rangee.alignment = BoxContainer.ALIGNMENT_CENTER
	rangee.add_theme_constant_override("separation", 8)
	vb.add_child(rangee)
	var groupe := ButtonGroup.new()
	for i in PALIERS.size():
		var p := PALIERS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = groupe
		b.text = "%s (×%.1f)" % [Translations.resource_name(p), p.multiplicateur]
		b.button_pressed = i == _palier_idx
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.toggled.connect(func(actif: bool) -> void:
			if actif:
				_palier_idx = i)
		rangee.add_child(b)
		_boutons_palier.append(b)

	vb.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	vb.add_child(actions)

	var btn_partir := Button.new()
	btn_partir.text = Translations.T("expe.partir_btn")
	btn_partir.custom_minimum_size = Vector2(180, 44)
	btn_partir.add_theme_font_size_override("font_size", 17)
	btn_partir.add_theme_color_override("font_color", tcolor.lightened(0.35))
	btn_partir.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_partir.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 8))
	btn_partir.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.48, 1.0, 2, 8))
	btn_partir.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_partir.pressed.connect(func() -> void: lancer.emit(PALIERS[_palier_idx]))
	actions.add_child(btn_partir)

	var btn_annuler := Button.new()
	btn_annuler.text = Translations.T("expe.annuler_btn")
	btn_annuler.custom_minimum_size = Vector2(110, 44)
	btn_annuler.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_annuler.pressed.connect(annuler)
	actions.add_child(btn_annuler)

# API publique : fermeture demandée (bouton Annuler, ou Échap capté par le
# Village — même rail que la fermeture de la HoloMap).
func annuler() -> void:
	annule.emit()
