# ============================================================
# HoloXlsxMap — Lecteur RUNTIME du gabarit Excel de carte (carte_holomap.xlsx).
#
# Un .xlsx est une archive ZIP de XML : on l'ouvre via ZIPReader puis on parse
# les feuilles avec XMLParser (aucune dépendance externe, 100 % Godot). On lit :
#   • « Paramètres » : taille de case (m), hauteur par défaut (m), taille de grille.
#   • « Carte »      : couleur de FOND de chaque case → APPARENCE (bâtiment / route /
#                      eau / parc / vide) ; texte de la case → hauteur (m) + forme.
#   • « Surélevé »   : même grille, ouvrages en hauteur (VIDE dans ce fichier — le
#                      code de lecture est prêt mais ne produit rien tant que c'est vide).
#
# L'APPARENCE est lue par FAMILLE DE COULEUR (nearest-match sur le RGB de remplissage
# réellement présent dans styles.xml) : la teinte exacte peut varier, l'auteur peut
# la changer. Les BORDURES sont IGNORÉES (canal lieux/tier pas encore fiable — cf.
# chantier) : tout est du décor, regroupé par couleur de fond uniquement.
#
# Les bâtiments sont regroupés par adjacence 4-connexe de même apparence ; chaque
# bloc reçoit la hauteur/forme tapée sur l'une de ses cases (max si plusieurs).
#
# Rien n'est codé en dur : grille, échelle et hauteur par défaut viennent de la
# feuille « Paramètres ».
# ============================================================
class_name HoloXlsxMap
extends RefCounted

enum Cell { VIDE, BATIMENT, ROUTE, EAU, PARC, PONT, SPORT,
	CIMETIERE, USINE, CASSE, SUPERMARCHE, COLLINE }
enum Forme { BOITE, PYRAMIDE, CYLINDRE, DOME, GRADINS }

const ALTITUDE_PONT_DEFAUT := 3.0   # m, si aucune altitude tapée (faible : décolle le tablier)

# Centroïdes de famille (repères d'auteur ; on classe au plus proche). Le gris
# acier (PONT) n'apparaît que sur le calque Surélevé (jamais sur la Carte).
const _FAMILLES := {
	Cell.BATIMENT:    Color8(0x3A, 0x42, 0x53),
	Cell.ROUTE:       Color8(0xD6, 0x24, 0x8F),
	Cell.EAU:         Color8(0x17, 0xC3, 0xC3),
	Cell.PARC:        Color8(0x5E, 0x73, 0x49),
	Cell.PONT:        Color8(0x9F, 0xB2, 0xC4),
	Cell.SPORT:       Color8(0xD2, 0xB4, 0x8C),   # sable/tan → terrain de sport (baseball)
	Cell.CIMETIERE:   Color8(0x6B, 0x7A, 0x8F),   # gris-ardoise bleuté → mémorial numérique
	Cell.USINE:       Color8(0x8B, 0x5E, 0x3C),   # brun rouille → usine désaffectée
	Cell.CASSE:       Color8(0xB0, 0x56, 0x0F),   # orange-rouille foncé → casse auto
	Cell.SUPERMARCHE: Color8(0xE8, 0xA2, 0x3D),   # ambre → hypermarché (distinct du sable sport)
	Cell.COLLINE:     Color8(0xC8, 0xA8, 0x6A),   # ocre/sable terne → relief de bordure (colline/désert)
}
# Familles « non-carte » → VIDE (fonds neutres du gabarit).
const _NEUTRES := [
	Color8(0xFF, 0xFF, 0xFF),  # blanc
	Color8(0x14, 0x14, 0x1C),  # sombre (fond carte)
	Color8(0x1E, 0x1E, 0x28),  # sombre (bandeaux)
	Color8(0xFF, 0xF7, 0xD6),  # jaune (cellules éditables Paramètres)
]

# ─── Sorties (remplies par charger()) ─────────────────────────
var ok := false
var grille := 60
var taille_case_m := 10.0
var hauteur_defaut_m := 3.0

var type_case := {}     # Vector2i(gx,gy) → Cell
var texte_case := {}    # Vector2i(gx,gy) → String (texte brut, cases peintes)

var batiments: Array = []   # [{cells:Array[Vector2i], bbox:Rect2i, hauteur_m:float, forme:Forme, source_eau:bool}]
var routes: Array = []      # Array[Vector2i]
var eaux: Array = []        # Array[Vector2i]
var parcs: Array = []       # Array[Vector2i]
var terrains: Array = []    # terrains de sport (baseball) : [{cells, bbox}]
# Familles bâties spécialisées : mêmes blocs que les bâtiments (cells, bbox,
# hauteur_m, forme), séparés par les bordures medium → un bloc = une parcelle.
var cimetieres: Array = []  # mémorial numérique (champ de stèles)
var usines: Array = []      # usine désaffectée (hall industriel bas et large)
var casses: Array = []      # casse auto (enclos plat + épaves)
var supermarches: Array = [] # hypermarché (volume bas étalé + enseignes)
var collines: Array = []    # relief de bordure : Array[Vector2i] (cases ocre)
var tours_orphelines: Array = []   # codes forme/hauteur posés sur une case NON-bâtiment (cf. 9c sur l'eau)
var ponts: Array = []       # calque « Surélevé » : {cells, bbox, altitude_m, piliers}
var routes_elevees: Array = []   # calque « Surélevé » : cases ROUTE magenta (autoroutes surélevées)

# Tables internes du classeur.
var _fills: Array = []       # fillId → Color (ou null)
var _xf_fill: Array = []     # styleIndex (s) → fillId
var _xf_border: Array = []   # styleIndex (s) → borderId
var _borders: Array = []     # borderId → masque de MURS (L=1 R=2 T=4 B=8 ; bordure medium/thick)
var border_case := {}        # Vector2i → masque de murs (cases de la Carte, séparateurs)
var _strings: Array = []     # sharedStrings
var _feuilles := {}          # nom de feuille → chemin xml interne

# ─── Chargement ───────────────────────────────────────────────
func charger(chemin: String) -> bool:
	ok = false
	var zip := ZIPReader.new()
	if zip.open(chemin) != OK:
		push_warning("[HoloXlsxMap] impossible d'ouvrir : %s" % chemin)
		return false
	_lire_styles(zip)
	_lire_strings(zip)
	_lire_workbook(zip)
	if not _lire_parametres(zip):
		push_warning("[HoloXlsxMap] feuille Paramètres illisible")
	_lire_carte(zip)
	_lire_sureleve(zip)
	zip.close()
	_regrouper_batiments()
	ok = true
	return true

# ─── styles.xml : fills (s→rgb), cellXfs (s→fillId/borderId), borders (murs) ──
func _lire_styles(zip: ZIPReader) -> void:
	_fills.clear()
	_xf_fill.clear()
	_xf_border.clear()
	_borders.clear()
	var p := _parser(zip, "xl/styles.xml")
	if p == null:
		return
	var dans_fills := false
	var dans_cellxfs := false
	var dans_borders := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			match n:
				"fills": dans_fills = true
				"cellXfs": dans_cellxfs = true
				"borders": dans_borders = true
				"fgColor":
					if dans_fills:
						_fills[_fills.size() - 1] = _rgb(p.get_named_attribute_value_safe("rgb"))
				"fill":
					if dans_fills:
						_fills.append(null)   # rempli si un fgColor suit
				"border":
					if dans_borders:
						_borders.append(0)
				"left", "right", "top", "bottom":
					if dans_borders and not _borders.is_empty() \
							and _est_mur_style(p.get_named_attribute_value_safe("style")):
						_borders[_borders.size() - 1] |= _bit_cote(n)
				"xf":
					if dans_cellxfs:
						var fid := -1
						if p.has_attribute("fillId"):
							fid = int(p.get_named_attribute_value("fillId"))
						_xf_fill.append(fid)
						var bid := 0
						if p.has_attribute("borderId"):
							bid = int(p.get_named_attribute_value("borderId"))
						_xf_border.append(bid)
		elif t == XMLParser.NODE_ELEMENT_END:
			match p.get_node_name():
				"fills": dans_fills = false
				"cellXfs": dans_cellxfs = false
				"borders": dans_borders = false

# Bordure de SÉPARATION volontaire (≠ fin quadrillage décoratif « thin »/« hair »).
func _est_mur_style(st: String) -> bool:
	return st == "medium" or st == "thick" or st == "double" or st.begins_with("medium")

func _bit_cote(cote: String) -> int:
	match cote:
		"left": return 1
		"right": return 2
		"top": return 4
		_: return 8   # bottom

# « FFRRGGBB » (ARGB) → Color. Renvoie null si vide/illisible.
func _rgb(hex: String) -> Variant:
	if hex.length() < 6:
		return null
	var h := hex.substr(hex.length() - 6, 6)   # ignore l'alpha de tête
	return Color.from_string("#" + h, Color.MAGENTA)

# ─── sharedStrings.xml : table de chaînes partagées ───────────
func _lire_strings(zip: ZIPReader) -> void:
	_strings.clear()
	var p := _parser(zip, "xl/sharedStrings.xml")
	if p == null:
		return
	var courant := ""
	var dans_si := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT and p.get_node_name() == "si":
			dans_si = true
			courant = ""
		elif t == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "si":
			_strings.append(courant)
			dans_si = false
		elif t == XMLParser.NODE_TEXT and dans_si:
			courant += p.get_node_data()

# ─── workbook.xml + rels : nom de feuille → fichier xml ───────
func _lire_workbook(zip: ZIPReader) -> void:
	_feuilles.clear()
	# rId → cible (worksheets/sheetN.xml)
	var rels := {}
	var pr := _parser(zip, "xl/_rels/workbook.xml.rels")
	if pr != null:
		while pr.read() == OK:
			if pr.get_node_type() == XMLParser.NODE_ELEMENT and pr.get_node_name() == "Relationship":
				rels[pr.get_named_attribute_value_safe("Id")] = pr.get_named_attribute_value_safe("Target")
	# nom de feuille → rId
	var pw := _parser(zip, "xl/workbook.xml")
	if pw != null:
		while pw.read() == OK:
			if pw.get_node_type() == XMLParser.NODE_ELEMENT and pw.get_node_name() == "sheet":
				var nom := pw.get_named_attribute_value_safe("name")
				var rid := pw.get_named_attribute_value_safe("r:id")
				var cible: String = rels.get(rid, "")
				if cible != "":
					if not cible.begins_with("xl/"):
						cible = "xl/" + cible
					_feuilles[nom] = cible

func _chemin_feuille(nom: String) -> String:
	return _feuilles.get(nom, "")

# ─── Paramètres : lit B4 / B5 / B6 (valeurs éditables) ────────
func _lire_parametres(zip: ZIPReader) -> bool:
	var chemin := _chemin_feuille("Paramètres")
	if chemin == "":
		return false
	var vals := _valeurs_cellules(zip, chemin)
	if vals.has("B4"): taille_case_m = float(vals["B4"])
	if vals.has("B5"): hauteur_defaut_m = float(vals["B5"])
	if vals.has("B6"): grille = int(vals["B6"])
	return true

# Lit toutes les cellules (ref → texte) d'une feuille simple.
func _valeurs_cellules(zip: ZIPReader, chemin: String) -> Dictionary:
	var out := {}
	var p := _parser(zip, chemin)
	if p == null:
		return out
	var ref := ""
	var est_str := false
	var lire_v := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			match p.get_node_name():
				"c":
					ref = p.get_named_attribute_value_safe("r")
					est_str = p.has_attribute("t") and p.get_named_attribute_value("t") == "s"
				"v":
					lire_v = true
		elif t == XMLParser.NODE_TEXT and lire_v:
			var v := p.get_node_data()
			out[ref] = _strings[int(v)] if (est_str and int(v) < _strings.size()) else v
			lire_v = false
		elif t == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "v":
			lire_v = false
	return out

# ─── Carte : fond → apparence, texte → hauteur/forme ──────────
func _lire_carte(zip: ZIPReader) -> void:
	type_case.clear()
	texte_case.clear()
	border_case.clear()
	var chemin := _chemin_feuille("Carte")
	if chemin == "":
		return
	_lire_grille(zip, chemin, type_case, texte_case, border_case)

# Parse une feuille-grille : remplit type[Vector2i]→Cell et texte[Vector2i]→String.
# Coordonnées de données 0-based : B2 → (0,0), BI61 → (59,59) (ligne 1 / colonne A
# = en-têtes de coordonnées, ignorées).
func _lire_grille(zip: ZIPReader, chemin: String, dico_type: Dictionary, dico_texte: Dictionary,
		dico_border: Dictionary = {}) -> void:
	var p := _parser(zip, chemin)
	if p == null:
		return
	var col := 0
	var ligne := 0
	var fill := -1
	var est_str := false
	var lire_v := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			match p.get_node_name():
				"c":
					var ref := p.get_named_attribute_value_safe("r")
					var rc := _ref_vers_rc(ref)
					col = rc.x
					ligne = rc.y
					var s := 0
					if p.has_attribute("s"):
						s = int(p.get_named_attribute_value("s"))
					fill = _xf_fill[s] if s >= 0 and s < _xf_fill.size() else -1
					est_str = p.has_attribute("t") and p.get_named_attribute_value("t") == "s"
					# Classe l'apparence dès l'ouverture (le texte arrivera via <v>).
					var gx := col - 2
					var gy := ligne - 2
					if gx >= 0 and gy >= 0 and gx < grille and gy < grille:
						dico_type[Vector2i(gx, gy)] = _classer(fill)
						var bid: int = int(_xf_border[s]) if s >= 0 and s < _xf_border.size() else 0
						if bid > 0 and bid < _borders.size() and int(_borders[bid]) != 0:
							dico_border[Vector2i(gx, gy)] = int(_borders[bid])
				"v":
					lire_v = true
		elif t == XMLParser.NODE_TEXT and lire_v:
			var gx := col - 2
			var gy := ligne - 2
			if gx >= 0 and gy >= 0 and gx < grille and gy < grille:
				var v := p.get_node_data()
				var txt: String = _strings[int(v)] if (est_str and int(v) < _strings.size()) else v
				if txt.strip_edges() != "":
					dico_texte[Vector2i(gx, gy)] = txt.strip_edges()
			lire_v = false
		elif t == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "v":
			lire_v = false

# ─── Surélevé : ponts (gris acier) + routes surélevées (magenta) ──
# Même grille que « Carte ». On superpose au sol (l'eau/route reste visible
# dessous, l'ouvrage est généré par-dessus à son altitude).
func _lire_sureleve(zip: ZIPReader) -> void:
	ponts.clear()
	routes_elevees.clear()
	var chemin := _chemin_feuille("Surélevé")
	if chemin == "":
		return
	var dico_type := {}
	var dico_texte := {}
	var dico_border := {}
	_lire_grille(zip, chemin, dico_type, dico_texte, dico_border)
	# Routes magenta surélevées (autoroutes) — distinctes des ponts.
	for cell: Vector2i in dico_type:
		if dico_type[cell] == Cell.ROUTE:
			routes_elevees.append(cell)
	# Ponts (gris acier) regroupés par adjacence 4-connexe (séparés par les bordures).
	var vus := {}
	for cell: Vector2i in dico_type:
		if dico_type[cell] != Cell.PONT or vus.has(cell):
			continue
		var bloc := _flood_type(cell, dico_type, Cell.PONT, vus, dico_border)
		ponts.append(_finaliser_pont(bloc, dico_texte))
	# Piliers : affinés depuis « Ouvrages d'art » (optionnel ; sinon sans piliers).
	_appliquer_ouvrages(zip)

# Flood-fill 4-connexe d'un bloc de type `t` dans `dico`, SANS franchir un mur
# (bordure medium/thick). Marque dans `vus`.
func _flood_type(depart: Vector2i, dico: Dictionary, t: int, vus: Dictionary, bord: Dictionary = {}) -> Array:
	var bloc: Array = []
	var pile: Array = [depart]
	while not pile.is_empty():
		var c: Vector2i = pile.pop_back()
		if vus.has(c) or dico.get(c, Cell.VIDE) != t:
			continue
		vus[c] = true
		bloc.append(c)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _mur(c, d, bord):
				pile.append(c + d)
	return bloc

# Y a-t-il un MUR (bordure de séparation) entre la case `a` et sa voisine `a+d` ?
# Bits : L=1 R=2 T=4 B=8. Le mur peut être posé sur l'une OU l'autre des deux cases.
func _mur(a: Vector2i, d: Vector2i, bord: Dictionary) -> bool:
	var wa: int = bord.get(a, 0)
	var wb: int = bord.get(a + d, 0)
	if d.x == 1:
		return (wa & 2) != 0 or (wb & 1) != 0
	if d.x == -1:
		return (wa & 1) != 0 or (wb & 2) != 0
	if d.y == 1:
		return (wa & 8) != 0 or (wb & 4) != 0
	return (wa & 4) != 0 or (wb & 8) != 0

# Bloc-pont : bbox + altitude (max des textes du bloc, défaut faible).
func _finaliser_pont(cells: Array, dico_texte: Dictionary) -> Dictionary:
	var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
	var alt := 0.0
	for c: Vector2i in cells:
		minx = mini(minx, c.x); miny = mini(miny, c.y)
		maxx = maxi(maxx, c.x); maxy = maxi(maxy, c.y)
		if dico_texte.has(c):
			var hf := _parse_hauteur_forme(dico_texte[c])
			if hf.x > alt:
				alt = hf.x
	if alt <= 0.0:
		alt = ALTITUDE_PONT_DEFAUT
	return {
		"cells": cells,
		"bbox": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1),
		"altitude_m": alt,
		"piliers": false,
	}

# « Ouvrages d'art » (optionnel) : une ligne « Pont… » avec Piliers=Oui active les
# piliers du pont dont la bbox contient le début du tracé. Les exemples par défaut
# (Autoroute/Passerelle) ne contiennent pas « pont » → ignorés.
func _appliquer_ouvrages(zip: ZIPReader) -> void:
	if ponts.is_empty():
		return
	var chemin := _chemin_feuille("Ouvrages d'art")
	if chemin == "":
		return
	var vals := _valeurs_cellules(zip, chemin)   # B=Type, C=Tracé, F=Piliers
	for ligne in range(2, 60):
		var typ := str(vals.get("B%d" % ligne, "")).to_lower()
		if not typ.contains("pont"):
			continue
		var piliers := str(vals.get("F%d" % ligne, "")).strip_edges().to_lower() == "oui"
		var debut := _parse_trace_debut(str(vals.get("C%d" % ligne, "")))
		for p in ponts:
			if (p["bbox"] as Rect2i).has_point(debut):
				p["piliers"] = piliers

# Début d'un tracé « 12x05 → 12x55 » → Vector2i(gx, gy) (0-based, L=ligne/C=colonne).
func _parse_trace_debut(trace: String) -> Vector2i:
	for tok in trace.split(" "):
		var t := tok.strip_edges().to_lower()
		if t.contains("x"):
			var p := t.split("x")
			if p.size() >= 2 and p[0].is_valid_int() and p[1].is_valid_int():
				return Vector2i(int(p[1]) - 1, int(p[0]) - 1)
	return Vector2i(-999, -999)

# ─── Regroupement des cases en éléments ───────────────────────
func _regrouper_batiments() -> void:
	batiments.clear()
	routes.clear()
	eaux.clear()
	parcs.clear()
	terrains.clear()
	collines.clear()
	tours_orphelines.clear()
	for cell: Vector2i in type_case:
		match type_case[cell]:
			Cell.ROUTE: routes.append(cell)
			Cell.EAU: eaux.append(cell)
			Cell.PARC: parcs.append(cell)
			Cell.COLLINE: collines.append(cell)
	# Bâtiments : flood-fill 4-connexe sur l'apparence BATIMENT, séparés par les
	# bordures medium/thick (cf. _mur) → on peut encadrer une case pour l'isoler.
	var vus := {}
	for cell: Vector2i in type_case:
		if type_case[cell] != Cell.BATIMENT or vus.has(cell):
			continue
		var bloc := _flood(cell, vus)
		batiments.append(_finaliser_bloc(bloc))
	# Terrains de sport (sable/tan) : flood-fill 4-connexe → un terrain par bloc.
	var vus_sp := {}
	for cell: Vector2i in type_case:
		if type_case[cell] != Cell.SPORT or vus_sp.has(cell):
			continue
		var bloc := _flood_type(cell, type_case, Cell.SPORT, vus_sp, border_case)
		var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
		for c: Vector2i in bloc:
			minx = mini(minx, c.x); miny = mini(miny, c.y)
			maxx = maxi(maxx, c.x); maxy = maxi(maxy, c.y)
		terrains.append({"cells": bloc, "bbox": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)})
	# Familles bâties spécialisées : chaque bloc 4-connexe (séparé par les bordures
	# medium/thick) = une parcelle, avec sa bbox + hauteur/forme tapées. Le rendu de
	# chaque famille est dédié (cf. HoloMap3D), mais le regroupement est identique.
	cimetieres = _blocs_famille(Cell.CIMETIERE)
	usines = _blocs_famille(Cell.USINE)
	casses = _blocs_famille(Cell.CASSE)
	supermarches = _blocs_famille(Cell.SUPERMARCHE)
	# Codes posés sur une case NON-bâtiment (ex. « 9c » sur l'eau) : tour isolée.
	# Le canal apparence reste celui du fond (l'eau garde son shimmer) ; le code
	# ajoute un volume paramétrique compact à cette case (cf. chantier : le
	# cylindre/pyramide/gradins DOIVENT apparaître).
	for cell: Vector2i in texte_case:
		if type_case.get(cell, Cell.VIDE) == Cell.BATIMENT:
			continue
		var hf := _parse_hauteur_forme(texte_case[cell])
		if hf.z > 0.5:   # un code reconnu (hauteur et/ou lettre de forme)
			tours_orphelines.append({
				"cell": cell,
				# Plus grand rectangle de MÊME apparence contenant la case (= le plan
				# d'eau / le bassin) → la tour se centre et se dimensionne dessus.
				"rect": _rect_local(cell, type_case.get(cell, Cell.VIDE)),
				"hauteur_m": (hf.x if hf.x > 0.0 else hauteur_defaut_m),
				"forme": int(hf.y),
			})

# Regroupe une FAMILLE bâtie (cimetière / usine / casse / supermarché) en blocs :
# flood-fill 4-connexe séparé par les bordures medium/thick → un bloc = une parcelle,
# finalisée comme un bâtiment (bbox + hauteur/forme tapées, défaut sinon).
func _blocs_famille(t: int) -> Array:
	var out: Array = []
	var vus := {}
	for cell: Vector2i in type_case:
		if type_case[cell] != t or vus.has(cell):
			continue
		out.append(_finaliser_bloc(_flood_type(cell, type_case, t, vus, border_case)))
	return out

# Flood-fill 4-connexe d'un bloc bâtiment ; marque les cases dans `vus`.
func _flood(depart: Vector2i, vus: Dictionary) -> Array:
	var bloc: Array = []
	var pile: Array = [depart]
	while not pile.is_empty():
		var c: Vector2i = pile.pop_back()
		if vus.has(c) or type_case.get(c, Cell.VIDE) != Cell.BATIMENT:
			continue
		vus[c] = true
		bloc.append(c)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _mur(c, d, border_case):   # une bordure medium/thick sépare deux bâtiments
				pile.append(c + d)
	return bloc

# Calcule bbox + hauteur (max des textes du bloc) + forme (1re lettre trouvée).
func _finaliser_bloc(cells: Array) -> Dictionary:
	var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
	var h := 0.0
	var f := Forme.BOITE
	for c: Vector2i in cells:
		minx = mini(minx, c.x); miny = mini(miny, c.y)
		maxx = maxi(maxx, c.x); maxy = maxi(maxy, c.y)
		if texte_case.has(c):
			var hf := _parse_hauteur_forme(texte_case[c])
			if hf.x > h:
				h = hf.x
			if int(hf.y) != Forme.BOITE:
				f = int(hf.y)
	if h <= 0.0:
		h = hauteur_defaut_m
	return {
		"cells": cells,
		"bbox": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1),
		"hauteur_m": h,
		"forme": f,
		"source_eau": false,
	}

# ─── Helpers ──────────────────────────────────────────────────
# Texte « 12g » / « 6 » / « 18P » / « P » → Vector3(hauteur_m, Forme, reconnu?0/1).
func _parse_hauteur_forme(txt: String) -> Vector3:
	var s := txt.strip_edges().to_upper()
	if s == "":
		return Vector3(0, Forme.BOITE, 0)
	var i := 0
	var num := ""
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		num += s[i]
		i += 1
	var reste := s.substr(i).strip_edges()
	var forme := Forme.BOITE
	var lettre_ok := false
	if reste.length() >= 1:
		match reste[0]:
			"B": forme = Forme.BOITE; lettre_ok = true
			"P": forme = Forme.PYRAMIDE; lettre_ok = true
			"C": forme = Forme.CYLINDRE; lettre_ok = true
			"D": forme = Forme.DOME; lettre_ok = true
			"G": forme = Forme.GRADINS; lettre_ok = true
	var h := float(num) if num != "" else 0.0
	var reconnu := 1.0 if (num != "" or lettre_ok) else 0.0
	return Vector3(h, forme, reconnu)

# Plus grand rectangle de cases de type `t` contenant `seed` (essaie horizontal-
# d'abord et vertical-d'abord, garde la plus grande aire). Sert à centrer une tour
# orpheline sur son plan d'eau (le code « 9c » est posé sur le bassin du lac).
func _rect_local(seed: Vector2i, t: int) -> Rect2i:
	var r1 := _rect_dir(seed, t, true)
	var r2 := _rect_dir(seed, t, false)
	return r1 if r1.get_area() >= r2.get_area() else r2

func _rect_dir(seed: Vector2i, t: int, horiz_dabord: bool) -> Rect2i:
	var x0 := seed.x; var x1 := seed.x; var y0 := seed.y; var y1 := seed.y
	if horiz_dabord:
		while _est_type(x0 - 1, y0, t): x0 -= 1
		while _est_type(x1 + 1, y0, t): x1 += 1
		while _bande_pleine(x0, x1, y0 - 1, t, true): y0 -= 1
		while _bande_pleine(x0, x1, y1 + 1, t, true): y1 += 1
	else:
		while _est_type(x0, y0 - 1, t): y0 -= 1
		while _est_type(x0, y1 + 1, t): y1 += 1
		while _bande_pleine(y0, y1, x0 - 1, t, false): x0 -= 1
		while _bande_pleine(y0, y1, x1 + 1, t, false): x1 += 1
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _est_type(x: int, y: int, t: int) -> bool:
	return type_case.get(Vector2i(x, y), Cell.VIDE) == t

# Toutes les cases de [a..b] sur la ligne/colonne `fixe` sont-elles de type `t` ?
func _bande_pleine(a: int, b: int, fixe: int, t: int, horizontale: bool) -> bool:
	for k in range(a, b + 1):
		var c := Vector2i(k, fixe) if horizontale else Vector2i(fixe, k)
		if type_case.get(c, Cell.VIDE) != t:
			return false
	return true

# Réf cellule « AT8 » → Vector2i(colonne 1-based, ligne 1-based).
func _ref_vers_rc(ref: String) -> Vector2i:
	var c := 0
	var i := 0
	while i < ref.length() and ref[i] >= "A" and ref[i] <= "Z":
		c = c * 26 + (ref.unicode_at(i) - 64)
		i += 1
	var l := int(ref.substr(i))
	return Vector2i(c, l)

# fillId → Cell par famille de couleur la plus proche (robuste aux variations de teinte).
func _classer(fill_id: int) -> int:
	if fill_id < 0 or fill_id >= _fills.size():
		return Cell.VIDE
	var col: Variant = _fills[fill_id]
	if col == null:
		return Cell.VIDE
	var c := col as Color
	var meilleur := Cell.VIDE
	var dmin := 1.0e9
	for cell_type: int in _FAMILLES:
		var d := _dist2(c, _FAMILLES[cell_type])
		if d < dmin:
			dmin = d
			meilleur = cell_type
	for neutre: Color in _NEUTRES:
		var d := _dist2(c, neutre)
		if d < dmin:
			dmin = d
			meilleur = Cell.VIDE
	return meilleur

func _dist2(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db

# Ouvre une entrée du zip dans un XMLParser, ou null si absente.
func _parser(zip: ZIPReader, chemin: String) -> XMLParser:
	if not zip.file_exists(chemin):
		return null
	var bytes := zip.read_file(chemin)
	if bytes.is_empty():
		return null
	var p := XMLParser.new()
	if p.open_buffer(bytes) != OK:
		return null
	return p

# Résumé texte (debug / test headless).
func resume() -> String:
	return ("grille=%d case=%.0fm h_defaut=%.0fm | bâtiments=%d routes=%d eau=%d parc=%d sport=%d " + \
		"cimetière=%d usine=%d casse=%d supermarché=%d colline=%d tours=%d ponts=%d routes_élevées=%d") % [
		grille, taille_case_m, hauteur_defaut_m,
		batiments.size(), routes.size(), eaux.size(), parcs.size(), terrains.size(),
		cimetieres.size(), usines.size(), casses.size(), supermarches.size(), collines.size(),
		tours_orphelines.size(), ponts.size(), routes_elevees.size()]
