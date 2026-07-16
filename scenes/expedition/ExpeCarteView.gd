# ============================================================
# ExpeCarteView — Vue de la carte de nœuds d'une expédition (Rework Combat,
# chantier 8). Rendu placeholder (DA hors scope), PARTAGÉ entre l'écran de
# jeu réel (ExpeditionScreen) et le sandbox dev (SandboxExpe) — un seul
# point de vérité pour le dessin et la navigation, pas de doublon.
#
# Vue PASSIVE : elle dessine l'état de la run (brouillard réel : un nœud non
# découvert n'est PAS dessiné) et émet l'INTENTION de déplacement
# (`deplacement_demande`) — clic sur un nœud adjacent découvert, ou flèches
# (voisin le mieux aligné avec la direction). L'HÔTE décide de la suite :
# run.deplacer_vers, gestion du combat en attente, rafraîchissement.
# ============================================================
class_name ExpeCarteView
extends Control

signal deplacement_demande(nid: int)

const COULEURS := {
	Enums.TypeNoeud.ENTREE:    Color(0.55, 0.55, 0.60),
	Enums.TypeNoeud.COMBAT:    Color(0.90, 0.35, 0.30),
	Enums.TypeNoeud.MYSTERE:   Color(0.70, 0.45, 0.95),
	Enums.TypeNoeud.COFFRE:    Color(0.95, 0.78, 0.30),
	Enums.TypeNoeud.FIN_ETAGE: Color(0.30, 0.90, 0.95),
}
const RAYON_NOEUD  := 16.0
const RAYON_CLIC   := 22.0
const MARGE        := 40.0

var run: ExpeRun = null

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL

func rafraichir() -> void:
	queue_redraw()

# ─── Rendu (brouillard réel : non découvert = pas dessiné) ───

func _pos_ecran(p: Vector2) -> Vector2:
	return Vector2(
		MARGE + p.x / ExpeCarte.LARGEUR * (size.x - MARGE * 2.0),
		MARGE + p.y / ExpeCarte.HAUTEUR * (size.y - MARGE * 2.0))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.10))
	if run == null:
		return
	# Arêtes : uniquement entre deux nœuds découverts.
	for nd in run.noeuds_visibles():
		for v in nd.voisins:
			var nv := run.carte.noeud(v)
			if nv.decouvert and v > nd.id:
				draw_line(_pos_ecran(nd.pos), _pos_ecran(nv.pos), Color(0.35, 0.40, 0.50), 2.0)
	# Nœuds découverts (les autres N'EXISTENT PAS à l'écran).
	for nd in run.noeuds_visibles():
		var pe := _pos_ecran(nd.pos)
		var col: Color = COULEURS.get(nd.type, Color.WHITE)
		if nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE:
			col = col.darkened(0.55)   # inerte
		draw_circle(pe, RAYON_NOEUD, col)
		draw_string(get_theme_default_font(), pe + Vector2(-14, 34), _etiquette(nd),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.95))
	# Marqueur joueur.
	var pj := _pos_ecran(run.carte.noeud(run.position_joueur).pos)
	draw_arc(pj, RAYON_CLIC, 0.0, TAU, 24, Color(1, 1, 1), 3.0)

func _etiquette(nd: ExpeNoeud) -> String:
	match nd.type:
		Enums.TypeNoeud.ENTREE:    return Translations.T("expe.noeud.entree")
		Enums.TypeNoeud.MYSTERE:   return Translations.T(
				"expe.noeud.mystere" if nd.contenu_mystere < 0 else "expe.noeud.mystere_resolu")
		Enums.TypeNoeud.COMBAT:    return Translations.T("expe.noeud.combat")
		Enums.TypeNoeud.COFFRE:    return Translations.T("expe.noeud.coffre")
		Enums.TypeNoeud.FIN_ETAGE: return Translations.T("expe.noeud.fin")
	return ""

# ─── Entrées : clic sur un nœud adjacent, flèches directionnelles ──

func _gui_input(ev: InputEvent) -> void:
	if run == null or run.est_terminee:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		grab_focus()
		for v in run.carte.noeud(run.position_joueur).voisins:
			var nd := run.carte.noeud(v)
			if nd.decouvert and _pos_ecran(nd.pos).distance_to(ev.position) <= RAYON_CLIC:
				deplacement_demande.emit(v)
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

# Flèche : demande le voisin adjacent le mieux aligné avec la direction.
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
