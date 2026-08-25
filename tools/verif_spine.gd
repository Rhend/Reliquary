# Outil dev : vérifie que le runtime spine-godot (GDExtension bin/) charge
# et que les assets Relic (assets/personnages/relic/) produisent un
# SpriteSpinePersonnage valide. Usage :
#   godot --headless --path . res://tools/verif_spine.tscn
#
# SCÈNE et pas `--script` : le chemin vérifié passe par le registre des
# personnages, donc par GameData — un autoload, que `--script` ne charge pas.
extends Node

func _ready() -> void:
	var ok := true
	print("SpineSprite dans ClassDB : ", ClassDB.class_exists("SpineSprite"))
	print("Assets présents : ", ResourceLoader.exists("res://assets/personnages/relic/Relic.skel"),
			" / ", ResourceLoader.exists("res://assets/personnages/relic/Relic.atlas"))
	print("SpriteSpinePersonnage.disponible() : ", SpriteSpinePersonnage.disponible())
	# creer_heros() = le chemin du JEU RÉEL (apparence lue du registre) : c'est
	# lui qu'il faut vérifier, l'export n'ayant pas de skin « default ».
	var sprite := SpriteSpinePersonnage.creer_heros()
	if sprite == null:
		push_error("creer_heros() a rendu null — runtime ou assets KO")
		ok = false
	else:
		var spine: Node = sprite.get_child(0) if sprite.get_child_count() > 0 else null
		if spine == null:
			push_error("pas d'enfant SpineSprite")
			ok = false
		else:
			print("Nœud Spine : ", spine.get_class(), " — échelle ", spine.get("scale"))
			var donnees: Resource = spine.get("skeleton_data_res")
			for m: Dictionary in donnees.get_method_list():
				var nom := str(m.get("name", ""))
				if "anim" in nom.to_lower():
					print("  méthode data : ", nom)
			var anims: Array = []
			for a in donnees.call("get_animations"):
				anims.append(str(a.call("get_name")))
			print("Animations réelles : ", anims)
			for attendu in [SpriteSpinePersonnage.ANIM_IDLE, SpriteSpinePersonnage.ANIM_ATTACK,
					SpriteSpinePersonnage.ANIM_ATTACK_SHOOT, SpriteSpinePersonnage.ANIM_HIT,
					SpriteSpinePersonnage.ANIM_DEATH]:
				if attendu not in anims:
					push_error("animation attendue absente : %s" % attendu)
					ok = false
			# Une apparence VIDE passerait tous les contrôles ci-dessus en
			# rendant un personnage invisible : on vérifie qu'il porte un corps.
			if not sprite.porte_attachement("R_H_Idle_Torse", "R_H_Idle_Torse"):
				push_error("apparence vide — aucune skin posée, Relic serait invisible")
				ok = false
		sprite.free()
	print("VERIF SPINE : ", "OK" if ok else "ECHEC")
	get_tree().quit(0 if ok else 1)
