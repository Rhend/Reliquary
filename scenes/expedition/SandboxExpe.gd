# ============================================================
# SandboxExpe — Scène ISOLÉE de test de la carte d'expédition (chantiers 2-3).
#
# Lançable directement (F6) : expédition complète sur un Lieu FACTICE —
# palier de profondeur sélectionnable, graine rejouable, navigation à la
# souris (clic sur un nœud adjacent) ou au clavier (flèches = nœud adjacent
# le plus proche dans la direction), brouillard de guerre réel (les nœuds
# non découverts ne sont PAS dessinés), choix Extraire / Continuer sur la
# Fin d'étage, journal des événements à droite.
#
# Chantier 3 : les nœuds Combat / Attaque surprise jouent de VRAIS combats
# CTB (avatar factice vs pool du bestiaire) ; PV de l'Avatar persistants
# entre les nœuds, affichés en permanence ; défaite = fin d'expédition
# immédiate.
#
# Chantier 5 : par défaut les combats sont JOUÉS À LA MAIN dans l'écran de
# combat (CombatCtbUi — Attaquer / Défendre, cible au choix, embuscade
# annoncée). La case « Combat auto » restaure l'auto-résolution du chantier 3
# (journal du moteur replié dans celui de la run) ; le ScreenshotTool et les
# suites de test pilotent ExpeRun directement et restent en auto.
#
# Outil de DEV : pas une UI de jeu (l'UI finale viendra avec sa DA).
# ============================================================
extends Control

const PALIERS: Array[PalierProfondeurData] = [
	preload("res://data/expedition/palier_peripherie.tres"),
	preload("res://data/expedition/palier_enceinte.tres"),
	preload("res://data/expedition/palier_noyau.tres"),
]
const CONFIG: ExpeCarteConfigData = preload("res://data/expedition/config_carte.tres")
const CONFIG_COMBAT: ExpeCombatConfigData = preload("res://data/expedition/config_combat.tres")
const POOL: PoolEnnemisData = preload("res://data/expedition/pool_defaut.tres")
const AVATAR: CombattantCtbData = preload("res://data/combat_ctb/avatar.tres")

const COULEURS := {
	Enums.TypeNoeud.ENTREE:    Color(0.55, 0.55, 0.60),
	Enums.TypeNoeud.COMBAT:    Color(0.90, 0.35, 0.30),
	Enums.TypeNoeud.MYSTERE:   Color(0.70, 0.45, 0.95),
	Enums.TypeNoeud.COFFRE:    Color(0.95, 0.78, 0.30),
	Enums.TypeNoeud.FIN_ETAGE: Color(0.30, 0.90, 0.95),
}

var run: ExpeRun
var _carte_view: Control
var _journal_label: Label
var _journal_scroll: ScrollContainer
var _btn_extraire: Button
var _btn_continuer: Button
var _opt_palier: OptionButton
var _spin_graine: SpinBox
var _chk_heros: CheckBox
var _chk_combat_auto: CheckBox
var _lbl_etat: Label
var _combat_data: Dictionary = {}    # payload du dernier combat_demarre (embuscade…)
var _combat_ui: CombatCtbUi = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construire_ui()
	_lancer()

func _construire_ui() -> void:
	var racine := HBoxContainer.new()
	racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(racine)

	# ── Colonne gauche : contrôles + carte ──
	var gauche := VBoxContainer.new()
	gauche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauche.size_flags_stretch_ratio = 2.4
	racine.add_child(gauche)

	var barre := HBoxContainer.new()
	gauche.add_child(barre)
	_opt_palier = OptionButton.new()
	for p in PALIERS:
		_opt_palier.add_item("%s (×%.1f)" % [p.nom_journal(), p.multiplicateur])
	barre.add_child(_opt_palier)
	_spin_graine = SpinBox.new()
	_spin_graine.min_value = 0
	_spin_graine.max_value = 999999
	_spin_graine.value = 1337
	_spin_graine.tooltip_text = "Graine RNG (0 = aléatoire)"
	barre.add_child(_spin_graine)
	var btn_go := Button.new()
	btn_go.text = "⟳ Relancer l'expédition"
	btn_go.pressed.connect(_lancer)
	barre.add_child(btn_go)
	_chk_heros = CheckBox.new()
	_chk_heros.text = "Héros réel"
	_chk_heros.button_pressed = true
	_chk_heros.tooltip_text = "Coché : le vrai héros (stats effectives, équipement compris,\n" \
			+ "via CtbPont.combattant_depuis_heros). Décoché : avatar factice (avatar.tres)."
	_chk_heros.toggled.connect(func(_on: bool) -> void: _lancer())
	barre.add_child(_chk_heros)
	_chk_combat_auto = CheckBox.new()
	_chk_combat_auto.text = "Combat auto"
	_chk_combat_auto.button_pressed = false
	_chk_combat_auto.tooltip_text = "Décoché : les combats se jouent à la main (écran de combat).\n" \
			+ "Coché : auto-résolution (comportement chantier 3 — captures, calibrage)."
	barre.add_child(_chk_combat_auto)
	_lbl_etat = Label.new()
	barre.add_child(_lbl_etat)

	_carte_view = Control.new()
	_carte_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_carte_view.draw.connect(_dessiner_carte)
	_carte_view.gui_input.connect(_input_carte)
	_carte_view.focus_mode = Control.FOCUS_ALL
	gauche.add_child(_carte_view)

	var choix := HBoxContainer.new()
	gauche.add_child(choix)
	_btn_extraire = Button.new()
	_btn_extraire.text = "▲ EXTRAIRE (fin d'expédition)"
	_btn_extraire.pressed.connect(func() -> void:
		run.extraire()
		_rafraichir())
	choix.add_child(_btn_extraire)
	_btn_continuer = Button.new()
	_btn_continuer.text = "▼ CONTINUER (étage suivant)"
	_btn_continuer.pressed.connect(func() -> void:
		run.continuer()
		_rafraichir())
	choix.add_child(_btn_continuer)

	# ── Colonne droite : journal ──
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	racine.add_child(_journal_scroll)
	_journal_label = Label.new()
	_journal_label.add_theme_font_size_override("font_size", 12)
	_journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_label)

func _lancer() -> void:
	if _combat_ui != null:
		_combat_ui.queue_free()
		_combat_ui = null
	var palier: PalierProfondeurData = PALIERS[maxi(_opt_palier.selected, 0)]
	run = ExpeRun.new(CONFIG, palier, "lieu_factice_sandbox", int(_spin_graine.value),
			_avatar_choisi(), POOL, CONFIG_COMBAT)
	run.combat_demarre.connect(func(_m: CtbMoteur, data: Dictionary) -> void:
		_combat_data = data)
	run.demarrer()
	_rafraichir()

# Héros RÉEL de la partie courante (défaut) ou avatar factice (tests/calibrage).
# Lancé seul (F6), le sandbox charge la sauvegarde pour refléter la vraie
# partie — jamais deux fois par-dessus une partie en cours ; il n'émet aucun
# signal de progression (rien à écrire).
func _avatar_choisi() -> CombattantCtbData:
	if _chk_heros == null or not _chk_heros.button_pressed:
		return AVATAR
	if not SaveManager.est_chargee():
		SaveManager.load_save()
	var heros := CtbPont.combattant_depuis_heros()
	return heros if heros != null else AVATAR

# Combat en attente après un déplacement : joué à la main dans l'écran de
# combat (défaut) ou auto-résolu si « Combat auto » est coché (le journal du
# moteur est replié dans celui de la run à la fin du combat, dans les deux
# cas). Le ScreenshotTool pilote ExpeRun directement : jamais d'UI chez lui.
func _traiter_combat() -> void:
	if run.combat_en_cours == null or _combat_ui != null:
		return
	if _chk_combat_auto.button_pressed:
		run.combat_en_cours.derouler_auto()
		return
	_combat_ui = CombatCtbUi.new(run.combat_en_cours,
			bool(_combat_data.get("embuscade", false)))
	_combat_ui.fermee.connect(func(_recap: Dictionary) -> void:
		_combat_ui.queue_free()
		_combat_ui = null
		_rafraichir())
	add_child(_combat_ui)

func _rafraichir() -> void:
	_carte_view.queue_redraw()
	_btn_extraire.visible = run.choix_ouvert
	_btn_continuer.visible = run.choix_ouvert and run.etage < CONFIG.nb_etages
	var pv := "PV %d/%d" % [int(roundf(run.pv_avatar)), int(roundf(run.avatar_data.pv_max))]
	if run.est_terminee:
		_lbl_etat.text = "  %s — %s" % [
				"☠ DÉFAITE" if run.defaite else "✔ Expédition terminée", pv]
	else:
		_lbl_etat.text = "  Étage %d/%d — %s" % [run.etage, CONFIG.nb_etages, pv]
	_journal_label.text = "\n".join(run.journal)
	await get_tree().process_frame   # attendre la mesure du label avant de scroller en bas
	_journal_scroll.scroll_vertical = int(_journal_scroll.get_v_scroll_bar().max_value)

# ─── Rendu de la carte (brouillard réel : non découvert = pas dessiné) ──
func _pos_ecran(p: Vector2) -> Vector2:
	var taille := _carte_view.size
	var marge := 40.0
	return Vector2(
		marge + p.x / ExpeCarte.LARGEUR * (taille.x - marge * 2.0),
		marge + p.y / ExpeCarte.HAUTEUR * (taille.y - marge * 2.0))

func _dessiner_carte() -> void:
	var cv := _carte_view
	cv.draw_rect(Rect2(Vector2.ZERO, cv.size), Color(0.06, 0.07, 0.10))
	if run == null:
		return
	# Arêtes : uniquement entre deux nœuds découverts.
	for nd in run.noeuds_visibles():
		for v in nd.voisins:
			var nv := run.carte.noeud(v)
			if nv.decouvert and v > nd.id:
				cv.draw_line(_pos_ecran(nd.pos), _pos_ecran(nv.pos), Color(0.35, 0.40, 0.50), 2.0)
	# Nœuds découverts (les autres N'EXISTENT PAS à l'écran).
	for nd in run.noeuds_visibles():
		var pe := _pos_ecran(nd.pos)
		var col: Color = COULEURS.get(nd.type, Color.WHITE)
		if nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE:
			col = col.darkened(0.55)   # inerte
		cv.draw_circle(pe, 16.0, col)
		var etiquette := _etiquette(nd)
		cv.draw_string(get_theme_default_font(), pe + Vector2(-14, 34), etiquette,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.95))
	# Marqueur joueur.
	var pj := _pos_ecran(run.carte.noeud(run.position_joueur).pos)
	cv.draw_arc(pj, 22.0, 0.0, TAU, 24, Color(1, 1, 1), 3.0)

func _etiquette(nd: ExpeNoeud) -> String:
	match nd.type:
		Enums.TypeNoeud.ENTREE:    return "Entrée"
		Enums.TypeNoeud.MYSTERE:   return "?" if nd.contenu_mystere < 0 else "? résolu"
		Enums.TypeNoeud.COMBAT:    return "Combat"
		Enums.TypeNoeud.COFFRE:    return "Coffre"
		Enums.TypeNoeud.FIN_ETAGE: return "Fin d'étage"
	return ""

# ─── Entrées : clic sur un nœud adjacent, flèches directionnelles ──
func _input_carte(ev: InputEvent) -> void:
	if run == null or run.est_terminee:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_carte_view.grab_focus()
		for v in run.carte.noeud(run.position_joueur).voisins:
			var nd := run.carte.noeud(v)
			if nd.decouvert and _pos_ecran(nd.pos).distance_to(ev.position) <= 22.0:
				run.deplacer_vers(v)
				_traiter_combat()
				_rafraichir()
				return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var dir := Vector2.ZERO
		match ev.keycode:
			KEY_LEFT:  dir = Vector2.LEFT
			KEY_RIGHT: dir = Vector2.RIGHT
			KEY_UP:    dir = Vector2.UP
			KEY_DOWN:  dir = Vector2.DOWN
		if dir != Vector2.ZERO:
			_deplacer_direction(dir)

# Flèche : va vers le voisin adjacent le mieux aligné avec la direction.
func _deplacer_direction(dir: Vector2) -> void:
	var cur := run.carte.noeud(run.position_joueur)
	var best := -1
	var best_dot := 0.35   # seuil : ignorer les voisins trop perpendiculaires
	for v in cur.voisins:
		var d := (run.carte.noeud(v).pos - cur.pos).normalized().dot(dir)
		if d > best_dot:
			best_dot = d
			best = v
	if best >= 0:
		run.deplacer_vers(best)
		_traiter_combat()
		_rafraichir()
