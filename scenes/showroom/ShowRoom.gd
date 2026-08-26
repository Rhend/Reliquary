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
#               fond scindé (`CombatFondScinde` — décor Christophe côté
#               joueur, biome placeholder côté adverse), même sol / mêmes
#               ancrages / même hauteur cible que CombatCtbUi — présentation
#               PARTAGÉE (pas un décor à part). Sert à juger la lisibilité
#               en situation.
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

enum Mode { LIBRE, COMBAT }

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
var _cam: Camera2D
var _fond_neutre: ColorRect
var _decor: Control            # fond scindé (mode combat) : biomes + diagonale + sol
var _sol_combat: Control       # ligne d'horizon + emplacements, dessinés dans _decor
var _voile: ColorRect         # brume claire PAR-DESSUS le décor (mode combat)
var _hud: Label
var _titre: Label
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
	_sol_combat = Control.new()
	_sol_combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sol_combat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sol_combat.draw.connect(_dessiner_sol_combat)
	_sol_combat.resized.connect(_sol_combat.queue_redraw)
	_decor.add_child(_sol_combat)

# Ligne d'horizon + bande dégradée sous les pieds — copie de la partie SOL de
# CombatCtbUi._dessiner_sol, réduite aux deux emplacements fixes de la
# vitrine (joueur / adverse, toujours 1 vs 1 ici). PLUS d'ellipse
# d'emplacement (26/08/2026) : elle datait de l'ère EnergyBoule (repère au
# sol d'un placeholder sans silhouette propre) — superflue maintenant que
# les monstres ont leurs propres sprites Spine posés dessus.
func _dessiner_sol_combat() -> void:
	var w := VUE.x
	var y := VUE.y * SOL_Y_FRAC
	_sol_combat.draw_line(Vector2(0, y), Vector2(w, y), UIColors.CYBER_SOL, 2.0)
	for i in 3:
		_sol_combat.draw_rect(Rect2(0.0, y + float(i) * 16.0, w, 16.0),
				Color(UIColors.CYBER_SOL, UIColors.CYBER_SOL.a * (0.45 - 0.13 * float(i))))

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
					str(e.get("atlas", "")), ap)
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
	_vider(_duel)
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
				str(_heros.get("atlas", "")), ap_h)
		if relic != null:
			relic.position = Vector2(VUE.x * SOL_X_JOUEUR, sol_y)
			_duel.add_child(relic)

	if _ennemis.is_empty():
		return
	var e := _ennemis[_idx_monstre]
	var ap_mob := _apparences(e)
	var mob := SpriteSpinePersonnage.creer(str(e.get("skel", "")), str(e.get("atlas", "")),
			ap_mob[clampi(_idx_palier, 0, ap_mob.size() - 1)])
	if mob != null:
		# Miroir horizontal : l'ennemi fait face au camp joueur.
		mob.scale = Vector2(-1.0, 1.0)
		mob.position = Vector2(VUE.x * SOL_X_ADVERSE, sol_y)
		_duel.add_child(mob)

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

const TOUCHES_ANIM := {
	KEY_I: Anim.REPOS, KEY_A: Anim.MELEE, KEY_T: Anim.TIR,
	KEY_X: Anim.HIT, KEY_M: Anim.MORT,
}

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
	_monde.visible = not combat
	_repere.visible = not combat
	_duel.visible = combat
	_decor.visible = combat
	_fond_neutre.visible = not combat
	_voile.visible = combat
	_appliquer_lumiere()
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
		_hud.text = "[Tab] mode libre    [←/→] monstre    [↑/↓] palier    [H] niveau héros    [V] %s    [B] lumière : %s\n" % [
				_nom_cosmetique(), _nom_lumiere()] \
				+ LIGNE_ANIMS + "    —    cadrage réel : sol %.2f · joueur %.2f · adverse %.2f · %d px" % [
				SOL_Y_FRAC, SOL_X_JOUEUR, SOL_X_ADVERSE,
				int(SpriteSpinePersonnage.HAUTEUR_CIBLE_PX)]
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
			_mode = Mode.LIBRE if _mode == Mode.COMBAT else Mode.COMBAT
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
		_:
			if TOUCHES_ANIM.has(code):
				_jouer_partout(int(TOUCHES_ANIM[code]))

func _repeupler() -> void:
	if _mode == Mode.COMBAT:
		_peupler_duel()
	else:
		_peupler_libre()
