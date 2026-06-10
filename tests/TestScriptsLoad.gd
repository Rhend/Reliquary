extends Node
# Smoke test : charge tous les scripts .gd du projet avec les autoloads actifs.
# Détecte les erreurs de compilation (identifiants disparus, signaux supprimés,
# constantes renommées…) sans avoir à ouvrir chaque scène à la main.

var _failed: Array[String] = []
var _count:  int = 0

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TEST CHARGEMENT DE TOUS LES SCRIPTS ===\n")
	_scan_dir("res://")
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d scripts chargés (échecs: %d)" \
			% [_count - _failed.size(), _count, _failed.size()])
	for f in _failed:
		print("  ✗ " + f)
	print("════════════════════════════════\n")
	get_tree().quit(0 if _failed.is_empty() else 1)

# Parcourt récursivement le projet (en ignorant .godot/) et tente de charger
# chaque script. Un script qui compile retourne une ressource valide.
func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full)
		elif entry.ends_with(".gd"):
			_count += 1
			var script := load(full)
			if script == null or not (script as GDScript).can_instantiate():
				_failed.append(full)
				print("  ✗ " + full)
			else:
				print("  ✓ " + full)
		entry = dir.get_next()
	dir.list_dir_end()
