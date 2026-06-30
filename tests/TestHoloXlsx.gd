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

	# ── Canal LIEUX (système ID) ──
	# Distinction code hauteur/forme (^\d+[BPCDGX]?$) vs ID de lieu.
	_ok("« 15P » = code hauteur/forme", m._est_code_hauteur_forme("15P"))
	_ok("« 9 » = code", m._est_code_hauteur_forme("9"))
	_ok("« 12G » = code", m._est_code_hauteur_forme("12G"))
	_ok("« P » = code (lettre de forme seule)", m._est_code_hauteur_forme("P"))
	_ok("« biome_marais » ≠ code", not m._est_code_hauteur_forme("biome_marais"))
	_ok("« biome_marais » = ID de lieu", m._est_id_lieu("biome_marais"))
	_ok("« 15P » n'est PAS un ID de lieu", not m._est_id_lieu("15P"))
	_ok("ID ignoré par le parsing hauteur/forme du décor",
			is_equal_approx(m._parse_hauteur_forme("biome_foret").z, 0.0))
	print("    (zones détectées sur le gabarit = %d ; rapport = %d msg)" % [m.zones.size(), m.rapport().size()])
	# Détection : un ID dans une cellule d'un bloc d'apparence → 1 zone (flood bornée par
	# bordure neutre). Carte synthétique : 2×2 cases BATIMENT + un ID dans l'une d'elles.
	var mz := _carte_zone_id()
	mz._detecter_zones()
	_eq("ID dans une cellule → 1 zone détectée", mz.zones.size(), 1)
	_ok("la zone porte l'ID lu", mz.zones.size() > 0 and str(mz.zones[0]["id"]) == "biome_foret")
	_eq("zone = bloc d'apparence (4 cellules)",
			(mz.zones[0]["cells"] as Array).size() if mz.zones.size() > 0 else -1, 4)
	# Une zone SANS ID (que des codes hauteur/forme) → aucun lieu.
	var mo := _carte_zone_id()
	mo.texte_case[Vector2i(3, 3)] = "15P"   # remplace l'ID par un code → décor inerte
	mo._detecter_zones()
	_eq("zone sans ID → 0 lieu", mo.zones.size(), 0)
	# Contour de périmètre (HoloMap3D._perimetre_local) : arêtes externes de la zone.
	var hmap := HoloMap3D.new()
	hmap.grille = 10
	hmap.taille_cellule = 1.0
	var centre := hmap._centre_emprise(5, 5, Vector2i(1, 1))
	_eq("contour 1 cellule → 8 points (4 arêtes)",
			hmap._perimetre_local([Vector2i(5, 5)], centre).size(), 8)
	_eq("contour 2×2 → 16 points (8 arêtes externes, internes exclues)",
			hmap._perimetre_local([Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)],
					centre).size(), 16)
	hmap.free()

	# ── Chantier VERTICALITÉ : nouvelles familles + validation croisée + croix rouges ──
	_test_verticalite()

	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % _fail.size())
	for f in _fail:
		print("  ✗ " + f)
	if _fail.is_empty():
		print("  ✓ lecteur Excel conforme")
	print("════════════════════════════════\n")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ── Chantier verticalité : familles surélevées, exclusion par feuille, validation ──
func _test_verticalite() -> void:
	print("\n  — verticalité (familles surélevées + validation croisée) —")
	# Classification des nouvelles familles (centroïdes, toutes familles confondues).
	_eq("classe 5A5E66 → prison", _classe(Color8(0x5A, 0x5E, 0x66)), HoloXlsxMap.Cell.PRISON)
	_eq("classe 7FD8A0 → passerelle", _classe(Color8(0x7F, 0xD8, 0xA0)), HoloXlsxMap.Cell.PASSERELLE)
	_eq("classe F2D43D → héliport", _classe(Color8(0xF2, 0xD4, 0x3D)), HoloXlsxMap.Cell.HELIPORT)
	_eq("classe BFF0FF → spots", _classe(Color8(0xBF, 0xF0, 0xFF)), HoloXlsxMap.Cell.SPOTS)
	_eq("classe E8843D → téléphérique", _classe(Color8(0xE8, 0x84, 0x3D)), HoloXlsxMap.Cell.TELEPHERIQUE)
	_eq("classe B89CE8 → antenne", _classe(Color8(0xB8, 0x9C, 0xE8)), HoloXlsxMap.Cell.ANTENNE)
	_eq("classe F58FD4 → enseigne", _classe(Color8(0xF5, 0x8F, 0xD4)), HoloXlsxMap.Cell.ENSEIGNE)
	# Exclusion PAR FEUILLE : une couleur surélevé-only (vert passerelle) ne doit PAS
	# être classée sur la CARTE (sinon une case bâtie proche deviendrait un trou).
	var mc := HoloXlsxMap.new()
	mc._fills = [Color8(0x7F, 0xD8, 0xA0)]
	_ok("vert passerelle EXCLU sur Carte (≠ PASSERELLE)",
			mc._classer(0, HoloXlsxMap._SURELEVE_ONLY) != HoloXlsxMap.Cell.PASSERELLE)
	# Et inversement : une couleur Carte-only (ocre colline) exclue sur le Surélevé.
	var ms := HoloXlsxMap.new()
	ms._fills = [Color8(0xC8, 0xA8, 0x6A)]
	_ok("ocre colline EXCLU sur Surélevé (≠ COLLINE)",
			ms._classer(0, HoloXlsxMap._CARTE_ONLY) != HoloXlsxMap.Cell.COLLINE)

	# Regroupement d'une famille surélevée : 2 blocs séparés, altitude = chiffre tapé.
	var mb := HoloXlsxMap.new()
	mb.grille = 30
	var dt := {}; var dx := {}
	for c: Vector2i in _carre(2, 2, 4): dt[c] = HoloXlsxMap.Cell.HELIPORT
	dt[Vector2i(2, 2)] = HoloXlsxMap.Cell.HELIPORT
	dx[Vector2i(3, 3)] = "30"   # altitude tapée
	dt[Vector2i(20, 20)] = HoloXlsxMap.Cell.HELIPORT   # 2e bloc isolé (1×1, sans altitude)
	var blocs := mb._blocs_sureleve(HoloXlsxMap.Cell.HELIPORT, dt, dx, {})
	_eq("2 blocs héliport séparés", blocs.size(), 2)
	_ok("altitude lue (30 m) sur le grand bloc",
			_a_bloc_alt(blocs, 16, 30.0))   # 4×4 = 16 cases, alt 30
	_ok("altitude défaut sur le bloc sans chiffre",
			_a_bloc_alt(blocs, 1, HoloXlsxMap.ALTITUDE_SURELEVE_DEFAUT))

	# Validation HÉLIPORT — bâtiment 5×5 à 30 m, toit assez large.
	_eq("héliport valide (4×4 sur toit, alt=sommet) → 0 croix",
			_croix_heliport(Rect2i(2, 2, 4, 4), 30.0, 30.0), 0)
	_eq("héliport trop petit (3×3) → 1 croix",
			_croix_heliport(Rect2i(2, 2, 3, 3), 30.0, 30.0), 1)
	_eq("héliport mauvaise altitude (≠ sommet) → 1 croix",
			_croix_heliport(Rect2i(2, 2, 4, 4), 12.0, 30.0), 1)
	_eq("héliport hors du toit (déborde) → 1 croix",
			_croix_heliport(Rect2i(4, 4, 4, 4), 30.0, 30.0), 1)

	# Validation SPOTS : sur le toit → force le toit plat ; hors bâtiment → croix.
	var msp := _bati_5x5(30.0)
	msp.spots = [Vector2i(3, 3)]
	msp._valider_verticalite()
	_eq("spots sur toit → 0 croix", msp.croix_rouges.size(), 0)
	_ok("spots forcent le toit plat du bâti dessous",
			bool((msp.batiments[0] as Dictionary).get("toit_plat", false)))
	var msp2 := _bati_5x5(30.0)
	msp2.spots = [Vector2i(40, 40)]   # hors de toute emprise bâtie
	msp2._valider_verticalite()
	_eq("spots sans bâtiment dessous → 1 croix", msp2.croix_rouges.size(), 1)

	# Validation ANTENNE : sans bâtiment → croix.
	var man := _bati_5x5(30.0)
	man.antennes = [Vector2i(40, 40)]
	man._valider_verticalite()
	_eq("antenne sans bâtiment → 1 croix", man.croix_rouges.size(), 1)

	# Validation PASSERELLE : altitude cohérente vs incohérente avec le bâti relié.
	var mp := _bati_5x5(30.0)   # bâti de 30 m en (2,2)-(6,6)
	mp.passerelles = [{"cells": [Vector2i(7, 4), Vector2i(8, 4)], "bbox": Rect2i(7, 4, 2, 1), "altitude_m": 25.0}]
	mp._valider_verticalite()
	_eq("passerelle 25 m vs bâti 30 m → cohérente (0 croix)", mp.croix_rouges.size(), 0)
	_ok("passerelle perce 1 porte dans le bâti touché",
			(mp.passerelles[0] as Dictionary).get("portes", []).size() == 1)
	var mp2 := _bati_5x5(10.0)   # bâti de 10 m
	mp2.passerelles = [{"cells": [Vector2i(7, 4)], "bbox": Rect2i(7, 4, 1, 1), "altitude_m": 30.0}]
	mp2._valider_verticalite()
	_eq("passerelle 30 m vs bâti 10 m → incohérente (1 croix)", mp2.croix_rouges.size(), 1)

	# bati_sous : lookup d'index.
	var mi := _bati_5x5(30.0)
	mi._valider_verticalite()
	_ok("bati_sous(case du toit) → bloc trouvé", not mi.bati_sous(Vector2i(4, 4)).is_empty())
	_ok("bati_sous(case vide) → vide", mi.bati_sous(Vector2i(40, 40)).is_empty())

# Carré n×n de Vector2i à partir de (x0,y0).
func _carre(x0: int, y0: int, n: int) -> Array:
	var out: Array = []
	for x in range(x0, x0 + n):
		for y in range(y0, y0 + n):
			out.append(Vector2i(x, y))
	return out

# Map synthétique : un bâtiment BOÎTE 5×5 en (2,2)-(6,6) à `h` mètres.
func _bati_5x5(h: float) -> HoloXlsxMap:
	var m := HoloXlsxMap.new()
	m.grille = 60
	m.batiments = [{"cells": _carre(2, 2, 5), "bbox": Rect2i(2, 2, 5, 5),
			"hauteur_m": h, "forme": HoloXlsxMap.Forme.BOITE}]
	return m

# Compte les croix rouges produites par un héliport `bb` à `alt`, sur un bâti de `som` m.
func _croix_heliport(bb: Rect2i, alt: float, som: float) -> int:
	var m := _bati_5x5(som)
	m.heliports = [{"cells": _carre(bb.position.x, bb.position.y, bb.size.x), "bbox": bb, "altitude_m": alt}]
	m._valider_verticalite()
	return m.croix_rouges.size()

# Un bloc de `n` cases à l'altitude `alt` existe-t-il dans `blocs` ?
func _a_bloc_alt(blocs: Array, n: int, alt: float) -> bool:
	for b in blocs:
		if (b["cells"] as Array).size() == n and is_equal_approx(b["altitude_m"], alt):
			return true
	return false

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

# Carte synthétique : un bloc 2×2 de BATIMENT en (3,3)-(4,4), avec un ID de lieu posé
# dans une cellule (border_case vide → la zone = la contiguïté d'apparence).
func _carte_zone_id() -> HoloXlsxMap:
	var m := HoloXlsxMap.new()
	m.grille = 10
	for c: Vector2i in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
		m.type_case[c] = HoloXlsxMap.Cell.BATIMENT
	m.texte_case[Vector2i(3, 3)] = "biome_foret"
	return m
