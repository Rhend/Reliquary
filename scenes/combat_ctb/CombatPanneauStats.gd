# ============================================================
# CombatPanneauStats — panneau d'informations en bas d'écran de combat
# (chantier UI_Concept2, 07/09/2026 ; REFONTE 11/2026, retour Rhend : « mieux
# cadrer les informations, plus lisible, plus pertinent »).
#
# Trois blocs séparés par un filet, lus du bord de l'écran vers le centre :
#   1. IDENTITÉ — nom en grand, pastille de rang (niveau du héros / palier de
#      rareté de l'ennemi, à sa couleur), BARRE de PV + valeur chiffrée ;
#   2. STATS    — les quatre qui pèsent dans le moteur CTB : DMG (ATK), CRIT,
#      PROT (réduction de la DEF), SPEED (VIT). Une stat modifiée par un bonus
#      de run se colore (vert = bonus, rouge = malus) ;
#   3. EFFETS   — garde et statuts actifs en pastilles (« ×stacks », durée
#      restante), et les capacités du combattant quand il en porte.
# Le panneau ENNEMI est le MIROIR du panneau allié : les deux identités sont
# aux bords extérieurs de l'écran, les effets vers le centre.
#
# Ammo / DIST / DODGE (présents sur le mockup d'origine) ont été RETIRÉS : aucune
# mécanique derrière dans ce moteur (ni portée, ni esquive, ni munitions) —
# trois « — » permanents noyaient les valeurs réelles. À réintroduire le jour
# où la mécanique existe.
#
# Générique par CAMP (`creer(camp_joueur)`) et par COMBATTANT
# (`definir_combattant`). Quel combattant montrer = décision de CombatCtbUi
# (allié actif ; ennemi survolé > inspecté > premier vivant), pas du widget.
# ============================================================
class_name CombatPanneauStats
extends PanelContainer

const LARGEUR_MIN := 480.0
# Hauteur FIXE : les deux panneaux restent alignés quel que soit leur contenu.
const HAUTEUR := 64.0   # au-delà, le panneau mord les pieds du rang arrière-bas
const MARGE_BORD_PX := 18      # côté bord d'écran
const MARGE_CENTRE_PX := 34    # côté centre : l'arête du panneau y est biseautée
const LARGEUR_IDENTITE := 236.0
const DUREE_BARRE_S := 0.25    # glissement de la barre de PV à chaque coup

var camp_joueur := true
var _cb: CtbCombattant = null
var _palier := 0   # palier de rareté affiché (camp ennemi seulement)

var _lbl_nom: Label
var _chip_rang: PanelContainer
var _lbl_rang: Label
var _barre_pv: TextureProgressBar
var _lbl_pv: Label
var _valeurs: Dictionary = {}   # nom de stat → Label de valeur
var _effets_box: HFlowContainer
var _tween_pv: Tween = null

static func creer(camp_joueur_: bool) -> CombatPanneauStats:
	var p := CombatPanneauStats.new()
	p.camp_joueur = camp_joueur_
	p._construire()
	return p

func _accent() -> Color:
	return UIColors.CYBER_ACCENT if camp_joueur else UIColors.COMBAT_ACCENT_ENNEMI

func _construire() -> void:
	custom_minimum_size = Vector2(LARGEUR_MIN, HAUTEUR)
	add_theme_stylebox_override("panel", CombatUiSkin.style_panneau_stats(camp_joueur))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Filet de sécurité : le panneau est forcé à une largeur EXACTE par
	# l'appelant (CombatCtbUi._repositionner_panel_stats) — si le contenu
	# déborde malgré tout, on le tronque plutôt que de peindre hors du panneau.
	clip_contents = true

	var marge := MarginContainer.new()
	marge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marge.add_theme_constant_override("margin_top", 5)
	marge.add_theme_constant_override("margin_bottom", 5)
	marge.add_theme_constant_override("margin_left",
			MARGE_BORD_PX if camp_joueur else MARGE_CENTRE_PX)
	marge.add_theme_constant_override("margin_right",
			MARGE_CENTRE_PX if camp_joueur else MARGE_BORD_PX)
	add_child(marge)
	var corps := HBoxContainer.new()
	corps.add_theme_constant_override("separation", 16)
	corps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marge.add_child(corps)

	var blocs: Array[Control] = [_bloc_identite(), _filet(), _bloc_stats(), _filet(),
			_bloc_effets()]
	if not camp_joueur:
		blocs.reverse()   # miroir : identité au bord DROIT de l'écran
	for b in blocs:
		corps.add_child(b)

# ── Bloc 1 : nom + rang, barre de PV + valeur ──
func _bloc_identite() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(LARGEUR_IDENTITE, 0.0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 10)
	ligne.alignment = BoxContainer.ALIGNMENT_BEGIN if camp_joueur else BoxContainer.ALIGNMENT_END
	ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ligne)
	_lbl_nom = ExpeStyle.label_mono("", 18, Color.WHITE)
	_chip_rang = PanelContainer.new()
	_chip_rang.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_rang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_rang = ExpeStyle.label_mono("", 11, UIColors.CYBER_TEXTE)
	var m := UIHelpers.margin_of(0)
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_lbl_rang)
	_chip_rang.add_child(m)
	# Le nom reste du côté du bord d'écran, la pastille vers le centre.
	for n: Control in ([_lbl_nom, _chip_rang] if camp_joueur else [_chip_rang, _lbl_nom]):
		ligne.add_child(n)

	var pv := HBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pv)
	_barre_pv = CombatUiSkin.barre_pv(camp_joueur)
	_barre_pv.custom_minimum_size = Vector2(0, 16)
	_barre_pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_barre_pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_barre_pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_pv = ExpeStyle.label_mono("", 14, UIColors.CYBER_TEXTE)
	_lbl_pv.custom_minimum_size = Vector2(78, 0)
	_lbl_pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if camp_joueur \
			else HORIZONTAL_ALIGNMENT_LEFT
	for n: Control in ([_barre_pv, _lbl_pv] if camp_joueur else [_lbl_pv, _barre_pv]):
		pv.add_child(n)
	return col

# ── Bloc 2 : les quatre stats qui comptent, valeur en grand sous son libellé ──
func _bloc_stats() -> Control:
	var rangee := HBoxContainer.new()
	rangee.add_theme_constant_override("separation", 18)
	rangee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for paire: Array in [["atk", "ctb.stats.dmg"], ["crit_chance", "ctb.stats.crit"],
			["def", "ctb.stats.prot"], ["vit", "ctb.stats.speed"]]:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.custom_minimum_size = Vector2(44, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var titre := ExpeStyle.label_mono(Translations.T(paire[1]), 10, Color(_accent(), 0.85))
		titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(titre)
		var val := ExpeStyle.label_mono("", 19, UIColors.CYBER_TEXTE)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val)
		_valeurs[paire[0]] = val
		rangee.add_child(col)
	return rangee

# ── Bloc 3 : garde, statuts, capacités — en pastilles ──
func _bloc_effets() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var titre := ExpeStyle.label_mono(Translations.T("ctb.stats.status_titre"), 10,
			Color(_accent(), 0.85))
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if camp_joueur \
			else HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(titre)
	_effets_box = HFlowContainer.new()
	_effets_box.alignment = FlowContainer.ALIGNMENT_BEGIN if camp_joueur \
			else FlowContainer.ALIGNMENT_END
	_effets_box.add_theme_constant_override("h_separation", 6)
	_effets_box.add_theme_constant_override("v_separation", 4)
	_effets_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_effets_box)
	return col

# Filet vertical entre deux blocs (couleur du camp, discret).
func _filet() -> Control:
	var f := ColorRect.new()
	f.color = Color(_accent(), 0.28)
	f.custom_minimum_size = Vector2(1, 0)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f

func _pastille(texte: String, couleur: Color) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", CombatUiSkin.style_pill(couleur))
	var m := UIHelpers.margin_of(0)
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 1)
	m.add_theme_constant_override("margin_bottom", 1)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(ExpeStyle.label_mono(texte, 11, couleur.lightened(0.45)))
	p.add_child(m)
	return p

# Lie le panneau à un combattant. `palier` = rareté à afficher pour un ennemi
# (même palier que son sprite/portrait — l'appelant le fournit, le widget ne
# le déduit pas). `null` vide le panneau (aucun combattant à montrer).
func definir_combattant(cb: CtbCombattant, palier: int = 0) -> void:
	var change := cb != _cb
	_cb = cb
	_palier = palier
	rafraichir(not change)

# `animer` : la barre de PV GLISSE vers sa nouvelle valeur (même combattant qui
# encaisse) au lieu de sauter — jamais quand le panneau change de combattant.
func rafraichir(animer: bool = true) -> void:
	if _cb == null:
		return
	# Rang — niveau : concept du HÉROS (ProgressionHeros). Un ennemi n'a pas de
	# niveau, il a un PALIER de rareté, affiché à SA couleur.
	var couleur_rang := _accent()
	if _cb.est_joueur():
		_lbl_rang.text = "%s %d" % [Translations.T("ctb.stats.niveau"), ProgressionHeros.niveau()]
	else:
		_lbl_rang.text = Translations.T("tier.%d" % _palier)
		couleur_rang = UIColors.tier_color(_palier)
	_lbl_rang.add_theme_color_override("font_color", couleur_rang.lightened(0.45))
	_chip_rang.add_theme_stylebox_override("panel", CombatUiSkin.style_pill(couleur_rang))
	_lbl_nom.text = CarteCombattantCtb.nom_ui(_cb.data)

	var pv_max := maxf(_cb.stat_finale("pv_max"), 1.0)
	var frac := clampf(_cb.pv / pv_max, 0.0, 1.0)
	_lbl_pv.text = "%d / %d" % [int(roundf(_cb.pv)), int(roundf(pv_max))]
	# Même échelle vert → rouge pour les deux camps : c'est un relevé de santé,
	# il doit se lire pareil des deux côtés (et rester lisible sur fond rouge).
	_lbl_pv.add_theme_color_override("font_color", UIColors.hero_hp(frac).lightened(0.25))
	if _tween_pv != null and _tween_pv.is_valid():
		_tween_pv.kill()
	if animer and is_inside_tree() and not is_equal_approx(_barre_pv.value, frac):
		_tween_pv = create_tween()
		_tween_pv.tween_property(_barre_pv, "value", frac, DUREE_BARRE_S) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_barre_pv.value = frac

	_poser_stat("atk", str(int(roundf(_cb.stat_finale("atk")))))
	_poser_stat("crit_chance", "%d%%" % int(roundf(_cb.stat_finale("crit_chance") * 100.0)))
	_poser_stat("def", "%d%%" % int(roundf(Balance.def_reduction(_cb.stat_finale("def")) * 100.0)))
	_poser_stat("vit", str(int(roundf(_cb.stat_finale("vit")))))

	UIHelpers.clear_children_now(_effets_box)
	if _cb.en_defense:
		_effets_box.add_child(_pastille(Translations.T("ctb.garde_pill"), UIColors.SHIELD))
	# Statuts regroupés : ×stacks, durée restante = max des stacks (comme la
	# pastille sous les pieds, CarteCombattantCtb).
	var par_statut: Dictionary = {}   # id → {"statut", "n", "restant"}
	for s: Dictionary in _cb.statuts:
		var sd := s["statut"] as StatutCtbData
		if not par_statut.has(sd.id):
			par_statut[sd.id] = {"statut": sd, "n": 0, "restant": 0}
		par_statut[sd.id]["n"] += 1
		par_statut[sd.id]["restant"] = maxi(int(par_statut[sd.id]["restant"]), int(s["restant"]))
	for id: String in par_statut:
		var grp: Dictionary = par_statut[id]
		var sd := grp["statut"] as StatutCtbData
		_effets_box.add_child(_pastille("%s ×%d (%d)" % [
				Translations.resource_name(sd, sd.id), int(grp["n"]), int(grp["restant"])],
				UIColors.POISON))
	# Capacités portées (vitrine : l'IA n'en joue jamais) — seulement s'il y en a.
	if not camp_joueur:
		for comp: CompetenceCtbData in _cb.data.competences:
			_effets_box.add_child(_pastille(Translations.resource_name(comp, comp.id),
					UIColors.CYBER_ACCENT_2))
	if _effets_box.get_child_count() == 0:
		_effets_box.add_child(ExpeStyle.label_mono("—", 12, UIColors.CYBER_TEXTE_MUTED))

# Valeur d'une stat, colorée quand un bonus % de run la modifie.
func _poser_stat(nom: String, texte: String) -> void:
	var lbl: Label = _valeurs[nom]
	lbl.text = texte
	var bonus := _cb.somme_bonus_pct(nom)
	var couleur := UIColors.CYBER_TEXTE
	if bonus > 0.0:
		couleur = UIColors.CYBER_OK
	elif bonus < 0.0:
		couleur = UIColors.CYBER_DANGER
	lbl.add_theme_color_override("font_color", couleur)
