extends Node
# ============================================================
# TestHoloTraffic — Valide la simulation de trafic (HoloTraffic) :
#   • les voitures roulent (déplacement non nul) ;
#   • elles NE SE CROISENT JAMAIS : sur un réseau quadrillé avec intersections,
#     la distance minimale entre deux voitures reste au-dessus du seuil de
#     croisement (un croisement ferait tomber la distance ≈ 0) ;
#   • PAS DE GRIDLOCK DURABLE : sur un réseau de boulevards 2 voies (carrefours
#     2×2, comme la vraie carte) à FORTE densité, la circulation continue de
#     s'écouler jusqu'au bout d'une longue simulation — l'ancien verrou par case
#     y gelait des carrefours entiers (deux voitures face à face, à vie).
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

var _fail: Array[String] = []

# Stub minimal pour appeler les statiques de holo_ville (qui ne lisent que h._excel).
class HStub:
	var _excel: HoloXlsxMap

func _ready() -> void:
	print("\n=== TEST SIMULATION DE TRAFIC (HoloTraffic) ===\n")
	_scenario_grille_simple()
	_scenario_boulevards_denses()
	_scenario_carte_reelle()

	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % _fail.size())
	for f in _fail:
		print("  ✗ " + f)
	if _fail.is_empty():
		print("  ✓ trafic conforme (roule + ne se croise pas + pas de gridlock)")
	print("════════════════════════════════\n")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── Scénario 1 : grille simple 1 voie (3 × 3 carrefours) ─────
func _scenario_grille_simple() -> void:
	print("[SCÉNARIO 1] grille 1 voie, 9 carrefours, 55 voitures")
	var rs := {}
	var routes: Array = []
	for gy in [6, 16, 26]:
		for gx in range(2, 29):
			var c := Vector2i(gx, gy)
			if not rs.has(c):
				rs[c] = true; routes.append(c)
	for gx in [6, 16, 26]:
		for gy in range(2, 29):
			var c := Vector2i(gx, gy)
			if not rs.has(c):
				rs[c] = true; routes.append(c)
	# Intersections = cases avec un voisin sur CHAQUE axe (croisement de routes).
	var inter := {}
	for c: Vector2i in rs:
		var hx: bool = rs.has(c + Vector2i(1, 0)) or rs.has(c + Vector2i(-1, 0))
		var vz: bool = rs.has(c + Vector2i(0, 1)) or rs.has(c + Vector2i(0, -1))
		if hx and vz:
			inter[c] = true
	var m := _simuler(routes, inter, 55, 600, 9876)

	# Seuil de croisement : bien en dessous d'un croisement de voies opposées (≈
	# 0.136 m) mais très au-dessus de 0 → un vrai croisement le ferait chuter.
	# (Un demi-tour anti-bouchon peut frôler une voiture arrêtée à ~0.05 m : c'est
	# un dégagement licite, pas un croisement — le seuil reste sous cette valeur.)
	var seuil := 0.04
	_ok("aucun croisement sur 600 pas (dmin=%.3f m > %.3f m)" % [m["dmin"], seuil], m["dmin"] > seuil)
	# Seuil haut → détecte aussi un éventuel BLOCAGE GÉNÉRAL (gridlock) à densité élevée.
	_ok("trafic fluide, pas de gridlock (déplacement cumulé=%.0f m)" % m["depl_total"], m["depl_total"] > 150.0)

# ─── Scénario 2 : boulevards 2 voies (carrefours 2×2), forte densité ──
# C'est la configuration de la vraie carte. Avec l'ancien verrou PAR CASE, deux
# voitures engagées face à face dans un carrefour 2×2 se bloquaient mutuellement
# pour toujours et le gel se propageait (bouchons « auto-créés »). Le verrou par
# CARREFOUR + le demi-tour anti-gridlock doivent garder l'écoulement jusqu'au bout.
func _scenario_boulevards_denses() -> void:
	print("\n[SCÉNARIO 2] boulevards 2 voies, 9 carrefours 2×2, forte densité, 120 s")
	var rs := {}
	var routes: Array = []
	for bande in [5, 15, 25]:
		for w in 2:
			for gx in range(2, 30):
				var c := Vector2i(gx, bande + w)
				if not rs.has(c):
					rs[c] = true; routes.append(c)
			for gy in range(2, 30):
				var c := Vector2i(bande + w, gy)
				if not rs.has(c):
					rs[c] = true; routes.append(c)
	# Carrefours = croisements de bandes H × V → blobs 2×2 (comme _routes_intersections).
	var inter := {}
	for bx in [5, 15, 25]:
		for by in [5, 15, 25]:
			for dx in 2:
				for dy in 2:
					inter[Vector2i(bx + dx, by + dy)] = true
	var n_pas := 2400   # 120 s simulées (dt 0.05)
	var fenetre := 480  # fenêtre finale observée : 24 s (> 2 cycles de feux)
	var m := _simuler(routes, inter, 110, n_pas, 4242, fenetre)

	_ok("aucun croisement sur %d pas (dmin=%.3f m > 0.030 m)" % [n_pas, m["dmin"]], m["dmin"] > 0.03)
	# L'écoulement CONTINUE en fin de simulation (pas de gel terminal) : sur les
	# 24 dernières secondes, le déplacement global reste substantiel…
	_ok("écoulement soutenu en fin de sim (fenêtre finale=%.0f m)" % m["depl_fenetre"], m["depl_fenetre"] > 40.0)
	# …et la grande majorité des voitures bougent encore (les arrêts licites —
	# feux, files qui avancent — ne figent pas une voiture 24 s d'affilée).
	var ratio: float = m["nb_mobiles"] / maxf(1.0, m["nb_voitures"])
	_ok("voitures encore mobiles en fin de sim : %d/%d (≥ 75 %%)" % [int(m["nb_mobiles"]), int(m["nb_voitures"])],
			ratio >= 0.75)

# ─── Scénario 3 : la VRAIE carte (gabarit Excel), densité du jeu ──
# Réseau réel (impasses aux berges, carrefours irréguliers, largeurs mixtes) +
# intersections calculées EXACTEMENT comme le jeu (holo_ville._routes_intersections)
# → garde-fou : la carte livrée ne peut pas re-gripper sans faire échouer ce test.
# Les seuils sont volontairement des seuils d'ÉCOULEMENT (pas des valeurs exactes) :
# le gabarit évolue, le test doit survivre aux éditions de la carte.
func _scenario_carte_reelle() -> void:
	var m := HoloXlsxMap.new()
	if not m.charger(HoloMap3D.CHEMIN_GABARIT_DEFAUT):
		print("\n[SCÉNARIO 3] gabarit illisible → scénario sauté (pas d'échec)")
		return
	var stub := HStub.new()
	stub._excel = m
	var Ville := preload("res://scenes/holomap3d/build/holo_ville.gd")
	var inter: Dictionary = Ville._routes_intersections(stub)
	var n_cars := clampi(int(m.routes.size() * 0.30), 8, 220)   # densité par défaut du jeu
	print("\n[SCÉNARIO 3] carte réelle : %d cases de route, %d carrefours-cases, %d voitures, 90 s"
			% [m.routes.size(), inter.size(), n_cars])
	var n_pas := 1800   # 90 s simulées
	var fenetre := 480  # fenêtre finale : 24 s
	var res := _simuler(m.routes, inter, n_cars, n_pas, 777, fenetre)

	_ok("aucun croisement sur la vraie carte (dmin=%.3f m > 0.030 m)" % res["dmin"], res["dmin"] > 0.03)
	_ok("écoulement soutenu en fin de sim (fenêtre finale=%.0f m)" % res["depl_fenetre"], res["depl_fenetre"] > 40.0)
	var ratio: float = res["nb_mobiles"] / maxf(1.0, res["nb_voitures"])
	_ok("voitures encore mobiles en fin de sim : %d/%d (≥ 75 %%)" % [int(res["nb_mobiles"]), int(res["nb_voitures"])],
			ratio >= 0.75)

# ─── Harnais : construit, simule, mesure ──────────────────────
# Renvoie : dmin (proximité minimale), depl_total, depl_fenetre (déplacement global
# sur les `fenetre` derniers pas), nb_mobiles (voitures ayant bougé > 0.05 m dans
# la fenêtre), nb_voitures.
func _simuler(routes: Array, inter: Dictionary, n_cars: int, n_pas: int,
		graine: int, fenetre: int = 0) -> Dictionary:
	var trafic := HoloTraffic.new()
	trafic.configurer(routes, inter, 14.5, 0.34, 0.06, ShaderMaterial.new(), n_cars, graine)
	trafic.set_process(false)   # on cadence nous-mêmes

	var dmin := 1.0e9
	var depl_total := 0.0
	var depl_fenetre := 0.0
	var prev: Array = trafic.positions()
	var mobiles := {}   # id → déplacement cumulé dans la fenêtre finale
	for pas in n_pas:
		trafic.pas_sim(0.05)
		var pos: Array = trafic.positions()
		for i in pos.size():
			for j in range(i + 1, pos.size()):
				var d: float = (pos[i] as Vector3).distance_to(pos[j])
				if d < dmin:
					dmin = d
		var en_fenetre: bool = fenetre > 0 and pas >= n_pas - fenetre
		for i in mini(pos.size(), prev.size()):
			var d: float = (pos[i] as Vector3).distance_to(prev[i])
			depl_total += d
			if en_fenetre:
				depl_fenetre += d
				mobiles[i] = float(mobiles.get(i, 0.0)) + d
		prev = pos
	var nb_voitures := prev.size()
	trafic.free()

	var nb_mobiles := 0
	for id in mobiles:
		if float(mobiles[id]) > 0.05:
			nb_mobiles += 1
	return {"dmin": dmin, "depl_total": depl_total, "depl_fenetre": depl_fenetre,
			"nb_mobiles": nb_mobiles, "nb_voitures": nb_voitures}

func _ok(nom: String, cond: bool) -> void:
	print(("  ✓ " if cond else "  ✗ ") + nom)
	if not cond:
		_fail.append(nom)
