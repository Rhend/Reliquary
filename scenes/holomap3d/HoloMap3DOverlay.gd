# ============================================================
# HoloMap3DOverlay — Embarque la carte holo 3D dans l'UI 2D du Village.
#
# Control plein écran (overlay ajouté au Village) qui héberge un SubViewport
# (monde 3D isolé) affiché par un SubViewportContainer. La scène HoloMap3D vit
# dans le viewport ; le SubViewportContainer relaie souris/clic vers la 3D
# (orbite, zoom, picking des pins) et porte le post-process holographique
# (scanlines/flicker/distorsion) via holo_post_container.gdshader.
#
# Chrome 2D net (titre, indice, ✕, Échap) DESSUS le viewport, non distordu.
# API : `lieu_selectionne(id)`, `peupler_lieux(liste)` — mêmes contrats que la
# version 2D qu'elle remplace, pour une intégration transparente.
# ============================================================
class_name HoloMap3DOverlay
extends Control

signal lieu_selectionne(id: String)
signal ferme

const POST_CONTAINER_SHADER := preload("res://scenes/holomap3d/holo_post_container.gdshader")

# Définis AVANT add_child par l'appelant.
var lieux: Array[HoloLieuData] = []
var titre := ""
var sous_titre := ""
var fermable := true
var grille := 28   # taille de grille de la carte (pour placer les lieux côté appelant) — doit refléter HoloMap3D.grille
# Gabarit Excel à reproduire (vide → ville procédurale). Renseigné → décor lu
# depuis le fichier (la grille réelle vient alors du gabarit, pas de `grille`).
var chemin_xlsx := ""
# Modèle Excel DÉJÀ parsé (pré-injecté dans HoloMap3D) → évite de relire le .xlsx.
var excel_preinjecte: HoloXlsxMap = null
# Overlay PERSISTANT (préchargement) : la fermeture met en VEILLE (caché, rendu 3D
# et process coupés) au lieu de détruire — la réouverture (reveiller) est instantanée.
var persistant := false
# Construit invisible : quelques frames de rendu à modulate 0 (les shaders GL
# compilent MAINTENANT, pas au premier affichage) puis mise en veille automatique.
var demarrer_en_veille := false

# Couleurs du chrome (DA neutre, hors palette de rareté).
const CHROME_TITRE := Color(0.82, 0.88, 0.98)

var _map: HoloMap3D
var _vp: SubViewport
var _cont: SubViewportContainer
var _cont_filtre_defaut := Control.MOUSE_FILTER_STOP
var _lbl_titre: Label
var _lbl_sous_titre: Label
var _reveil_demande := false   # reveiller() appelé pendant le préchauffage → ne pas se rendormir

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Fond sombre (sous le viewport).
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0)  # noir (cohérent avec le fond 3D)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Conteneur + viewport 3D isolé, post-process porté par le conteneur.
	var cont := SubViewportContainer.new()
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont.stretch = true
	var mat := ShaderMaterial.new()
	mat.shader = POST_CONTAINER_SHADER
	cont.material = mat
	add_child(cont)
	_cont = cont
	_cont_filtre_defaut = cont.mouse_filter

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.physics_object_picking = true   # picking 3D des pins
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Anti-aliasing : configuré par HoloMap3D lui-même sur son viewport porteur
	# (supersampling 1.5× + MSAA 4×, cf. HoloMap3D._setup_viewport_aa) → même
	# qualité que la scène lancée seule ou capturée par le ScreenshotTool.
	cont.add_child(_vp)

	_map = HoloMap3D.new()
	_map.post_process_interne = false   # le post est sur le conteneur
	_map.grille = grille
	_map.chemin_xlsx = chemin_xlsx      # non vide → carte lue depuis le gabarit Excel
	if excel_preinjecte != null:
		_map._excel = excel_preinjecte  # modèle déjà parsé → pas de relecture du .xlsx
	if demarrer_en_veille:
		_map.intro_actif = false        # l'intro sera jouée au premier reveiller()
	if not lieux.is_empty():
		_map.lieux = lieux
	_map.lieu_selectionne.connect(func(id: String) -> void: lieu_selectionne.emit(id))
	_vp.add_child(_map)

	_construire_chrome()

	if demarrer_en_veille:
		# Invisible mais RENDU (modulate 0) : le préchauffage a besoin de vraies
		# frames dessinées pour compiler les shaders. Souris ignorée en attendant.
		modulate.a = 0.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_prechauffer()

# Préchauffage : laisse quelques frames se rendre (invisibles), puis veille
# complète. Si reveiller() arrive entre-temps (clic « Carte » précoce), on reste éveillé.
func _prechauffer() -> void:
	for i in 4:
		await get_tree().process_frame
	if not _reveil_demande and is_inside_tree():
		veille()

# Coupe tout (invisible, rendu 3D gelé, process du monde stoppé) SANS détruire :
# la géométrie et les shaders compilés restent prêts pour la prochaine ouverture.
func veille() -> void:
	_reveil_demande = false
	visible = false
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cont.mouse_filter = _cont_filtre_defaut
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_map.process_mode = Node.PROCESS_MODE_DISABLED

# Réveille un overlay en veille : rendu + process relancés, caméra réinitialisée
# et intro rejouée (même ressenti qu'une ouverture à neuf, sans le coût du build).
func reveiller() -> void:
	_reveil_demande = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cont.mouse_filter = _cont_filtre_defaut
	_map.process_mode = Node.PROCESS_MODE_INHERIT
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true
	_map.rejouer_intro()

# Met à jour le chrome (réouverture d'un overlay persistant : la langue a pu changer).
func definir_titres(nouveau_titre: String, nouveau_sous_titre: String) -> void:
	titre = nouveau_titre
	sous_titre = nouveau_sous_titre
	if is_instance_valid(_lbl_titre):
		_lbl_titre.text = nouveau_titre
	if is_instance_valid(_lbl_sous_titre):
		_lbl_sous_titre.text = nouveau_sous_titre

func _construire_chrome() -> void:
	if titre != "" or sous_titre != "":
		var head := VBoxContainer.new()
		head.set_anchors_preset(Control.PRESET_TOP_WIDE)
		head.offset_top = 16.0
		head.add_theme_constant_override("separation", 2)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(head)
		if titre != "":
			var t := UIHelpers.label(titre, 22, CHROME_TITRE)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
			t.add_theme_constant_override("shadow_offset_y", 2)
			head.add_child(t)
			_lbl_titre = t
		if sous_titre != "":
			var s := UIHelpers.label(sous_titre, 12, UIColors.TEXT_MUTED)
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.add_child(s)
			_lbl_sous_titre = s

	if fermable:
		var close := Button.new()
		close.text = "✕"
		close.add_theme_font_size_override("font_size", 20)
		close.add_theme_color_override("font_color", CHROME_TITRE)
		close.add_theme_color_override("font_hover_color", Color.WHITE)
		close.flat = true
		close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		close.offset_left = -52.0
		close.offset_top = 10.0
		close.offset_right = -12.0
		close.offset_bottom = 46.0
		close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		close.pressed.connect(_fermer)
		add_child(close)

func _fermer() -> void:
	ferme.emit()
	if persistant:
		veille()   # préchargé : on se rendort, prêt pour la prochaine ouverture
	else:
		queue_free()

# API publique : fermeture demandée par l'hôte (ex. Échap capté par Village dans
# _unhandled_key_input, phase qui précède notre _unhandled_input).
func fermer() -> void:
	if fermable:
		_fermer()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return   # en veille : un Control caché reçoit encore _unhandled_input
	if fermable and event.is_action_pressed("ui_cancel"):
		_fermer()
		get_viewport().set_input_as_handled()

# API publique : (re)peuple la carte 3D à partir des lieux découverts.
# Rafraîchissement LÉGER (les lieux seuls, pas le décor) : le décor ne dépend pas
# des découvertes, seul l'état des lieux évolue entre deux ouvertures.
func peupler_lieux(nouvelle_liste: Array[HoloLieuData]) -> void:
	lieux = nouvelle_liste
	if is_instance_valid(_map):
		_map.rafraichir_lieux(nouvelle_liste)
