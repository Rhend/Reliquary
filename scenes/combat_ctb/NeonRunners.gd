# ============================================================
# NeonRunners — les points lumineux qui courent le long des enseignes néon.
#
# Un nœud par COPIE de plan dans le ruban de CombatDecorCity, posé en ENFANT du
# Sprite2D de cette copie. Ce parentage n'est pas un détail, c'est tout le
# design : le sprite porte déjà `scale = taille_affichée / taille_source`, donc
# un enfant travaille directement dans les PIXELS DE L'IMAGE — exactement les
# coordonnées que le bake a produites, sans la moindre conversion. Et comme le
# ruban défile, se replie (fmod), compense le zoom-duel et reçoit la brume
# atmosphérique en amont, les points héritent des quatre gratuitement. Aucun de
# ces effets n'a eu à être recâblé ici.
#
# Chaque enseigne reçoit une phase et une vitesse tirées d'un RNG SEEDÉ sur son
# index : deux enseignes voisines ne battent jamais ensemble, et pourtant le
# résultat est reproductible d'un lancement à l'autre (donc testable). Les
# copies d'un même ruban partagent, elles, la même graine — ce sont les mêmes
# immeubles répétés, leurs enseignes doivent battre pareil.
#
# Une fraction reste ÉTEINTE. Une ville dont chaque enseigne pulse en même
# temps ne fait pas vivante, elle fait sapin de Noël ; ce sont les tubes morts
# qui rendent les autres crédibles.
#
# Rendu additif (BLEND_MODE_ADD) : sur un décor nocturne, un point additif se
# comporte comme une vraie source lumineuse au lieu d'un autocollant clair.
# ============================================================
class_name NeonRunners
extends Node2D

# ─── Réglages d'ambiance (calibrage à l'œil, tout est ici) ──

# Vitesse du point le long du tube, en pixels SOURCE par seconde. Bornes d'un
# tirage par enseigne. À l'échelle du décor cadré (~0,31), 160-320 px/s source
# donnent 50-100 px/s à l'écran : lisible sans attirer l'œil hors du combat.
const VITESSE_MIN := 160.0
const VITESSE_MAX := 320.0

# Longueur de la traînée, en fraction du périmètre de l'enseigne, bornée en
# pixels source. Proportionnel plutôt que fixe : sur une petite enseigne, une
# traînée fixe ferait le tour complet et on ne verrait plus qu'un halo.
const TRAINEE_FRACTION := 0.22
const TRAINEE_MIN := 70.0
const TRAINEE_MAX := 260.0

# Épaisseur du trait, en pixels source. Les tubes de Christophe font ~20 px :
# une traînée un peu plus fine se pose DESSUS au lieu de déborder.
const EPAISSEUR := 7.0

# Rayon du halo de tête, en pixels source, et intensité générale de l'effet.
const HALO_RAYON := 5.0
const INTENSITE := 1.0

# Blanchiment du CŒUR du point. C'est le réglage qui décide si l'effet se voit :
# un point de la couleur de son tube, ajouté sur un tube déjà saturé, ne change
# quasiment rien — les canaux sont au plafond (mesuré : il fallait amplifier la
# différence six fois pour l'apercevoir). Un chenillard réel se repère parce
# qu'il est SUREXPOSÉ, donc plus blanc que le néon qu'il parcourt. On garde la
# teinte dans le halo, qui déborde sur le décor sombre, et on blanchit le cœur.
const COEUR_BLANC := 0.70
const TRAINEE_BLANC := 0.45

# Fraction d'enseignes laissées DÉFINITIVEMENT éteintes — des tubes morts, qui
# rendent les autres crédibles. Basse, parce que le cycle ci-dessous éteint déjà
# la plupart des enseignes la plupart du temps.
const PROPORTION_ETEINTES := 0.12

# CYCLE D'ALLUMAGE (27/08/2026). Un point qui court en permanence sur chaque
# enseigne fait un décor mécanique : l'œil finit par lire une horloge. Chaque
# enseigne suit donc son propre cycle — elle s'allume, le point fait un ou
# plusieurs tours, elle s'éteint, puis rien pendant un moment. Période et part
# allumée sont tirées par enseigne, donc jamais deux voisines ensemble ; à un
# instant donné, un tiers environ des enseignes est actif.
const CYCLE_MIN := 6.0
const CYCLE_MAX := 15.0
const PART_ALLUMEE_MIN := 0.22
const PART_ALLUMEE_MAX := 0.45
# Fondu d'allumage et d'extinction, en secondes. Sans lui le point apparaît et
# disparaît d'un coup, ce qui se lit comme un raté d'affichage, pas comme un néon.
const FONDU := 0.45

# En dessous de ce périmètre APPARENT (px écran), pas de point : sur une
# enseigne minuscule, la traînée dégénère en scintillement illisible. Le
# critère est la taille RENDUE, pas le numéro de plan — un plan relivré plus
# grand ou plus petit se règle donc tout seul.
const MIN_PERIMETRE_ECRAN := 60.0

# Nombre de sommets de la traînée. 12 suffit : elle épouse des angles droits.
const SEGMENTS_TRAINEE := 12

# ─── État ───────────────────────────────────────────────────

# Un élément par enseigne allumée :
#   {points, longueur, couleur, vitesse, phase, trainee}
var _runners: Array[Dictionary] = []
var _temps := 0.0

# Pose les points lumineux d'un calque sur `sprite` (une copie du ruban).
# Rend null si le calque n'a pas de tracé baké, si le bake est périmé, ou si
# rien n'est assez grand à l'écran : dans tous ces cas le décor reste
# strictement ce qu'il était, sans point — jamais d'écran cassé.
static func poser(sprite: Sprite2D, chemin_calque: String,
		taille_source: Vector2, echelle_ecran: float) -> NeonRunners:
	var bake := NeonsCiteData.charger()
	if bake == null:
		return null
	var traces := bake.traces(chemin_calque, taille_source)
	if traces.is_empty():
		return null

	var noeud := NeonRunners.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	noeud.material = mat
	# Graine stable : le même calque donne toujours la même ville qui clignote.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chemin_calque)

	for t: Dictionary in traces:
		var points := t.get("points", PackedVector2Array()) as PackedVector2Array
		var longueur := float(t.get("longueur", 0.0))
		# Le tirage est consommé AVANT tout rejet, sinon écarter une enseigne
		# décalerait la phase de toutes les suivantes.
		var vitesse := rng.randf_range(VITESSE_MIN, VITESSE_MAX)
		var phase := rng.randf() * maxf(longueur, 1.0)
		var eteinte := rng.randf() < PROPORTION_ETEINTES
		var cycle := rng.randf_range(CYCLE_MIN, CYCLE_MAX)
		var part := rng.randf_range(PART_ALLUMEE_MIN, PART_ALLUMEE_MAX)
		var phase_cycle := rng.randf() * cycle
		if eteinte or points.size() < 3 or longueur <= 0.0:
			continue
		if longueur * echelle_ecran < MIN_PERIMETRE_ECRAN:
			continue
		noeud._runners.append({
			"points": points,
			"longueur": longueur,
			"couleur": t.get("couleur", Color.WHITE) as Color,
			"vitesse": vitesse,
			"phase": phase,
			"trainee": clampf(longueur * TRAINEE_FRACTION, TRAINEE_MIN, TRAINEE_MAX),
			"cycle": cycle,
			"allumee": cycle * part,
			"phase_cycle": phase_cycle,
		})

	if noeud._runners.is_empty():
		noeud.queue_free()
		return null
	sprite.add_child(noeud)
	return noeud

func _process(delta: float) -> void:
	_temps += delta
	queue_redraw()

func _draw() -> void:
	for r in _runners:
		# Le cycle d'abord : une enseigne éteinte ne coûte pas un seul calcul.
		var vif := intensite_cycle(r, _temps)
		if vif <= 0.0:
			continue
		var points := r["points"] as PackedVector2Array
		var longueur := float(r["longueur"])
		var trainee := float(r["trainee"])
		var tete := float(r["phase"]) + _temps * float(r["vitesse"])
		var ruban := _trainee(points, longueur, tete, trainee)
		if ruban.size() < 2:
			continue

		var base := r["couleur"] as Color
		# Dégradé de la queue (invisible) vers la tête (pleine). En additif,
		# l'alpha module l'apport lumineux : la traînée s'éteint derrière le
		# point au lieu de laisser une trace uniforme. Elle blanchit aussi en
		# approchant de la tête, pour la même raison que le cœur.
		var couleurs := PackedColorArray()
		for i in ruban.size():
			var k := float(i) / float(ruban.size() - 1)
			var c := base.lerp(Color.WHITE, TRAINEE_BLANC * k)
			couleurs.append(Color(c.r, c.g, c.b, k * k * INTENSITE * vif))
		draw_polyline_colors(ruban, couleurs, EPAISSEUR, true)

		# Halo de tête : trois disques concentriques. Un seul disque net ferait
		# une pastille ; l'empilement additif donne la retombée d'une lampe.
		# Les deux grands gardent la TEINTE (c'est eux qui débordent sur la
		# façade sombre et signent la couleur de l'enseigne), le petit est le
		# cœur surexposé qui reste lisible même sur un tube saturé.
		var t := ruban[ruban.size() - 1]
		var coeur := base.lerp(Color.WHITE, COEUR_BLANC)
		draw_circle(t, HALO_RAYON * 2.6, Color(base.r, base.g, base.b, 0.12 * INTENSITE * vif))
		draw_circle(t, HALO_RAYON * 1.5, Color(base.r, base.g, base.b, 0.30 * INTENSITE * vif))
		draw_circle(t, HALO_RAYON * 0.8, Color(coeur.r, coeur.g, coeur.b, 0.95 * INTENSITE * vif))

# Intensité du cycle d'allumage d'une enseigne à l'instant `temps` : 0 hors de
# sa fenêtre allumée, 1 en plein dedans, avec un fondu à chaque extrémité.
static func intensite_cycle(r: Dictionary, temps: float) -> float:
	var cycle := float(r.get("cycle", 0.0))
	var allumee := float(r.get("allumee", 0.0))
	if cycle <= 0.0 or allumee <= 0.0:
		return 1.0   # runner sans cycle (tests, données anciennes) : toujours vif
	var t := fposmod(temps + float(r.get("phase_cycle", 0.0)), cycle)
	if t >= allumee:
		return 0.0
	# Le fondu ne peut pas dépasser la moitié de la fenêtre, sinon une fenêtre
	# courte n'atteindrait jamais sa pleine intensité.
	var fondu := minf(FONDU, allumee * 0.5)
	if fondu <= 0.0:
		return 1.0
	return clampf(minf(t, allumee - t) / fondu, 0.0, 1.0)

# Les `n` sommets de la traînée, de la queue vers la TÊTE, en une seule marche
# le long de la polyligne fermée. Appeler un échantillonnage par sommet ferait
# n balayages complets du tracé à chaque frame, pour chaque enseigne.
static func _trainee(points: PackedVector2Array, longueur: float,
		tete: float, taille: float) -> PackedVector2Array:
	var sortie := PackedVector2Array()
	var m := points.size() - 1   # nombre de segments (le tracé est refermé)
	if m < 2 or longueur <= 0.0 or taille <= 0.0:
		return sortie

	var pas := taille / float(SEGMENTS_TRAINEE - 1)
	var reste := fposmod(tete - taille, longueur)
	# Segment de départ.
	var i := 0
	while i < m - 1 and reste > points[i].distance_to(points[i + 1]):
		reste -= points[i].distance_to(points[i + 1])
		i += 1

	var a_poser := SEGMENTS_TRAINEE
	# Borne dure : une polyligne dégénérée ne doit pas pouvoir figer la frame.
	var garde := SEGMENTS_TRAINEE + m * 2 + 8
	while a_poser > 0 and garde > 0:
		garde -= 1
		var seg := points[i].distance_to(points[i + 1])
		if seg <= 0.0 or reste > seg:
			reste -= maxf(seg, 0.0)
			i = (i + 1) % m
			continue
		sortie.append(points[i] + (points[i + 1] - points[i]) / seg * reste)
		a_poser -= 1
		reste += pas
	return sortie
