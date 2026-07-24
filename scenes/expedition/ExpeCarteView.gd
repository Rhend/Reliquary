# ============================================================
# ExpeCarteView — Vue de la carte de nœuds d'une expédition (Rework Combat,
# chantier 8, peau cyberpunk + navigation par chemin au chantier 10 ;
# brouillard « hack » + hiérarchie visuelle 07/2026, retour Rhend).
# PARTAGÉE entre l'écran de jeu réel (ExpeditionScreen) et le sandbox dev
# (SandboxExpe) — un seul point de vérité pour le dessin et la navigation.
#
# BROUILLARD DE GUERRE « HACK » : la TOPOLOGIE ENTIÈRE de l'étage est
# affichée d'emblée (positions + liaisons — les distances se lisent tout de
# suite), mais seuls les nœuds DÉCOUVERTS (les N+1 des nœuds résolus — la
# sémantique d'ExpeRun) montrent leur nature. Au-delà : nœud CHIFFRÉ —
# petit, éteint, glyphe hexadécimal qui défile (déchiffrement en cours),
# liaison en pointillés. Rien de chiffré n'est cliquable — le CONTRAT
# d'entrée est inchangé (clic = nœud découvert ATTEIGNABLE uniquement).
#
# HIÉRARCHIE (du plus au moins saillant) : position COURANTE (réticule
# hexagonal animé) → destinations ATTEIGNABLES (glyphe plein, halo pulsé,
# étiquette pleine) → découverts inaccessibles (atténués) → résolus
# (éteints, ✓) → chiffrés (fantômes). Légende compacte en pied de carte.
#
# Vue PASSIVE : émet l'INTENTION de déplacement (`deplacement_demande`) —
# l'HÔTE valide (ExpeRun.chemin_vers) et joue le trajet séquencé.
# Flèches clavier = voisin adjacent (inchangé).
#
# Style : 100 % tokens UIColors.CYBER_* + ExpeStyle (peau intérimaire).
# ============================================================
class_name ExpeCarteView
extends Control

signal deplacement_demande(nid: int)

# Séquencement du trajet multi-nœuds (utilisé par les hôtes — un seul point).
const DELAI_PAS := 0.12

const RAYON_NOEUD    := 16.0
const RAYON_RESOLU   := 13.0
const RAYON_CHIFFRE  := 10.0
const RAYON_CLIC     := 22.0
const MARGE          := 40.0
const PAS_GRILLE     := 48.0
const GLYPHES_HEX    := "0123456789ABCDEF"   # défilement des nœuds chiffrés

var run: ExpeRun = null

var _atteignables: Dictionary = {}   # nid → true (recalculé à chaque rafraichir)
var _t := 0.0                        # horloge des animations (pulse, défilement)

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL

# Animations sobres (halo pulsé, glyphes chiffrés, réticule) : redessin
# piloté par le temps — coupé quand la vue est cachée (combat par-dessus).
func _process(dt: float) -> void:
	if run == null or not is_visible_in_tree():
		return
	_t += dt
	queue_redraw()

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
		# Boss d'assaut (chantier 11) : rouge = danger, c'est SON métier.
		Enums.TypeNoeud.BOSS:      return UIColors.CYBER_DANGER
	return Color.WHITE

# Glyphe d'un type de nœud — la SYMBOLIQUE se lit sans étiquette (le texte
# la confirme). Un seul point de vérité, réutilisable par une future légende.
static func glyphe_noeud(type: int) -> String:
	match type:
		Enums.TypeNoeud.ENTREE:    return "◇"
		Enums.TypeNoeud.COMBAT:    return "▲"
		Enums.TypeNoeud.MYSTERE:   return "?"
		Enums.TypeNoeud.COFFRE:    return "◆"
		Enums.TypeNoeud.FIN_ETAGE: return "◎"
		Enums.TypeNoeud.BOSS:      return "☠"
	return ""

# ─── Rendu (brouillard « hack » : chiffré = fantôme, jamais cliquable) ───

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

	# ── Liaisons : TOUTES tracées (la topologie se lit d'emblée). Décodée
	# (deux nœuds découverts) = pleine ; sinon = pointillés fantômes.
	for nd in run.carte.noeuds:
		for v in nd.voisins:
			if v <= nd.id:
				continue
			var nv := run.carte.noeud(v)
			var a := _pos_ecran(nd.pos)
			var b := _pos_ecran(nv.pos)
			if nd.decouvert and nv.decouvert:
				draw_line(a, b, UIColors.CYBER_ARETE, 2.0)
			else:
				draw_dashed_line(a, b, UIColors.CYBER_ARETE_CHIFFREE, 1.0, 7.0)

	# ── Nœuds CHIFFRÉS (au-delà des N+1) : fantômes au glyphe hexa défilant.
	for nd in run.carte.noeuds:
		if nd.decouvert:
			continue
		var pe := _pos_ecran(nd.pos)
		var col := UIColors.CYBER_CHIFFRE
		draw_circle(pe, RAYON_CHIFFRE, Color(UIColors.CYBER_BG_PANEL, 0.85))
		draw_arc(pe, RAYON_CHIFFRE, 0.0, TAU, 24, col, 1.0)
		# Défilement pseudo-aléatoire déterministe (id + temps) — le « flux
		# chiffré » vit sans consommer aucun RNG de jeu.
		var glyphe := GLYPHES_HEX[(nd.id * 7 + int(_t * 5.0)) % GLYPHES_HEX.length()]
		draw_string(mono, pe + Vector2(-RAYON_CHIFFRE, 4.0), glyphe,
				HORIZONTAL_ALIGNMENT_CENTER, RAYON_CHIFFRE * 2.0, 11, col)

	# ── Nœuds DÉCOUVERTS : hiérarchie accessible > inaccessible > résolu.
	for nd in run.noeuds_visibles():
		var pe := _pos_ecran(nd.pos)
		var col := couleur_noeud(nd.type)
		var accessible: bool = _atteignables.has(nd.id) or nd.id == run.position_joueur
		var resolu_inerte: bool = nd.resolu and nd.type != Enums.TypeNoeud.FIN_ETAGE
		var rayon := RAYON_RESOLU if resolu_inerte else RAYON_NOEUD
		if resolu_inerte:
			col = col.darkened(0.55)   # inerte
		if not accessible:
			col.a = 0.35   # visible mais INACCESSIBLE (aucun chemin résolu)
		draw_circle(pe, rayon, Color(UIColors.CYBER_BG_PANEL_2, maxf(col.a, 0.85)))
		draw_arc(pe, rayon, 0.0, TAU, 32, col, 2.0)
		# Glyphe du type au centre — la nature du nœud se lit d'un coup d'œil.
		var g := "✓" if resolu_inerte else glyphe_noeud(nd.type)
		draw_string(mono, pe + Vector2(-rayon, 5.0), g,
				HORIZONTAL_ALIGNMENT_CENTER, rayon * 2.0, 13,
				col.lightened(0.35) if accessible else col)
		# Halo PULSÉ des destinations atteignables non résolues (invitation).
		if accessible and not nd.resolu and nd.id != run.position_joueur:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0 + float(nd.id))
			draw_arc(pe, rayon + 4.0 + pulse * 2.0, 0.0, TAU, 32,
					Color(col, 0.25 + 0.25 * pulse), 1.0)
		var etiquette := _etiquette(nd)
		if etiquette != "":
			draw_string(mono, pe + Vector2(-60.0, rayon + 16.0), etiquette,
					HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12,
					Color(UIColors.CYBER_TEXTE, 1.0 if accessible else 0.45)
					if not resolu_inerte else Color(UIColors.CYBER_TEXTE_MUTED, 0.55))

	# ── Position courante : réticule hexagonal + balayage rotatif.
	var pj := _pos_ecran(run.carte.noeud(run.position_joueur).pos)
	var pts := PackedVector2Array()
	for i in 7:
		var ang := TAU * float(i) / 6.0 - TAU / 12.0
		pts.append(pj + Vector2(cos(ang), sin(ang)) * RAYON_CLIC)
	draw_polyline(pts, UIColors.CYBER_ACCENT, 2.5)
	draw_arc(pj, RAYON_CLIC + 5.0, _t * 1.8, _t * 1.8 + TAU * 0.28, 18,
			Color(UIColors.CYBER_ACCENT, 0.55), 1.5)
	draw_arc(pj, RAYON_CLIC + 5.0, _t * 1.8 + TAU * 0.5, _t * 1.8 + TAU * 0.78, 18,
			Color(UIColors.CYBER_ACCENT, 0.55), 1.5)

	_dessiner_legende(mono)

# Légende compacte en pied de carte : les 3 états qui guident la lecture
# (position, destination accessible, secteur chiffré) — jamais perplexe.
func _dessiner_legende(mono: Font) -> void:
	var yl := size.y - 14.0
	var xl := 14.0
	draw_arc(Vector2(xl + 5.0, yl - 4.0), 5.0, 0.0, TAU, 16, UIColors.CYBER_ACCENT, 1.5)
	xl += 14.0
	xl = _texte_legende(mono, xl, yl, Translations.T("expe.legende_position"))
	draw_circle(Vector2(xl + 5.0, yl - 4.0), 4.0, UIColors.CYBER_NOEUD_FIN)
	xl += 14.0
	xl = _texte_legende(mono, xl, yl, Translations.T("expe.legende_accessible"))
	draw_string(mono, Vector2(xl, yl), GLYPHES_HEX[int(_t * 5.0) % 16],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIColors.CYBER_CHIFFRE)
	xl += 12.0
	_texte_legende(mono, xl, yl, Translations.T("expe.legende_chiffre"))

func _texte_legende(mono: Font, xl: float, yl: float, texte: String) -> float:
	draw_string(mono, Vector2(xl, yl), texte, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			UIColors.CYBER_TEXTE_MUTED)
	return xl + mono.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0

func _etiquette(nd: ExpeNoeud) -> String:
	match nd.type:
		Enums.TypeNoeud.ENTREE:    return Translations.T("expe.noeud.entree")
		Enums.TypeNoeud.MYSTERE:   return Translations.T(
				"expe.noeud.mystere" if nd.contenu_mystere < 0 else "expe.noeud.mystere_resolu")
		Enums.TypeNoeud.COMBAT:    return Translations.T("expe.noeud.combat")
		Enums.TypeNoeud.COFFRE:    return Translations.T("expe.noeud.coffre")
		Enums.TypeNoeud.FIN_ETAGE: return Translations.T("expe.noeud.fin")
		Enums.TypeNoeud.BOSS:      return Translations.T("expe.noeud.boss")
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
