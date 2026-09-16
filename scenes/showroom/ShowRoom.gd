# ============================================================
# ShowRoom — vitrine dev des assets Spine = L'ÉCRAN DE COMBAT RÉEL, FUSIONNÉ
# (09/2026). Avant cette date, la vitrine reconstruisait sa propre copie du
# décor/des sprites/de la file « au cadrage réel » à côté de CombatCtbUi —
# les deux divergeaient en silence à chaque réglage oublié d'un côté (retour
# Rhend : « c'est censé être la même UI, arrêtons de doubler le travail »).
# Elle INSTANCIE désormais le VRAI `CombatCtbUi`, avec un faux combat (héros
# RÉEL vs la créature choisie) : Attaquer/Défendre/Compétence sont les VRAIS
# boutons, la file d'initiative est le VRAI moteur CTB, le zoom-duel est le
# VRAI `DuelZoomFx`. Toute évolution du combat réel se répercute ici sans
# rien à resynchroniser.
#
# Reste propre à la vitrine (dev UNIQUEMENT, jamais dans le vrai combat) :
#   • ←/→ / ↑/↓  — créature / palier de la créature previsualisée ;
#   • H / V       — niveau d'équipement / accessoire de visage du héros ;
#   • B           — éclairage du décor (ne module JAMAIS les personnages) ;
#   • Tab         — bascule duel ⇄ décor de l'Usine seul (diagnostic) ;
#   • F1          — affiche/masque ce mémo (masqué par défaut : la vitrine ne
#                    doit pas avoir l'air différente du vrai combat tant
#                    qu'on n'a pas demandé l'aide).
#
# Lancée seule (F6, ou `godot --path . res://scenes/showroom/ShowRoom.tscn`),
# ou depuis le bouton dev du QG (`Village.DEBUG_SHOWROOM_BTN`) qui pose
# `scene_retour` avant de changer de scène. N'ÉCRIT JAMAIS la sauvegarde —
# `SaveManager.load_save()` n'est appelé QUE pour LIRE le héros réel quand la
# vitrine est lancée seule (même garde que SandboxExpe), jamais pour écrire.
# ============================================================
class_name ShowRoom
extends Control

const REGISTRE := SpinePersonnagesData.CHEMIN
const NB_PALIERS := SpinePersonnagesData.NB_PALIERS               # paliers d'une créature (5)
const NB_NIVEAUX_HEROS := SpinePersonnagesData.NB_PALIERS_RARETE  # niveaux d'équipement du héros (6)

const AVATAR_FACTICE: CombattantCtbData = preload("res://data/combat_ctb/avatar.tres")
const ENNEMI_FACTICE: CombattantCtbData = preload("res://data/combat_ctb/ennemi_moyen.tres")

# ─── Cadrage : LU de CombatCtbUi pour le décor Usine seul, jamais recopié ──
const SOL_Y_FRAC := CombatCtbUi.SOL_Y_FRAC
const BANDE_VS_PX := CombatCtbUi.BANDE_VS_PX

# ─── Éclairage du décor (jamais des personnages) ─────────────
const NIVEAUX_LUMIERE: Array[Dictionary] = [
	{"nom": "Nuit",   "voile": 0.00},
	{"nom": "Studio", "voile": 0.10},
	{"nom": "Jour",   "voile": 0.22},
	{"nom": "Blanc",  "voile": 0.34},
]
const TEINTE_VOILE := Color(0.78, 0.82, 0.90)
# Démarre en « Studio » : un fond quasi noir noie les paliers Commun (gris foncé).
const LUMIERE_DEFAUT := 1

enum Mode { DUEL, USINE }

# Scène à recharger en sortant. Posée par l'appelant AVANT le changement de
# scène (cf. Village._ouvrir_showroom) ; vide quand la vitrine est lancée
# seule, auquel cas Échap quitte pour de bon. `static` : survit au
# changement de scène, contrairement à un membre.
static var scene_retour := ""

var _registre: SpinePersonnagesData
var _ennemis: Array[Dictionary] = []
var _heros: Dictionary = {}

var _mode: int = Mode.DUEL
var _idx_monstre := 0
var _idx_palier := 0            # palier PRÉVISUALISÉ de la créature (previsu_palier_ennemi)
var _idx_niveau_heros := 0      # 0-based ; niveau réel = +1 (previsu_niveau_heros)
var _idx_cosmetique := 0
var _idx_lumiere := LUMIERE_DEFAUT
var _aide_visible := false

var _combat_ui: CombatCtbUi = null
var _decor_usine: Control
var _hud: Label
var _aide: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_registre = load(REGISTRE) as SpinePersonnagesData
	if _registre != null:
		_ennemis = _registre.ennemis()
		_heros = _registre.heros()
	_construire_chrome()
	_lancer_duel()
	_appliquer_mode()

# ─── Chrome dev : décor Usine (diagnostic) + statut + aide ───

func _construire_chrome() -> void:
	_decor_usine = Control.new()
	_decor_usine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor_usine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor_usine.visible = false
	add_child(_decor_usine)
	_retirer_masques(CombatDecorFactory.construire(_decor_usine, SOL_Y_FRAC, 0.5, BANDE_VS_PX))

	# CanvasLayer au-dessus de tout (y compris CombatCtbUi, ajouté/retiré au
	# gré des rebuilds) — l'ordre d'ajout dans l'arbre n'a plus d'importance.
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	_hud = UIHelpers.label("", 13, UIColors.TEXT_MUTED)
	_hud.position = Vector2(10, 6)
	hud_layer.add_child(_hud)

	_construire_aide(hud_layer)

# Retire tout `material` (le masque d'écrêtage adverse) d'un sous-arbre : le
# mode Usine veut voir le décor COMPLET, jamais coupé à la diagonale du combat.
func _retirer_masques(racine: Node) -> void:
	if racine is CanvasItem:
		(racine as CanvasItem).material = null
	for enfant in racine.get_children():
		_retirer_masques(enfant)

# Mémo des commandes propres à la vitrine — MASQUÉ par défaut : la vitrine ne
# doit rien avoir de plus qu'un vrai combat tant qu'on n'a pas demandé l'aide
# (retour Rhend : « une UI toute bête quand on ne se rappelle plus la touche »).
func _construire_aide(parent: CanvasLayer) -> void:
	_aide = PanelContainer.new()
	_aide.visible = false
	_aide.anchor_left = 1.0; _aide.anchor_right = 1.0
	_aide.offset_left = -300.0; _aide.offset_right = -12.0
	_aide.offset_top = 12.0
	_aide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.07, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.12, 0.86, 0.95, 0.55)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(3)
	_aide.add_theme_stylebox_override("panel", style)
	parent.add_child(_aide)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_aide.add_child(vb)
	var titre := UIHelpers.label("COMMANDES VITRINE (F1 pour fermer)", 12, UIColors.TEXT_HEADER)
	vb.add_child(titre)
	for ligne in [
		"← / →   créature",
		"↑ / ↓   palier de la créature",
		"H       niveau d'équipement du héros",
		"V       accessoire de visage du héros",
		"B       éclairage du décor",
		"Tab     décor Usine seul ⇄ duel",
	]:
		vb.add_child(UIHelpers.label(ligne, 12, UIColors.TEXT_MUTED))
	var note := UIHelpers.label(
			"Le reste (Attaquer, Défendre, cible…) est le VRAI combat — mêmes boutons.",
			11, UIColors.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(270, 0)
	vb.add_child(note)

# ─── Duel : instancie le VRAI CombatCtbUi ────────────────────

# (Re)construit ENTIÈREMENT l'écran de combat réel pour la créature courante
# (←/→, ou premier lancement) — change les stats réelles du combattant
# adverse, donc son identité dans le moteur, pas juste son skin. Le palier
# prévisualisé/le niveau du héros, eux, ne passent PLUS par ici : voir
# `CombatCtbUi.previsu_rafraichir_visuel` (hot-reload, ↑/↓/H/V), qui ne
# touche que le visuel sans reconstruire le combat en cours.
func _lancer_duel() -> void:
	if _combat_ui != null:
		_combat_ui.queue_free()
		_combat_ui = null
	if _ennemis.is_empty():
		_rafraichir_hud()
		return
	var m := CtbMoteur.new()
	m.ajouter(_avatar_choisi(), Enums.CampCtb.JOUEUR)
	m.ajouter(_ennemi_choisi(), Enums.CampCtb.ADVERSE)
	m.demarrer()
	_combat_ui = CombatCtbUi.new(m, false)
	_combat_ui.previsu_niveau_heros = _idx_niveau_heros + 1
	_combat_ui.previsu_cosmetique_heros = _idx_cosmetique
	_combat_ui.previsu_palier_ennemi = _idx_palier
	# Rejouer un duel frais après victoire/défaite/clic de sortie : la
	# vitrine reste sur la MÊME créature/le même palier, prête à rejouer —
	# jamais un retour au QG (elle n'a pas de flux de jeu à fermer).
	_combat_ui.fermee.connect(func(_r: Dictionary) -> void: _lancer_duel())
	add_child(_combat_ui)
	_combat_ui.visible = _mode == Mode.DUEL
	_appliquer_lumiere()
	_rafraichir_hud()

# Héros RÉEL de la partie courante (mêmes rails que SandboxExpe._avatar_choisi) :
# lancée seule, la vitrine charge la sauvegarde pour refléter la vraie
# partie — jamais deux fois par-dessus une partie en cours ; aucune écriture.
func _avatar_choisi() -> CombattantCtbData:
	if not SaveManager.est_chargee():
		SaveManager.load_save()
	var heros := CtbPont.combattant_depuis_heros()
	return heros if heros != null else AVATAR_FACTICE

func _ennemi_choisi() -> CombattantCtbData:
	if _ennemis.is_empty():
		return ENNEMI_FACTICE
	var entite_id := _entity_id_pour(_ennemis[clampi(_idx_monstre, 0, _ennemis.size() - 1)])
	if entite_id == "":
		return ENNEMI_FACTICE
	var d := CtbPont.combattant_depuis_entite(entite_id)
	return d if d != null else ENNEMI_FACTICE

# id GameData (bestiaire, ex. "creature_flamebot") d'une entrée du registre
# Spine (id COURT, ex. "flamebot") — sens INVERSE de `SpinePersonnagesData.
# par_id`, qui va du bestiaire vers le registre. "" si la créature visuelle
# n'a pas (encore) de fiche de stats — la vitrine retombe sur ENNEMI_FACTICE.
func _entity_id_pour(entree: Dictionary) -> String:
	var court := str(entree.get("id", ""))
	for id in GameData.entities.keys():
		if str(id).trim_prefix("creature_") == court:
			return str(id)
	return ""

# ─── Éclairage ───────────────────────────────────────────────

func _appliquer_lumiere() -> void:
	if _combat_ui == null:
		return
	var alpha := float(NIVEAUX_LUMIERE[_idx_lumiere]["voile"])
	_combat_ui.previsu_definir_voile(Color(TEINTE_VOILE.r, TEINTE_VOILE.g, TEINTE_VOILE.b, alpha))

# ─── Modes ────────────────────────────────────────────────────

func _appliquer_mode() -> void:
	var duel: bool = _mode == Mode.DUEL
	if _combat_ui != null:
		_combat_ui.visible = duel
	_decor_usine.visible = not duel
	_rafraichir_hud()

func _rafraichir_hud() -> void:
	if _hud == null:
		return
	if _registre == null or _ennemis.is_empty():
		_hud.text = "AUCUN ASSET SPINE DISPONIBLE (registre vide)    [F1] aide"
		return
	if _mode == Mode.USINE:
		_hud.text = "USINE SEULE — décor sans masque ni ville (diagnostic)    [Tab] duel    [F1] aide"
		return
	var nom_m := str(_ennemis[_idx_monstre].get("nom", "?"))
	_hud.text = "%s · %s   vs   héros Nv%d    [F1] aide" % [
			nom_m, GameData.get_tier_name(_idx_palier), _idx_niveau_heros + 1]

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

func _touche(code: int) -> void:
	match code:
		KEY_ESCAPE:
			_sortir()
		KEY_F1:
			_aide_visible = not _aide_visible
			_aide.visible = _aide_visible
		KEY_TAB, KEY_C:
			_mode = Mode.USINE if _mode == Mode.DUEL else Mode.DUEL
			_appliquer_mode()
		KEY_LEFT, KEY_RIGHT:
			if _mode == Mode.DUEL and not _ennemis.is_empty():
				_idx_monstre = wrapi(_idx_monstre + (1 if code == KEY_RIGHT else -1),
						0, _ennemis.size())
				_lancer_duel()
		KEY_UP, KEY_DOWN:
			# Hot-reload (pas de _lancer_duel) : le palier prévisualisé ne
			# change QUE le skin de l'ennemi, jamais ses stats — inutile de
			# reconstruire le combat pour ça (retour Rhend, voir CombatCtbUi.
			# previsu_rafraichir_visuel).
			if _mode == Mode.DUEL and _combat_ui != null:
				_idx_palier = wrapi(_idx_palier + (1 if code == KEY_DOWN else -1), 0, NB_PALIERS)
				_combat_ui.previsu_palier_ennemi = _idx_palier
				_combat_ui.previsu_rafraichir_visuel(true)
				_rafraichir_hud()
		KEY_H:
			if _mode == Mode.DUEL and _combat_ui != null:
				_idx_niveau_heros = wrapi(_idx_niveau_heros + 1, 0, NB_NIVEAUX_HEROS)
				_combat_ui.previsu_niveau_heros = _idx_niveau_heros + 1
				_combat_ui.previsu_rafraichir_visuel(false)
				_rafraichir_hud()
		KEY_V:
			if _mode == Mode.DUEL and _combat_ui != null:
				var jeux := SpinePersonnagesData.cosmetiques(_heros)
				if jeux.size() > 1:
					_idx_cosmetique = wrapi(_idx_cosmetique + 1, 0, jeux.size())
					_combat_ui.previsu_cosmetique_heros = _idx_cosmetique
					_combat_ui.previsu_rafraichir_visuel(false)
					_rafraichir_hud()
		KEY_B:
			_idx_lumiere = wrapi(_idx_lumiere + 1, 0, NIVEAUX_LUMIERE.size())
			_appliquer_lumiere()
			_rafraichir_hud()
