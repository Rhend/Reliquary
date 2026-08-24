# ============================================================
# ShowRoom — vitrine dev des assets Spine de Christophe.
#
# OUTIL DE DEV, jamais atteint depuis le jeu : aucune écriture de sauvegarde,
# aucun EventBus, aucune dépendance au flux de partie. Se lance seule
# (F6 dans l'éditeur, ou `godot --path . res://scenes/showroom/ShowRoom.tscn`).
#
# Deux modes :
#   • LIBRE   — fond neutre + repère de sol, tous les monstres visibles :
#               une RANGÉE par monstre, ses paliers de gauche à droite
#               (Commun → Légendaire). Caméra pan/zoom libre.
#   • COMBAT  — cadrage RÉEL d'une bataille : le monstre courant à
#               l'emplacement adverse, Relic à l'emplacement joueur, même
#               sol / mêmes ancrages / même hauteur cible que CombatCtbUi,
#               sur le décor city. Sert à juger la lisibilité en situation.
#
# Le contenu vient du registre data/personnages/spine_personnages.tres :
# un monstre livré = une entrée, il apparaît ici sans toucher ce fichier.
#
# Sans le GDExtension spine-godot (ou sans assets), la scène ne plante pas :
# elle affiche un message d'absence — même contrat que CombatCtbUi.
# ============================================================
class_name ShowRoom
extends Node2D

const REGISTRE := "res://data/personnages/spine_personnages.tres"
const DECOR_DIR := "res://assets/background/city/"
# Couches du décor, du plan le PLUS LOINTAIN au plus proche (les fichiers sont
# pré-calés sur un même canevas 4770×2655 : un simple empilement suffit).
const DECOR_COUCHES: Array[String] = [
	"Background_City_Plan_Fond.png",
	"Background_City_Plan_Fond_2.png",
	"Background_City_Plan_5_Immeuble_01.png",
	"Background_City_Plan_5_Immeuble_02.png",
	"Background_City_Plan_4_Immeuble_01.png",
	"Background_City_Plan_4_Immeuble_01_Neon.png",
	"Background_City_Plan_4_Immeuble_02.png",
	"Background_City_Plan_3_Immeuble_01.png",
	"Background_City_Plan_3_Immeuble_01_Neon.png",
	"Background_City_Plan_2_Sol.png",
]

# Paliers montrés : Commun(0) → Légendaire(4). Unique(5) est hors échelle
# créature (Balance.ENTITY_MAX_TIER), et les exports n'ont que 5 skins.
const NB_PALIERS := 5

# ─── Mise en page du mode LIBRE ──────────────────────────────
const COL_PAS := 320.0     # écart horizontal entre deux paliers
const RANG_PAS := 360.0    # écart vertical entre deux monstres
const MARGE_G := 260.0     # colonne de gauche : nom du monstre

# ─── Cadrage COMBAT : repris tel quel de CombatCtbUi ─────────
const VUE := Vector2(1280, 720)     # taille de référence du projet
const SOL_Y_FRAC := 0.60
const SOL_X_JOUEUR := 0.34
const SOL_X_ADVERSE := 0.66
# Hauteur du SOL DANS le décor city, en fraction de l'image cadrée. Mesurée sur
# la livraison de Christophe : le trottoir commence plus bas que le sol du
# combat (0.60), donc le décor est REMONTÉ pour que les pieds y posent
# vraiment — sans ça les personnages flottent. À réajuster si le décor change ;
# c'est aussi l'arbitrage qui se posera à l'intégration en combat réel (bouger
# le décor, ou bouger SOL_Y_FRAC).
const DECOR_SOL_FRAC := 0.688

enum Mode { LIBRE, COMBAT }

var _registre: SpinePersonnagesData
var _ennemis: Array[Dictionary] = []
var _mode: int = Mode.LIBRE
var _idx_monstre := 0
var _idx_palier := 0

var _monde: Node2D            # sprites du mode LIBRE (espace monde)
var _duel: Node2D             # sprites du mode COMBAT
var _cam: Camera2D
var _fond_neutre: ColorRect
var _decor: Control
var _hud: Label
var _titre: Label
var _repere: Node2D           # lignes de sol du mode LIBRE

func _ready() -> void:
	_registre = load(REGISTRE) as SpinePersonnagesData
	if _registre != null:
		_ennemis = _registre.ennemis()
	_construire()
	if _ennemis.is_empty() or not SpriteSpinePersonnage.disponible():
		_titre.text = "AUCUN ASSET SPINE DISPONIBLE\n" \
				+ "(GDExtension bin/ absent, ou registre vide)"
		return
	_peupler_libre()
	_appliquer_mode()

# ─── Construction ────────────────────────────────────────────

func _construire() -> void:
	# Fond (CanvasLayer : collé à l'écran, insensible à la caméra).
	var fond_layer := CanvasLayer.new()
	fond_layer.layer = -1
	add_child(fond_layer)

	_fond_neutre = ColorRect.new()
	_fond_neutre.color = UIColors.BG_DARK
	_fond_neutre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fond_neutre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond_layer.add_child(_fond_neutre)

	_decor = Control.new()
	_decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor.visible = false
	fond_layer.add_child(_decor)
	_construire_decor()

	# Monde (mode LIBRE) : repère de sol dessous, sprites dessus.
	_repere = Node2D.new()
	_repere.draw.connect(_dessiner_reperes)
	add_child(_repere)
	_monde = Node2D.new()
	add_child(_monde)
	_duel = Node2D.new()
	add_child(_duel)

	_cam = Camera2D.new()
	_cam.enabled = true
	add_child(_cam)

	# HUD (au-dessus de tout).
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	_titre = UIHelpers.label("", 18, UIColors.TEXT_HEADER)
	_titre.position = Vector2(16, 12)
	hud_layer.add_child(_titre)
	_hud = UIHelpers.label("", 12, UIColors.TEXT_MUTED)
	_hud.position = Vector2(16, VUE.y - 78)
	hud_layer.add_child(_hud)

func _construire_decor() -> void:
	# Cale le SOL du décor sur celui du combat, sans laisser de vide au cadre.
	# Décaler seul ne suffit pas : remonter le décor découvre le bas de l'écran.
	# On cherche donc la hauteur H telle que le sol tombe sur SOL_Y_FRAC ET que
	# le rectangle déborde des deux côtés — les deux contraintes donnent chacune
	# une hauteur minimale, on garde la plus grande (le surplus est rogné par
	# STRETCH_KEEP_ASPECT_COVERED, comportement voulu pour un fond).
	var h := maxf(VUE.y * SOL_Y_FRAC / DECOR_SOL_FRAC,
			VUE.y * (1.0 - SOL_Y_FRAC) / (1.0 - DECOR_SOL_FRAC))
	var haut := VUE.y * SOL_Y_FRAC - DECOR_SOL_FRAC * h
	_decor.offset_top = haut
	_decor.offset_bottom = haut + h - VUE.y
	for nom in DECOR_COUCHES:
		var chemin := DECOR_DIR + nom
		if not ResourceLoader.exists(chemin):
			continue   # couche non livrée : on empile ce qui existe
		var tr := TextureRect.new()
		tr.texture = load(chemin)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_decor.add_child(tr)

# ─── Mode LIBRE : une rangée par monstre ─────────────────────

func _peupler_libre() -> void:
	for i in _ennemis.size():
		var e := _ennemis[i]
		var y := i * RANG_PAS
		var nom := UIHelpers.label(str(e.get("nom", "?")), 16, UIColors.TEXT_HEADER)
		nom.position = Vector2(-MARGE_G, y - 40.0)
		_monde.add_child(nom)
		for t in NB_PALIERS:
			var sprite := SpriteSpinePersonnage.creer(str(e.get("skel", "")),
					str(e.get("atlas", "")),
					SpinePersonnagesData.skin_pour_palier(e, t))
			if sprite == null:
				continue
			sprite.position = Vector2(t * COL_PAS, y)
			_monde.add_child(sprite)
			# Étiquette de palier SOUS les pieds (l'origine du squelette est
			# au sol : tout le sprite est au-dessus de `position`).
			var lbl := UIHelpers.label(GameData.get_tier_name(t), 12, UIColors.tier_color(t))
			lbl.position = Vector2(t * COL_PAS - 44.0, y + 8.0)
			_monde.add_child(lbl)
	_repere.queue_redraw()

func _dessiner_reperes() -> void:
	for i in _ennemis.size():
		var y := i * RANG_PAS
		_repere.draw_line(Vector2(-MARGE_G, y), Vector2(NB_PALIERS * COL_PAS, y),
				Color(1, 1, 1, 0.14), 2.0)

# ─── Mode COMBAT : duel au cadrage réel ──────────────────────

func _peupler_duel() -> void:
	for c in _duel.get_children():
		c.queue_free()
	if _ennemis.is_empty():
		return
	var sol_y := VUE.y * SOL_Y_FRAC

	# Vis-à-vis : le héros du registre, à l'emplacement du camp joueur.
	var h := _registre.heros()
	if not h.is_empty():
		var relic := SpriteSpinePersonnage.creer(str(h.get("skel", "")),
				str(h.get("atlas", "")), SpinePersonnagesData.skin_pour_palier(h, 0))
		if relic != null:
			relic.position = Vector2(VUE.x * SOL_X_JOUEUR, sol_y)
			_duel.add_child(relic)

	var e := _ennemis[_idx_monstre]
	var mob := SpriteSpinePersonnage.creer(str(e.get("skel", "")), str(e.get("atlas", "")),
			SpinePersonnagesData.skin_pour_palier(e, _idx_palier))
	if mob != null:
		# Miroir horizontal : l'ennemi fait face au camp joueur.
		mob.scale = Vector2(-1.0, 1.0)
		mob.position = Vector2(VUE.x * SOL_X_ADVERSE, sol_y)
		_duel.add_child(mob)

# ─── Modes & caméra ──────────────────────────────────────────

func _appliquer_mode() -> void:
	var combat: bool = _mode == Mode.COMBAT
	_monde.visible = not combat
	_repere.visible = not combat
	_duel.visible = combat
	_decor.visible = combat
	_fond_neutre.visible = not combat
	if combat:
		_peupler_duel()
		# Cadrage figé, identique au jeu : caméra centrée sur la vue de réf.
		_cam.zoom = Vector2.ONE
		_cam.position = VUE * 0.5
	else:
		_cadrer_tout()
	_rafraichir_hud()

# Recentre la caméra sur l'ensemble des rangées (état d'entrée du mode libre).
func _cadrer_tout() -> void:
	const PAD := 80.0   # sinon le nom du monstre affleure le bord gauche
	var largeur := MARGE_G + NB_PALIERS * COL_PAS + PAD
	var hauteur := maxf(RANG_PAS, _ennemis.size() * RANG_PAS)
	_cam.position = Vector2(largeur * 0.5 - MARGE_G - PAD * 0.5,
			hauteur * 0.5 - RANG_PAS * 0.5)
	_cam.zoom = Vector2.ONE * minf(VUE.x / largeur, VUE.y / (hauteur + 200.0))

func _rafraichir_hud() -> void:
	if _ennemis.is_empty():
		return
	if _mode == Mode.COMBAT:
		var e := _ennemis[_idx_monstre]
		_titre.text = "COMBAT — %s  ·  %s" % [str(e.get("nom", "?")),
				GameData.get_tier_name(_idx_palier)]
		_hud.text = "[Tab] mode libre    [←/→] monstre    [↑/↓] palier\n" \
				+ "cadrage réel : sol %.2f · joueur %.2f · adverse %.2f · %d px" % [
				SOL_Y_FRAC, SOL_X_JOUEUR, SOL_X_ADVERSE,
				int(SpriteSpinePersonnage.HAUTEUR_CIBLE_PX)]
	else:
		_titre.text = "SHOWROOM — %d monstre(s) × %d paliers" % [_ennemis.size(), NB_PALIERS]
		_hud.text = "[Tab] mode combat    [glisser] déplacer    [molette] zoom    [R] recadrer\n" \
				+ "une rangée par monstre · paliers de gauche à droite (Commun → Légendaire)"

# ─── Entrées ─────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		_touche((event as InputEventKey).keycode)
		return
	if _mode != Mode.LIBRE:
		return
	# Mode libre : glisser pour déplacer, molette pour zoomer.
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			_cam.position -= mm.relative / _cam.zoom
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.zoom = (_cam.zoom * 1.1).clampf(0.05, 4.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.zoom = (_cam.zoom / 1.1).clampf(0.05, 4.0)

func _touche(code: int) -> void:
	match code:
		KEY_TAB, KEY_C:
			_mode = Mode.LIBRE if _mode == Mode.COMBAT else Mode.COMBAT
			_appliquer_mode()
		KEY_R:
			if _mode == Mode.LIBRE:
				_cadrer_tout()
		KEY_ESCAPE:
			get_tree().quit()
		KEY_LEFT, KEY_RIGHT:
			if _mode == Mode.COMBAT and not _ennemis.is_empty():
				var pas := 1 if code == KEY_RIGHT else -1
				_idx_monstre = wrapi(_idx_monstre + pas, 0, _ennemis.size())
				_peupler_duel()
				_rafraichir_hud()
		KEY_UP, KEY_DOWN:
			if _mode == Mode.COMBAT:
				var pas := 1 if code == KEY_DOWN else -1
				_idx_palier = wrapi(_idx_palier + pas, 0, NB_PALIERS)
				_peupler_duel()
				_rafraichir_hud()
