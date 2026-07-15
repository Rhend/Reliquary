# ============================================================
# CombatCtbUi — Écran de combat CTB JOUABLE (Rework Combat, chantier 5).
#
# Écran scindé (référence Advanced Wars) : camp joueur à gauche, camp adverse
# à droite (jusqu'à 3 combattants par camp — architecture N-vs-N actée), Lieu
# en fond purement COSMÉTIQUE (placeholder : BiomeBackground scindé en
# diagonale, survivant de l'ancien écran de combat). DA finale hors scope.
#
# Pilote un CtbMoteur DÉJÀ démarré, en pull-based :
#   • activation du camp joueur → attend l'input (Attaquer / Défendre —
#     PAS de bouton Objet : les consommables n'existent pas, « contenu
#     absent, pas grisé ») ; Attaquer → choix de cible parmi les ennemis
#     vivants (boutons ou clic sur la carte ennemie) ;
#   • activations ennemies : auto-résolues (IA du moteur), séquencées par de
#     courtes pauses pour rester lisibles.
#
# Lisibilité : file d'initiative des N_FILE prochaines activations (ordre
# seul, recalculée après chaque action via moteur.prevoir_ordre), PV +
# statuts par carte (CarteCombattantCtb), dégâts flottants distincts
# (normal / CRITIQUE / tick de DoT) via le signal structuré
# `moteur.evenement`, annonce d'embuscade à l'ouverture.
#
# Transitions placeholder : fondu noir en entrée (carte → combat) ; l'issue
# (VICTOIRE / DÉFAITE) s'affiche en fin de bataille, clic pour revenir à la
# carte → signal `fermee(recap)` (l'appelant libère l'écran ; la suite —
# reprise de run, Game Over — reste chez lui).
#
# `facteur_delais` : multiplicateur des pauses (1.0 jeu ; 0.0 = aucun délai
# ni clic de sortie — tests headless).
# ============================================================
class_name CombatCtbUi
extends Control

signal fermee(recap: Dictionary)

const N_FILE := 6              # activations prédites affichées (proposition actée)
const BANDE_VS_PX := 80.0      # largeur de la découpe diagonale des deux fonds

var moteur: CtbMoteur
var embuscade := false
var facteur_delais := 1.0

var _cartes: Dictionary = {}   # CtbCombattant → CarteCombattantCtb
var _file_box: HBoxContainer
var _bandeau_tour: Label
var _btn_attaquer: Button
var _btn_defendre: Button
var _rangee_cibles: HBoxContainer
var _fx: Control               # couche des textes flottants (plein écran)
var _voile: ColorRect          # fondu de transition + écran d'issue
var _voile_contenu: VBoxContainer
var _recap: Dictionary = {}
var _action_en_attente: Dictionary = {}
signal _action_choisie

func _init(m: CtbMoteur, avec_embuscade: bool = false) -> void:
	moteur = m
	embuscade = avec_embuscade

func _ready() -> void:
	# and_offsets : set_anchors_preset seul CONSERVE les offsets courants —
	# ajouté à un SubViewport (ScreenshotTool), l'écran restait en 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloque la carte en dessous
	_construire()
	moteur.evenement.connect(_sur_evenement)
	moteur.victoire.connect(func(r: Dictionary) -> void: _recap = r)
	moteur.defaite.connect(func(r: Dictionary) -> void: _recap = r)
	_boucle()

# ─── Construction (100 % code — règle projet) ────────────────

func _construire() -> void:
	# Fond scindé : ambiance Ville côté joueur, biome côté adverse (presets
	# BiomeBackground survivants — placeholder du Lieu, purement cosmétique).
	var fond_joueur := BiomeBackground.new()
	fond_joueur.apply_preset("city")
	fond_joueur.set_split(1, BANDE_VS_PX)
	add_child(fond_joueur)
	var fond_adverse := BiomeBackground.new()
	fond_adverse.apply_preset("forest")
	fond_adverse.set_split(2, BANDE_VS_PX)
	add_child(fond_adverse)
	var seam := Control.new()
	seam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seam.draw.connect(_dessiner_diagonale.bind(seam))
	seam.resized.connect(seam.queue_redraw)
	add_child(seam)

	# Colonne générale : file d'initiative / arène / barre d'actions.
	var colonne := VBoxContainer.new()
	colonne.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	colonne.add_theme_constant_override("separation", 8)
	add_child(colonne)

	var haut := VBoxContainer.new()
	haut.add_theme_constant_override("separation", 2)
	colonne.add_child(haut)
	var titre_file := UIHelpers.label(Translations.T("ctb.file_titre"), 11, UIColors.TEXT_MUTED)
	titre_file.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	haut.add_child(titre_file)
	var centre_file := HBoxContainer.new()
	centre_file.alignment = BoxContainer.ALIGNMENT_CENTER
	haut.add_child(centre_file)
	_file_box = HBoxContainer.new()
	_file_box.add_theme_constant_override("separation", 6)
	centre_file.add_child(_file_box)

	# Arène scindée : cartes du camp joueur | vide central | cartes adverses.
	var arene := HBoxContainer.new()
	arene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(arene)
	var camp_joueur := _colonne_camp(arene, BoxContainer.ALIGNMENT_CENTER)
	var milieu := Control.new()
	milieu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	milieu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arene.add_child(milieu)
	var camp_adverse := _colonne_camp(arene, BoxContainer.ALIGNMENT_CENTER)
	for cb in moteur.combattants:
		var carte := CarteCombattantCtb.new(cb)
		carte.cliquee.connect(_sur_cible_cliquee)
		_cartes[cb] = carte
		(camp_joueur if cb.est_joueur() else camp_adverse).add_child(carte)

	# Barre d'actions (bas) : bandeau de tour + Attaquer / Défendre + cibles.
	# AUCUN bouton Objet : contenu absent, pas grisé (pilier projet).
	var bas := PanelContainer.new()
	var style_bas := UIHelpers.card_style(UIColors.TEXT_HEADER, 0.10, 0.35, 1, 6)
	style_bas.bg_color = Color(UIColors.PANEL_BG_DARK.r, UIColors.PANEL_BG_DARK.g,
			UIColors.PANEL_BG_DARK.b, 0.88)
	style_bas.set_content_margin_all(10)
	bas.add_theme_stylebox_override("panel", style_bas)
	colonne.add_child(bas)
	var bas_v := VBoxContainer.new()
	bas_v.add_theme_constant_override("separation", 6)
	bas.add_child(bas_v)
	_bandeau_tour = UIHelpers.label("", 14, UIColors.TEXT_HEADER)
	_bandeau_tour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bas_v.add_child(_bandeau_tour)
	var rangee := HBoxContainer.new()
	rangee.alignment = BoxContainer.ALIGNMENT_CENTER
	rangee.add_theme_constant_override("separation", 12)
	bas_v.add_child(rangee)
	_btn_attaquer = Button.new()
	_btn_attaquer.text = Translations.T("ctb.attaquer")
	_btn_attaquer.pressed.connect(_sur_attaquer)
	rangee.add_child(_btn_attaquer)
	_btn_defendre = Button.new()
	_btn_defendre.text = Translations.T("ctb.defendre")
	_btn_defendre.pressed.connect(func() -> void:
		_valider_action({"type": Enums.ActionCtb.DEFENDRE}))
	rangee.add_child(_btn_defendre)
	_rangee_cibles = HBoxContainer.new()
	_rangee_cibles.alignment = BoxContainer.ALIGNMENT_CENTER
	_rangee_cibles.add_theme_constant_override("separation", 8)
	bas_v.add_child(_rangee_cibles)
	_montrer_actions(false)

	# Couche FX (dégâts flottants) au-dessus de tout le contenu de jeu.
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	# Voile de transition (début / fin de bataille) — au-dessus de tout.
	_voile = ColorRect.new()
	_voile.color = Color(0, 0, 0, 1)
	_voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_voile)
	_voile_contenu = VBoxContainer.new()
	_voile_contenu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_voile_contenu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_voile_contenu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_voile_contenu.alignment = BoxContainer.ALIGNMENT_CENTER
	_voile.add_child(_voile_contenu)

func _colonne_camp(parent: Control, alignement: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = alignement as BoxContainer.AlignmentMode
	v.add_theme_constant_override("separation", 10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var marge := UIHelpers.margin_of(16)
	marge.add_child(v)
	parent.add_child(marge)
	return v

# Bande diagonale placeholder entre les deux fonds scindés (l'ancien
# séparateur CombatVS a été supprimé avec le moteur temps réel).
func _dessiner_diagonale(seam: Control) -> void:
	var w := seam.size.x
	var h := seam.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var demi := 3.0
	var xt := w * 0.5 + BANDE_VS_PX * 0.5
	var xb := w * 0.5 - BANDE_VS_PX * 0.5
	var accent := BiomeBackground.accent_for_biome("")
	seam.draw_colored_polygon(PackedVector2Array([
		Vector2(xt - demi, 0), Vector2(xt + demi, 0),
		Vector2(xb + demi, h), Vector2(xb - demi, h),
	]), Color(accent.r, accent.g, accent.b, 0.55))

# ─── Boucle de combat (pull-based, asynchrone) ───────────────

func _boucle() -> void:
	await _intro()
	while not moteur.termine and is_inside_tree():
		_rafraichir_tout()
		var c := moteur.activer_suivant()
		_rafraichir_tout()   # les ticks DÉBUT (Saignement) sont déjà passés
		if moteur.termine:
			break
		if c == null:
			await _pause(0.5)   # activation consommée (mort au tick DÉBUT)
			continue
		_marquer_actif(c)
		if c.est_joueur():
			_bandeau_tour.text = Translations.T("ctb.a_toi") % CarteCombattantCtb.nom_ui(c.data)
			_montrer_actions(true)
			await _action_choisie
			if not is_inside_tree():
				return
			_montrer_actions(false)
			moteur.jouer(_action_en_attente)
		else:
			_bandeau_tour.text = CarteCombattantCtb.nom_ui(c.data)
			await _pause(0.55)   # séquencement lisible des activations ennemies
			if not is_inside_tree():
				return
			moteur.jouer(moteur.action_auto(c))
		_marquer_actif(null)
		_rafraichir_tout()
		await _pause(0.35)
	if is_inside_tree():
		await _outro()

# ─── Actions du joueur ───────────────────────────────────────

func _montrer_actions(on: bool) -> void:
	_btn_attaquer.visible = on
	_btn_defendre.visible = on
	UIHelpers.clear_children_now(_rangee_cibles)
	if not on:
		_bandeau_tour.text = ""
		_mettre_cibles_en_avant(false)

func _sur_attaquer() -> void:
	if not _btn_attaquer.visible:
		return   # pas d'activation joueur ouverte (press programmatique hors tour)
	var vivants: Array[CtbCombattant] = _ennemis_vivants()
	if vivants.size() <= 1:
		_valider_action({"type": Enums.ActionCtb.ATTAQUER,
				"cible": vivants[0] if vivants.size() == 1 else null})
		return
	# Plusieurs cibles : boutons nominatifs + cartes ennemies cliquables.
	UIHelpers.clear_children_now(_rangee_cibles)
	_rangee_cibles.add_child(UIHelpers.label(
			Translations.T("ctb.choisir_cible"), 12, UIColors.TEXT_MUTED))
	for cb in vivants:
		var b := Button.new()
		b.text = CarteCombattantCtb.nom_ui(cb.data)
		b.pressed.connect(_sur_cible_cliquee.bind(cb))
		_rangee_cibles.add_child(b)
	var annuler := Button.new()
	annuler.text = Translations.T("ctb.annuler")
	annuler.pressed.connect(func() -> void:
		UIHelpers.clear_children_now(_rangee_cibles)
		_mettre_cibles_en_avant(false))
	_rangee_cibles.add_child(annuler)
	_mettre_cibles_en_avant(true)
	AudioManager.play_sfx("ui_select", -10.0)

func _sur_cible_cliquee(cible: CtbCombattant) -> void:
	if not _btn_attaquer.visible or not cible.est_vivant():
		return
	_valider_action({"type": Enums.ActionCtb.ATTAQUER, "cible": cible})

func _valider_action(action: Dictionary) -> void:
	AudioManager.play_sfx("ui_select", -8.0)
	_action_en_attente = action
	_action_choisie.emit()

func _mettre_cibles_en_avant(on: bool) -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).marquer_ciblable(
				on and not cb.est_joueur() and cb.est_vivant())

func _ennemis_vivants() -> Array[CtbCombattant]:
	var out: Array[CtbCombattant] = []
	for cb in moteur.combattants:
		if not cb.est_joueur() and cb.est_vivant():
			out.append(cb)
	return out

# ─── Affichage ───────────────────────────────────────────────

func _rafraichir_tout() -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).rafraichir()
	_rafraichir_file()

# File d'initiative : ordre des N_FILE prochaines activations (sans valeurs
# numériques — l'ordre suffit), recalculée après chaque action.
func _rafraichir_file() -> void:
	UIHelpers.clear_children_now(_file_box)
	for cb in moteur.prevoir_ordre(N_FILE):
		var couleur := UIColors.ENERGY_ACCENT if cb.est_joueur() else UIColors.TYPE_CREATURE
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIHelpers.card_style(couleur, 0.18, 0.7, 1, 5))
		var m := UIHelpers.margin_of(4)
		m.add_child(UIHelpers.label(CarteCombattantCtb.nom_ui(cb.data), 11,
				couleur.lightened(0.35)))
		chip.add_child(m)
		_file_box.add_child(chip)

func _marquer_actif(c: CtbCombattant) -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).marquer_actif(cb == c)

# ─── Retours visuels (signal structuré du moteur) ────────────

func _sur_evenement(e: Dictionary) -> void:
	if not is_inside_tree():
		return
	match str(e.get("type", "")):
		"attaque":
			var cible := e["cible"] as CtbCombattant
			var degats := int(e["degats"])
			var crit := bool(e["crit"])
			var couleur: Color
			if cible.est_joueur():
				couleur = UIColors.DMG_HEAVY_ENEMY if crit else UIColors.DMG_BY_ENEMY
			else:
				couleur = UIColors.DMG_HEAVY_HERO if crit else UIColors.DMG_BY_HERO
			var texte := (Translations.T("ctb.crit_float") % degats) if crit else str(degats)
			AudioManager.play_sfx("attack", -6.0)
			_flotter(cible, texte, 22 if crit else 17, couleur, crit)
		"tick_statut":
			# Tick de DoT : distinct des coups (violet, préfixe du statut).
			_flotter(e["cible"] as CtbCombattant, "−%d %s" % [int(e["degats"]),
					str(e["nom"])], 14, UIColors.POISON, false)
		"statut_pose":
			var sd := e["statut"] as StatutCtbData
			# StatutCtbData partage les champs nom_affichage_* : même chemin
			# Translations que les combattants (pas de FR en dur).
			var nom := Translations.entity_name({
				"nom_affichage_fr": sd.nom_affichage_fr,
				"nom_affichage_en": sd.nom_affichage_en,
			}, sd.id)
			_flotter(e["cible"] as CtbCombattant, "+ %s" % nom, 13, UIColors.POISON, false)
		"defense":
			_flotter(e["combattant"] as CtbCombattant,
					Translations.T("ctb.garde_pill"), 15, UIColors.SHIELD, false)

func _flotter(cb: CtbCombattant, texte: String, taille: int, couleur: Color,
		punch: bool) -> void:
	var carte := _cartes.get(cb) as CarteCombattantCtb
	if carte == null or _fx == null:
		return
	var pos := carte.centre_fx() - _fx.global_position
	UIHelpers.float_text(_fx, texte, taille, couleur, pos, 46.0, punch)

# ─── Transitions de bataille (placeholder assumé) ────────────

# Fondu d'ouverture (carte → combat) + annonce d'embuscade le cas échéant.
func _intro() -> void:
	var titre := UIHelpers.label(Translations.T("ctb.combat_titre"), 34, UIColors.TEXT_HEADER)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(titre)
	if embuscade:
		AudioManager.play_sfx("trap_appear", -4.0)
		var amb := UIHelpers.label(Translations.T("ctb.embuscade"), 26, UIColors.MECH_AMBUSH)
		amb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_voile_contenu.add_child(amb)
		var sous := UIHelpers.label(Translations.T("ctb.embuscade_sub"), 13,
				UIColors.MECH_AMBUSH.lightened(0.35))
		sous.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_voile_contenu.add_child(sous)
	await _pause(1.1 if embuscade else 0.7)
	if not is_inside_tree():
		return
	if facteur_delais > 0.0:
		var tw := create_tween()
		tw.tween_property(_voile, "color:a", 0.0, 0.45)
		await tw.finished
	else:
		_voile.color.a = 0.0
	_voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIHelpers.clear_children_now(_voile_contenu)

# Fin de bataille : l'issue s'affiche AVANT le retour à la carte ;
# clic pour continuer (fermeture immédiate si facteur_delais = 0 — tests).
func _outro() -> void:
	_montrer_actions(false)
	_marquer_actif(null)
	_rafraichir_tout()
	var gagne := moteur.victoire_joueur
	AudioManager.play_sfx("summary_victory" if gagne else "summary_defeat", -4.0)
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP
	var issue := UIHelpers.label(
			Translations.T("ctb.victoire" if gagne else "ctb.defaite"), 42,
			UIColors.LOG_VICTORY if gagne else UIColors.LOG_DEFEAT)
	issue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(issue)
	var invite := UIHelpers.label(Translations.T("ctb.continuer"), 13, UIColors.TEXT_MUTED)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(invite)
	if facteur_delais > 0.0:
		var tw := create_tween()
		tw.tween_property(_voile, "color:a", 0.72, 0.5)
		await tw.finished
		if not is_inside_tree():
			return
		await _clic_sur_voile()
		if not is_inside_tree():
			return
	fermee.emit(_recap)

func _clic_sur_voile() -> void:
	while is_inside_tree():
		var ev: InputEvent = await _voile.gui_input
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			return

func _pause(secondes: float) -> void:
	if facteur_delais <= 0.0:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(secondes * facteur_delais).timeout
