# ============================================================
# ExpeCarte — Génération PROCÉDURALE de la carte d'un étage d'expédition
# (Rework Combat, chantier 2). Modèle free-roam type Dicefolk : graphe
# spatial 2D CONNEXE, déplacement libre le long des arêtes, retour en
# arrière autorisé — pas de DAG à la Slay the Spire.
#
# Algorithme (seedable via le rng fourni) :
#   1. N ∈ [noeuds_min ; noeuds_max] positions tirées par REJET (distance
#      minimale) dans un rectangle LARGEUR×HAUTEUR.
#   2. Adjacence par triangulation de Delaunay (arêtes planaires naturelles),
#      puis ÉLAGAGE aléatoire : chaque arête candidate n'est retirée que si
#      le graphe RESTE connexe → connexité garantie par construction.
#   3. Entrée = nœud le plus à GAUCHE, Fin d'étage = le plus à DROITE
#      (destination lointaine, visible d'emblée — le joueur peut foncer).
#   4. Types des nœuds intérieurs : tirage pondéré par nœud
#      (poids_combat / poids_mystere / poids_coffre du .tres de config).
#
# Toutes les valeurs de génération vivent dans ExpeCarteConfigData
# (data/expedition/config_carte.tres) — aucune valeur d'équilibrage en dur.
# ============================================================
class_name ExpeCarte
extends RefCounted

# Dimensions du rectangle de génération (layout abstrait, PAS de l'équilibrage
# — le rendu met à l'échelle librement).
const LARGEUR := 10.0
const HAUTEUR := 6.0

var noeuds: Array[ExpeNoeud] = []
var entree_id := 0
var fin_id := 0

# Génère la carte d'UN étage. `rng` est fourni par l'appelant (seedable →
# génération reproductible, testée).
static func generer(cfg: ExpeCarteConfigData, rng: RandomNumberGenerator) -> ExpeCarte:
	var carte := ExpeCarte.new()
	var n := rng.randi_range(cfg.noeuds_min, cfg.noeuds_max)
	var pts := _positions(n, cfg.distance_min_noeuds, rng)
	var aretes := _aretes_delaunay(pts)
	aretes = _elaguer(aretes, pts.size(), cfg.elagage_aretes, rng)

	# Entrée / Fin : extrémités horizontales de l'étage.
	var entree := 0
	var fin := 0
	for i in pts.size():
		if pts[i].x < pts[entree].x:
			entree = i
		if pts[i].x > pts[fin].x:
			fin = i

	for i in pts.size():
		var nd := ExpeNoeud.new()
		nd.id = i
		nd.pos = pts[i]
		if i == entree:
			nd.type = Enums.TypeNoeud.ENTREE
		elif i == fin:
			nd.type = Enums.TypeNoeud.FIN_ETAGE
		else:
			nd.type = _tirer_type(cfg, rng)
		carte.noeuds.append(nd)
	for a: Vector2i in aretes:
		carte.noeuds[a.x].voisins.append(a.y)
		carte.noeuds[a.y].voisins.append(a.x)
	carte.entree_id = entree
	carte.fin_id = fin
	return carte

func noeud(nid: int) -> ExpeNoeud:
	return noeuds[nid]

# Connexité du graphe (BFS depuis l'entrée) — exposée pour les tests.
func est_connexe() -> bool:
	if noeuds.is_empty():
		return false
	var vus := {entree_id: true}
	var pile: Array[int] = [entree_id]
	while not pile.is_empty():
		var cur: int = pile.pop_back()
		for v in noeuds[cur].voisins:
			if not vus.has(v):
				vus[v] = true
				pile.append(v)
	return vus.size() == noeuds.size()

# Empreinte déterministe de la carte (positions, types, arêtes) — sert au
# test de reproductibilité par graine.
func empreinte() -> String:
	var parts: PackedStringArray = []
	for nd in noeuds:
		var vs := nd.voisins.duplicate()
		vs.sort()
		parts.append("%d:%d:(%.3f,%.3f):%s" % [nd.id, nd.type, nd.pos.x, nd.pos.y, str(vs)])
	return "|".join(parts)

# ─── Internes ────────────────────────────────────────────────

# Positions par rejet : distance minimale respectée tant que possible ; si le
# rectangle sature (config extrême), la contrainte se relâche progressivement
# plutôt que de générer moins de nœuds que demandé.
static func _positions(n: int, dist_min: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := dist_min
	var essais := 0
	while pts.size() < n:
		essais += 1
		if essais > 400:   # rectangle saturé → relâche la distance et repart
			d *= 0.8
			essais = 0
		var p := Vector2(rng.randf() * LARGEUR, rng.randf() * HAUTEUR)
		var ok := true
		for q in pts:
			if p.distance_to(q) < d:
				ok = false
				break
		if ok:
			pts.append(p)
	return pts

# Arêtes uniques de la triangulation de Delaunay. Secours (points dégénérés,
# triangulation vide) : chaîne séquentielle — connexe par construction.
static func _aretes_delaunay(pts: PackedVector2Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var vues := {}
	var tris := Geometry2D.triangulate_delaunay(pts)
	if tris.is_empty():
		for i in range(pts.size() - 1):
			out.append(Vector2i(i, i + 1))
		return out
	for t in range(0, tris.size(), 3):
		for e: Vector2i in [Vector2i(tris[t], tris[t + 1]),
				Vector2i(tris[t + 1], tris[t + 2]), Vector2i(tris[t + 2], tris[t])]:
			var k := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
			if not vues.has(k):
				vues[k] = true
				out.append(k)
	return out

# Élagage : dans un ordre mélangé (rng), chaque arête est candidate au retrait
# avec probabilité `proba` — retirée SEULEMENT si le graphe reste connexe.
static func _elaguer(aretes: Array[Vector2i], nb: int, proba: float,
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var ordre := aretes.duplicate()
	for i in range(ordre.size() - 1, 0, -1):   # Fisher-Yates avec le rng seedé
		var j := rng.randi_range(0, i)
		var tmp: Vector2i = ordre[i]
		ordre[i] = ordre[j]
		ordre[j] = tmp
	var restantes := ordre
	for a: Vector2i in ordre.duplicate():
		if rng.randf() >= proba:
			continue
		var sans := restantes.duplicate()
		sans.erase(a)
		if _connexe_avec(sans, nb):
			restantes = sans
	return restantes

static func _connexe_avec(aretes: Array[Vector2i], nb: int) -> bool:
	if nb == 0:
		return false
	var adj := {}
	for a: Vector2i in aretes:
		if not adj.has(a.x):
			adj[a.x] = []
		if not adj.has(a.y):
			adj[a.y] = []
		adj[a.x].append(a.y)
		adj[a.y].append(a.x)
	var vus := {0: true}
	var pile: Array[int] = [0]
	while not pile.is_empty():
		var cur: int = pile.pop_back()
		for v in adj.get(cur, []):
			if not vus.has(v):
				vus[v] = true
				pile.append(v)
	return vus.size() == nb

# Tirage pondéré du type d'un nœud intérieur (poids du .tres).
static func _tirer_type(cfg: ExpeCarteConfigData, rng: RandomNumberGenerator) -> Enums.TypeNoeud:
	var total := cfg.poids_combat + cfg.poids_mystere + cfg.poids_coffre
	var roll := rng.randf() * maxf(total, 0.0001)
	if roll < cfg.poids_combat:
		return Enums.TypeNoeud.COMBAT
	if roll < cfg.poids_combat + cfg.poids_mystere:
		return Enums.TypeNoeud.MYSTERE
	return Enums.TypeNoeud.COFFRE
