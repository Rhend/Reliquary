# ============================================================
# ExpeLancementPanel — Panneau de LANCEMENT d'expédition (Rework Combat,
# chantier 8). Ouvert PAR-DESSUS la HoloMap quand le joueur clique un Lieu :
# c'est sur la carte que se choisissent destination et lancement (flux acté
# 06/07/2026). Placeholder DA (100 % code, règle projet).
#
# Contenu : destination (le Lieu cliqué — nom/palier via l'entité GameData),
# choix du PALIER DE PROFONDEUR (Périphérie / Enceinte / Noyau — rappel :
# aucun effet mécanique, le paramètre circule), MARQUEURS de complétion des
# 3 strates (chantier 11 — ◆ complétée / ◇ non, placeholder acté), puis
# PARTIR ou Annuler. Quand les 3 strates du Lieu sont complétées ET qu'un
# Lieutenant y est mappé, l'option ASSAUT apparaît (règle pilier : ABSENTE
# avant, jamais grisée) : elle émet `lancer_assaut` — expédition spéciale
# d'1 étage terminée par le nœud Boss, palier dédié « Assaut ».
# Le panneau ne lance rien lui-même : il émet `lancer(palier)` /
# `lancer_assaut` / `annule`, le Village orchestre (fermeture de la carte,
# écran d'expédition).
# ============================================================
class_name ExpeLancementPanel
extends Control

signal lancer(palier: PalierProfondeurData)
signal lancer_assaut
signal annule

const PALIERS: Array[PalierProfondeurData] = [
	preload("res://data/expedition/palier_peripherie.tres"),
	preload("res://data/expedition/palier_enceinte.tres"),
	preload("res://data/expedition/palier_noyau.tres"),
]
# Même ressource que le Village (destination → pool + Lieutenant).
const DESTINATIONS: ExpeDestinationsData = preload("res://data/expedition/destinations.tres")

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

	# Gabarit AGRANDI (retour Rhend post-chantier 10) : le modal respire.
	var boite := PanelContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.custom_minimum_size = Vector2(640, 0)
	boite.add_theme_stylebox_override("panel",
			ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 0.96, 1, 2))
	boite.resized.connect(func() -> void:
		boite.position = (size - boite.size) * 0.5)
	add_child(boite)

	var m := UIHelpers.margin_of(30)
	boite.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	m.add_child(vb)

	var titre := ExpeStyle.label_mono(Translations.T("expe.lancement_titre"), 26,
			UIColors.CYBER_ACCENT)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(titre)

	var dest := ExpeStyle.label_mono(Translations.T("expe.destination")
			% Translations.entity_name(lieu, lieu_id), 17, tcolor.lightened(0.2))
	dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dest)

	vb.add_child(HSeparator.new())

	var lbl_palier := ExpeStyle.label_mono(Translations.T("expe.palier_titre"), 14,
			UIColors.CYBER_TEXTE_MUTED)
	lbl_palier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_palier)

	# Choix du palier : 3 boutons radio (groupe), Périphérie présélectionnée.
	var rangee := HBoxContainer.new()
	rangee.alignment = BoxContainer.ALIGNMENT_CENTER
	rangee.add_theme_constant_override("separation", 10)
	vb.add_child(rangee)
	var groupe := ButtonGroup.new()
	for i in PALIERS.size():
		var p := PALIERS[i]
		var b := ExpeStyle.bouton("%s (×%.1f)" % [Translations.resource_name(p),
				p.multiplicateur], UIColors.CYBER_ACCENT, 15, Vector2(0, 44))
		b.toggle_mode = true
		b.button_group = groupe
		b.button_pressed = i == _palier_idx
		b.toggled.connect(func(actif: bool) -> void:
			if actif:
				_palier_idx = i)
		rangee.add_child(b)
		_boutons_palier.append(b)

	# Mécanique forte du Lieu (chantier 15) : affichée SEULEMENT si le biome
	# en a une (contenu absent, pas grisé) — le joueur choisit son palier en
	# sachant ce qui l'attend en profondeur (Enceinte/Noyau/Assaut).
	var meca := str(GameData.get_entity(lieu_id).get("mecanique_forte_id", ""))
	if meca != "":
		var lbl_meca := ExpeStyle.label_mono(
				Translations.T("expe.lancement_mecanique")
				% Translations.T("meca." + meca), 13, UIColors.CYBER_ACCENT_2)
		lbl_meca.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lbl_meca)

	# Marqueurs de complétion des strates (chantier 11, placeholder acté) :
	# ◆ = complétée jusqu'au bout (fin du 3e étage), ◇ = pas encore.
	var marqueurs: PackedStringArray = []
	for p in PALIERS:
		marqueurs.append("%s %s" % [
				"◆" if GameData.strate_completee(lieu_id, p.id) else "◇",
				Translations.resource_name(p)])
	var lbl_strates := ExpeStyle.label_mono(
			Translations.T("expe.strates") % "  ·  ".join(marqueurs), 13,
			UIColors.CYBER_TEXTE_MUTED)
	lbl_strates.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_strates)

	# Option ASSAUT (chantier 11) : ABSENTE tant que les 3 strates ne sont pas
	# complétées ou que le Lieu n'a pas de Lieutenant mappé (jamais grisée —
	# règle pilier). Rouge = danger : l'assaut du Lieutenant en est un.
	var lieutenant := DESTINATIONS.lieutenant_pour(lieu_id)
	if GameData.nb_strates_completees(lieu_id) >= PALIERS.size() and lieutenant != null:
		vb.add_child(HSeparator.new())
		var btn_assaut := ExpeStyle.bouton(Translations.T("expe.assaut_btn")
				% Translations.resource_name(lieutenant),
				UIColors.CYBER_DANGER, 17, Vector2(0, 50))
		btn_assaut.pressed.connect(func() -> void: lancer_assaut.emit())
		vb.add_child(btn_assaut)

	vb.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	vb.add_child(actions)

	var btn_partir := ExpeStyle.bouton(Translations.T("expe.partir_btn"),
			UIColors.CYBER_ACCENT, 19, Vector2(240, 54))
	btn_partir.pressed.connect(func() -> void: lancer.emit(PALIERS[_palier_idx]))
	actions.add_child(btn_partir)

	var btn_annuler := ExpeStyle.bouton(Translations.T("expe.annuler_btn"),
			UIColors.CYBER_TEXTE_MUTED, 15, Vector2(140, 54))
	btn_annuler.pressed.connect(annuler)
	actions.add_child(btn_annuler)

	ExpeStyle.scanlines(self)

# API publique : fermeture demandée (bouton Annuler, ou Échap capté par le
# Village — même rail que la fermeture de la HoloMap).
func annuler() -> void:
	annule.emit()
