# ============================================================
# CarteCombattantCtb — HUD compact d'UN combattant, posé SOUS SES PIEDS dans
# la scène de combat CTB (chantier UI_Concept2, 07/09/2026 — le mockup fait
# foi : plus de carte en colonne latérale, un mini-HUD ancré au personnage).
#
# Contenu : pills de statut compactes (garde, DoT — mêmes données qu'avant,
# juste rétrécies) au-dessus d'une barre de PV (chrome RÉEL de Christophe,
# `CombatUiSkin.barre_pv`). Pas de nom : le nom vit désormais dans
# `CombatPanneauStats`, pas ici.
#
# Ni clic ni survol : le ciblage à la souris (anneau or + réticule) est DÉJÀ
# peint dans la scène par `CombatCtbUi._dessiner_sol`, et le halo « c'est ton
# tour » DÉJÀ porté par `CombatOmbrePortee` — les dupliquer ici serait un
# doublon, pas un habillage.
#
# `definir_position(pied)` : positionné par l'appelant (CombatCtbUi.
# _placer_orbes, même point que l'ombre) — ce widget ne connaît pas la scène.
# `rafraichir()` relit tout depuis le CtbCombattant (source de vérité).
# `centre_fx()` : point d'ancrage des dégâts flottants (coordonnées écran).
# ============================================================
class_name CarteCombattantCtb
extends VBoxContainer

const LARGEUR_BARRE_PX := 100.0
const HAUTEUR_BARRE_PX := 13.0

var cb: CtbCombattant

var _barre_pv: TextureProgressBar
var _pv_txt: Label
var _pills: HFlowContainer

# Nom d'affichage localisé d'un combattant CTB — TOUJOURS via Translations
# (les champs nom_affichage_* de la ressource, l'id en secours).
static func nom_ui(d: CombattantCtbData) -> String:
	return Translations.resource_name(d, d.id)

func _init(combattant: CtbCombattant) -> void:
	cb = combattant
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_pills = HFlowContainer.new()
	_pills.alignment = FlowContainer.ALIGNMENT_CENTER
	_pills.add_theme_constant_override("h_separation", 2)
	_pills.add_theme_constant_override("v_separation", 2)
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pills)

	_barre_pv = CombatUiSkin.barre_pv(cb.est_joueur())
	_barre_pv.custom_minimum_size = Vector2(LARGEUR_BARRE_PX, HAUTEUR_BARRE_PX)
	_barre_pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_barre_pv)

	# Score DANS la barre (même recette que l'ancienne carte) : Label enfant
	# de la TextureProgressBar, étalé sur tout son rect et centré.
	_pv_txt = ExpeStyle.label_mono("", 9, UIColors.CYBER_TEXTE)
	_pv_txt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pv_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pv_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pv_txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_txt.add_theme_constant_override("outline_size", 2)
	_pv_txt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_barre_pv.add_child(_pv_txt)

	rafraichir()

# Centre le widget au-dessus du point « pied » (même point que l'ombre
# portée) — appelé par CombatCtbUi._placer_orbes() à chaque disposition.
# Chevauche légèrement l'ellipse au sol (retour Rhend : « un peu plus basse »).
# `decalage_bas_px` (retour Rhend 17/09/2026 : « décaler en bas de 5% ») :
# poussée verticale SUPPLÉMENTAIRE fournie par l'appelant (fraction de la
# hauteur de la scène côté CombatCtbUi — ce widget ne connaît pas la scène).
func definir_position(pied: Vector2, decalage_bas_px: float = 0.0) -> void:
	reset_size()
	position = pied - Vector2(size.x * 0.5, size.y - 4.0) + Vector2(0.0, decalage_bas_px)

# Point d'ancrage des textes flottants (au-dessus du widget, coordonnées de
# l'ANCÊTRE FX : l'appelant convertit depuis le global).
func centre_fx() -> Vector2:
	return global_position + Vector2(size.x * 0.5, 0.0)

# Relit l'état du combattant : barre + valeurs de PV (couleur par fraction),
# pills de statuts regroupées par type (stacks ×N, durée max restante en
# activations), pill de garde si en défense, grisé si mort.
func rafraichir() -> void:
	var pv_max := cb.stat_finale("pv_max")
	var frac := cb.pv / maxf(pv_max, 0.001)
	_barre_pv.value = frac
	_pv_txt.text = "%d / %d" % [int(roundf(cb.pv)), int(roundf(pv_max))]
	# La barre elle-même reste au chrome de Christophe (non teintée par la
	# fraction — choix DA) : le texte porte seul l'alerte de PV bas.
	_pv_txt.add_theme_color_override("font_color", _couleur_pv(frac))
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
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", CombatUiSkin.style_pill(couleur))
	var l := ExpeStyle.label_mono(texte, 8, couleur.lightened(0.45))
	var m := UIHelpers.margin_of(2)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
