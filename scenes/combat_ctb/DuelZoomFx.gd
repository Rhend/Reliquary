# ============================================================
# DuelZoomFx — zoom-DUEL façon Darkest Dungeon, SOURCE PARTAGÉE.
#
# L'attaquant et sa cible GLISSENT au centre de l'écran face à face pendant
# que la scène punch-in fort, tenue le temps du coup, puis chacun regagne son
# emplacement. Extrait de CombatCtbUi._duel_attaque (26/08/2026) pour que la
# vitrine (ShowRoom, touches [A]/[T] en mode combat) rejoue EXACTEMENT le même
# effet — jamais une deuxième recette qui pourrait diverger en silence,
# comme CombatFondScinde pour le décor scindé.
#
# `jouer()` ne connaît QUE des CanvasItem et des positions : aucune notion de
# combat, d'orbe ou de sprite Spine. L'appelant fournit :
#   • `couche_scene` — le nœud dont le SCALE simule le punch-in caméra (un
#     Control avec pivot_offset : `_couche_scene` en combat réel, `_decor` en
#     vitrine — tout ce qui est dessous en hérite, décor compris) ;
#   • `foyer` — le point regardé, dans l'espace de `couche_scene` (centre de
#     l'écran en mêlée ; milieu du couple tireur/cible en tir) ;
#   • `att`/`cible` — les nœuds à faire converger (ou pas), et leur position
#     CIBLE `pos_att`/`pos_cib` déjà résolue par l'appelant (lui seul sait
#     traduire un pied en position de nœud — orbe ou sprite Spine n'ont pas
#     la même origine).
# ============================================================
class_name DuelZoomFx

const ZOOM := 1.40
const ZOOM_CRIT := 1.55       # un crit frappe plus fort → caméra aussi
# Distance TOTALE entre les deux pieds au centre (face à face) — chacun se
# pose à ECART_PX/2 du foyer. 120 (valeur d'origine, calibrée à l'œil quand
# l'adversaire n'était qu'un orbe EnergyBoule minuscule) faisait carrément se
# chevaucher deux personnages Spine pleine taille (276 px de haut) une fois
# les deux sprites réels affrontés dans la vitrine (27/08/2026, signalé par
# Rhend) — les torses, sans même compter les armes, débordaient déjà de
# 60 px de chaque côté du foyer.
const ECART_PX := 240.0
const FOCUS_HAUT_PX := 60.0   # remonte le pivot des pieds vers les torses
const DUREE_IN := 0.14
# Tenue calibrée pour qu'en COMBAT RÉEL le duel (in + tenue + out = 0.89 s)
# soit ENTIÈREMENT retombé avant la première activation ennemie qui suit
# (pause post-action 0.35 s + pause de bandeau 0.55 s = 0.90 s dans
# CombatCtbUi — sinon le coup ennemi se jouerait pendant le dé-zoom,
# contredisant « ennemis sans effet de caméra »). Toucher ces valeurs
# implique de revérifier ce calage.
const TENUE := 0.45
const DUREE_OUT := 0.30

# Rejoue l'effet. `crit` accentue le punch-in ; `converger` = false (tir) :
# personne ne bouge, seul le punch-in reste, recentré sur `foyer`.
# `facteur_delais` <= 0 → rien ne joue (tests headless) : rend null.
# `fin` (optionnel) est appelée à la fin du tween.
static func jouer(couche_scene: Control, foyer: Vector2,
		att: CanvasItem, pos_att: Vector2, cible: CanvasItem, pos_cib: Vector2,
		crit: bool, converger: bool, facteur_delais: float,
		fin: Callable = Callable()) -> Tween:
	if facteur_delais <= 0.0 or couche_scene == null or att == null or cible == null:
		return null
	# CanvasItem n'a PAS de `position` propre (Node2D et Control la déclarent
	# chacun séparément) : `:=` ne peut pas l'inférer sur un paramètre typé
	# CanvasItem — annotation explicite pour lever l'ambiguïté.
	var origine_att: Vector2 = att.position
	var origine_cib: Vector2 = cible.position
	couche_scene.pivot_offset = foyer - Vector2(0.0, FOCUS_HAUT_PX)
	var zoom := ZOOM_CRIT if crit else ZOOM
	var f := facteur_delais
	var tw := couche_scene.create_tween()
	tw.tween_property(couche_scene, "scale", Vector2.ONE * zoom,
			DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if converger:
		tw.parallel().tween_property(att, "position", pos_att,
				DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cible, "position", pos_cib,
				DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(TENUE * f)
	tw.tween_property(couche_scene, "scale", Vector2.ONE,
			DUREE_OUT * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if converger:
		tw.parallel().tween_property(att, "position", origine_att,
				DUREE_OUT * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(cible, "position", origine_cib,
				DUREE_OUT * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if fin.is_valid():
		tw.finished.connect(fin)
	return tw
