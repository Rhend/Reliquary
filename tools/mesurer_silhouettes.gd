# ============================================================
# mesurer_silhouettes.gd — OUTIL DEV : bake des hauteurs de corps réelles.
#
#   godot --path . res://tools/mesurer_silhouettes.tscn
#
# ⚠ PAS de --headless : l'outil doit RENDRE pour compter des pixels. C'est tout
# l'intérêt — les bornes du squelette (get_bounds) comptent des régions d'atlas
# transparentes et l'arme, la silhouette non. Voir SilhouettesData pour le
# pourquoi et le contrat d'obsolescence.
#
# Pour chaque entrée du registre Spine :
#   1. construit le personnage à sa PREMIÈRE apparence (Nv1 / Commun) ;
#   2. lui pose la skin de mesure — arme et VFX retirés ;
#   3. le rend dans un SubViewport transparent et scanne l'alpha ;
#   4. reconvertit la hauteur visible en unités Spine (÷ échelle).
#
# Le résultat est écrit dans data/personnages/silhouettes.tres, VERSIONNÉ.
# Une SCÈNE et pas un --script : le registre dépend de GameData, donc des
# autoloads (même raison que verif_spine).
# ============================================================
extends Node2D

# Assez grand pour contenir le plus grand personnage à l'échelle de mesure,
# marges comprises. Le scan est en O(pixels) : inutile de voir trop grand.
const TAILLE_VP := Vector2i(768, 768)
# Hauteur à laquelle on rend pour mesurer. Plus c'est haut, plus la mesure est
# fine (un pixel d'erreur pèse moins), tant que ça tient dans le viewport.
const HAUTEUR_MESURE := 600.0
# En dessous, un pixel est considéré comme du vide. Les bords antialiasés d'un
# sprite Spine traînent des alphas très faibles qui gonfleraient la silhouette.
const SEUIL_ALPHA := 0.08

var _vp: SubViewport

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = TAILLE_VP
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	if not SpriteSpinePersonnage.disponible():
		push_error("mesurer_silhouettes : runtime spine-godot absent — rien à mesurer.")
		get_tree().quit(1)
		return

	var registre := SpinePersonnagesData.charger()
	if registre == null:
		push_error("mesurer_silhouettes : registre introuvable.")
		get_tree().quit(1)
		return

	var mesures := {}
	print("═══ Bake des silhouettes ═══")
	for entree in registre.personnages:
		var resultat := await _mesurer(entree)
		if resultat.is_empty():
			continue
		mesures[str(entree.get("skel", ""))] = resultat

	if mesures.is_empty():
		push_error("mesurer_silhouettes : aucune mesure — rien n'est écrit.")
		get_tree().quit(1)
		return
	_ecrire(mesures)
	get_tree().quit(0)

# Rend un personnage corps nu et rend {hauteur, bornes}, ou {} en cas d'échec.
func _mesurer(entree: Dictionary) -> Dictionary:
	var chemin_skel := str(entree.get("skel", ""))
	var nom := str(entree.get("nom", "?"))
	var apparences := SpinePersonnagesData.apparences(entree)
	if apparences.is_empty():
		print("  %-14s ignoré (aucune apparence)" % nom)
		return {}

	var sprite := SpriteSpinePersonnage.creer(chemin_skel,
			str(entree.get("atlas", "")), apparences[0], HAUTEUR_MESURE)
	if sprite == null:
		print("  %-14s ignoré (sprite non constructible)" % nom)
		return {}
	# Bornes AVANT de dénuder : c'est la grandeur que le runtime recalculera
	# pour détecter qu'un asset a bougé sans re-bake.
	var bornes := sprite.bornes_corps()
	var echelle: float = (sprite.get_child(0).get("scale") as Vector2).y
	sprite.poser_skin_mesure(apparences[0])
	# Centré en bas : le personnage a l'origine aux pieds, il pousse vers le haut.
	sprite.position = Vector2(TAILLE_VP.x * 0.5, TAILLE_VP.y - 40.0)
	_vp.add_child(sprite)

	# Deux frames : une pour poser la pose, une pour qu'elle soit dessinée.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var visible_px := _hauteur_visible(_vp.get_texture().get_image())
	_vp.remove_child(sprite)
	sprite.queue_free()

	if visible_px <= 0 or echelle <= 0.0:
		print("  %-14s ignoré (rien de dessiné)" % nom)
		return {}
	var hauteur := visible_px / echelle
	print("  %-14s silhouette %4d px → %7.1f unités  (bornes %7.1f, soit %+.0f %%)"
			% [nom, visible_px, hauteur, bornes,
			   (bornes / hauteur - 1.0) * 100.0 if hauteur > 0.0 else 0.0])
	return {"hauteur": hauteur, "bornes": bornes}

# Nombre de lignes de pixels contenant au moins un pixel opaque.
func _hauteur_visible(img: Image) -> int:
	var haut := -1
	var bas := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a <= SEUIL_ALPHA:
				continue
			if haut < 0:
				haut = y
			bas = y
			break
	return 0 if haut < 0 else bas - haut + 1

func _ecrire(mesures: Dictionary) -> void:
	var data := SilhouettesData.new()
	data.mesures = mesures
	var err := ResourceSaver.save(data, SilhouettesData.CHEMIN)
	if err != OK:
		push_error("mesurer_silhouettes : écriture impossible (%d)" % err)
		return
	print("→ ", SilhouettesData.CHEMIN, " écrit (", mesures.size(), " squelettes)")
