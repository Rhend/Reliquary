extends Node
# ============================================================
# TestNeonsCite — enseignes néon vivantes du décor de ville (27/08/2026).
#
# Deux choses à garder, et elles n'ont pas la même nature :
#
#   • LA DONNÉE BAKÉE reste fidèle aux images. C'est le test qui compte : un
#     plan relivré par Christophe sans re-bake décollerait tous les points de
#     leurs enseignes, en silence et joliment — le pire mode de panne, celui
#     qu'on ne remarque qu'en regardant de près. On recalcule donc l'empreinte
#     des .png sources et on la compare à celle du bake. Mêmes rails que le
#     contrôle de silhouettes de TestShowRoom et que l'instantané de la holomap.
#
#   • LE RENDU dégrade proprement. Bake absent, bake périmé, tracé dégénéré :
#     dans tous les cas le décor doit rester exactement ce qu'il était, sans
#     point, jamais cassé. Un effet d'ambiance ne fait pas tomber un combat.
#
# N'ÉCRIT PAS la sauvegarde : rien ici ne touche à l'état de partie, mais
# CombatDecorCity est monté pour de vrai, donc on coupe par principe.
# ============================================================

var _results: Array = []

func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_couper_sauvegarde()
	await _run_all()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _couper_sauvegarde() -> void:
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false

func _run_all() -> void:
	print("\n=== TEST NEONS CITE (enseignes vivantes du décor) ===\n")
	_test_bake_present()
	_test_bake_a_jour()
	_test_integrite_traces()
	_test_traces_sur_la_lumiere()
	_test_cycle()
	_test_obsolescence()
	_test_echantillon()
	_test_trainee()
	await _test_montage_decor()

# ─── 1. Le bake existe et couvre les calques néon du décor ──

func _test_bake_present() -> void:
	print("[TEST 1] Présence du bake")
	var bake := NeonsCiteData.charger()
	_assert(bake != null, "le bake des néons se charge")
	if bake == null:
		return
	_assert(not bake.enseignes.is_empty(), "le bake n'est pas vide")

	# Tout calque « _Neon » empilé par le décor doit avoir ses tracés : c'est
	# le signal « Christophe a livré un plan de plus, le bake l'ignore encore ».
	for plan in CombatDecorCity.PLANS:
		var fichier := str(plan["f"])
		if not fichier.contains("_Neon"):
			continue
		var chemin := CombatDecorCity.DECOR_DIR + fichier
		if not ResourceLoader.exists(chemin):
			continue
		_assert(bake.enseignes.has(chemin), "%s : tracés bakés présents" % fichier)

# ─── 2. Anti-périmé : le bake correspond aux images réelles ─

func _test_bake_a_jour() -> void:
	print("\n[TEST 2] Le bake correspond encore aux images livrées")
	var bake := NeonsCiteData.charger()
	if bake == null:
		return
	for chemin: String in bake.enseignes:
		var e := bake.enseignes[chemin] as Dictionary
		_assert(ResourceLoader.exists(chemin), "%s : le calque existe" % chemin.get_file())
		if not ResourceLoader.exists(chemin):
			continue
		# Empreinte du fichier source : exacte, et ne coûte que ~400 Ko de
		# lecture. Le runtime, lui, n'a que la taille de texture (voir test 4).
		var reelle := NeonsCiteData.empreinte_fichier(chemin)
		_assert(reelle != "", "%s : source lisible" % chemin.get_file())
		_assert(reelle == str(e.get("empreinte", "")),
				"%s : le bake correspond à l'image livrée (sinon : re-baker)"
						% chemin.get_file())
		# Le cadrage baké doit être celui de la texture que le décor affichera.
		var tex := load(chemin) as Texture2D
		if tex != null:
			_assert(tex.get_size() == (e.get("source", Vector2.ZERO) as Vector2),
					"%s : cadrage baké = cadrage de la texture" % chemin.get_file())

# ─── 3. Les tracés sont exploitables ────────────────────────

func _test_integrite_traces() -> void:
	print("\n[TEST 3] Intégrité des tracés")
	var bake := NeonsCiteData.charger()
	if bake == null:
		return
	var total := 0
	for chemin: String in bake.enseignes:
		var e := bake.enseignes[chemin] as Dictionary
		var source := e.get("source", Vector2.ZERO) as Vector2
		var traces := e.get("traces", []) as Array
		_assert(not traces.is_empty(), "%s : au moins une enseigne" % chemin.get_file())
		var ok_points := true
		var ok_ferme := true
		var ok_longueur := true
		var ok_dedans := true
		var ok_vif := true
		for t: Dictionary in traces:
			total += 1
			var pts := t.get("points", PackedVector2Array()) as PackedVector2Array
			var lg := float(t.get("longueur", 0.0))
			var col := t.get("couleur", Color.BLACK) as Color
			if pts.size() < 4:
				ok_points = false
				continue
			# Refermé : le runtime compte dessus pour boucler sans cas spécial.
			if pts[0] != pts[pts.size() - 1]:
				ok_ferme = false
			var somme := 0.0
			for i in pts.size() - 1:
				somme += pts[i].distance_to(pts[i + 1])
			if absf(somme - lg) > 0.5 or lg <= 0.0:
				ok_longueur = false
			for p in pts:
				if p.x < 0.0 or p.y < 0.0 or p.x > source.x or p.y > source.y:
					ok_dedans = false
					break
			# Un néon est lumineux : une composante sombre est un artefact de
			# raccord, pas une enseigne, et le bake doit l'avoir écartée.
			if col.v < 0.2:
				ok_vif = false
		var nom := chemin.get_file()
		_assert(ok_points, "%s : chaque tracé a au moins 4 sommets" % nom)
		_assert(ok_ferme, "%s : chaque tracé est refermé" % nom)
		_assert(ok_longueur, "%s : la longueur bakée = le périmètre réel" % nom)
		_assert(ok_dedans, "%s : les sommets tombent dans l'image" % nom)
		_assert(ok_vif, "%s : aucune enseigne éteinte/noire retenue" % nom)
	print("  (%d enseignes bakées au total)" % total)

# ─── 3 bis. Les tracés tombent sur le TUBE, pas à côté ──────

# Le test qui garde le calage, de bout en bout. Le suivi de contour rend le bord
# extérieur de la forme, halo peint compris : sans recentrage, les sommets
# atterrissent dans le vide juste à côté de l'enseigne — visible à l'œil, et
# invisible à tout test qui ne regarderait que la géométrie. On relit donc les
# pixels de l'image sous les sommets et on exige qu'ils soient LUMINEUX.
func _test_traces_sur_la_lumiere() -> void:
	print("\n[TEST 3 bis] Les tracés suivent la lumière du néon")
	var bake := NeonsCiteData.charger()
	if bake == null:
		return
	for chemin: String in bake.enseignes:
		var tex := load(chemin) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var traces := (bake.enseignes[chemin] as Dictionary).get("traces", []) as Array
		var touches := 0
		var total := 0
		for t: Dictionary in traces:
			var pts := t.get("points", PackedVector2Array()) as PackedVector2Array
			# Un sommet sur trois suffit à juger, et garde le test rapide.
			for i in range(0, pts.size(), 3):
				total += 1
				if _lumiere_autour(img, pts[i], 3) > 0.33:
					touches += 1
		var part := float(touches) / maxf(float(total), 1.0)
		# Pas 100 % : un angle vif reste un compromis (le décalage y coupe la
		# corde) et quelques sommets peuvent tomber juste à côté du tube.
		_assert(part >= 0.80,
				"%s : %d %% des sommets tombent sur du néon allumé (attendu ≥ 80 %%)"
						% [chemin.get_file(), int(part * 100.0)])

# Luminance la plus forte dans un carré de rayon `r` autour de `p`, sur [0,1].
func _lumiere_autour(img: Image, p: Vector2, r: int) -> float:
	var pic := 0.0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := int(round(p.x)) + dx
			var y := int(round(p.y)) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			pic = maxf(pic, maxf(maxf(c.r, c.g), c.b) * c.a)
	return pic

# ─── 3 ter. Le cycle d'allumage ─────────────────────────────

func _test_cycle() -> void:
	print("\n[TEST 3 ter] Cycle d'allumage des enseignes")
	# Cycle de 10 s dont 4 allumées, sans déphasage : bornes calculables à la main.
	var r := {"cycle": 10.0, "allumee": 4.0, "phase_cycle": 0.0}
	_assert(NeonRunners.intensite_cycle(r, 2.0) == 1.0,
			"en plein milieu de la fenêtre, l'enseigne est à pleine intensité")
	_assert(NeonRunners.intensite_cycle(r, 6.0) == 0.0,
			"hors de la fenêtre, l'enseigne est éteinte")
	_assert(NeonRunners.intensite_cycle(r, 9.9) == 0.0,
			"elle reste éteinte jusqu'au bout du cycle")
	# Le cycle se répète : c'est ce qui fait respirer la ville sans fin.
	_assert(NeonRunners.intensite_cycle(r, 12.0) == 1.0,
			"le cycle recommence au tour suivant")
	# Fondus : ni apparition ni disparition brutale.
	var entree := NeonRunners.intensite_cycle(r, 0.1)
	var sortie := NeonRunners.intensite_cycle(r, 3.9)
	_assert(entree > 0.0 and entree < 1.0, "l'allumage passe par un fondu")
	_assert(sortie > 0.0 and sortie < 1.0, "l'extinction passe par un fondu")

	# Une fenêtre plus courte que deux fondus doit quand même s'allumer à fond.
	var court := {"cycle": 8.0, "allumee": 0.4, "phase_cycle": 0.0}
	_assert(NeonRunners.intensite_cycle(court, 0.2) == 1.0,
			"une fenêtre très courte atteint quand même sa pleine intensité")
	# Sans cycle déclaré (données anciennes, runner de test) : toujours vif.
	_assert(NeonRunners.intensite_cycle({}, 3.0) == 1.0,
			"un runner sans cycle reste allumé en permanence")

	# Les enseignes ne battent pas ensemble : c'est tout l'objet du déphasage.
	var decor_runners := _runners_du_decor()
	if decor_runners.size() >= 4:
		var actives := 0
		for rr: Dictionary in decor_runners:
			if NeonRunners.intensite_cycle(rr, 3.0) > 0.0:
				actives += 1
		_assert(actives > 0 and actives < decor_runners.size(),
				"à un instant donné, une partie seulement des enseignes est allumée (%d/%d)"
						% [actives, decor_runners.size()])

func _runners_du_decor() -> Array:
	var hote := Control.new()
	hote.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hote)
	var decor := CombatDecorCity.construire(hote, CombatCtbUi.SOL_Y_FRAC, 0.5)
	var sortie: Array = []
	if decor != null:
		for n: NeonRunners in _collecter(decor):
			sortie.append_array(n._runners)
	hote.queue_free()
	return sortie

# ─── 4. Le garde-fou d'obsolescence du RUNTIME ──────────────

func _test_obsolescence() -> void:
	print("\n[TEST 4] Rejet d'un bake périmé (contrôle runtime)")
	var bake := NeonsCiteData.charger()
	if bake == null or bake.enseignes.is_empty():
		return
	var chemin: String = bake.enseignes.keys()[0]
	var source := (bake.enseignes[chemin] as Dictionary).get("source", Vector2.ZERO) as Vector2

	_assert(not bake.traces(chemin, source).is_empty(),
			"au bon cadrage, les tracés sortent")
	_assert(not bake.traces(chemin).is_empty(),
			"sans cadrage fourni, le contrôle est sauté (usage des tests)")
	# Une relivraison à un autre cadrage décalerait tous les points : on préfère
	# ne rien dessiner plutôt que dessiner faux.
	_assert(bake.traces(chemin, source + Vector2(64, 0)).is_empty(),
			"à un cadrage différent, les tracés sont refusés")
	_assert(bake.traces("res://inexistant.png", source).is_empty(),
			"un calque inconnu ne rend rien")

# ─── 5. Échantillonnage le long d'un tracé ──────────────────

func _test_echantillon() -> void:
	print("\n[TEST 5] Parcours d'un tracé")
	# Carré de 10 de côté, refermé : périmètre 40, géométrie vérifiable à la main.
	var carre := PackedVector2Array([Vector2(0, 0), Vector2(10, 0),
			Vector2(10, 10), Vector2(0, 10), Vector2(0, 0)])
	var lg := 40.0

	var a := NeonsCiteData.echantillon(carre, lg, 5.0)
	_assert((a[0] as Vector2).is_equal_approx(Vector2(5, 0)),
			"à 5 sur 40, on est au milieu du premier côté")
	var b := NeonsCiteData.echantillon(carre, lg, 15.0)
	_assert((b[0] as Vector2).is_equal_approx(Vector2(10, 5)),
			"à 15, on est au milieu du deuxième côté")
	_assert((b[1] as Vector2).is_equal_approx(Vector2.DOWN),
			"la tangente suit le sens de parcours")
	# Le repli est ce qui fait tourner le point indéfiniment.
	var c := NeonsCiteData.echantillon(carre, lg, 45.0)
	_assert((c[0] as Vector2).is_equal_approx(Vector2(5, 0)),
			"à 45, le parcours a bouclé (45 = 5 + un tour)")
	var d := NeonsCiteData.echantillon(carre, lg, -5.0)
	_assert((d[0] as Vector2).is_equal_approx(Vector2(0, 5)),
			"une distance négative se replie aussi (dernier côté)")
	# Dégénérescences : on rend un point neutre, on ne plante pas.
	var vide := NeonsCiteData.echantillon(PackedVector2Array(), 0.0, 3.0)
	_assert(vide.size() == 2, "un tracé vide rend un échantillon neutre")

# ─── 6. Construction de la traînée ──────────────────────────

func _test_trainee() -> void:
	print("\n[TEST 6] Traînée du point lumineux")
	var carre := PackedVector2Array([Vector2(0, 0), Vector2(100, 0),
			Vector2(100, 100), Vector2(0, 100), Vector2(0, 0)])
	var lg := 400.0

	var ruban := NeonRunners._trainee(carre, lg, 50.0, 40.0)
	_assert(ruban.size() == NeonRunners.SEGMENTS_TRAINEE,
			"la traînée a le nombre de sommets attendu")
	if ruban.size() >= 2:
		# La tête est en fin de tableau : c'est l'ordre que _draw suppose pour
		# faire monter l'alpha de la queue vers le point.
		_assert(ruban[ruban.size() - 1].is_equal_approx(Vector2(50, 0)),
				"le dernier sommet est la TÊTE (à la distance demandée)")
		_assert(ruban[0].is_equal_approx(Vector2(10, 0)),
				"le premier sommet est la queue, une longueur en arrière")
		# Aucun saut : une traînée qui téléporte ferait un éclair en travers.
		var pas := 40.0 / float(NeonRunners.SEGMENTS_TRAINEE - 1)
		var continu := true
		for i in ruban.size() - 1:
			if ruban[i].distance_to(ruban[i + 1]) > pas * 1.5 + 0.01:
				continu = false
		_assert(continu, "les sommets se suivent sans saut")

	# Passage d'angle : la traînée doit épouser le coin, pas le couper.
	var coin := NeonRunners._trainee(carre, lg, 105.0, 20.0)
	var plie := false
	for p in coin:
		if p.x >= 99.9 and p.y > 0.1:
			plie = true
	_assert(plie, "la traînée tourne bien l'angle au lieu de le couper")

	# Le repli vaut aussi pour la traînée (tête juste après le bouclage).
	var boucle := NeonRunners._trainee(carre, lg, 5.0, 40.0)
	_assert(boucle.size() == NeonRunners.SEGMENTS_TRAINEE,
			"la traînée survit au passage par l'origine du tracé")
	# Dégénérescences : jamais de boucle infinie ni de crash.
	_assert(NeonRunners._trainee(carre, lg, 10.0, 0.0).is_empty(),
			"une traînée de longueur nulle ne rend rien")
	_assert(NeonRunners._trainee(PackedVector2Array([Vector2.ZERO]), 0.0, 1.0, 5.0).is_empty(),
			"un tracé dégénéré ne rend rien")

# ─── 7. Montage réel dans le décor ──────────────────────────

func _test_montage_decor() -> void:
	print("\n[TEST 7] Montage dans le décor de ville")
	var hote := Control.new()
	hote.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hote)
	var decor := CombatDecorCity.construire(hote, CombatCtbUi.SOL_Y_FRAC, 0.5)
	await get_tree().process_frame
	_assert(decor != null, "le décor se construit")
	if decor == null:
		return

	var runners := _collecter(decor)
	_assert(not runners.is_empty(), "des points lumineux sont montés sur le décor")

	var tous_dans_sprite := true
	var tous_additifs := true
	for r: NeonRunners in runners:
		if not (r.get_parent() is Sprite2D):
			tous_dans_sprite = false
		var mat := r.material as CanvasItemMaterial
		if mat == null or mat.blend_mode != CanvasItemMaterial.BLEND_MODE_ADD:
			tous_additifs = false
	# Le parentage EST le design : c'est lui qui donne défilement, zoom et
	# brume aux points. Le casser les figerait sur place sans rien signaler.
	_assert(tous_dans_sprite, "chaque groupe de points vit dans une copie du ruban")
	_assert(tous_additifs, "les points sont rendus en additif")

	# Le décor doit rester intact quand le bake ne s'applique pas.
	var orphelin := Sprite2D.new()
	var sans := NeonRunners.poser(orphelin, "res://inexistant_neon.png",
			Vector2(4770, 2655), 0.31)
	_assert(sans == null, "un calque sans tracé ne monte simplement rien")
	orphelin.free()

	# Et les points doivent AVANCER : c'est tout l'objet de l'effet.
	var cible: NeonRunners = runners[0]
	var avant := NeonRunners._trainee(
			cible._runners[0]["points"], cible._runners[0]["longueur"],
			cible._temps * float(cible._runners[0]["vitesse"]), 40.0)
	cible._process(0.5)
	var apres := NeonRunners._trainee(
			cible._runners[0]["points"], cible._runners[0]["longueur"],
			cible._temps * float(cible._runners[0]["vitesse"]), 40.0)
	_assert(not avant.is_empty() and not apres.is_empty()
			and not avant[avant.size() - 1].is_equal_approx(apres[apres.size() - 1]),
			"le point se déplace avec le temps")

	hote.queue_free()

func _collecter(racine: Node) -> Array:
	var sortie: Array = []
	if racine is NeonRunners:
		sortie.append(racine)
	for enfant in racine.get_children():
		sortie.append_array(_collecter(enfant))
	return sortie

# ─── Utilitaires ────────────────────────────────────────────

func _assert(cond: bool, label: String) -> void:
	_results.append({"ok": cond, "label": label})
	print(("  ✓ " if cond else "  ✗ ") + label)

func _print_report() -> void:
	var total := _results.size()
	var passed := _results.filter(func(r): return r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, total, total - passed])
	if passed < total:
		print("ÉCHECS :")
		for r in _results:
			if not r["ok"]:
				print("  ✗ " + r["label"])
	print("════════════════════════════════\n")
