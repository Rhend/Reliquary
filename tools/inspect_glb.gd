extends SceneTree
# Outil ponctuel : dumpe la structure d'un .glb (noeuds, surfaces, tris, AABB)
# dans tools/inspect_glb_out.txt (le print() se perd sous Windows sans console).
# Usage : godot --headless --path . --script res://tools/inspect_glb.gd

var _lignes: PackedStringArray = []

func _init() -> void:
	var chemin := "res://assets/props/holomap/supermarche_panneau_toit.glb"
	var ps: PackedScene = load(chemin)
	if ps == null:
		_lignes.append("ERREUR : chargement impossible : " + chemin)
		_flush()
		quit(1)
		return
	var racine := ps.instantiate()
	_dump(racine, 0)
	racine.free()
	_flush()
	quit(0)

func _flush() -> void:
	var f := FileAccess.open("res://tools/inspect_glb_out.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lignes))
	f.close()

func _dump(n: Node, prof: int) -> void:
	var ind := "  ".repeat(prof)
	var ligne := ind + n.name + " (" + n.get_class() + ")"
	if n is Node3D:
		ligne += "  pos=" + str((n as Node3D).position) + " scale=" + str((n as Node3D).scale)
	_lignes.append(ligne)
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			var aabb := m.get_aabb()
			_lignes.append(ind + "  AABB pos=" + str(aabb.position) + " size=" + str(aabb.size))
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				var nv: int = arr[Mesh.ARRAY_VERTEX].size()
				var nidx: int = arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else nv
				var mat := m.surface_get_material(si)
				var mat_nom: String = mat.resource_name if mat != null else "<aucun>"
				_lignes.append(ind + "  surface " + str(si) + " : " + str(nidx / 3) + " tris, " + str(nv) + " verts, mat=" + mat_nom)
	for c in n.get_children():
		_dump(c, prof + 1)
