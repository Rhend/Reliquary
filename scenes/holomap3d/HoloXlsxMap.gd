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

enum Cell { VIDE, BATIMENT, ROUTE, EAU, PARC }
enum Forme { BOITE, PYRAMIDE, CYLINDRE, DOME, GRADINS }

# Centroïdes de famille (repères d'auteur ; on classe au plus proche).
const _FAMILLES := {
	Cell.BATIMENT: Color8(0x3A, 0x42, 0x53),
	Cell.ROUTE:    Color8(0xD6, 0x24, 0x8F),
	Cell.EAU:      Color8(0x17, 0xC3, 0xC3),
	Cell.PARC:     Color8(0x5E, 0x73, 0x49),
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
var tours_orphelines: Array = []   # codes forme/hauteur posés sur une case NON-bâtiment (cf. 9c sur l'eau)
var sureleve: Array = []    # ouvrages du calque « Surélevé » (VIDE pour l'instant)

# Tables internes du classeur.
var _fills: Array = []       # fillId → Color (ou null)
var _xf_fill: Array = []     # styleIndex (s) → fillId
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

# ─── styles.xml : fills (fillId→rgb) + cellXfs (s→fillId) ──────
func _lire_styles(zip: ZIPReader) -> void:
	_fills.clear()
	_xf_fill.clear()
	var p := _parser(zip, "xl/styles.xml")
	if p == null:
		return
	var dans_fills := false
	var dans_cellxfs := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			match n:
				"fills": dans_fills = true
				"cellXfs": dans_cellxfs = true
				"fgColor":
					if dans_fills:
						_fills[_fills.size() - 1] = _rgb(p.get_named_attribute_value_safe("rgb"))
				"fill":
					if dans_fills:
						_fills.append(null)   # rempli si un fgColor suit
				"xf":
					if dans_cellxfs:
						var fid := -1
						if p.has_attribute("fillId"):
							fid = int(p.get_named_attribute_value("fillId"))
						_xf_fill.append(fid)
		elif t == XMLParser.NODE_ELEMENT_END:
			match p.get_node_name():
				"fills": dans_fills = false
				"cellXfs": dans_cellxfs = false

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
	var chemin := _chemin_feuille("Carte")
	if chemin == "":
		return
	_lire_grille(zip, chemin, type_case, texte_case)

# Parse une feuille-grille : remplit type[Vector2i]→Cell et texte[Vector2i]→String.
# Coordonnées de données 0-based : B2 → (0,0), BI61 → (59,59) (ligne 1 / colonne A
# = en-têtes de coordonnées, ignorées).
func _lire_grille(zip: ZIPReader, chemin: String, dico_type: Dictionary, dico_texte: Dictionary) -> void:
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

# ─── Surélevé : prêt mais ne produit rien tant que c'est vide ─
func _lire_sureleve(zip: ZIPReader) -> void:
	sureleve.clear()
	var chemin := _chemin_feuille("Surélevé")
	if chemin == "":
		return
	var dico_type := {}
	var dico_texte := {}
	_lire_grille(zip, chemin, dico_type, dico_texte)
	# Cases peintes (non vides) → ouvrages surélevés, altitude = chiffre de la case.
	for cell: Vector2i in dico_type:
		if dico_type[cell] == Cell.VIDE:
			continue
		var h := hauteur_defaut_m
		var f := Forme.BOITE
		if dico_texte.has(cell):
			var hf := _parse_hauteur_forme(dico_texte[cell])
			if hf.x > 0.0:
				h = hf.x
			f = int(hf.y)
		sureleve.append({"cell": cell, "type": dico_type[cell], "altitude_m": h, "forme": f})

# ─── Regroupement des cases en éléments ───────────────────────
func _regrouper_batiments() -> void:
	batiments.clear()
	routes.clear()
	eaux.clear()
	parcs.clear()
	tours_orphelines.clear()
	for cell: Vector2i in type_case:
		match type_case[cell]:
			Cell.ROUTE: routes.append(cell)
			Cell.EAU: eaux.append(cell)
			Cell.PARC: parcs.append(cell)
	# Bâtiments : flood-fill 4-connexe sur l'apparence BATIMENT (couleur seule).
	var vus := {}
	for cell: Vector2i in type_case:
		if type_case[cell] != Cell.BATIMENT or vus.has(cell):
			continue
		var bloc := _flood(cell, vus)
		batiments.append(_finaliser_bloc(bloc))
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
		pile.append(c + Vector2i(1, 0))
		pile.append(c + Vector2i(-1, 0))
		pile.append(c + Vector2i(0, 1))
		pile.append(c + Vector2i(0, -1))
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
	return "grille=%d case=%.0fm h_defaut=%.0fm | bâtiments=%d routes=%d eau=%d parc=%d tours=%d surélevé=%d" % [
		grille, taille_case_m, hauteur_defaut_m,
		batiments.size(), routes.size(), eaux.size(), parcs.size(),
		tours_orphelines.size(), sureleve.size()]
