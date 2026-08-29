# ============================================================
# bake_neons_cite.gd — OUTIL DEV : extraction des tracés d'enseignes néon.
#
#   godot --headless --path . --script res://tools/bake_neons_cite.gd
#
# Pour chaque calque néon livré par Christophe (DÉCOUPAGE déjà isolé, 29/08/2026
# — le calque est transparent partout sauf sur les enseignes elles-mêmes ; PLUS
# de façade nue à diffuser, l'ancienne méthode par différence est morte avec la
# livraison du 24/08/2026) :
#   1. seuil sur le CANAL ALPHA du calque → masque des pixels d'enseigne ;
#   2. composantes connexes → une par enseigne ;
#   3. filtrage du bruit (miettes, franges d'antialiasing) ;
#   4. suivi de CONTOUR extérieur (Moore-neighbor) → le tracé du néon ;
#   5. simplification Douglas-Peucker → une vingtaine de sommets au lieu de mille ;
#   6. couleur vive de l'enseigne, pondérée par la luminance.
#
# Le résultat est écrit dans data/decor/neons_cite.tres, VERSIONNÉ.
# Voir NeonsCiteData pour le pourquoi du bake et le contrat d'obsolescence.
#
# BALAYAGE EN DEUX PASSES, et pas une seule à pleine résolution : un plan fait
# 12,6 M pixels et une boucle GDScript dessus se compte en minutes. On localise
# donc les enseignes sur un masque au 1/4 (790 k pixels, quelques secondes),
# puis on ne travaille FIN que dans leurs boîtes — quelques centaines de
# milliers de pixels au total. Le flood fill est refait à pleine résolution
# dans chaque boîte : deux enseignes que la passe grossière aurait fusionnées
# s'y reséparent d'elles-mêmes.
#
# Un `--script` et non une scène : l'outil ne lit que des images, il n'a besoin
# d'aucun autoload (contrairement à verif_spine ou mesurer_silhouettes, qui
# dépendent du registre, donc de GameData).
# ============================================================
extends SceneTree

const DIR := "res://assets/background/city/"

# Les calques néon (découpages déjà isolés). Ajouter un calque = ajouter une ligne.
const NEONS := [
	"Background_City_Plan_4_Immeuble_01_Neon.png",
	"Background_City_Plan_4_Immeuble_01_Neon_2.png",
	"Background_City_Plan_3_Immeuble_01_Neon.png",
	"Background_City_Plan_3_Immeuble_01_Neon_2.png",
]

# Sous-échantillonnage de la passe de localisation. 4 est sûr : la plus petite
# enseigne retenue fait 24 px de côté, soit 6 cellules grossières.
const PAS_GROS := 4
# Marge, en cellules grossières, ajoutée autour d'une boîte avant la passe fine.
# Le sous-échantillonnage peut rater les quelques pixels de bord d'une enseigne.
const MARGE_GROS := 3
# Taille minimale d'une composante grossière pour mériter une passe fine. Une
# enseigne retenue fait 24 px de côté, soit 36 cellules : exiger 3 écarte le
# poivre et sel d'antialiasing sans risque, et surtout évite de payer une
# passe fine (et son flood fill) pour chaque pixel de bruit isolé.
const MIN_CELLULES_GROS := 3
# Une boîte qui couvre une grande part du cadre n'est pas une enseigne : c'est
# du bruit structurel qui a relié tout le plan. On la signale et on l'écarte,
# plutôt que de lancer un flood fill sur douze millions de pixels.
const AIRE_BOITE_MAX := 0.08

# Seuil sur le canal ALPHA (fraction de 255) au-delà duquel un pixel du calque
# est considéré comme faisant partie d'une enseigne. 0,10 laisse passer le halo
# diffus peint autour du tube sans rien perdre des enseignes (mesuré : le cœur
# tranche net, à 255).
const SEUIL_HALO := 0.10

# DEUX seuils, parce qu'on pose deux questions différentes (27/08/2026).
# Christophe peint un HALO diffus autour de chaque enseigne (alpha faible mais
# non nul). Ce halo fait bien partie du calque — et c'est tant mieux pour
# LOCALISER l'enseigne — mais si on suit le contour de tout ça, on épouse le
# bord du halo et le point court à côté du tube, dans le vide. Le contour se
# trace donc sur un masque SERRÉ qui ne garde que le cœur opaque ; le halo, de
# faible alpha, en tombe. Repli : si le seuil serré ne laisse rien d'exploitable
# dans une boîte (une enseigne peu contrastée, tout en halo — cas mesuré sur
# Plan_3_Immeuble_01_Neon_2, aucun pixel à alpha plein), on retombe sur le
# seuil large pour cette boîte.
const SEUIL_COEUR := 0.25

# Rejets. Mesurés sur la livraison du 24/08/2026 : les vraies enseignes font
# 900 à 6000 px et 42 px de côté minimum ; le bruit résiduel fait 100 et 380 px
# (des traits de 38x10, invisibles une fois le décor à l'échelle).
const MIN_PIXELS := 600
const MIN_COTE := 24
# Une composante quasi noire n'est pas une enseigne : une frange
# d'antialiasing sombre peut passer le seuil alpha sans être un tube allumé.
# Un néon, par définition, est lumineux.
const LUM_MIN := 0.12

# Tolérance de la simplification, en pixels source. 2,5 px ≈ 0,8 px à l'écran
# une fois le décor cadré : les angles restent nets, le nombre de sommets chute.
const EPSILON_DP := 2.5

# RECENTRAGE SUR LE TUBE (27/08/2026). Le suivi de contour rend le bord
# EXTÉRIEUR de la forme : le point courait donc sur la face externe du tube et
# se voyait « posé juste à côté » du néon, décalé d'une demi-épaisseur. On
# MESURE l'épaisseur du tube sous chaque sommet (on sonde vers l'intérieur tant
# qu'on reste dans la forme) et on rentre le tracé de sa moitié.
#   • fenêtre de tangente : le contour est fait de pixels adjacents, sa tangente
#     brute est en escalier — on la prend sur ±4 points pour la lisser ;
#   • plafond : une forme PLEINE (un panneau à fond coloré, comme les enseignes
#     à caractères) mesure toute sa largeur, et la moitié mettrait le point en
#     plein milieu du panneau au lieu de son bord lumineux. On plafonne donc à
#     la demi-épaisseur du CADRE de ces panneaux, mesurée à ~10 px sur la
#     livraison — au-delà, le point décollait vers l'intérieur.
const FENETRE_TANGENTE := 4
const SONDE_MAX := 60
const DECALAGE_MAX := 24.0

# Valeur minimale de la couleur d'un point. La moyenne d'un panneau plein tire
# vers le sombre (le texte, le fond du panneau) ; on garde la TEINTE mesurée
# mais on la remonte en luminosité, un point lumineux étant lumineux par nature.
const VALEUR_MIN := 0.85

# Voisinage 8, index 0 = ouest, puis dans le sens horaire. L'ordre importe :
# c'est lui qui donne son sens de rotation au suivi de contour.
const D8 := [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			 Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]

func _init() -> void:
	print("═══ Bake des tracés de néons ═══")
	var data := NeonsCiteData.new()
	var total := 0
	for nom in NEONS:
		var chemin_neon: String = DIR + str(nom)
		var entree := _analyser(chemin_neon)
		if entree.is_empty():
			continue
		data.enseignes[chemin_neon] = entree
		total += (entree["traces"] as Array).size()

	if total == 0:
		push_error("bake_neons_cite : aucun tracé extrait — rien n'est écrit.")
		quit(1)
		return
	_ecrire(data, total)
	quit(0)

# ─── Analyse d'un calque ─────────────────────────────────────

func _analyser(chemin_neon: String) -> Dictionary:
	print("\n> ", chemin_neon.get_file())
	var neon := _image(chemin_neon)
	if neon == null:
		push_error("  chargement impossible — calque ignoré.")
		return {}

	var W := neon.get_width()
	var H := neon.get_height()
	var dn := neon.get_data()
	var boites := _localiser(dn, W, H)
	print("  %d zone(s) candidate(s) localisée(s) au 1/%d" % [boites.size(), PAS_GROS])

	var traces: Array = []
	var rejets := {"petit": 0, "sombre": 0, "contour": 0}
	var t1 := Time.get_ticks_msec()
	for boite: Rect2i in boites:
		for t in _extraire(dn, W, boite, rejets):
			traces.append(t)
	print("  extraction des contours : %d ms" % (Time.get_ticks_msec() - t1))

	traces.sort_custom(func(a, b): return float(a["longueur"]) > float(b["longueur"]))
	print("  -> %d enseigne(s) retenue(s)   [rejets : %d trop petites, %d non lumineuses, %d sans contour]"
			% [traces.size(), rejets["petit"], rejets["sombre"], rejets["contour"]])
	for t in traces:
		print("      %-9s perimetre %6.0f px   %3d sommets   %s"
				% [str(t["nom"]), float(t["longueur"]),
				   (t["points"] as PackedVector2Array).size(),
				   (t["couleur"] as Color).to_html(false)])
		t.erase("nom")   # confort de log seulement, hors de la donnée versionnée

	# Un calque analysé mais sans tracé exploitable (tout sous le plancher de
	# taille — mesuré sur Plan_3_Immeuble_01_Neon_2, du texte en traits trop
	# fins pour le plancher calibré sur les enseignes-tubes) reste ENREGISTRÉ,
	# avec `traces` vide : c'est ce qui distingue « rien à en tirer » d'« oublié
	# de re-baker » pour le contrôle d'obsolescence et pour le test de présence.
	return {
		"source": Vector2(W, H),
		"empreinte": NeonsCiteData.empreinte_fichier(chemin_neon),
		"traces": traces,
	}

func _image(chemin: String) -> Image:
	# `load()` plutôt que `Image.load_from_file` : on passe par la texture
	# importée, ce qui évite l'avertissement « ne marchera pas à l'export » et
	# lit exactement ce que le jeu affichera.
	var tex := load(chemin) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

# Vrai si le pixel du calque néon fait partie d'une enseigne, au seuil demandé
# (fraction d'alpha, 0-255).
static func _opaque(dn: PackedByteArray, i: int, seuil: int) -> bool:
	return dn[i + 3] > seuil

static func _seuil_brut(fraction: float) -> int:
	return int(fraction * 255.0)

# ─── Passe 1 : où sont les enseignes ? ──────────────────────

# Rend des boîtes en coordonnées PLEINES, déjà marginées et clampées.
func _localiser(dn: PackedByteArray, W: int, H: int) -> Array:
	var wg := W / PAS_GROS
	var hg := H / PAS_GROS
	var masque := PackedByteArray()
	masque.resize(wg * hg)
	# Lecture inlinée plutôt qu'un appel à _opaque : c'est la boucle la plus
	# chaude du bake (790 k tours), et un appel de fonction GDScript y pèse plus
	# que le calcul lui-même.
	var seuil := _seuil_brut(SEUIL_HALO)
	var t0 := Time.get_ticks_msec()
	for y in hg:
		var oy := y * PAS_GROS * W * 4
		var ligne := y * wg
		for x in wg:
			var i := oy + x * PAS_GROS * 4
			if dn[i + 3] > seuil:
				masque[ligne + x] = 1
	print("  masque de localisation : %d ms" % (Time.get_ticks_msec() - t0))

	var boites: Array = []
	var aire_max := int(float(W) * float(H) * AIRE_BOITE_MAX)
	var ignorees := 0
	for cellules: PackedInt32Array in _composantes(masque, wg, hg):
		if cellules.size() < MIN_CELLULES_GROS:
			ignorees += 1
			continue
		var b := _bornes(cellules, wg)
		var x0 := maxi(0, (b.position.x - MARGE_GROS) * PAS_GROS)
		var y0 := maxi(0, (b.position.y - MARGE_GROS) * PAS_GROS)
		var x1 := mini(W - 1, (b.end.x + MARGE_GROS) * PAS_GROS)
		var y1 := mini(H - 1, (b.end.y + MARGE_GROS) * PAS_GROS)
		if (x1 - x0 + 1) * (y1 - y0 + 1) > aire_max:
			push_warning(("bake_neons_cite : zone de %dx%d px écartée — trop vaste "
					+ "pour une enseigne (bruit de différence ?)") % [x1 - x0 + 1, y1 - y0 + 1])
			continue
		boites.append(Rect2i(x0, y0, x1 - x0, y1 - y0))
	if ignorees > 0:
		print("  %d amas de moins de %d cellules ignorés (poivre et sel)"
				% [ignorees, MIN_CELLULES_GROS])
	return boites

# ─── Passe 2 : contour fin dans une boîte ───────────────────

func _extraire(dn: PackedByteArray, W: int,
		boite: Rect2i, rejets: Dictionary) -> Array:
	var bw := boite.size.x + 1
	var bh := boite.size.y + 1
	if bw <= 2 or bh <= 2:
		return []
	# Seuil SERRÉ d'abord (on veut le tube, pas son halo) ; repli sur le seuil
	# large si cette boîte n'a alors plus rien d'assez grand pour être suivi.
	# Les rejets de la passe serrée ne comptent que si elle aboutit : sinon ils
	# seraient additionnés à ceux du repli et le bilan compterait double.
	var essai := {"petit": 0, "sombre": 0, "contour": 0}
	var sortie := _extraire_au_seuil(dn, W, boite, bw, bh, SEUIL_COEUR, essai)
	if sortie.is_empty():
		return _extraire_au_seuil(dn, W, boite, bw, bh, SEUIL_HALO, rejets)
	for cle in essai:
		rejets[cle] += essai[cle]
	return sortie

func _extraire_au_seuil(dn: PackedByteArray, W: int,
		boite: Rect2i, bw: int, bh: int, fraction: float, rejets: Dictionary) -> Array:
	var seuil := _seuil_brut(fraction)
	var masque := PackedByteArray()
	masque.resize(bw * bh)
	for y in bh:
		var oy := (boite.position.y + y) * W * 4 + boite.position.x * 4
		for x in bw:
			if _opaque(dn, oy + x * 4, seuil):
				masque[y * bw + x] = 1

	var sortie: Array = []
	for cellules: PackedInt32Array in _composantes(masque, bw, bh):
		var b := _bornes(cellules, bw)
		if cellules.size() < MIN_PIXELS \
				or b.size.x + 1 < MIN_COTE or b.size.y + 1 < MIN_COTE:
			rejets["petit"] += 1
			continue
		var couleur := _couleur(dn, W, boite, cellules, bw)
		if couleur.v < LUM_MIN:
			rejets["sombre"] += 1
			continue

		# Masque de la SEULE composante courante : le suivi de contour ne doit
		# pas pouvoir sauter sur une enseigne voisine partageant la boîte.
		var seule := PackedByteArray()
		seule.resize(bw * bh)
		for k in cellules:
			seule[k] = 1
		var points := _contour(seule, bw, bh, cellules[0])
		if points.size() < 4:
			rejets["contour"] += 1
			continue
		# Recentrer AVANT de simplifier : sur le contour dense, les normales
		# sont régulières et le décalage reste lisse. Le faire après reviendrait
		# à pousser une poignée de sommets isolés, en creusant les angles.
		points = _recentrer(points, seule, bw, bh, dn, W, boite.position)
		points = _simplifier(points, EPSILON_DP)
		if points.size() < 3:
			rejets["contour"] += 1
			continue

		# En coordonnées de l'image, et REFERMÉ : répéter le premier sommet
		# évite au runtime d'avoir à traiter le dernier segment à part.
		var absolus := PackedVector2Array()
		for p in points:
			absolus.append(p + Vector2(boite.position))
		absolus.append(absolus[0])
		sortie.append({
			"nom": "%dx%d" % [b.size.x + 1, b.size.y + 1],
			"points": absolus,
			"couleur": _aviver(couleur),
			"longueur": _longueur(absolus),
		})
	return sortie

# ─── Briques génériques ─────────────────────────────────────

# Composantes connexes (8-connexité) d'un masque binaire. Rend une liste de
# PackedInt32Array d'indices, flood fill itératif — la récursion exploserait la
# pile sur une enseigne de plusieurs milliers de pixels.
static func _composantes(masque: PackedByteArray, w: int, h: int) -> Array:
	var vu := PackedByteArray()
	vu.resize(w * h)
	var sortie: Array = []
	for depart in w * h:
		if masque[depart] == 0 or vu[depart] == 1:
			continue
		var pile := PackedInt32Array([depart])
		var cellules := PackedInt32Array()
		vu[depart] = 1
		while not pile.is_empty():
			var k: int = pile[pile.size() - 1]
			pile.remove_at(pile.size() - 1)
			cellules.append(k)
			var cx := k % w
			var cy := k / w
			for d: Vector2i in D8:
				var nx := cx + d.x
				var ny := cy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nk := ny * w + nx
				if masque[nk] == 1 and vu[nk] == 0:
					vu[nk] = 1
					pile.append(nk)
		# Les indices doivent être croissants : le suivi de contour part du
		# premier, et il lui faut le pixel le plus haut de la ligne la plus
		# haute — donc un pixel dont le voisin OUEST est hors composante.
		cellules.sort()
		sortie.append(cellules)
	return sortie

static func _bornes(cellules: PackedInt32Array, w: int) -> Rect2i:
	var x0 := cellules[0] % w
	var x1 := x0
	var y0 := cellules[0] / w
	var y1 := y0
	for k in cellules:
		var x := k % w
		var y := k / w
		x0 = mini(x0, x)
		x1 = maxi(x1, x)
		y0 = mini(y0, y)
		y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

# Couleur d'une enseigne, pondérée par la LUMINANCE au carré : les pixels du
# tube néon pèsent, le fond sombre du panneau ne pèse presque rien. Une moyenne
# nue rendrait un violet grisâtre pour une enseigne rouge vif.
static func _couleur(dn: PackedByteArray, W: int, boite: Rect2i,
		cellules: PackedInt32Array, bw: int) -> Color:
	var somme := Vector3.ZERO
	var poids := 0.0
	for k in cellules:
		var i := (boite.position.y + k / bw) * W * 4 + (boite.position.x + k % bw) * 4
		var c := Vector3(dn[i] / 255.0, dn[i + 1] / 255.0, dn[i + 2] / 255.0)
		var p: float = maxf(maxf(c.x, c.y), c.z)
		p *= p
		somme += c * p
		poids += p
	if poids <= 0.0:
		return Color.BLACK
	somme /= poids
	return Color(somme.x, somme.y, somme.z)

# Remonte la couleur à une valeur franche en gardant teinte et saturation.
static func _aviver(c: Color) -> Color:
	if c.v >= VALEUR_MIN or c.v <= 0.0:
		return c
	return Color.from_hsv(c.h, c.s, VALEUR_MIN, 1.0)

# Suivi de contour extérieur (Moore-neighbor). `depart` est le premier pixel en
# ordre de lecture : il n'a donc aucun voisin de composante à l'ouest, ce qui
# donne un point d'amorçage valide pour le backtrack.
static func _contour(masque: PackedByteArray, w: int, h: int, depart: int) -> PackedVector2Array:
	var s := Vector2i(depart % w, depart / w)
	var p := s
	var dir := 0   # direction de p vers le pixel d'où l'on vient (ouest au départ)
	var points := PackedVector2Array()
	var garde := w * h * 4   # borne dure : jamais de boucle infinie sur un masque tordu
	while garde > 0:
		garde -= 1
		points.append(Vector2(p))
		var avance := false
		for k in 8:
			var d := (dir + 1 + k) % 8
			var q: Vector2i = p + D8[d]
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			if masque[q.y * w + q.x] == 0:
				continue
			dir = (d + 4) % 8   # on regarde désormais vers p, qu'on vient de quitter
			p = q
			avance = true
			break
		if not avance or p == s:
			break
	return points

# Rentre le contour d'une demi-épaisseur de tube, pour que le point coure AU
# MILIEU du néon et non sur sa face externe. L'épaisseur est mesurée, pas
# supposée : chaque sommet sonde vers l'intérieur de la forme, et on retient la
# MÉDIANE — une moyenne serait tirée par les angles, où la sonde traverse en
# diagonale et mesure bien plus que le tube.
static func _recentrer(points: PackedVector2Array, masque: PackedByteArray,
		w: int, h: int, dn: PackedByteArray, W: int, origine: Vector2i) -> PackedVector2Array:
	var n := points.size()
	if n < 8:
		return points
	var normales := PackedVector2Array()
	var mesures := PackedFloat32Array()
	for i in n:
		var a := points[(i - FENETRE_TANGENTE + n) % n]
		var b := points[(i + FENETRE_TANGENTE) % n]
		var t := (b - a)
		if t.length_squared() <= 0.0:
			normales.append(Vector2.ZERO)
			continue
		t = t.normalized()
		var nor := Vector2(-t.y, t.x)
		# Le sens du parcours n'est pas garanti : on garde la normale qui
		# pointe vers la matière plutôt que de raisonner sur l'aire signée.
		if not _dedans(masque, w, h, points[i] + nor * 2.0):
			nor = -nor
		normales.append(nor)
		# On avance dans la forme et on retient la profondeur du pixel le PLUS
		# LUMINEUX. C'est ça, le tube : le halo peint autour de l'enseigne est
		# plus faible, le fond du panneau aussi. Chercher un maximum de lumière
		# plutôt qu'une demi-épaisseur géométrique rend la mesure insensible à
		# l'épaisseur du halo, qui varie d'une enseigne à l'autre.
		var meilleure := 0.0
		var pic := -1.0
		var d := 0.0
		while d < float(SONDE_MAX) and _dedans(masque, w, h, points[i] + nor * d):
			var lum := _luminance(dn, W, origine, points[i] + nor * d)
			if lum > pic:
				pic = lum
				meilleure = d
			d += 1.0
		mesures.append(meilleure)

	if mesures.is_empty():
		return points
	# MÉDIANE et non par-sommet : un décalage constant garde le tracé homothétique
	# au tube. Décaler chaque sommet de sa propre mesure ferait onduler la ligne
	# au gré du bruit de l'antialiasing.
	var triees := mesures.duplicate()
	triees.sort()
	var decalage := minf(triees[triees.size() / 2], DECALAGE_MAX)
	if decalage < 1.0:
		return points

	var sortie := PackedVector2Array()
	for i in n:
		sortie.append(points[i] + normales[i] * decalage)
	return sortie

# Luminance (canal le plus fort) du pixel de l'image néon sous un point local.
static func _luminance(dn: PackedByteArray, W: int, origine: Vector2i, p: Vector2) -> float:
	var x := origine.x + int(round(p.x))
	var y := origine.y + int(round(p.y))
	var i := (y * W + x) * 4
	if i < 0 or i + 2 >= dn.size():
		return 0.0
	return float(maxi(maxi(dn[i], dn[i + 1]), dn[i + 2]))

static func _dedans(masque: PackedByteArray, w: int, h: int, p: Vector2) -> bool:
	var x := int(round(p.x))
	var y := int(round(p.y))
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return masque[y * w + x] == 1

# Douglas-Peucker, itératif (pile de segments) sur une polyligne OUVERTE. Le
# premier point est le sommet le plus haut-gauche du contour, donc un vrai
# angle : l'ancrage ne coupe pas un côté en son milieu.
static func _simplifier(points: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var garder := PackedByteArray()
	garder.resize(n)
	garder[0] = 1
	garder[n - 1] = 1
	var pile: Array = [Vector2i(0, n - 1)]
	while not pile.is_empty():
		var seg: Vector2i = pile.pop_back()
		var a := points[seg.x]
		var b := points[seg.y]
		var pire := 0.0
		var idx := -1
		for i in range(seg.x + 1, seg.y):
			var d := _distance_segment(points[i], a, b)
			if d > pire:
				pire = d
				idx = i
		if idx >= 0 and pire > eps:
			garder[idx] = 1
			pile.append(Vector2i(seg.x, idx))
			pile.append(Vector2i(idx, seg.y))
	var sortie := PackedVector2Array()
	for i in n:
		if garder[i] == 1:
			sortie.append(points[i])
	return sortie

static func _distance_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _longueur(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total

func _ecrire(data: NeonsCiteData, total: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
			NeonsCiteData.CHEMIN.get_base_dir()))
	var err := ResourceSaver.save(data, NeonsCiteData.CHEMIN)
	if err != OK:
		push_error("bake_neons_cite : écriture impossible (%d)" % err)
		return
	print("\n-> ", NeonsCiteData.CHEMIN, " ecrit (%d plan(s), %d enseigne(s))"
			% [data.enseignes.size(), total])
