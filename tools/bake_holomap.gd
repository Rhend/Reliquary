extends SceneTree
# ============================================================
# bake_holomap — Fige le gabarit Excel de la HoloMap dans son instantané baké.
#
# Le .xlsx (Carte Holo/) est l'outil d'AUTORING : il n'est JAMAIS exporté (le
# joueur ne doit ni le voir ni pouvoir le modifier — cf. export_presets.cfg).
# Le build charge à la place l'instantané figé ici (data/holomap/*.snapshot,
# embarqué dans le .pck). À relancer après CHAQUE édition de la carte :
#
#   godot --headless --path . --script res://tools/bake_holomap.gd
#
# Garde-fou : TestHoloXlsx (CI) échoue si l'instantané n'est plus à jour.
# ============================================================

func _init() -> void:
	var chemin_xlsx := "res://Carte Holo/carte_holomap.xlsx"
	if not FileAccess.file_exists(chemin_xlsx):
		push_error("[bake_holomap] gabarit introuvable : %s (le bake se fait sur la machine d'autoring)" % chemin_xlsx)
		quit(1)
		return
	var m := HoloXlsxMap.new()
	if not m.charger(chemin_xlsx):
		push_error("[bake_holomap] gabarit illisible : %s" % chemin_xlsx)
		quit(1)
		return
	print("[bake_holomap] ", m.resume())
	if not m.croix_rouges.is_empty():
		print("[bake_holomap] ⚠ %d croix rouge(s) (contraintes violées) — bakées telles quelles" % m.croix_rouges.size())
	if not m.sauver_snapshot():
		quit(1)
		return
	var f := FileAccess.open(HoloXlsxMap.CHEMIN_SNAPSHOT_DEFAUT, FileAccess.READ)
	print("[bake_holomap] instantané écrit : %s (%.0f Ko)" % [
		HoloXlsxMap.CHEMIN_SNAPSHOT_DEFAUT, f.get_length() / 1024.0])
	f.close()
	quit(0)
