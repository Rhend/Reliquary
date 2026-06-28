extends Node
# ============================================================
# TestHoloXlsx — Valide le lecteur runtime du gabarit Excel (HoloXlsxMap) sur
# res://Carte Holo/carte_holomap.xlsx :
#   • Paramètres lus DEPUIS la feuille (grille / taille de case / hauteur défaut),
#   • apparences classées par couleur de FOND (bâtiment / eau …),
#   • bâtiments regroupés par couleur (adjacence 4-connexe),
#   • formes lues (pyramide 12 m, gradins 12 m, cylindre 9 m « 9c » sur l'eau),
#   • feuilles vides (Surélevé) → ne produisent rien.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

var _fail: Array[String] = []

func _ready() -> void:
	print("\n=== TEST LECTEUR GABARIT EXCEL (HoloXlsxMap) ===\n")
	var m := HoloXlsxMap.new()
	_ok("charger", m.charger("res://Carte Holo/carte_holomap.xlsx"))
	# Paramètres lus depuis la feuille (pas en dur).
	_eq("grille", m.grille, 60)
	_eqf("taille_case_m", m.taille_case_m, 10.0)
	_eqf("hauteur_defaut_m", m.hauteur_defaut_m, 3.0)
	# Apparence par couleur de fond.
	_eq("apparence 12p = bâtiment", m.type_case.get(Vector2i(29, 29), -1), HoloXlsxMap.Cell.BATIMENT)
	_eq("apparence 12g = bâtiment", m.type_case.get(Vector2i(30, 35), -1), HoloXlsxMap.Cell.BATIMENT)
	_eq("apparence 9c = eau", m.type_case.get(Vector2i(44, 6), -1), HoloXlsxMap.Cell.EAU)
	# Regroupement des bâtiments (la carte évolue → on vérifie ≥ 8, pas un compte exact).
	_ok("bâtiments lus (>= 8)", m.batiments.size() >= 8)
	# Séparation par BORDURE : des cases encadrées (medium) deviennent des bâtiments
	# 1×1 distincts avec LEUR hauteur (régression du bug de fusion).
	_ok("bordure → bâtiment 1×1 à sa hauteur (19,20 = 9 m)", _bati_unitaire(m, Vector2i(19, 20), 9.0))
	_ok("bordure → bâtiment 1×1 à sa hauteur (17,20 = 4 m)", _bati_unitaire(m, Vector2i(17, 20), 4.0))
	# Formes lues (le texte d'une case donne hauteur + forme du bloc).
	_ok("pyramide 12 m présente", _a_forme(m, HoloXlsxMap.Forme.PYRAMIDE, 12.0))
	_ok("gradins 12 m présent", _a_forme(m, HoloXlsxMap.Forme.GRADINS, 12.0))
	# « 9c » est posé sur l'eau → tour orpheline cylindre 9 m (cf. chantier).
	_ok("tour(s) orpheline(s) lue(s)", m.tours_orphelines.size() >= 1)
	_ok("cylindre 9 m (tour)", _a_tour(m, HoloXlsxMap.Forme.CYLINDRE, 9.0))
	# La tour se centre sur le plan d'eau : son rectangle (bassin du lac) contient la
	# case « 9c » et fait au moins 3x3 (≠ la seule case du texte).
	var rect := Rect2i()
	for t in m.tours_orphelines:
		if (t["rect"] as Rect2i).has_point(Vector2i(44, 6)):
			rect = t["rect"]
	print("    (rect tour 9c = %s)" % str(rect))
	_ok("tour centrée sur le bassin (rect contient 9c, >= 3x3)",
			rect.has_point(Vector2i(44, 6)) and rect.size.x >= 3 and rect.size.y >= 3)
	# Décor au sol présent.
	_ok("routes peintes", m.routes.size() > 0)
	_ok("eau peinte", m.eaux.size() > 0)
	_ok("parcs peints", m.parcs.size() > 0)
	# Nouvelles familles (peintes sur la carte réelle) : classées + regroupées en blocs.
	_ok("colline (ruban de bordure) lue (> 0)", m.collines.size() > 0)
	_ok("usine(s) lue(s) (>= 1)", m.usines.size() >= 1)
	_ok("casse(s) auto lue(s) (>= 1)", m.casses.size() >= 1)
	_ok("supermarché(s) lu(s) (>= 1)", m.supermarches.size() >= 1)
	_ok("cimetière(s) lu(s) (>= 1)", m.cimetieres.size() >= 1)
	# Classification par famille de couleur (nearest-match) — y compris la distinction
	# ambre (supermarché) / ocre (colline) / sable (sport), proches mais distincts.
	_eq("classe 6B7A8F → cimetière", _classe(Color8(0x6B, 0x7A, 0x8F)), HoloXlsxMap.Cell.CIMETIERE)
	_eq("classe 8B5E3C → usine", _classe(Color8(0x8B, 0x5E, 0x3C)), HoloXlsxMap.Cell.USINE)
	_eq("classe B0560F → casse", _classe(Color8(0xB0, 0x56, 0x0F)), HoloXlsxMap.Cell.CASSE)
	_eq("classe E8A23D → supermarché", _classe(Color8(0xE8, 0xA2, 0x3D)), HoloXlsxMap.Cell.SUPERMARCHE)
	_eq("classe C8A86A → colline", _classe(Color8(0xC8, 0xA8, 0x6A)), HoloXlsxMap.Cell.COLLINE)
	_eq("classe D2B48C → sport", _classe(Color8(0xD2, 0xB4, 0x8C)), HoloXlsxMap.Cell.SPORT)
	_eq("classe B5B5B8 = parking", _classe(Color8(0xB5, 0xB5, 0xB8)), HoloXlsxMap.Cell.PARKING)
	_eq("classe 3A4253 = batiment (pas parking)", _classe(Color8(0x3A, 0x42, 0x53)), HoloXlsxMap.Cell.BATIMENT)
	# Bloc ceinturé (rendu : groupe entouré d'une bordure épaisse = bâtiment plein).
	var me := HoloXlsxMap.new()
	me.border_case = {Vector2i(0, 0): 15}   # 15 = murs sur les 4 côtés
	_ok("bloc_enclos : case ceinturée = oui", me.bloc_enclos([Vector2i(0, 0)]))
	var me2 := HoloXlsxMap.new()
	_ok("bloc_enclos : 2 cases nues = non", not me2.bloc_enclos([Vector2i(0, 0), Vector2i(1, 0)]))
	# Calque Surélevé : ponts (gris acier) à faible altitude, sans piliers (Ouvrages
	# = exemples génériques → ignorés). Pas de route surélevée.
	_ok("ponts lus (>= 1)", m.ponts.size() >= 1)
	_ok("ponts à altitude faible (1-4 m)", _ponts_altitude_faible(m, 4.0))
	_ok("ponts sans piliers (Ouvrages ignoré)", _aucun_pilier(m))
	_eq("routes surélevées", m.routes_elevees.size(), 0)

	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % _fail.size())
	for f in _fail:
		print("  ✗ " + f)
	if _fail.is_empty():
		print("  ✓ lecteur Excel conforme")
	print("════════════════════════════════\n")
	get_tree().quit(0 if _fail.is_empty() else 1)

# Classe une couleur de fond isolée → Cell (teste les centroïdes de famille sans fichier).
func _classe(col: Color) -> int:
	var m := HoloXlsxMap.new()
	m._fills = [col]
	return m._classer(0)

func _bati_unitaire(m: HoloXlsxMap, cell: Vector2i, hauteur: float) -> bool:
	for b in m.batiments:
		var cells: Array = b["cells"]
		if cells.size() == 1 and cells[0] == cell and is_equal_approx(b["hauteur_m"], hauteur):
			return true
	return false

func _a_forme(m: HoloXlsxMap, forme: int, hauteur: float) -> bool:
	for b in m.batiments:
		if int(b["forme"]) == forme and is_equal_approx(b["hauteur_m"], hauteur):
			return true
	return false

func _a_tour(m: HoloXlsxMap, forme: int, hauteur: float) -> bool:
	for t in m.tours_orphelines:
		if int(t["forme"]) == forme and is_equal_approx(t["hauteur_m"], hauteur):
			return true
	return false

func _ponts_altitude_faible(m: HoloXlsxMap, maxi_m: float) -> bool:
	for p in m.ponts:
		if p["altitude_m"] < 0.5 or p["altitude_m"] > maxi_m:
			return false
	return not m.ponts.is_empty()

func _aucun_pilier(m: HoloXlsxMap) -> bool:
	for p in m.ponts:
		if p["piliers"]:
			return false
	return true

func _ok(nom: String, cond: bool) -> void:
	print(("  ✓ " if cond else "  ✗ ") + nom)
	if not cond:
		_fail.append(nom)

func _eq(nom: String, got: int, want: int) -> void:
	_ok("%s (=%d, attendu %d)" % [nom, got, want], got == want)

func _eqf(nom: String, got: float, want: float) -> void:
	_ok("%s (=%.2f, attendu %.2f)" % [nom, got, want], is_equal_approx(got, want))
