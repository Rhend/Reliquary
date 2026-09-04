# ============================================================
# ShowRoom — vitrine dev des assets Spine de Christophe.
#
# OUTIL DE DEV, jamais atteint depuis le jeu : aucune écriture de sauvegarde,
# aucun EventBus, aucune dépendance au flux de partie. Se lance seule
# (F6 dans l'éditeur, ou `godot --path . res://scenes/showroom/ShowRoom.tscn`).
#
# Trois modes (Tab/C font défiler) :
#   • LIBRE   — fond neutre + repère de sol, tous les monstres visibles :
#               une RANGÉE par monstre, ses paliers de gauche à droite
#               (Commun → Légendaire). Caméra pan/zoom libre.
#   • COMBAT  — cadrage RÉEL d'une bataille : le monstre courant à
#               l'emplacement adverse, Relic à l'emplacement joueur, même
#               fond scindé (`CombatFondScinde` — décor Christophe des DEUX
#               côtés depuis le 28/08/2026), même sol / mêmes ancrages / même
#               hauteur cible que CombatCtbUi — présentation PARTAGÉE (pas un
#               décor à part). Sert à juger la lisibilité en situation.
#   • USINE   — diagnostic (28/08/2026, demande Rhend) : le décor de l'Usine
#               SEUL, plein écran, sans masque adverse ni ville — pour juger
#               le travail de Christophe tel quel, sans le mélanger avec le
#               découpage du split de combat (un problème séparé).
#
# Le contenu vient du registre data/personnages/spine_personnages.tres :
# un monstre livré = une entrée, il apparaît ici sans toucher ce fichier.
#
# Trois axes se règlent au clavier, parce que la livraison « costumes » de
# Relic (24/08/2026) les a rendus réels :
#   • le NIVEAU d'équipement — 6 costumes, une colonne chacun en mode libre,
#     [H] en mode combat ;
#   • l'ACCESSOIRE de visage — [V], indépendant du niveau, appliqué partout ;
#   • l'ANIMATION — [I] repos, [A] mêlée, [T] tir, [X] coup reçu, [M] mort,
#     jouée sur tous les sprites affichés d'un coup.
#
# Sans le GDExtension spine-godot (ou sans assets), la scène ne plante pas :
# elle affiche un message d'absence — même contrat que CombatCtbUi.
# ============================================================
class_name ShowRoom
extends Node2D

const REGISTRE := SpinePersonnagesData.CHEMIN

# Paliers montrés : Commun(0) → Légendaire(4). Unique(5) est hors échelle
# créature (Balance.ENTITY_MAX_TIER), et les exports n'ont que 5 skins.
const NB_PALIERS := SpinePersonnagesData.NB_PALIERS

# ─── Mise en page du mode LIBRE ──────────────────────────────
const COL_PAS := 320.0     # écart horizontal entre deux paliers
const RANG_PAS := 360.0    # écart vertical entre deux monstres
const MARGE_G := 260.0     # colonne de gauche : nom du monstre

# ─── Cadrage COMBAT : LU de CombatCtbUi, jamais recopié ──────
# La vitrine ne vaut que si elle montre le cadrage RÉEL. Ces valeurs étaient
# dupliquées ici, ce qui laissait les deux écrans diverger en silence dès qu'on
# bougeait un ancrage — c'est arrivé au recentrage du 26/08/2026.
const VUE := Vector2(1280, 720)     # taille de référence du projet
const SOL_Y_FRAC := CombatCtbUi.SOL_Y_FRAC
const SOL_X_JOUEUR := CombatCtbUi.SOL_X_JOUEUR
const SOL_X_ADVERSE := CombatCtbUi.SOL_X_ADVERSE
const BANDE_VS_PX := CombatCtbUi.BANDE_VS_PX

# ─── Éclairage de la vitrine ─────────────────────────────────
# RÈGLE : on éclaire le DÉCOR, jamais les personnages. Moduler les sprites
# fausserait ce qu'on vient juger (couleurs, contraste, lisibilité) — un asset
# doit se défendre tel quel. Le niveau agit donc sur le fond en mode libre, et
# sur un voile posé PAR-DESSUS le décor en mode combat.
#
# Plusieurs niveaux parce qu'un asset doit tenir sur fond sombre ET clair :
# les silhouettes noires disparaissent sur l'un, les pièces claires sur l'autre.
const NIVEAUX_LUMIERE: Array[Dictionary] = [
	{"nom": "Nuit",   "fond": Color(0.043, 0.051, 0.075), "voile": 0.00},
	{"nom": "Studio", "fond": Color(0.180, 0.196, 0.235), "voile": 0.10},
	{"nom": "Jour",   "fond": Color(0.545, 0.573, 0.620), "voile": 0.22},
	{"nom": "Blanc",  "fond": Color(0.855, 0.871, 0.898), "voile": 0.34},
]
# Démarre en « Studio » : le fond quasi noir d'origine noyait les paliers
# Commun, qui sont gris foncé — on n'y voyait rien.
const LUMIERE_DEFAUT := 1

enum Mode { LIBRE, COMBAT, USINE }

# Scène à recharger en sortant. Posée par l'appelant AVANT le changement de
# scène (cf. Village._ouvrir_showroom) ; vide quand la vitrine est lancée
# seule (F6 / ligne de commande), auquel cas Échap quitte pour de bon.
# `static` : survit au changement de scène, contrairement à un membre.
static var scene_retour := ""

var _registre: SpinePersonnagesData
var _ennemis: Array[Dictionary] = []
var _heros: Dictionary = {}
var _heros_apparences: Array[Dictionary] = []
var _mode: int = Mode.COMBAT   # arrivée directe en mode combat (26/08/2026)
var _idx_monstre := 0
var _idx_palier := 0
var _idx_heros := 0        # apparence du héros = son niveau d'équipement (Nv1…Nv6)
var _idx_cosmetique := 0   # jeu d'accessoires « Random » cumulé sur le héros
var _idx_lumiere := LUMIERE_DEFAUT

var _monde: Node2D            # sprites du mode LIBRE (espace monde)
var _duel: Node2D             # sprites du mode COMBAT
var _duel_heros: SpriteSpinePersonnage = null    # dans _duel, ou null
var _duel_monstre: SpriteSpinePersonnage = null  # dans _duel, ou null
var _duel_tween: Tween = null   # zoom-duel en cours ([A]/[T] en mode combat)
var _duel_ordre_restaure: Array = []   # [_duel_heros, index d'origine dans _duel]
var _cam: Camera2D
var _fond_neutre: ColorRect
var _decor: Control            # fond scindé (mode combat) : biomes + diagonale + sol
var _decor_usine: Control      # mode USINE : décor d'Usine SEUL, plein écran, sans masque
var _voile: ColorRect         # brume claire PAR-DESSUS le décor (mode combat)
var _hud: Label
var _titre: Label
var _panneau_file: PanelContainer   # file d'initiative mockée (mode combat)
var _file_box: HBoxContainer
var _repere: Node2D           # lignes de sol du mode LIBRE
# Étiquettes du mode libre + leur couleur d'origine : sur fond clair il faut
# les réassombrir, et on ne peut pas partir de la couleur déjà modifiée.
var _labels_libre: Array[Dictionary] = []

func _ready() -> void:
	_registre = load(REGISTRE) as SpinePersonnagesData
	if _registre != null:
		_ennemis = _registre.ennemis()
		_heros = _registre.heros()
		_recalculer_apparences_heros()
	_construire()
	if _registre == null or not SpriteSpinePersonnage.disponible():
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
	_fond_neutre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fond_neutre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond_layer.add_child(_fond_neutre)

	_decor = Control.new()
	_decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor.visible = false
	fond_layer.add_child(_decor)
	_construire_fond_combat()

	# Mode USINE (diagnostic, 28/08/2026, demande Rhend) : le décor de l'Usine
	# SEUL, plein écran, SANS le masque adverse ni la ville — pour juger le
	# travail de Christophe tel quel, sans mélanger ça avec le problème
	# (séparé) de la fenêtre coupée en deux par le split de combat.
	_decor_usine = Control.new()
	_decor_usine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor_usine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor_usine.visible = false
	fond_layer.add_child(_decor_usine)
	_retirer_masques(CombatDecorFactory.construire(_decor_usine, SOL_Y_FRAC, 0.5, BANDE_VS_PX))

	# Voile : posé APRÈS le décor donc au-dessus. Lever les noirs par-dessus
	# est fiable partout, là où un modulate > 1 dépend du rendu (GL Compatibility).
	_voile = ColorRect.new()
	_voile.color = Color(0.78, 0.82, 0.90, 0.0)
	_voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voile.visible = false
	fond_layer.add_child(_voile)

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

	# File d'initiative — MOCKUP du chrome réel de CombatCtbUi (même panneau,
	# mêmes chips, mêmes couleurs de camp) : la vitrine n'a pas de CtbMoteur
	# pour calculer un vrai `prevoir_ordre`, donc on alterne joueur/adverse sur
	# N_FILE cases pour juger le rendu des deux blocs de couleur en situation.
	# Visible en mode COMBAT seulement (_appliquer_mode).
	_panneau_file = PanelContainer.new()
	_panneau_file.anchor_left = 0.5; _panneau_file.anchor_right = 0.5
	_panneau_file.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panneau_file.offset_top = 12.0
	_panneau_file.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panneau_file.visible = false
	var style_file := ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 1.0)
	style_file.bg_color = UIColors.CYBER_BG
	_panneau_file.add_theme_stylebox_override("panel", style_file)
	hud_layer.add_child(_panneau_file)
	var haut_file := VBoxContainer.new()
	haut_file.add_theme_constant_override("separation", 2)
	haut_file.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panneau_file.add_child(haut_file)
	var titre_file := ExpeStyle.label_mono(Translations.T("ctb.file_titre"), 11,
			UIColors.CYBER_TEXTE_MUTED)
	titre_file.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	haut_file.add_child(titre_file)
	var centre_file := HBoxContainer.new()
	centre_file.alignment = BoxContainer.ALIGNMENT_CENTER
	centre_file.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haut_file.add_child(centre_file)
	_file_box = HBoxContainer.new()
	_file_box.add_theme_constant_override("separation", 6)
	_file_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre_file.add_child(_file_box)

	# Bandeau de raccourcis (bas) : REPREND le panneau de la barre d'actions du
	# vrai combat — même style/mêmes marges (`ExpeStyle.style_panneau`,
	# `UIColors.CYBER_ACCENT`), plein largeur, ancré en bas (26/08/2026). La
	# vitrine n'a pas de boutons Attaquer/Défendre/Compétence/Objet à y poser :
	# on y met le texte des raccourcis déjà écrit (`_rafraichir_hud`), pas de
	# contenu nouveau.
	var panneau_bas := PanelContainer.new()
	panneau_bas.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panneau_bas.offset_left = 0.0
	panneau_bas.offset_right = 0.0
	panneau_bas.offset_top = -60.0
	panneau_bas.offset_bottom = 0.0
	panneau_bas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style_bas := ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 0.90)
	style_bas.set_content_margin_all(10)
	panneau_bas.add_theme_stylebox_override("panel", style_bas)
	hud_layer.add_child(panneau_bas)
	_hud = ExpeStyle.label_mono("", 12, UIColors.CYBER_TEXTE_MUTED)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panneau_bas.add_child(_hud)

	# Pose le niveau d'entrée même si la vitrine reste vide (registre absent) :
	# sinon le ColorRect garderait sa couleur par défaut.
	_appliquer_lumiere()

# Fond scindé du mode COMBAT — REPRIS À L'IDENTIQUE de CombatCtbUi via
# `CombatFondScinde` (SOURCE PARTAGÉE, pas une copie) : la vitrine doit juger
# les personnages sur la présentation RÉELLE du combat, pas sur un décor à
# part — et les deux ne peuvent plus diverger puisqu'ils appellent le même code.
func _construire_fond_combat() -> void:
	CombatFondScinde.construire(_decor, SOL_Y_FRAC, SOL_X_JOUEUR, CombatCtbUi.BANDE_VS_PX)

# Retire tout `material` (le masque d'écrêtage adverse) d'un sous-arbre : sert
# au mode USINE, qui veut voir le décor COMPLET, jamais coupé à la diagonale.
func _retirer_masques(racine: Node) -> void:
	if racine is CanvasItem:
		(racine as CanvasItem).material = null
	for enfant in racine.get_children():
		_retirer_masques(enfant)

# ─── Mode LIBRE : une rangée par monstre ─────────────────────

# Rangées affichées : le HÉROS d'abord (c'est le mètre étalon — on juge la
# taille des monstres par rapport à lui), puis les ennemis dans l'ordre du
# registre. Chaque rangée montre les apparences de l'entrée : 5 paliers de
# rareté pour un ennemi, les 6 niveaux d'équipement pour Relic (et les
# variantes nommées le jour où les skins M/F arrivent).
func _rangees() -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	if not _heros.is_empty():
		sortie.append(_heros)
	sortie.append_array(_ennemis)
	return sortie

# Apparences d'une entrée AU JEU COSMÉTIQUE COURANT — passage obligé de la
# vitrine : sans lui, [V] ne changerait le visage que du héros en duel.
func _apparences(entree: Dictionary) -> Array[Dictionary]:
	return SpinePersonnagesData.apparences(entree, _idx_cosmetique)

# Le héros pilote deux axes indépendants : son niveau d'équipement ([H]) et
# son accessoire de visage ([V]). Changer le second reconstruit la liste, d'où
# le reclampage du premier.
func _recalculer_apparences_heros() -> void:
	if _heros.is_empty():
		_heros_apparences = []
		return
	_heros_apparences = _apparences(_heros)
	_idx_heros = clampi(_idx_heros, 0, maxi(0, _heros_apparences.size() - 1))

func _peupler_libre() -> void:
	_vider(_monde)
	_labels_libre.clear()
	var rangees := _rangees()
	for i in rangees.size():
		var e := rangees[i]
		var y := i * RANG_PAS
		var nom := UIHelpers.label(str(e.get("nom", "?")), 16, UIColors.TEXT_HEADER)
		nom.position = Vector2(-MARGE_G, y - 40.0)
		_monde.add_child(nom)
		_labels_libre.append({"node": nom, "base": UIColors.TEXT_HEADER})
		var apparences := _apparences(e)
		for k in apparences.size():
			var ap := apparences[k]
			var sprite := SpriteSpinePersonnage.creer(str(e.get("skel", "")),
					str(e.get("atlas", "")), ap, SpinePersonnagesData.hauteur_cible_px(e))
			if sprite == null:
				continue
			sprite.position = Vector2(k * COL_PAS, y)
			_monde.add_child(sprite)
			# Étiquette SOUS les pieds (l'origine du squelette est au sol :
			# tout le sprite est au-dessus de `position`). Couleur de rareté
			# quand c'en est un, neutre pour une variante nommée.
			# Apparence unique et sans nom propre → l'étiquette répéterait le
			# nom de la rangée : on s'en passe.
			if apparences.size() == 1 and str(ap.get("skin", "")) == "":
				continue
			var palier := int(ap.get("palier", -1))
			var teinte: Color = UIColors.tier_color(palier) if palier >= 0 else UIColors.TEXT_MUTED
			var lbl := UIHelpers.label(str(ap.get("nom", "?")), 12, teinte)
			lbl.position = Vector2(k * COL_PAS - 44.0, y + 8.0)
			_monde.add_child(lbl)
			_labels_libre.append({"node": lbl, "base": teinte})
	_appliquer_lumiere()

func _dessiner_reperes() -> void:
	var rangees := _rangees()
	# Un trait blanc translucide disparaît sur fond clair : on l'inverse.
	var teinte := Color(0, 0, 0, 0.20) if _fond_clair() else Color(1, 1, 1, 0.14)
	for i in rangees.size():
		var y := i * RANG_PAS
		var cols: int = maxi(1, _apparences(rangees[i]).size())
		_repere.draw_line(Vector2(-MARGE_G, y), Vector2((cols - 1) * COL_PAS + 120.0, y),
				teinte, 2.0)

# ─── Éclairage ───────────────────────────────────────────────

# Seuil BAS (0,35 et non 0,5) : dès qu'on quitte les fonds franchement sombres,
# du texte clair devient pénible bien avant que le fond soit « clair » au sens
# strict. Un gris moyen se lit mieux avec du texte sombre.
const SEUIL_FOND_CLAIR := 0.35

func _fond_clair() -> bool:
	return (NIVEAUX_LUMIERE[_idx_lumiere]["fond"] as Color).get_luminance() > SEUIL_FOND_CLAIR

# Applique le niveau courant : fond du mode libre, voile du mode combat, et
# lisibilité des textes qui se posent dessus.
func _appliquer_lumiere() -> void:
	var niveau := NIVEAUX_LUMIERE[_idx_lumiere]
	_fond_neutre.color = niveau["fond"]
	_voile.color.a = float(niveau["voile"])
	# `_titre` seul repose directement sur le fond neutre en mode libre : sur un
	# niveau clair il faut l'assombrir. `_hud` vit désormais dans un panneau à
	# fond opaque (`panneau_bas`, CYBER_BG_PANEL) — toujours sombre quel que
	# soit le niveau de lumière choisi, donc plus besoin de le réassombrir.
	var titre_sur_clair: bool = _fond_clair() and _mode == Mode.LIBRE
	_titre.add_theme_color_override("font_color", _lisible(UIColors.TEXT_HEADER, titre_sur_clair))
	for entree in _labels_libre:
		var lbl: Label = entree["node"]
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color",
					_lisible(entree["base"] as Color, _fond_clair()))
	_repere.queue_redraw()

# Les couleurs de l'UI sont pensées pour un fond sombre : telles quelles, elles
# blanchissent sur fond clair. On les assombrit sans toucher à leur teinte, pour
# que les couleurs de rareté restent reconnaissables.
static func _lisible(base: Color, sur_fond_clair: bool) -> Color:
	return base.darkened(0.70) if sur_fond_clair else base

# ─── Mode COMBAT : duel au cadrage réel ──────────────────────

func _peupler_duel() -> void:
	_zoom_duel_interrompre()   # sinon un tween en cours anime des nœuds sur le point d'être libérés
	_vider(_duel)
	_duel_heros = null
	_duel_monstre = null
	if _ennemis.is_empty():
		return
	var sol_y := VUE.y * SOL_Y_FRAC

	# Vis-à-vis : le héros, à l'emplacement du camp joueur, dans l'apparence
	# courante (une seule tant que Relic n'expose que « default »).
	if not _heros.is_empty():
		var ap_h: Dictionary = {}
		if _idx_heros < _heros_apparences.size():
			ap_h = _heros_apparences[_idx_heros]
		var relic := SpriteSpinePersonnage.creer(str(_heros.get("skel", "")),
				str(_heros.get("atlas", "")), ap_h, SpinePersonnagesData.hauteur_cible_px(_heros))
		if relic != null:
			# Le camp joueur est à GAUCHE : le héros regarde vers la droite.
			# Explicite même si l'export va déjà dans ce sens — le jour où une
			# livraison arrive retournée, ça se corrige dans le registre.
			relic.orienter(SpinePersonnagesData.echelle_x(_heros, true))
			relic.position = Vector2(VUE.x * SOL_X_JOUEUR, sol_y)
			# Ombre AVANT le sprite (ordre d'ajout = ordre de dessin, voir
			# CombatOmbrePortee) — même vitrine partagée que le vrai combat.
			# Anneau laissé ACTIF en permanence : la ShowRoom est le banc
			# d'essai, pas de notion de tour ici, autant pouvoir juger l'anneau
			# sans attendre un combat réel. Taille à l'échelle du personnage,
			# comme dans le vrai combat (voir CombatOmbrePortee).
			var ombre_h := CombatOmbrePortee.creer(true, relic.largeur_rendue_px())
			if ombre_h != null:
				ombre_h.position = relic.position
				ombre_h.definir_actif(true)
				_duel.add_child(ombre_h)
			_duel.add_child(relic)
			_duel_heros = relic

	if _ennemis.is_empty():
		return
	var e := _ennemis[_idx_monstre]
	var ap_mob := _apparences(e)
	var mob := SpriteSpinePersonnage.creer(str(e.get("skel", "")), str(e.get("atlas", "")),
			ap_mob[clampi(_idx_palier, 0, ap_mob.size() - 1)],
			SpinePersonnagesData.hauteur_cible_px(e))
	if mob != null:
		# Le camp adverse est à DROITE : l'ennemi regarde vers la gauche. Le
		# miroir n'est plus systématique — il dépend du sens d'export déclaré
		# dans le registre, seul endroit qui sait comment l'asset a été livré.
		mob.orienter(SpinePersonnagesData.echelle_x(e, false))
		mob.position = Vector2(VUE.x * SOL_X_ADVERSE, sol_y)
		var ombre_m := CombatOmbrePortee.creer(false, mob.largeur_rendue_px())
		if ombre_m != null:
			ombre_m.position = mob.position
			ombre_m.definir_actif(true)
			_duel.add_child(ombre_m)
		_duel.add_child(mob)
		_duel_monstre = mob

	_rafraichir_file_combat()

# File d'initiative mockée (voir _construire) : alterne joueur/adverse sur
# CombatCtbUi.N_FILE cases avec les noms réellement affichés (héros à son
# apparence courante, monstre courant) — juste l'ordre change d'un vrai
# combat, jamais la couleur ni le style des blocs.
func _rafraichir_file_combat() -> void:
	if _file_box == null:
		return
	UIHelpers.clear_children_now(_file_box)
	if _duel_heros == null or _duel_monstre == null:
		return
	var nom_h := _nom_apparence_heros()
	var nom_m := str(_ennemis[_idx_monstre].get("nom", "?"))
	for i in CombatCtbUi.N_FILE:
		var est_joueur := i % 2 == 0
		var couleur := ExpeStyle.accent_camp(est_joueur)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", ExpeStyle.style_chip(couleur))
		var m := UIHelpers.margin_of(4)
		m.add_child(ExpeStyle.label_mono(nom_h if est_joueur else nom_m, 11,
				couleur.lightened(0.35)))
		chip.add_child(m)
		_file_box.add_child(chip)

# ─── Zoom-DUEL (mode combat) : la vraie mise en scène, pas une pâle copie ─
#
# [A]/[T] rejouent EXACTEMENT le zoom-duel de CombatCtbUi (`DuelZoomFx`,
# SOURCE PARTAGÉE — mêmes constantes ZOOM/ECART/TENUE, jamais une recette à
# part). La différence tient à la géographie de la vitrine, pas à l'effet :
# le combat réel n'a qu'UN nœud à zoomer (`_couche_scene`, un Control qui
# porte à la fois le décor ET les sprites) ; la vitrine a DEUX arbres
# séparés — `_decor` (Control dans un CanvasLayer, hors caméra) pour le fond,
# `_duel` (Node2D dans l'espace caméra) pour les personnages. La caméra de
# combat étant figée à l'identité (zoom 1, centrée sur VUE), les deux espaces
# coïncident pixel pour pixel : on peut donc zoomer les deux en parallèle
# avec le même `foyer` et le même facteur, sans jamais les fusionner.
func _zoom_duel(converger: bool) -> void:
	if _duel_heros == null or _duel_monstre == null:
		return
	_zoom_duel_interrompre()
	var centre := Vector2(VUE.x * 0.5, VUE.y * SOL_Y_FRAC)
	# Même contrat que CombatCtbUi : mêlée → centre de l'écran (les deux corps
	# y viennent) ; tir → milieu du couple, personne ne bouge.
	var foyer: Vector2 = centre if converger \
			else (_duel_heros.position + _duel_monstre.position) * 0.5
	var origine_h := _duel_heros.position
	var origine_m := _duel_monstre.position
	var pos_h := centre + Vector2(-DuelZoomFx.ECART_PX * 0.5, 0.0)
	var pos_m := centre + Vector2(DuelZoomFx.ECART_PX * 0.5, 0.0)
	# Le héros (toujours l'attaquant ici) doit rester DEVANT le monstre : sinon
	# son arme, qui déborde de son propre corps pendant le geste, disparaît
	# derrière lui dès que la convergence les rapproche — même correctif que
	# `CombatCtbUi._duel_attaque` (recette partagée, même bug des deux côtés).
	if converger:
		_duel_ordre_restaure = [_duel_heros, _duel_heros.get_index()]
		_duel.move_child(_duel_heros, _duel.get_child_count() - 1)
	_decor.pivot_offset = foyer - Vector2(0.0, DuelZoomFx.FOCUS_HAUT_PX)
	_duel_tween = create_tween()
	_duel_tween.tween_method(_poser_zoom_scene.bind(foyer), 1.0, DuelZoomFx.ZOOM,
			DuelZoomFx.DUREE_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if converger:
		_duel_tween.parallel().tween_property(_duel_heros, "position", pos_h,
				DuelZoomFx.DUREE_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_duel_tween.parallel().tween_property(_duel_monstre, "position", pos_m,
				DuelZoomFx.DUREE_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_duel_tween.tween_interval(DuelZoomFx.TENUE)
	_duel_tween.tween_method(_poser_zoom_scene.bind(foyer), DuelZoomFx.ZOOM, 1.0,
			DuelZoomFx.DUREE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if converger:
		_duel_tween.parallel().tween_property(_duel_heros, "position", origine_h,
				DuelZoomFx.DUREE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_duel_tween.parallel().tween_property(_duel_monstre, "position", origine_m,
				DuelZoomFx.DUREE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_duel_tween.finished.connect(func() -> void:
		_duel_restaurer_ordre()
		_duel_tween = null)

# Replace le héros à son rang d'origine dans `_duel` une fois le duel fini
# (ou interrompu) — le z-order ne doit servir que le temps du geste.
func _duel_restaurer_ordre() -> void:
	if _duel_ordre_restaure.is_empty():
		return
	var noeud := _duel_ordre_restaure[0] as CanvasItem
	var index: int = _duel_ordre_restaure[1]
	_duel_ordre_restaure = []
	if is_instance_valid(noeud) and _duel != null:
		_duel.move_child(noeud, index)

# Applique un zoom `s` autour de `foyer` aux DEUX espaces de coordonnées de
# la vitrine : `_decor` (Control, pivot_offset natif) et `_duel` (Node2D,
# sans pivot natif — position ET scale recalculées ensemble, même formule
# que la compensation de profondeur de CombatDecorCity : position = foyer ×
# (1 − s), en repartant d'une position de repos à l'origine (0,0)).
func _poser_zoom_scene(s: float, foyer: Vector2) -> void:
	_decor.scale = Vector2.ONE * s
	_duel.scale = Vector2.ONE * s
	_duel.position = foyer * (1.0 - s)

# Coupe net un zoom-duel en cours : la scène redevient nette instantanément
# (appelé avant de repeupler — un nouveau duel, ou un changement de monstre/
# palier, ne doit pas hériter d'un tween qui animerait des nœuds libérés).
func _zoom_duel_interrompre() -> void:
	if _duel_tween != null and _duel_tween.is_valid():
		_duel_tween.kill()
	_duel_tween = null
	_duel_restaurer_ordre()
	_decor.scale = Vector2.ONE
	_duel.scale = Vector2.ONE
	_duel.position = Vector2.ZERO

# Vide un porte-sprites : retiré de l'arbre AVANT queue_free, sinon les
# anciens sprites restent visibles (et animables) jusqu'à la fin de la frame.
func _vider(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()

# ─── Animations à la demande ─────────────────────────────────
# La livraison de Christophe porte 5 animations : les regarder est la moitié
# du travail de la vitrine. La touche joue sur TOUS les sprites affichés —
# en mode libre, les 6 costumes attaquent ensemble, ce qui rend les
# différences de silhouette immédiatement lisibles.

enum Anim { REPOS, MELEE, TIR, HIT, MORT }

# [A]/[T] n'y sont PLUS : en mode combat ils déclenchent la vraie mise en
# scène (`_attaquer_combat`), pas juste une animation jouée « partout ».
const TOUCHES_ANIM := {
	KEY_I: Anim.REPOS, KEY_X: Anim.HIT, KEY_M: Anim.MORT,
}

# [A]/[T] en mode COMBAT (26/08/2026) : la vraie mise en scène d'un événement
# d'attaque — le héros joue son geste, le monstre encaisse (Hit), la scène
# rejoue le zoom-duel (`_zoom_duel`) — au lieu de « tout le monde joue
# l'animation », qui n'a de sens qu'en mode libre (comparer les costumes).
func _attaquer_combat(a_distance: bool) -> void:
	if _duel_heros == null or _duel_monstre == null:
		return
	_duel_heros.jouer_attaque(a_distance)
	_duel_monstre.jouer_hit()
	_zoom_duel(not a_distance)

func _jouer_partout(anim: int) -> void:
	for parent: Node in [_monde, _duel]:
		for c in parent.get_children():
			var sprite := c as SpriteSpinePersonnage
			if sprite == null:
				continue
			match anim:
				Anim.REPOS: sprite.reprendre_repos()
				Anim.MELEE: sprite.jouer_attaque()
				Anim.TIR:   sprite.jouer_attaque(true)
				Anim.HIT:   sprite.jouer_hit()
				Anim.MORT:  sprite.jouer_mort()

# ─── Modes & caméra ──────────────────────────────────────────

func _appliquer_mode() -> void:
	var combat: bool = _mode == Mode.COMBAT
	var usine: bool = _mode == Mode.USINE
	var libre: bool = _mode == Mode.LIBRE
	_monde.visible = libre
	_repere.visible = libre
	_duel.visible = combat
	_decor.visible = combat
	_decor_usine.visible = usine
	_fond_neutre.visible = libre
	_voile.visible = combat   # pas de voile en USINE : jugement brut, sans filtre
	# _panneau_file (mockup file d'initiative) reste MASQUÉ (demande Rhend,
	# 27/08/2026) : il coiffait le haut du gap et cachait le point émetteur
	# de la coupure holographique. Code conservé, juste jamais rendu visible.
	_appliquer_lumiere()
	if combat:
		_peupler_duel()
		# Cadrage figé, identique au jeu : caméra centrée sur la vue de réf.
		_cam.zoom = Vector2.ONE
		_cam.position = VUE * 0.5
	elif usine:
		_cam.zoom = Vector2.ONE
		_cam.position = VUE * 0.5
	else:
		_cadrer_tout()
	_rafraichir_hud()

# Recentre la caméra sur l'ensemble des rangées (état d'entrée du mode libre).
func _cadrer_tout() -> void:
	const PAD := 80.0   # sinon le nom du monstre affleure le bord gauche
	# Largeur = la rangée la PLUS fournie : le héros porte 6 niveaux
	# d'équipement là où les ennemis n'ont que 5 paliers.
	var cols := 1
	for r in _rangees():
		cols = maxi(cols, _apparences(r).size())
	var largeur := MARGE_G + cols * COL_PAS + PAD
	var hauteur := maxf(RANG_PAS, _rangees().size() * RANG_PAS)
	_cam.position = Vector2(largeur * 0.5 - MARGE_G - PAD * 0.5,
			hauteur * 0.5 - RANG_PAS * 0.5)
	_cam.zoom = Vector2.ONE * minf(VUE.x / largeur, VUE.y / (hauteur + 200.0))

func _rafraichir_hud() -> void:
	if _mode == Mode.COMBAT:
		if _ennemis.is_empty():
			return
		var e := _ennemis[_idx_monstre]
		_titre.text = "COMBAT — %s  ·  %s   vs   %s" % [str(e.get("nom", "?")),
				GameData.get_tier_name(_idx_palier), _nom_apparence_heros()]
		# Hauteurs cibles PAR ENTITÉ (chara design, 09/2026) : plus un seul « px »
		# valable pour tout le monde — on affiche celle du héros ET celle de
		# l'adversaire courant, chacune résolue depuis son propre écart en %.
		_hud.text = "[Tab] mode libre    [←/→] monstre    [↑/↓] palier    [H] niveau héros    [V] %s    [B] lumière : %s\n" % [
				_nom_cosmetique(), _nom_lumiere()] \
				+ LIGNE_ANIMS + "    —    cadrage réel : sol %.2f · joueur %.2f · adverse %.2f · héros %d px · adverse %d px" % [
				SOL_Y_FRAC, SOL_X_JOUEUR, SOL_X_ADVERSE,
				int(SpinePersonnagesData.hauteur_cible_px(_heros)),
				int(SpinePersonnagesData.hauteur_cible_px(e))]
	elif _mode == Mode.USINE:
		_titre.text = "USINE SEULE — plein écran, sans masque ni ville (diagnostic)"
		_hud.text = "[Tab] mode suivant    —    décor Christophe tel quel, écrêtage adverse retiré"
	else:
		_titre.text = "SHOWROOM — héros (%d niveaux) + %d monstre(s) × %d paliers" % [
				_heros_apparences.size(), _ennemis.size(), NB_PALIERS]
		_hud.text = "[Tab] mode combat    [glisser] déplacer    [molette] zoom    [R] recadrer    [V] %s    [B] lumière : %s\n" % [
				_nom_cosmetique(), _nom_lumiere()] \
				+ LIGNE_ANIMS \
				+ ("    —    [Échap] retour au QG" if scene_retour != "" else "")

# Rappel des animations livrées — une seule ligne, valable dans les deux modes.
const LIGNE_ANIMS := "[I] repos  [A] mêlée  [T] tir (mêlée si non livré)  [X] coup reçu  [M] mort"

# Jeu d'accessoires « Random » courant — « visage : Visage 2 ». Sans jeu
# déclaré, la touche n'a rien à faire : on le dit plutôt que d'afficher un
# libellé vide.
func _nom_cosmetique() -> String:
	var jeux := SpinePersonnagesData.cosmetiques(_heros)
	if jeux.is_empty():
		return "visage : —"
	return "visage : %s" % str(jeux[clampi(_idx_cosmetique, 0, jeux.size() - 1)].get("nom", "?"))

func _nom_lumiere() -> String:
	return str(NIVEAUX_LUMIERE[_idx_lumiere]["nom"])

# Libellé de l'apparence courante du héros (son niveau d'équipement) — le nom
# du personnage s'il n'en a qu'une : afficher un libellé d'apparence
# laisserait croire qu'il y a un choix.
func _nom_apparence_heros() -> String:
	if _heros_apparences.size() <= 1:
		return str(_heros.get("nom", "?"))
	return str(_heros_apparences[_idx_heros].get("nom", "?"))

# Retour à la scène d'origine si la vitrine a été ouverte depuis le jeu,
# sinon fermeture (elle est alors la scène racine).
func _sortir() -> void:
	if scene_retour == "":
		get_tree().quit()
		return
	var cible := scene_retour
	scene_retour = ""   # la prochaine ouverture repose sa propre destination
	get_tree().change_scene_to_file(cible)

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
			_mode = wrapi(_mode + 1, 0, 3)
			_appliquer_mode()
		KEY_R:
			if _mode == Mode.LIBRE:
				_cadrer_tout()
		KEY_ESCAPE:
			_sortir()
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
		KEY_B:
			# Vaut dans LES DEUX modes : un asset doit tenir sur fond sombre
			# comme sur fond clair.
			_idx_lumiere = wrapi(_idx_lumiere + 1, 0, NIVEAUX_LUMIERE.size())
			_appliquer_lumiere()
			_rafraichir_hud()
		KEY_H:
			# Niveau d'équipement du héros. Utile en COMBAT seulement : en
			# mode libre, sa rangée montre déjà les 6 niveaux côte à côte.
			if _mode == Mode.COMBAT and _heros_apparences.size() > 1:
				_idx_heros = wrapi(_idx_heros + 1, 0, _heros_apparences.size())
				_peupler_duel()
				_rafraichir_hud()
		KEY_V:
			# Accessoire de visage « Random ». Il change TOUTE la vitrine :
			# c'est un axe indépendant du niveau, on le juge sur les 6.
			var jeux := SpinePersonnagesData.cosmetiques(_heros)
			if jeux.size() > 1:
				_idx_cosmetique = wrapi(_idx_cosmetique + 1, 0, jeux.size())
				_recalculer_apparences_heros()
				_repeupler()
				_rafraichir_hud()
		KEY_A, KEY_T:
			# Mode combat : vraie mise en scène (geste + Hit + zoom-duel). Mode
			# libre : pas de vis-à-vis possible, retombe sur « tout le monde
			# joue l'animation » (comparer les costumes d'un coup).
			if _mode == Mode.COMBAT:
				_attaquer_combat(code == KEY_T)
			else:
				_jouer_partout(Anim.TIR if code == KEY_T else Anim.MELEE)
		_:
			if TOUCHES_ANIM.has(code):
				_jouer_partout(int(TOUCHES_ANIM[code]))

func _repeupler() -> void:
	if _mode == Mode.COMBAT:
		_peupler_duel()
	else:
		_peupler_libre()
