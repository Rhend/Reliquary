# ============================================================
# CarteCombattantCtb — Carte d'UN combattant dans l'écran de combat CTB
# (Rework Combat, chantier 5). Placeholder propre : nom, barre + valeurs de
# PV, pills de statuts DoT (type, stacks, durée restante en activations),
# marqueur de garde (Défendre). 100 % construite en code (règle projet).
#
# États visuels pilotés par l'écran (CombatCtbUi) :
#   • marquer_actif(bool)   — liseré clair : c'est l'activation de ce combattant
#   • marquer_ciblable(bool)— liseré or + clic = choisir pour cible (signal cliquee)
# `rafraichir()` relit tout depuis le CtbCombattant (source de vérité).
# `centre_fx()` : point d'ancrage des dégâts flottants (coordonnées écran).
# ============================================================
class_name CarteCombattantCtb
extends PanelContainer

signal cliquee(cb: CtbCombattant)

var cb: CtbCombattant

var _couleur_camp: Color
var _nom: Label
var _barre_pv: ProgressBar
var _barre_fill: StyleBoxFlat
var _pv_txt: Label
var _pills: HFlowContainer
var _actif := false
var _ciblable := false

# Nom d'affichage localisé d'un combattant CTB — TOUJOURS via Translations
# (les champs nom_affichage_* de la ressource, l'id en secours).
static func nom_ui(d: CombattantCtbData) -> String:
	return Translations.resource_name(d, d.id)

func _init(combattant: CtbCombattant) -> void:
	cb = combattant
	# Accents de camp de la peau cyberpunk (cyan joueur / magenta adverse).
	_couleur_camp = ExpeStyle.accent_camp(cb.est_joueur())
	custom_minimum_size = Vector2(240, 0)
	_appliquer_style()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)

	_nom = ExpeStyle.label_mono(nom_ui(cb.data), 15, UIColors.CYBER_TEXTE)
	v.add_child(_nom)

	_barre_pv = ProgressBar.new()
	_barre_pv.show_percentage = false
	_barre_pv.custom_minimum_size = Vector2(0, 12)
	_barre_pv.min_value = 0.0
	_barre_pv.max_value = 1.0
	var barre_fond := UIHelpers.card_style(UIColors.BG_BAR, 0.9, 0.4, 1, 3)
	_barre_fill = UIHelpers.card_style(UIColors.HP_HIGH, 0.95, 0.0, 0, 3)
	_barre_pv.add_theme_stylebox_override("background", barre_fond)
	_barre_pv.add_theme_stylebox_override("fill", _barre_fill)
	v.add_child(_barre_pv)

	_pv_txt = ExpeStyle.label_mono("", 12, UIColors.CYBER_TEXTE)
	v.add_child(_pv_txt)

	_pills = HFlowContainer.new()
	_pills.add_theme_constant_override("h_separation", 4)
	_pills.add_theme_constant_override("v_separation", 4)
	v.add_child(_pills)

	gui_input.connect(_sur_input)
	rafraichir()

# Point d'ancrage des textes flottants (centre haut de la carte, coordonnées
# de l'ANCÊTRE FX : l'appelant convertit depuis le global).
func centre_fx() -> Vector2:
	return global_position + Vector2(size.x * 0.5, 8.0)

func marquer_actif(on: bool) -> void:
	_actif = on
	_appliquer_style()

func marquer_ciblable(on: bool) -> void:
	_ciblable = on
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	_appliquer_style()

# Relit l'état du combattant : barre + valeurs de PV (couleur par fraction),
# pills de statuts regroupées par type (stacks ×N, durée max restante en
# activations), pill de garde si en défense, grisé si mort.
func rafraichir() -> void:
	var pv_max := cb.stat_finale("pv_max")
	var frac := cb.pv / maxf(pv_max, 0.001)
	_barre_pv.value = frac
	_barre_fill.bg_color = _couleur_pv(frac)
	_pv_txt.text = "%d / %d" % [int(roundf(cb.pv)), int(roundf(pv_max))]
	modulate = Color(1, 1, 1, 1.0) if cb.est_vivant() else Color(0.45, 0.45, 0.45, 0.75)

	UIHelpers.clear_children_now(_pills)
	if cb.en_defense:
		_pills.add_child(_pill(Translations.T("ctb.garde_pill"), UIColors.SHIELD))
	# Regroupement par statut : ×stacks, durée restante = max des stacks.
	var par_statut: Dictionary = {}   # id → {"statut": StatutCtbData, "n": int, "restant": int}
	for s: Dictionary in cb.statuts:
		var sd := s["statut"] as StatutCtbData
		if not par_statut.has(sd.id):
			par_statut[sd.id] = {"statut": sd, "n": 0, "restant": 0}
		par_statut[sd.id]["n"] += 1
		par_statut[sd.id]["restant"] = maxi(int(par_statut[sd.id]["restant"]), int(s["restant"]))
	for id: String in par_statut:
		var grp: Dictionary = par_statut[id]
		var sd := grp["statut"] as StatutCtbData
		var nom := Translations.resource_name(sd, sd.id)
		_pills.add_child(_pill("☠ %s ×%d (%d)" % [nom, int(grp["n"]), int(grp["restant"])],
				UIColors.POISON))

func _pill(texte: String, couleur: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ExpeStyle.style_chip(couleur))
	var l := ExpeStyle.label_mono(texte, 11, couleur.lightened(0.45))
	var m := UIHelpers.margin_of(3)
	m.add_child(l)
	p.add_child(m)
	return p

func _couleur_pv(frac: float) -> Color:
	if frac > 0.60:
		return UIColors.HP_HIGH
	if frac > 0.30:
		return UIColors.HP_MID
	if frac > 0.15:
		return UIColors.HP_LOW
	return UIColors.HP_CRITICAL

func _appliquer_style() -> void:
	# Peau cyberpunk : bordure fine au camp ; les ÉTATS restent des infos de
	# jeu (or = ciblable, éclairci = activation en cours) — jamais dégradés.
	var c := _couleur_camp
	var epaisseur := 1
	if _ciblable:
		c = UIColors.SELECTION_GOLD
		epaisseur = 2
	elif _actif:
		c = _couleur_camp.lightened(0.5)
		epaisseur = 2
	var style := ExpeStyle.style_panneau(c, 0.88, epaisseur, 2)
	add_theme_stylebox_override("panel", style)

func _sur_input(ev: InputEvent) -> void:
	if _ciblable and ev is InputEventMouseButton \
			and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		cliquee.emit(cb)
