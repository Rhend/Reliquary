# Outil dev JETABLE-ISH : décrit le contrat Spine réel d'un export de
# Christophe (animations, skins, slots, taille du squelette) — à lancer après
# chaque livraison d'assets pour savoir ce que le code peut piloter.
#   godot --headless --path . --script res://tools/inspect_spine_ennemis.gd
extends SceneTree

const CIBLES: Array = [
	["Relic",    "res://assets/personnages/relic/Relic.skel",             "res://assets/personnages/relic/Relic.atlas"],
	["FlameBot", "res://assets/personnages/ennemis/flamebot/FlameBot.skel", "res://assets/personnages/ennemis/flamebot/FlameBot.atlas"],
	["WorkBot",  "res://assets/personnages/ennemis/workbot/WorkBot.skel",   "res://assets/personnages/ennemis/workbot/WorkBot.atlas"],
]

func _init() -> void:
	if not ClassDB.class_exists("SpineSkeletonDataResource"):
		push_error("runtime spine-godot absent")
		quit(1)
		return
	for cible: Array in CIBLES:
		_decrire(str(cible[0]), str(cible[1]), str(cible[2]))
	quit(0)

func _decrire(nom: String, chemin_skel: String, chemin_atlas: String) -> void:
	print("\n═══ ", nom, " ═══")
	if not ResourceLoader.exists(chemin_skel) or not ResourceLoader.exists(chemin_atlas):
		print("  ABSENT (skel ou atlas non importé)")
		return
	var donnees := ClassDB.instantiate("SpineSkeletonDataResource") as Resource
	donnees.skeleton_file_res = load(chemin_skel)
	donnees.atlas_res = load(chemin_atlas)
	if not bool(donnees.call("is_skeleton_data_loaded")):
		print("  DONNÉES INVALIDES (atlas mal raccordé ?)")
		return
	print("  taille : %.0f x %.0f" % [donnees.call("get_width"), donnees.call("get_height")])
	var anims: Array = []
	for a in donnees.call("get_animations"):
		anims.append(str(a.call("get_name")))
	print("  animations : ", anims)
	var skins: Array = []
	for s in donnees.call("get_skins"):
		skins.append(str(s.call("get_name")))
	print("  skins : ", skins)
	# (get_default_skin / SpineSlotData.get_slot_name ne sont pas exposés par ce
	# build du runtime — inutile d'insister, skins + animations suffisent.)
	print("  slots : ", donnees.call("get_slots").size())
