# ============================================================
# BootWarmupScreen — écran de préchauffe au lancement du jeu (retour Rhend
# 07/09/2026 : après l'écran de chargement d'ouverture de combat, un écran de
# chargement au DÉMARRAGE qui met en cache un maximum d'assets pour que le
# jeu, une fois lancé, reste rapide et fluide).
#
# Cible précisément ce que AssetCache existe déjà pour accélérer : le décor
# de combat (Usine, ~22 calques jusqu'à 4770×2655 px — seul décor affiché
# depuis le 02/10/2026, la ville n'est plus warmée, voir CombatFondScinde) et
# les squelettes Spine (héros + ennemis du registre) — sans lui, ces fichiers
# n'étaient chargés/décodés qu'au PREMIER combat de la partie, avec le même
# gel qu'avant le chantier d'AssetCache. Ici, ce coût est payé une seule fois,
# à un moment où un temps de chargement est attendu, plutôt qu'en pleine
# bataille.
#
# Posé et laissé peindre AVANT de bloquer sur le premier chargement (le hub
# du Village, construit juste avant par `_build_ui()`, continue d'exister
# EN DESSOUS pendant ce temps — cet écran n'est qu'un voile plein cadre
# par-dessus, retiré en fondu une fois la liste épuisée).
# ============================================================
class_name BootWarmupScreen
extends Control

var _barre: ProgressBar
var _texte: Label

# Fichiers chargés entre deux frames : `AssetCache.charger()` est un simple
# `load()`, pas coûteux en soi — cette pause ne sert qu'à faire progresser la
# barre à l'écran, pas à étaler le chargement. Un yield PAR fichier (~43 ici)
# traînerait inutilement (capturé par ScreenshotTool, dont les attentes fixes
# après ouverture du Village comptent sur un boot bref).
const FICHIERS_PAR_FRAME := 6

static func demarrer(parent: Control) -> void:
	var ecran := BootWarmupScreen.new()
	parent.add_child(ecran)

# Chemins des assets lourds rechargés à chaque combat (voir AssetCache) —
# préchauffés une fois pour toutes ici. Les entrées absentes de la livraison
# (`ResourceLoader.exists` faux) sont simplement ignorées par AssetCache.charger.
static func _chemins_a_prechauffer() -> PackedStringArray:
	var chemins: PackedStringArray = [
		SpriteSpinePersonnage.CHEMIN_SKEL, SpriteSpinePersonnage.CHEMIN_ATLAS,
	]
	for plan in CombatDecorFactory.PLANS:
		chemins.append(CombatDecorFactory.DECOR_DIR + str(plan["f"]))
	var registre := SpinePersonnagesData.charger()
	if registre != null:
		for p: Dictionary in registre.personnages:
			if p.has("skel"):
				chemins.append(str(p["skel"]))
			if p.has("atlas"):
				chemins.append(str(p["atlas"]))
	return chemins

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500
	_construire_visuel()
	_prechauffer()

func _construire_visuel() -> void:
	var fond := ColorRect.new()
	fond.color = UIColors.BG_DARK
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fond)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 14)
	add_child(centre)

	var titre := UIHelpers.label(Translations.T("boot.titre"), 30, UIColors.TEXT_HEADER)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(titre)

	_barre = ProgressBar.new()
	_barre.custom_minimum_size = Vector2(320, 12)
	_barre.max_value = 100.0
	_barre.show_percentage = false
	_barre.add_theme_stylebox_override("background",
			UIHelpers.card_style(UIColors.BG_BAR, 1.0, 0.0, 0, 4))
	_barre.add_theme_stylebox_override("fill",
			UIHelpers.card_style(UIColors.TIER_PEU_COMMUN, 1.0, 0.0, 0, 4))
	centre.add_child(_barre)

	_texte = UIHelpers.label(Translations.T("boot.chargement"), 13, UIColors.TOOLTIP_BODY)
	_texte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_texte)

func _prechauffer() -> void:
	await get_tree().process_frame   # laisser le fond peindre avant de bloquer
	var chemins := _chemins_a_prechauffer()
	var total := maxi(chemins.size(), 1)
	for i in chemins.size():
		AssetCache.charger(chemins[i])
		var dernier := i == chemins.size() - 1
		if (i + 1) % FICHIERS_PAR_FRAME == 0 or dernier:
			if is_instance_valid(_barre):
				_barre.value = float(i + 1) / float(total) * 100.0
			await get_tree().process_frame
	if not is_inside_tree():
		return
	var tw := create_tween()
	await tw.tween_property(self, "modulate:a", 0.0, 0.3).finished
	queue_free()
