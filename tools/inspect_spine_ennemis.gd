# Outil dev JETABLE-ISH : décrit le contrat Spine réel d'un export de
# Christophe (animations, skins, slots, taille du squelette) — à lancer après
# chaque livraison d'assets pour savoir ce que le code peut piloter.
#   godot --headless --path . res://tools/inspect_spine_ennemis.tscn
#
# SCÈNE et pas `--script` : il lit les niveaux via SpriteSpinePersonnage, qui
# dépend du registre, donc de GameData — un autoload que `--script` ne charge pas.
extends Node

const CIBLES: Array = [
	["Relic",    "res://assets/personnages/relic/Relic.skel",             "res://assets/personnages/relic/Relic.atlas"],
	["FlameBot", "res://assets/personnages/ennemis/flamebot/FlameBot.skel", "res://assets/personnages/ennemis/flamebot/FlameBot.atlas"],
	["WorkBot",  "res://assets/personnages/ennemis/workbot/WorkBot.skel",   "res://assets/personnages/ennemis/workbot/WorkBot.atlas"],
]

func _ready() -> void:
	if not ClassDB.class_exists("SpineSkeletonDataResource"):
		push_error("runtime spine-godot absent")
		get_tree().quit(1)
		return
	for cible: Array in CIBLES:
		_decrire(str(cible[0]), str(cible[1]), str(cible[2]))
	get_tree().quit(0)

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
	# Niveaux d'ÉQUIPEMENT : Relic ne les porte pas en skins mais en SLOTS
	# suffixés « _Nv<n> » (cf. SpriteSpinePersonnage.niveaux_du_slot). Les
	# lister ici évite de redécouvrir la structure à chaque livraison.
	var slots: Array = donnees.call("get_slots")
	var niveaux: Array[int] = []
	for slot in slots:
		for n in SpriteSpinePersonnage.niveaux_du_slot(str(slot.call("get_name"))):
			if n not in niveaux:
				niveaux.append(n)
	niveaux.sort()
	# (les ennemis ont aussi un slot par palier — mais leur palier se commute
	# par la SKIN, on ne leur passe jamais de niveau à purger.)
	print("  slots : ", slots.size(), " — suffixes « _Nv » trouvés : ",
			niveaux if not niveaux.is_empty() else "aucun")
