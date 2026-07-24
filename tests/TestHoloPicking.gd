extends Node
# ============================================================
# TestHoloPicking — Régression du picking des ZONES D'EXPÉDITION sur la
# carte holo 3D (HoloMap3DOverlay → SubViewport → Area3D des HoloLocation3D).
#
# Reproduit le flux RÉEL de la souris : événements poussés sur la fenêtre
# racine (règle projet : root.size = 1280×720 d'abord), relayés par le
# SubViewportContainer au viewport 3D, résolus par le picking physique.
# Couvre :
#   1. les zones à ID du gabarit Excel (données des Lieux — jamais vides) ;
#   2. le survol + clic de CHAQUE lieu sur un overlay fraîchement construit
#      (+ PERSISTANCE du survol souris immobile, vérifiée en fenêtré) ;
#   3. le survol + clic après un cycle VEILLE → peupler_lieux → RÉVEIL
#      (chemin de réouverture de l'overlay persistant, chantier 12) ;
#   4. l'absence de sélection fantôme (clic dans le vide) ;
#   5. le VRAI Village : ouverture de la carte, clic Lieu → panneau de
#      lancement, Annuler → la carte répond toujours (empilement réel).
#
# ⚠ La section 5 instancie le vrai Village : protocole TestFluxExpedition —
# sauvegarde réelle mise de côté (.avant_test) puis restaurée avant de quitter.
#
# NOTE headless : le « passive hover » du moteur re-picke chaque frame à la
# position RÉELLE de la souris OS ; en headless (souris figée hors carte) le
# survol retombe dès qu'aucun motion n'arrive. Les assertions de survol
# passent donc par le SIGNAL survol_change (l'entrée a bien eu lieu) ; la
# persistance souris immobile n'est vérifiée qu'en fenêtré (vraie souris,
# Input.warp_mouse).
# ⚠ Le mode FENÊTRÉ est un outil de diagnostic MANUEL : il warpe la vraie
# souris — ne pas toucher souris/clavier pendant le run, et aucune fenêtre
# (console comprise) ne doit recouvrir celle du jeu, sinon échecs parasites.
# La CI utilise le mode headless, déterministe.
# ============================================================

const SAUV := "user://IdleEvolutionSave.json"
const META := SaveManager.META_PATH
const FICHIERS_SAUV: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]

var _fail: Array[String] = []
var _nb_ok := 0
var _selections: Array[String] = []
var _survols: Array[String] = []   # ids reçus via survol_change(actif=true)

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _ready() -> void:
	print("\n=== TEST PICKING HOLOMAP (zones d'expédition) ===\n")
	# Fenêtre headless : 64×64 par défaut → tout picking au-delà tombe hors
	# champ. À poser AVANT toute construction d'UI (règle projet, cf. CLAUDE.md).
	get_tree().root.size = Vector2i(1280, 720)
	_proteger_sauvegarde()
	await get_tree().process_frame

	var xlsx := HoloXlsxMap.new()
	_check("gabarit chargé", xlsx.charger(HoloMap3D.CHEMIN_GABARIT_DEFAUT))
	_test_zones_gabarit(xlsx)

	var holo := _construire_overlay(xlsx)
	add_child(holo)
	await _attendre(1.6)   # intro de matérialisation (~1.15 s) + marge

	print("\n[2] Picking sur overlay fraîchement construit")
	await _test_picking(holo)

	print("\n[2b] Caméra BASSE (plongée min) : le corps de chaque zone répond au bon lieu")
	await _test_angle_bas(holo)

	print("\n[3] Picking après veille → peupler_lieux → réveil (réouverture ch.12)")
	holo.veille()
	await get_tree().process_frame
	holo.peupler_lieux(_lieux_depuis_zones(xlsx))
	holo.reveiller()
	await _attendre(1.6)   # l'intro est rejouée au réveil
	await _test_picking(holo)

	print("\n[4] Clic dans le vide → aucune sélection fantôme")
	_selections.clear()
	await _cliquer(Vector2(20.0, 700.0))   # coin bas-gauche : hors de toute zone
	_check("clic dans le vide → rien", _selections.is_empty())
	holo.queue_free()
	await get_tree().process_frame

	print("\n[5] Empilement RÉEL : Village → carte → clic Lieu → lancement → Annuler")
	await _test_village()

	_restaurer_sauvegarde()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── 1. Zones à ID du gabarit ────────────────────────────────

func _test_zones_gabarit(xlsx: HoloXlsxMap) -> void:
	print("[1] Zones à ID du gabarit (source des Lieux)")
	_check("au moins une zone à ID", not xlsx.zones.is_empty())
	for z: Dictionary in xlsx.zones:
		var id := str(z["id"])
		var cells: Array = z["cells"]
		var bbox: Rect2i = z["bbox"]
		print("    zone « %s » : %d cellule(s), bbox %s" % [id, cells.size(), str(bbox)])
		_check("zone « %s » : cellules non vides" % id, not cells.is_empty())
		_check("zone « %s » : bbox valide" % id, bbox.size.x >= 1 and bbox.size.y >= 1)

# ─── Overlay de test (lieux fabriqués depuis les zones réelles) ──

func _construire_overlay(xlsx: HoloXlsxMap) -> HoloMap3DOverlay:
	var holo := HoloMap3DOverlay.new()
	holo.titre = "TEST"
	holo.chemin_xlsx = HoloMap3D.CHEMIN_GABARIT_DEFAUT
	holo.excel_preinjecte = xlsx
	holo.lieux = _lieux_depuis_zones(xlsx)
	holo.persistant = true   # veille/réveil au lieu de free (chemin ch.12)
	holo.lieu_selectionne.connect(func(id: String) -> void: _selections.append(id))
	return holo

# Même construction que Village._lieux_depuis_zones, découverte FORCÉE →
# indépendant de l'état de sauvegarde (le test vise le picking, pas GameData).
func _lieux_depuis_zones(xlsx: HoloXlsxMap) -> Array[HoloLieuData]:
	var out: Array[HoloLieuData] = []
	for z: Dictionary in xlsx.zones:
		var bbox: Rect2i = z["bbox"]
		var l := HoloLieuData.new()
		l.id = str(z["id"])
		l.nom_affichage_fr = l.id
		l.tier = 1
		l.cellule = bbox.position
		l.emprise = Vector2i(maxi(1, bbox.size.x), maxi(1, bbox.size.y))
		var cells: Array[Vector2i] = []
		for c: Vector2i in z["cells"]:
			cells.append(c)
		l.cells = cells
		l.decouvert = true
		out.append(l)
	return out

# ─── 2/3. Survol + clic de chaque lieu ───────────────────────

func _test_picking(holo: HoloMap3DOverlay) -> void:
	var map: HoloMap3D = holo._map
	_check("carte présente", is_instance_valid(map))
	var locs := _locs_de(map)
	_check("des HoloLocation3D existent", not locs.is_empty())
	for loc in locs:
		if not loc.survol_change.is_connected(_sur_survol_change):
			loc.survol_change.connect(_sur_survol_change)
		var pos := _pos_ecran_pin(map, loc)
		if pos.x < 0.0 or pos.y < 0.0 or pos.x >= 1280.0 or pos.y >= 720.0:
			print("    (« %s » hors champ à l'écran %s — ignoré)" % [loc.lieu_id, str(pos)])
			continue
		# Survol : l'entrée doit être détectée (barrière + tooltip côté jeu).
		_survols.clear()
		var stable := await _survoler_jusqua(map, loc, pos)
		_check("survol « %s » détecté (pin à %s)" % [loc.lieu_id, str(pos.round())],
				stable or _survols.has(loc.lieu_id))
		# PERSISTANCE (fenêtré seulement — vraie souris posée sur le pin) :
		# souris immobile → le survol doit TENIR (barrière/tooltip stables).
		if stable and not _headless():
			for i in 40:   # ~0.66 s d'immobilité totale
				await get_tree().physics_frame
			await get_tree().process_frame
			_check("survol « %s » PERSISTE souris immobile" % loc.lieu_id,
					map._hovered == loc)
		# Clic : la sélection doit porter l'ID du lieu.
		_selections.clear()
		await _cliquer(pos)
		_check("clic « %s » → lieu_selectionne" % loc.lieu_id,
				_selections.size() == 1 and _selections[0] == loc.lieu_id)
		# Sortie de survol : plus de lieu actif (pas de tooltip fantôme).
		await _survoler(Vector2(10.0, 710.0))
		_check("sortie de survol « %s »" % loc.lieu_id, map._hovered == null)

# Caméra à plongée MINIMALE (vue la plus rasante que l'orbite autorise) : le
# joueur explore la carte sous cet angle — chaque zone doit rester détectable
# en visant son CORPS (mi-hauteur du marqueur). Les colonnes de collision des
# zones de premier plan ne doivent pas voler le survol des zones derrière.
func _test_angle_bas(holo: HoloMap3DOverlay) -> void:
	var map: HoloMap3D = holo._map
	var plongee_avant := map.plongee_deg
	map.plongee_deg = map.plongee_min
	map._appliquer_camera()
	await get_tree().process_frame
	for loc in _locs_de(map):
		var wp := loc.to_global(Vector3(0.0, loc.hauteur * 0.5, 0.0))
		if map._cam.is_position_behind(wp):
			continue
		var pos: Vector2 = map._cam.unproject_position(wp)
		if pos.x < 0.0 or pos.y < 0.0 or pos.x >= 1280.0 or pos.y >= 720.0:
			print("    (« %s » hors champ — ignoré)" % loc.lieu_id)
			continue
		_survols.clear()
		var stable := await _survoler_jusqua(map, loc, pos)
		var vole := ""
		if not (stable or _survols.has(loc.lieu_id)):
			vole = " [%s]" % ("rien" if map._hovered == null else map._hovered.lieu_id + " devant")
			_diag_rayon(map, pos)
		_check("angle bas : zone « %s » répond (corps à %s)%s"
				% [loc.lieu_id, str(pos.round()), vole],
				stable or _survols.has(loc.lieu_id))
		await _survoler(Vector2(10.0, 710.0))
	map.plongee_deg = plongee_avant
	map._appliquer_camera()
	await get_tree().process_frame

func _locs_de(map: HoloMap3D) -> Array[HoloLocation3D]:
	var out: Array[HoloLocation3D] = []
	if is_instance_valid(map._lieux_node):
		for c in map._lieux_node.get_children():
			if c is HoloLocation3D:
				out.append(c)
	return out

func _sur_survol_change(loc: HoloLocation3D, actif: bool) -> void:
	if actif:
		_survols.append(loc.lieu_id)

# Point écran visé : le PIN diamant (au-dessus du toit) — la partie du
# marqueur toujours dégagée du décor depuis la caméra par défaut.
func _pos_ecran_pin(map: HoloMap3D, loc: HoloLocation3D) -> Vector2:
	var cam: Camera3D = map._cam
	var wp := loc.to_global(Vector3(0.0, loc.hauteur + loc.pin_float, 0.0))
	if cam.is_position_behind(wp):
		return Vector2(-1, -1)
	return cam.unproject_position(wp)

# ─── 5. Empilement réel : Village complet ────────────────────

func _test_village() -> void:
	var village: Village = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	village.open_expedition_map()
	await _attendre(1.8)   # build (pas de préchargement encore) + intro
	var overlay := village._holo_overlay as HoloMap3DOverlay
	_check("open_expedition_map ouvre la carte", overlay != null and is_instance_valid(overlay))
	if overlay == null:
		village.queue_free()
		return
	var map: HoloMap3D = overlay._map
	var locs := _locs_de(map)
	_check("des Lieux découverts existent au Village", not locs.is_empty())
	if locs.is_empty():
		village.queue_free()
		return
	for loc in locs:
		if not loc.survol_change.is_connected(_sur_survol_change):
			loc.survol_change.connect(_sur_survol_change)
	var loc0 := locs[0]
	var pos := _pos_ecran_pin(map, loc0)
	_check("pin « %s » à l'écran" % loc0.lieu_id,
			pos.x >= 0.0 and pos.y >= 0.0 and pos.x < 1280.0 and pos.y < 720.0)
	# Survol à travers l'empilement réel (hub dessous, chrome, autoloads).
	_survols.clear()
	var stable := await _survoler_jusqua(map, loc0, pos)
	if not (stable or _survols.has(loc0.lieu_id)):
		_log_control_sous(pos)   # diagnostic : qui capte la souris ?
	_check("survol « %s » dans le VRAI Village" % loc0.lieu_id,
			stable or _survols.has(loc0.lieu_id))
	# Clic → panneau de lancement d'expédition.
	await _cliquer(pos)
	await get_tree().process_frame
	var panneau: ExpeLancementPanel = village._expe_lancement
	_check("clic Lieu → panneau de lancement ouvert",
			panneau != null and is_instance_valid(panneau))
	if panneau != null and is_instance_valid(panneau):
		_check("panneau : destination = lieu cliqué", panneau.lieu_id == loc0.lieu_id)
		panneau.annuler()
		await get_tree().process_frame
		_check("Annuler ferme le panneau",
				village._expe_lancement == null or not is_instance_valid(village._expe_lancement))
	# La carte doit répondre ENCORE après l'aller-retour panneau.
	_survols.clear()
	_selections.clear()
	var stable2 := await _survoler_jusqua(map, loc0, pos)
	_check("survol répond encore après Annuler", stable2 or _survols.has(loc0.lieu_id))
	await _cliquer(pos)
	await get_tree().process_frame
	_check("clic répond encore après Annuler (panneau rouvert)",
			village._expe_lancement != null and is_instance_valid(village._expe_lancement))
	village.queue_free()
	await get_tree().process_frame

# Diagnostic d'échec : rayon physique DIRECT depuis la caméra à ce point
# d'écran — révèle ce que le picking devrait rencontrer (et où).
func _diag_rayon(map: HoloMap3D, pos: Vector2) -> void:
	var origine: Vector3 = map._cam.project_ray_origin(pos)
	var dir: Vector3 = map._cam.project_ray_normal(pos)
	var params := PhysicsRayQueryParameters3D.create(origine, origine + dir * 1000.0)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var res: Dictionary = map.get_world_3d().direct_space_state.intersect_ray(params)
	if res.is_empty():
		print("    [diag] rayon (%s → %s) : AUCUNE collision" % [str(origine), str(dir)])
	else:
		var col := res["collider"] as Node
		print("    [diag] rayon touche %s à %s" % [
				col.lieu_id if col is HoloLocation3D else str(col), str(res["position"])])

# Diagnostic d'échec : quel Control (chemin complet) est sous ce point ?
func _log_control_sous(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev)
	await get_tree().process_frame
	var c := get_tree().root.gui_get_hovered_control()
	print("    [diag] Control sous %s : %s" % [str(pos.round()),
			"aucun" if c == null else str(c.get_path())])

# ─── Simulation souris (root.push_input → SubViewportContainer → 3D) ──

# Survol avec polling : émet le mouvement puis attend que `loc` soit survolé
# (latence du warp OS en fenêtré). true si l'état STABLE a été observé.
func _survoler_jusqua(map: HoloMap3D, loc: HoloLocation3D, pos: Vector2) -> bool:
	_emettre_motion(pos)
	for i in 72:   # ~1.2 s au pas physique
		await get_tree().physics_frame
		if map._hovered == loc:
			return true
	return false

func _survoler(pos: Vector2) -> void:
	_emettre_motion(pos)
	for i in 3:
		await get_tree().physics_frame   # le picking se résout au pas physique
	await get_tree().process_frame

# Fenêtré : VRAIE souris déplacée par l'OS — le pipeline complet
# (DisplayServer → Window → SubViewportContainer) est exercé.
# Headless : push synthétique sur la racine (pas de souris OS).
func _emettre_motion(pos: Vector2) -> void:
	if not _headless():
		Input.warp_mouse(pos)
		return
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev)

func _cliquer(pos: Vector2) -> void:
	await _survoler(pos)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	get_tree().root.push_input(press)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pos
	rel.global_position = pos
	get_tree().root.push_input(rel)
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame

# ─── Protection de la sauvegarde réelle (protocole TestFluxExpedition) ──

func _proteger_sauvegarde() -> void:
	for f: String in FICHIERS_SAUV:
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f),
					ProjectSettings.globalize_path(f) + ".avant_test")
	# Le méta réel a déjà été lu par SaveManager._ready : partie neuve propre.
	SaveManager._meta_chargee = true
	SaveManager._reconstructions = 1
	SaveManager._appliquer_nom_hero()

func _restaurer_sauvegarde() -> void:
	for f: String in FICHIERS_SAUV:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if FileAccess.file_exists(f + ".avant_test"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f) + ".avant_test",
					ProjectSettings.globalize_path(f))

# ─── Harnais ─────────────────────────────────────────────────

func _attendre(secondes: float) -> void:
	await get_tree().create_timer(secondes).timeout

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
