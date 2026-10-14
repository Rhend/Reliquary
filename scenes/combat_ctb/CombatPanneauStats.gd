# ============================================================
# CombatPanneauStats — panneau de stats détaillé en bas d'écran (chantier
# UI_Concept2, 07/09/2026 — assets `Panel_Separator_01/02/03` livrés mais
# jamais branchés). Identité (nom/niveau), PV, Ammo, grille DMG/CRIT/DIST/
# PROT/SPEED, colonne de statuts actifs.
#
# Générique par CAMP (`creer(camp_joueur)` choisit PANEL_BACK/BORDER/SEPARATEUR
# _HERO ou _ENNEMI) et par COMBATTANT (`definir_combattant`). Camp joueur :
# `CombatCtbUi` y met l'allié en sélection (UI_Concept2). Camp ennemi
# (UI_Concept4.png, DA rouge, 13/10/2026) : même grille + une colonne
# /Ability/ (compétences du combattant — l'IA n'en joue jamais, elle reste donc
# presque toujours à « — » ; c'est une VITRINE de ce que la créature porte) et
# le PALIER de rareté à la place du niveau. Quel ennemi montrer = décision de
# CombatCtbUi (survol > cible > ennemi actif), pas du widget.
#
# Trois stats n'ont AUCUNE mécanique derrière dans ce moteur CTB (Ammo, DIST,
# DODGE — CLAUDE.md : « AUCUNE notion de portée ou de distance dans le CTB »,
# pas d'esquive) : affichées en « — », placeholders assumés qui marquent la
# place du futur, pas une valeur réelle. DMG est un nombre UNIQUE
# (stat_finale("atk")) — pas de fourchette min-max façon mockup, le moteur n'en
# a pas.
# ============================================================
class_name CombatPanneauStats
extends PanelContainer

const LARGEUR_MIN := 480.0

var camp_joueur := true
var _cb: CtbCombattant = null
var _palier := 0   # palier de rareté affiché (camp ennemi seulement)

var _lbl_dodge: Label
var _abilities_box: VBoxContainer
var _lbl_identite: Label
var _lbl_pv: Label
var _lbl_ammo: Label
var _lbl_dmg: Label
var _lbl_crit: Label
var _lbl_dist: Label
var _lbl_prot: Label
var _lbl_speed: Label
var _statuts_box: VBoxContainer

static func creer(camp_joueur_: bool) -> CombatPanneauStats:
	var p := CombatPanneauStats.new()
	p.camp_joueur = camp_joueur_
	p._construire()
	return p

func _construire() -> void:
	custom_minimum_size = Vector2(LARGEUR_MIN, 0.0)
	add_theme_stylebox_override("panel", CombatUiSkin.style_panneau_stats(camp_joueur))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Filet de sécurité : le panneau est forcé à une largeur EXACTE par
	# l'appelant (jusqu'au trait de séparation, CombatCtbUi._repositionner_
	# panel_stats) — si le contenu déborde malgré tout, on le tronque plutôt
	# que de laisser du texte peint hors de son propre panneau.
	clip_contents = true

	var marge := UIHelpers.margin_of(8)
	marge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marge)
	var corps := HBoxContainer.new()
	corps.add_theme_constant_override("separation", 12)
	corps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marge.add_child(corps)

	# ── Colonne identité : nom/niveau, PV, Ammo ──
	var col_id := VBoxContainer.new()
	col_id.add_theme_constant_override("separation", 2)
	col_id.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corps.add_child(col_id)
	_lbl_identite = ExpeStyle.label_mono("", 14, UIColors.CYBER_TEXTE)
	col_id.add_child(_lbl_identite)
	_lbl_pv = ExpeStyle.label_mono("", 12, UIColors.CYBER_TEXTE)
	col_id.add_child(_lbl_pv)
	_lbl_ammo = ExpeStyle.label_mono("", 12, UIColors.CYBER_TEXTE_MUTED)
	col_id.add_child(_lbl_ammo)

	# ── Colonne stats : grille 4 colonnes (label/valeur × 2 groupes/ligne),
	# décorée d'un soulignement (Panel_Separator_0X) sous DMG et PROT — le
	# reste du panneau reste sans ornement, un liseré sous chaque ligne
	# chargerait l'écran pour rien.
	var col_stats := VBoxContainer.new()
	col_stats.add_theme_constant_override("separation", 2)
	col_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corps.add_child(col_stats)
	var grille := GridContainer.new()
	grille.columns = 4
	grille.add_theme_constant_override("h_separation", 8)
	grille.add_theme_constant_override("v_separation", 2)
	col_stats.add_child(grille)
	_lbl_dmg = _cellule(grille, Translations.T("ctb.stats.dmg"),
			CombatUiSkin.separateur(1, camp_joueur))
	_lbl_crit = _cellule(grille, Translations.T("ctb.stats.crit"), null)
	_lbl_dist = _cellule(grille, Translations.T("ctb.stats.dist"), null)
	_lbl_dodge = _cellule(grille, Translations.T("ctb.stats.dodge"), null)
	_lbl_prot = _cellule(grille, Translations.T("ctb.stats.prot"),
			CombatUiSkin.separateur(2, camp_joueur))
	_lbl_speed = _cellule(grille, Translations.T("ctb.stats.speed"), null)

	# ── Colonne capacités (camp ennemi seulement, UI_Concept4) ──
	if not camp_joueur:
		var col_cap := VBoxContainer.new()
		col_cap.add_theme_constant_override("separation", 4)
		col_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corps.add_child(col_cap)
		col_cap.add_child(_titre_colonne(Translations.T("ctb.stats.abilities_titre")))
		_abilities_box = VBoxContainer.new()
		_abilities_box.add_theme_constant_override("separation", 2)
		_abilities_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_cap.add_child(_abilities_box)

	# ── Colonne statuts ──
	var col_statuts := VBoxContainer.new()
	col_statuts.add_theme_constant_override("separation", 4)
	col_statuts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_statuts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corps.add_child(col_statuts)
	col_statuts.add_child(_titre_colonne(Translations.T("ctb.stats.status_titre")))
	_statuts_box = VBoxContainer.new()
	_statuts_box.add_theme_constant_override("separation", 2)
	_statuts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_statuts.add_child(_statuts_box)

# Titre de colonne (« / Status / », « / Ability / ») + soulignement décoratif.
func _titre_colonne(texte: String) -> VBoxContainer:
	var titre := VBoxContainer.new()
	titre.add_theme_constant_override("separation", 1)
	titre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titre.add_child(ExpeStyle.label_mono(texte, 11, UIColors.CYBER_TEXTE_MUTED))
	var soulignement := TextureRect.new()
	soulignement.texture = CombatUiSkin.separateur(3, camp_joueur)
	soulignement.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	soulignement.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	soulignement.custom_minimum_size = Vector2(56, 7)
	soulignement.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titre.add_child(soulignement)
	return titre

# Une cellule de stat = label muet + valeur (2 cases de la grille), avec un
# soulignement optionnel (Panel_Separator_0X) posé SOUS le label.
func _cellule(grille: GridContainer, label_texte: String, separateur: Texture2D) -> Label:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ExpeStyle.label_mono(label_texte, 11, UIColors.CYBER_ACCENT_2))
	if separateur != null:
		var soulign := TextureRect.new()
		soulign.texture = separateur
		soulign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		soulign.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		soulign.custom_minimum_size = Vector2(40, 5)
		soulign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(soulign)
	grille.add_child(col)
	var val := ExpeStyle.label_mono("", 11, UIColors.CYBER_TEXTE)
	grille.add_child(val)
	return val

# Lie le panneau à un combattant. `palier` = rareté à afficher pour un ennemi
# (même palier que son sprite/portrait — l'appelant le fournit, le widget ne
# le déduit pas). `null` vide le panneau (aucun combattant à montrer).
func definir_combattant(cb: CtbCombattant, palier: int = 0) -> void:
	_cb = cb
	_palier = palier
	rafraichir()

func rafraichir() -> void:
	if _cb == null:
		return
	var pv_max := _cb.stat_finale("pv_max")
	# Niveau : concept du HÉROS (ProgressionHeros). Un ennemi n'a pas de niveau,
	# il a un PALIER de rareté — c'est lui qui s'affiche à cette place.
	var rang: String
	if _cb.est_joueur():
		rang = "%s %d" % [Translations.T("ctb.stats.niveau"), ProgressionHeros.niveau()]
	else:
		rang = Translations.T("tier.%d" % _palier)
	_lbl_identite.text = "%s / %s /" % [CarteCombattantCtb.nom_ui(_cb.data), rang]
	_lbl_pv.text = "%s : %d / %d" % [Translations.T("ctb.stats.pv"),
			int(roundf(_cb.pv)), int(roundf(pv_max))]
	_lbl_ammo.text = "%s : — / —" % Translations.T("ctb.stats.ammo")
	_lbl_dmg.text = str(int(roundf(_cb.stat_finale("atk"))))
	_lbl_crit.text = "%d%%" % int(roundf(_cb.stat_finale("crit_chance") * 100.0))
	_lbl_dist.text = "—"
	_lbl_dodge.text = "—"
	_lbl_prot.text = "%d%%" % int(roundf(Balance.def_reduction(_cb.stat_finale("def")) * 100.0))
	_lbl_speed.text = str(int(roundf(_cb.stat_finale("vit"))))

	if _abilities_box != null:
		UIHelpers.clear_children_now(_abilities_box)
		for comp: CompetenceCtbData in _cb.data.competences:
			_abilities_box.add_child(ExpeStyle.label_mono(
					Translations.resource_name(comp, comp.id), 11, UIColors.CYBER_TEXTE))
		if _cb.data.competences.is_empty():
			_abilities_box.add_child(ExpeStyle.label_mono("—", 11, UIColors.CYBER_TEXTE_MUTED))

	UIHelpers.clear_children_now(_statuts_box)
	if _cb.en_defense:
		_statuts_box.add_child(ExpeStyle.label_mono(Translations.T("ctb.garde_pill"), 11,
				UIColors.SHIELD))
	var par_statut: Dictionary = {}   # id → StatutCtbData (dédoublonné, comme la pill de scène)
	for s: Dictionary in _cb.statuts:
		var sd := s["statut"] as StatutCtbData
		par_statut[sd.id] = sd
	for id: String in par_statut:
		var sd: StatutCtbData = par_statut[id]
		_statuts_box.add_child(ExpeStyle.label_mono(
				Translations.resource_name(sd, sd.id), 11, UIColors.POISON))
