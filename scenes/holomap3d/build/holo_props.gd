# ============================================================
# holo_props — props .glb de l'artiste (assets/props/holomap/) réduits en
# fil-de-fer néon.
#
# Le moteur ne rend PAS les faces des props : il en extrait les ARÊTES DURES
# (bord de silhouette, pli franc entre deux faces) et les dessine en lignes,
# comme le reste de la ville. Les diagonales de triangulation (faces
# coplanaires) sont éliminées → le dessin reste propre même sur un export brut.
#
# Les objets du .glb sont groupés par RÔLE de couleur d'après leur nom
# (`cadre` → néon principal, `texte` → accent) ; à défaut de nom parlant :
# 1er objet = cadre, suivants = texte. Les transforms de nœuds NON appliqués
# à l'export sont composés ici (robuste aux exports sloppy).
#
# Coordonnées renvoyées : locales au .glb, en MÈTRES réels
# (cf. Carte Holo/SPECS_ASSETS.md — le placement/échelle est fait par famille,
# ex. holo_decor._prop_sur_toit).
# ============================================================
extends RefCounted

const CHEMIN := "res://assets/props/holomap/%s.glb"
const COS_PLI := 0.966   # cos(15°) : deux faces plus coplanaires que ça → arête invisible
const QUANT := 2048.0    # soudure des sommets au ~0.5 mm (les exports dupliquent par normale)

static var _cache: Dictionary = {}

# Arêtes néon d'un prop. Retour : {"cadre": PackedVector3Array (paires de points),
# "texte": PackedVector3Array, "aabb": AABB} — ou {} si le .glb est absent/vide
# (l'appelant garde alors son rendu procédural de secours). Mise en cache.
static func aretes(nom: String) -> Dictionary:
	if _cache.has(nom):
		return _cache[nom]
	var res := _extraire(nom)
	_cache[nom] = res
	return res

static func _extraire(nom: String) -> Dictionary:
	var chemin := CHEMIN % nom
	if not ResourceLoader.exists(chemin):
		return {}
	var ps := load(chemin) as PackedScene
	if ps == null:
		return {}
	var racine: Node = ps.instantiate()
	var roles := {"cadre": PackedVector3Array(), "texte": PackedVector3Array()}
	var compteur := [0]
	_collecter(racine, Transform3D.IDENTITY, roles, compteur)
	racine.free()
	var cadre: PackedVector3Array = roles["cadre"]
	var texte: PackedVector3Array = roles["texte"]
	if cadre.is_empty() and texte.is_empty():
		return {}
	var pts := cadre + texte
	var aabb := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		aabb = aabb.expand(p)
	return {"cadre": cadre, "texte": texte, "aabb": aabb}

static func _collecter(n: Node, xf: Transform3D, roles: Dictionary, compteur: Array) -> void:
	var xfl := xf
	if n is Node3D:
		xfl = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			var role := _role(String(n.name), int(compteur[0]))
			compteur[0] = int(compteur[0]) + 1
			var dest: PackedVector3Array = roles[role]
			for si in m.get_surface_count():
				if m.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
					_aretes_surface(m.surface_get_arrays(si), xfl, dest)
			roles[role] = dest
	for c in n.get_children():
		_collecter(c, xfl, roles, compteur)

static func _role(nom: String, index: int) -> String:
	var b := nom.to_lower()
	if b.contains("texte") or b.contains("text"):
		return "texte"
	if b.contains("cadre") or b.contains("frame"):
		return "cadre"
	return "cadre" if index == 0 else "texte"

# Arêtes dures d'une surface triangulée : soudure par position quantifiée
# (retrouve l'adjacence réelle malgré les sommets dupliqués par normale), puis
# une arête est retenue si elle borde UNE seule face (bord ouvert) ou si ses
# deux faces forment un pli franc (angle > ~15°).
static func _aretes_surface(arr: Array, xf: Transform3D, dest: PackedVector3Array) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var soude := {}                    # position quantifiée → id soudé
	var pos := PackedVector3Array()    # id soudé → position (transform composée)
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	for i in verts.size():
		var p := xf * verts[i]
		var k := Vector3i((p * QUANT).round())
		if not soude.has(k):
			soude[k] = pos.size()
			pos.append(p)
		remap[i] = soude[k]
	# etat[arête] = normale de la 1re face rencontrée, puis verdict "dure"/"plate".
	var etat := {}
	for t in idx.size() / 3:
		var a := remap[idx[t * 3]]
		var b := remap[idx[t * 3 + 1]]
		var c := remap[idx[t * 3 + 2]]
		if a == b or b == c or a == c:
			continue
		var nrm := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		if nrm.length_squared() < 1e-12:
			continue
		nrm = nrm.normalized()
		for e: Vector2i in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
			var v: Variant = etat.get(key)
			if v == null:
				etat[key] = nrm
			elif v is Vector3:
				etat[key] = "plate" if (v as Vector3).dot(nrm) > COS_PLI else "dure"
			# 3e face et plus sur la même arête : verdict des deux premières conservé.
	for key: Vector2i in etat:
		var v: Variant = etat[key]
		if v is String and v == "plate":
			continue
		dest.append(pos[key.x])
		dest.append(pos[key.y])
