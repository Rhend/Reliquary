# Outil dev : composition de DÉCOR de chaque zone à ID du gabarit — sert à
# choisir quel district devient quel Lieu (chantier 17).
#   godot --headless --path . --script res://tools/inspect_zones.gd
extends SceneTree

func _init() -> void:
	var m := HoloXlsxMap.new()
	if not m.charger("res://Carte Holo/carte_holomap.xlsx"):
		push_error("gabarit illisible")
		quit(1)
		return
	for z: Dictionary in m.zones:
		var compo: Dictionary = {}
		for c: Vector2i in z["cells"]:
			var t: int = m.type_case.get(c, -1)
			compo[t] = int(compo.get(t, 0)) + 1
		var noms: PackedStringArray = []
		for t: int in compo:
			noms.append("%s×%d" % [_nom(t), compo[t]])
		print("zone « %s » bbox %s : %s" % [str(z["id"]), str(z["bbox"]), ", ".join(noms)])
		# Voisinage immédiat (anneau de 2 cases autour de la bbox).
		var bbox: Rect2i = z["bbox"]
		var autour: Dictionary = {}
		for y in range(bbox.position.y - 2, bbox.end.y + 2):
			for x in range(bbox.position.x - 2, bbox.end.x + 2):
				if bbox.has_point(Vector2i(x, y)):
					continue
				var t: int = m.type_case.get(Vector2i(x, y), -1)
				autour[t] = int(autour.get(t, 0)) + 1
		var noms2: PackedStringArray = []
		for t: int in autour:
			if int(autour[t]) >= 4:
				noms2.append("%s×%d" % [_nom(t), autour[t]])
		print("    autour : %s" % ", ".join(noms2))
	quit(0)

func _nom(t: int) -> String:
	if t < 0:
		return "vide"
	var cles := HoloXlsxMap.Cell.keys()
	return str(cles[t]).to_lower() if t < cles.size() else "type%d" % t
