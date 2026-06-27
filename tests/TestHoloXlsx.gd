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
	# Regroupement par couleur seule → 11 bâtiments (les routes séparent les blocs).
	_eq("nb bâtiments", m.batiments.size(), 11)
	# Formes lues (le texte d'une case donne hauteur + forme du bloc).
	_ok("pyramide 12 m présente", _a_forme(m, HoloXlsxMap.Forme.PYRAMIDE, 12.0))
	_ok("gradins 12 m présent", _a_forme(m, HoloXlsxMap.Forme.GRADINS, 12.0))
	# « 9c » est posé sur l'eau → tour orpheline cylindre 9 m (cf. chantier).
	_eq("nb tours orphelines", m.tours_orphelines.size(), 1)
	_ok("cylindre 9 m (tour)", _a_tour(m, HoloXlsxMap.Forme.CYLINDRE, 9.0))
	# Décor au sol présent.
	_ok("routes peintes", m.routes.size() > 0)
	_ok("eau peinte", m.eaux.size() > 0)
	_ok("parcs peints", m.parcs.size() > 0)
	# Feuille Surélevé vide → aucun ouvrage produit.
	_ok("surélevé vide", m.sureleve.is_empty())

	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % _fail.size())
	for f in _fail:
		print("  ✗ " + f)
	if _fail.is_empty():
		print("  ✓ lecteur Excel conforme")
	print("════════════════════════════════\n")
	get_tree().quit(0 if _fail.is_empty() else 1)

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

func _ok(nom: String, cond: bool) -> void:
	print(("  ✓ " if cond else "  ✗ ") + nom)
	if not cond:
		_fail.append(nom)

func _eq(nom: String, got: int, want: int) -> void:
	_ok("%s (=%d, attendu %d)" % [nom, got, want], got == want)

func _eqf(nom: String, got: float, want: float) -> void:
	_ok("%s (=%.2f, attendu %.2f)" % [nom, got, want], is_equal_approx(got, want))
