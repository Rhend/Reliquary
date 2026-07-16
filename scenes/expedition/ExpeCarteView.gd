# ============================================================
# ExpeCarteView — Vue de la carte de nœuds d'une expédition (Rework Combat,
# chantier 8, peau cyberpunk + navigation par chemin au chantier 10).
# PARTAGÉE entre l'écran de jeu réel (ExpeditionScreen) et le sandbox dev
# (SandboxExpe) — un seul point de vérité pour le dessin et la navigation.
#
# Vue PASSIVE : elle dessine l'état de la run (brouillard réel : un nœud non
# découvert n'est PAS dessiné) et émet l'INTENTION de déplacement
# (`deplacement_demande`) — l'HÔTE valide (ExpeRun.chemin_vers) et joue le
# trajet. Navigation par chemin (chantier 10) : clic possible sur N'IMPORTE
# QUEL nœud découvert ATTEIGNABLE (chemin de nœuds résolus — cf. ExpeRun) ;
# un nœud visible mais inaccessible est affiché ATTÉNUÉ et n'est pas
# cliquable (curseur normal). Flèches clavier = voisin adjacent (inchangé).
#
# Style : 100 % tokens UIColors.CYBER_* + ExpeStyle (peau intérimaire).
# ============================================================
class_name ExpeCarteView
extends Control

signal deplacement_demande(nid: int)

# Séquencement du trajet multi-nœuds (utilisé par les hôtes — un seul point).
const DELAI_PAS := 0.12

const RAYON_NOEUD := 16.0
const RAYON_CLIC  := 22.0
const MARGE       := 40.0
const PAS_GRILLE  := 48.0

var run: ExpeRun = null

var _atteignables: Dictionary = {}   # nid → true (recalculé à chaque rafraichir)

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL

func rafraichir() -> void:
	_atteignables = run.atteignables() if run != null else {}
	queue_redraw()

# Couleur d'un type de nœud — tokens de la peau (jamais de littéral ici).
static func couleur_noeud(type: int) -> Color:
	match type:
		Enums.TypeNoeud.ENTREE:    return UIColors.CYBER_NOEUD_ENTREE
		Enums.TypeNoeud.COMBAT:    return UIColors.CYBER_NOEUD_COMBAT
		Enums.TypeNoeud.MYSTERE:   return UIColors.CYBER_NOEUD_MYSTERE
		Enums.TypeNoeud.COFFRE:    return UIColors.CYBER_NOEUD_COFFRE
		Enums.TypeNoeud.FIN_ETAGE: return UIColors.CYBER_NOEUD_FIN
	return Color.WHITE

# ─── Rendu (brouillard réel : non découvert = pas dessiné) ───

func _pos_ecran(p: Vector2) -> Vector2:
	return Vector2(
		MARGE + p.x / ExpeCarte.LARGEUR * (size.x - MARGE * 2.0),
		MARGE + p.y / ExpeCarte.HAUTEUR * (size.y - MARGE * 2.0))

func _draw() -> void:
	# Fond + grille technique discrète (peau cyberpunk).
	draw_rect(Rect2(Vector2.ZERO, size), UIColors.CYBER_BG)
	var x := PAS_GRILLE
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), UIColors.CYBER_GRILLE, 1.0)
		x += PAS_GRILLE
	var y := PAS_GRILLE
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), UIColors.CYBER_GRILLE, 1.0)
		y += PAS_GRILLE
	if run == null:
		return
	var mono := ExpeStyle.police_mono()
	# Arêtes : uniquement entre deux nœuds découverts.
	for nd in run.noeuds_visibles():
		for v in nd.voisins:
			var nv := run.carte.noeud(v)
			if nv.decouvert and v > nd.id:
				draw_line(_pos_ecran(nd.pos), _pos_ecran(nv.pos), UIColors.CYBER_ARETE, 2.0)
	# Nœuds découverts (les autres N'EXISTENT PAS à l'écran).
	for nd in run.noeuds_visibles():
		var pe := _pos_ecran(nd.pos)
		var col := couleur_noeud(nd.type)
		var accessible: bool = _atteignables.has(nd.id) or nd.id == run.position_joueur
		if nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE:
			col = col.darkened(0.55)   # inerte
		if not accessible:
			col.a = 0.35   # visible mais INACCESSIBLE (aucun chemin résolu)
		draw_circle(pe, RAYON_NOEUD, Color(UIColors.CYBER_BG_PANEL_2, col.a))
		draw_arc(pe, RAYON_NOEUD, 0.0, TAU, 32, col, 2.0)
		draw_circle(pe, RAYON_NOEUD * 0.45, col)
		# Halo fin des destinations atteignables NON résolues (invitation).
		if accessible and not nd.resolu and nd.id != run.position_joueur:
			draw_arc(pe, RAYON_NOEUD + 4.0, 0.0, TAU, 32, Color(col, 0.35), 1.0)
		draw_string(mono, pe + Vector2(-14, 34), _etiquette(nd),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(UIColors.CYBER_TEXTE, 1.0 if accessible else 0.45))
	# Marqueur joueur (accent).
	var pj := _pos_ecran(run.carte.noeud(run.position_joueur).pos)
	draw_arc(pj, RAYON_CLIC, 0.0, TAU, 32, UIColors.CYBER_ACCENT, 2.5)
	draw_arc(pj, RAYON_CLIC + 4.0, 0.0, TAU, 32, Color(UIColors.CYBER_ACCENT, 0.30), 1.0)

func _etiquette(nd: ExpeNoeud) -> String:
	match nd.type:
		Enums.TypeNoeud.ENTREE:    return Translations.T("expe.noeud.entree")
		Enums.TypeNoeud.MYSTERE:   return Translations.T(
				"expe.noeud.mystere" if nd.contenu_mystere < 0 else "expe.noeud.mystere_resolu")
		Enums.TypeNoeud.COMBAT:    return Translations.T("expe.noeud.combat")
		Enums.TypeNoeud.COFFRE:    return Translations.T("expe.noeud.coffre")
		Enums.TypeNoeud.FIN_ETAGE: return Translations.T("expe.noeud.fin")
	return ""

# ─── Entrées : clic sur un nœud ATTEIGNABLE, flèches directionnelles ──

# Nid du nœud découvert sous le point (−1 si aucun).
func _noeud_sous(pos: Vector2) -> int:
	if run == null:
		return -1
	for nd in run.noeuds_visibles():
		if _pos_ecran(nd.pos).distance_to(pos) <= RAYON_CLIC:
			return nd.id
	return -1

func _gui_input(ev: InputEvent) -> void:
	if run == null or run.est_terminee:
		return
	if ev is InputEventMouseMotion:
		# Curseur : main sur un nœud atteignable, flèche sinon (feedback
		# atteignable vs visible-mais-inaccessible).
		var survole := _noeud_sous(ev.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
				if survole >= 0 and _atteignables.has(survole) else Control.CURSOR_ARROW
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		grab_focus()
		var nid := _noeud_sous(ev.position)
		# Navigation par chemin (chantier 10) : tout nœud découvert atteignable
		# est cliquable — l'hôte valide le chemin et joue le trajet séquencé.
		if nid >= 0 and _atteignables.has(nid):
			deplacement_demande.emit(nid)
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var dir := Vector2.ZERO
		match ev.keycode:
			KEY_LEFT:  dir = Vector2.LEFT
			KEY_RIGHT: dir = Vector2.RIGHT
			KEY_UP:    dir = Vector2.UP
			KEY_DOWN:  dir = Vector2.DOWN
		if dir != Vector2.ZERO:
			_demander_direction(dir)

# Flèche : demande le voisin adjacent le mieux aligné avec la direction
# (déplacement pas à pas historique — sous-ensemble de la navigation par chemin).
func _demander_direction(dir: Vector2) -> void:
	var cur := run.carte.noeud(run.position_joueur)
	var best := -1
	var best_dot := 0.35   # seuil : ignorer les voisins trop perpendiculaires
	for v in cur.voisins:
		var d := (run.carte.noeud(v).pos - cur.pos).normalized().dot(dir)
		if d > best_dot:
			best_dot = d
			best = v
	if best >= 0:
		deplacement_demande.emit(best)
