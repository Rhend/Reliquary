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
	voile.color = Color(UIColors.CYBER_BG, 0.60)
	voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(voile)

	var lieu := GameData.get_entity(lieu_id)
	var tier := int(lieu.get("maitrise_actuelle", 0))
	# Le nom de la destination garde sa couleur de PALIER (palette de rareté =
	# source unique) ; le chrome du panneau est à l'accent de la peau.
	var tcolor := UIColors.tier_color(tier)

	var boite := PanelContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.custom_minimum_size = Vector2(460, 0)
	boite.add_theme_stylebox_override("panel",
			ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 0.96, 1, 2))
	boite.resized.connect(func() -> void:
		boite.position = (size - boite.size) * 0.5)
	add_child(boite)

	var m := UIHelpers.margin_of(18)
	boite.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)

	var titre := ExpeStyle.label_mono(Translations.T("expe.lancement_titre"), 20,
			UIColors.CYBER_ACCENT)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(titre)

	var dest := ExpeStyle.label_mono(Translations.T("expe.destination")
			% Translations.entity_name(lieu, lieu_id), 14, tcolor.lightened(0.2))
	dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dest)

	vb.add_child(HSeparator.new())

	var lbl_palier := ExpeStyle.label_mono(Translations.T("expe.palier_titre"), 12,
			UIColors.CYBER_TEXTE_MUTED)
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
		var b := ExpeStyle.bouton("%s (×%.1f)" % [Translations.resource_name(p),
				p.multiplicateur], UIColors.CYBER_ACCENT, 13, Vector2(0, 36))
		b.toggle_mode = true
		b.button_group = groupe
		b.button_pressed = i == _palier_idx
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

	var btn_partir := ExpeStyle.bouton(Translations.T("expe.partir_btn"),
			UIColors.CYBER_ACCENT, 17, Vector2(180, 44))
	btn_partir.pressed.connect(func() -> void: lancer.emit(PALIERS[_palier_idx]))
	actions.add_child(btn_partir)

	var btn_annuler := ExpeStyle.bouton(Translations.T("expe.annuler_btn"),
			UIColors.CYBER_TEXTE_MUTED, 14, Vector2(110, 44))
	btn_annuler.pressed.connect(annuler)
	actions.add_child(btn_annuler)

	ExpeStyle.scanlines(self)

# API publique : fermeture demandée (bouton Annuler, ou Échap capté par le
# Village — même rail que la fermeture de la HoloMap).
func annuler() -> void:
	annule.emit()
