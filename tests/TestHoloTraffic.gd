extends Node
# ============================================================
# TestHoloTraffic — Valide la simulation de trafic (HoloTraffic) :
#   • les voitures roulent (déplacement non nul) ;
#   • elles NE SE CROISENT JAMAIS : sur un réseau quadrillé avec intersections,
#     la distance minimale entre deux voitures reste au-dessus du seuil de
#     croisement (un croisement ferait tomber la distance ≈ 0).
# Réseau synthétique : 3 routes horizontales × 3 verticales = 9 carrefours.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

var _fail: Array[String] = []

func _ready() -> void:
	print("\n=== TEST SIMULATION DE TRAFIC (HoloTraffic) ===\n")
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

	var cell := 0.34
	var trafic := HoloTraffic.new()
	trafic.configurer(routes, inter, 14.5, cell, 0.06, ShaderMaterial.new(), 40, 9876)
	trafic.set_process(false)   # on cadence nous-mêmes

	var dmin := 1.0e9
	var deplacement := 0.0
	var prev: Array = trafic.positions()
	for _step in 600:
		trafic.pas_sim(0.05)
		var pos: Array = trafic.positions()
		for i in pos.size():
			for j in range(i + 1, pos.size()):
				var d: float = (pos[i] as Vector3).distance_to(pos[j])
				if d < dmin:
					dmin = d
		for i in mini(pos.size(), prev.size()):
			deplacement += (pos[i] as Vector3).distance_to(prev[i])
		prev = pos
	trafic.free()

	# Seuil de croisement : bien en dessous d'un croisement de voies opposées (≈
	# 0.136 m) mais très au-dessus de 0 → un vrai croisement le ferait chuter.
	var seuil := 0.08
	_ok("aucun croisement sur 600 pas (dmin=%.3f m > %.3f m)" % [dmin, seuil], dmin > seuil)
	_ok("les voitures roulent (déplacement cumulé=%.1f m)" % deplacement, deplacement > 10.0)

	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % _fail.size())
	for f in _fail:
		print("  ✗ " + f)
	if _fail.is_empty():
		print("  ✓ trafic conforme (roule + ne se croise pas)")
	print("════════════════════════════════\n")
	get_tree().quit(0 if _fail.is_empty() else 1)

func _ok(nom: String, cond: bool) -> void:
	print(("  ✓ " if cond else "  ✗ ") + nom)
	if not cond:
		_fail.append(nom)
