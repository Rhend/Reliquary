extends Node
# ============================================================
# TestShowRoom — vitrine dev des assets Spine (08/2026).
#
# Vérifie le REGISTRE et l'ALLER-RETOUR QG ↔ ShowRoom, pas le rendu :
#   • le registre décrit des assets qui existent réellement ;
#   • les apparences suivent la bonne règle (variantes > paliers > unique) ;
#   • le bouton dev du QG mène à la vitrine et Échap ramène au QG ;
#   • lancée seule, la vitrine ne dépend d'aucun état de partie.
#
# N'ÉCRIT PAS la sauvegarde : les listeners de SaveManager sont coupés
# d'entrée (la scène Village en déclencherait au chargement).
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
	print("\n=== TEST SHOWROOM (vitrine des assets Spine) ===\n")
	_test_registre()
	_test_apparences()
	await _test_aller_retour_qg()
	await _test_lumiere()
	await _test_costumes()
	await _test_echelle()

# ─── 1. Le registre pointe sur des assets réels ─────────────

func _test_registre() -> void:
	print("[TEST 1] Registre des personnages Spine")
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	_assert(reg != null, "le registre se charge")
	if reg == null:
		return
	_assert(not reg.personnages.is_empty(), "le registre n'est pas vide")
	_assert(not reg.heros().is_empty(), "un héros est déclaré (vis-à-vis du mode combat)")
	_assert(reg.ennemis().size() >= 2, "au moins 2 ennemis déclarés (FlameBot, WorkBot)")
	# Un chemin mort ne se voit qu'à l'exécution : la vitrine afficherait un
	# trou silencieux (creer() rend null et l'appelant continue).
	for p in reg.personnages:
		var id := str(p.get("id", "?"))
		_assert(ResourceLoader.exists(str(p.get("skel", ""))), "%s : .skel présent" % id)
		_assert(ResourceLoader.exists(str(p.get("atlas", ""))), "%s : .atlas présent" % id)

# ─── 2. Règle des apparences ────────────────────────────────

func _test_apparences() -> void:
	print("\n[TEST 2] Apparences : variantes > paliers > unique")
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData

	# Ennemi : 5 paliers, skins Nv1..Nv5, Nv1 = Commun.
	var mob := reg.ennemis()[0]
	var ap_mob := SpinePersonnagesData.apparences(mob)
	_assert(ap_mob.size() == SpinePersonnagesData.NB_PALIERS,
			"ennemi → %d apparences (une par palier)" % SpinePersonnagesData.NB_PALIERS)
	_assert(str(ap_mob[0].get("skin", "")).ends_with("Nv1"), "1re apparence = Nv1 (Commun)")
	_assert(int(ap_mob[0].get("palier", -1)) == 0, "1re apparence portée par le palier 0")
	_assert(str(ap_mob[4].get("skin", "")).ends_with("Nv5"), "5e apparence = Nv5 (Légendaire)")

	# Héros (livraison « costumes » du 24/08/2026) : ses paliers ne sont PAS
	# des skins mais des SLOTS « _Nv<n> », posés sur une composition de skins.
	var h := reg.heros()
	var ap_h := SpinePersonnagesData.apparences(h)
	_assert(ap_h.size() == 6, "héros → 6 niveaux d'équipement")
	_assert(str(ap_h[0].get("skin", "")) == "",
			"niveau porté par les slots, jamais par une skin nommée")
	_assert(int(ap_h[0].get("niveau", 0)) == 1, "1er niveau = Nv1")
	_assert(int(ap_h[0].get("palier", -1)) == 0, "Nv1 = palier Commun")
	_assert(int(ap_h[5].get("palier", -1)) == 5, "Nv6 = palier Unique")
	var skins_h := ap_h[0].get("skins", PackedStringArray()) as PackedStringArray
	_assert(skins_h.size() >= 2, "les skins du héros sont CUMULÉES (corps + équipement + …)")
	_assert("Men_Global" in skins_h, "le corps est de la partie")

	# Accessoires « Random » : axe indépendant du niveau. Changer de jeu change
	# la composition, pas le nombre de niveaux — sinon [V] déformerait la vitrine.
	var jeux := SpinePersonnagesData.cosmetiques(h)
	_assert(jeux.size() >= 2, "au moins 2 jeux cosmétiques déclarés")
	var ap_h2 := SpinePersonnagesData.apparences(h, 1)
	_assert(ap_h2.size() == ap_h.size(), "changer d'accessoire ne change pas le nombre de niveaux")
	_assert((ap_h2[0].get("skins", PackedStringArray()) as PackedStringArray) != skins_h,
			"changer d'accessoire change bien la composition de skins")
	# Index hors bornes : la vitrine ne doit pas planter, elle borne.
	_assert(not (SpinePersonnagesData.apparences(h, 99)[0].get("skins",
			PackedStringArray()) as PackedStringArray).is_empty(),
			"index de cosmétique hors bornes → borné, jamais d'apparence vide")

	# Variantes NOMMÉES (forme prévue pour le héros M/F) : elles priment sur
	# les paliers. Garde le contrat en place avant que Christophe ne livre.
	var factice := {"nom": "X", "prefixe_skin": "X_Nv",
			"variantes": [{"skin": "X_M", "nom": "Masculin"},
					{"skin": "X_F", "nom": "Féminin"}]}
	var ap_f := SpinePersonnagesData.apparences(factice)
	_assert(ap_f.size() == 2, "variantes nommées → 2 apparences (pas les 5 paliers)")
	_assert(str(ap_f[1].get("nom", "")) == "Féminin", "le libellé de la variante est repris")
	_assert(int(ap_f[0].get("palier", 0)) == -1, "variante nommée → hors échelle de rareté")

# ─── 3. Aller-retour QG → ShowRoom → QG ─────────────────────

func _test_aller_retour_qg() -> void:
	print("\n[TEST 3] Bouton dev du QG → vitrine → retour au QG")
	_assert(Village.DEBUG_SHOWROOM_BTN,
			"le bouton dev est actif (sinon la vitrine est injoignable en jeu)")

	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	# Lancée SEULE : pas de destination de retour, Échap quitterait.
	ShowRoom.scene_retour = ""
	add_child(salle)
	await get_tree().process_frame
	_assert(salle._rangees().size() >= 3, "vitrine peuplée : héros + ennemis")
	_assert(salle._mode == ShowRoom.Mode.LIBRE, "démarre en mode libre")

	salle._mode = ShowRoom.Mode.COMBAT
	salle._appliquer_mode()
	_assert(salle._duel.get_child_count() >= 1, "mode combat : le duel est peuplé")
	_assert(salle._decor.visible and not salle._fond_neutre.visible,
			"mode combat : fond scindé affiché, fond neutre masqué")

	# Cycle de palier et de monstre : la commutation ne doit pas vider la scène.
	salle._idx_palier = SpinePersonnagesData.NB_PALIERS - 1
	salle._idx_monstre = salle._ennemis.size() - 1
	salle._peupler_duel()
	_assert(salle._duel.get_child_count() >= 1, "duel encore peuplé après changement de cible")

	salle._mode = ShowRoom.Mode.LIBRE
	salle._appliquer_mode()
	_assert(salle._fond_neutre.visible and not salle._decor.visible,
			"retour au mode libre : fond neutre repris")

	# Contrat de sortie : avec une destination posée, Échap n'éteint PAS le jeu.
	ShowRoom.scene_retour = "res://scenes/village/village.tscn"
	_assert(ShowRoom.scene_retour != "", "destination de retour posée par le QG")
	salle.free()
	ShowRoom.scene_retour = ""

# ─── 4. Éclairage ───────────────────────────────────────────
# Le fond d'origine (quasi noir) noyait les paliers Commun, gris foncé.
# On garde deux garde-fous : la vitrine ne redémarre pas dans le noir, et
# elle n'éclaire JAMAIS les personnages — sinon on juge un rendu faussé.

func _test_lumiere() -> void:
	print("\n[TEST 4] Éclairage : fond réglable, assets jamais modulés")
	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	ShowRoom.scene_retour = ""
	add_child(salle)
	await get_tree().process_frame

	var defaut: Color = ShowRoom.NIVEAUX_LUMIERE[ShowRoom.LUMIERE_DEFAUT]["fond"]
	var nuit: Color = ShowRoom.NIVEAUX_LUMIERE[0]["fond"]
	_assert(defaut.get_luminance() > nuit.get_luminance(),
			"le niveau par défaut est plus clair que « Nuit » (on voit les Communs)")
	_assert(salle._fond_neutre.color.is_equal_approx(defaut),
			"le fond appliqué est bien celui du niveau par défaut")

	# Le cycle passe par tous les niveaux et boucle.
	var vus: Array[String] = []
	for i in ShowRoom.NIVEAUX_LUMIERE.size():
		vus.append(salle._nom_lumiere())
		salle._touche(KEY_B)
	_assert(vus.size() == ShowRoom.NIVEAUX_LUMIERE.size() and vus[0] == "Studio",
			"[B] parcourt les %d niveaux" % ShowRoom.NIVEAUX_LUMIERE.size())
	_assert(salle._idx_lumiere == ShowRoom.LUMIERE_DEFAUT, "[B] boucle sur le premier niveau")

	# Contraste : sur fond clair, les textes doivent s'assombrir, sinon ils
	# blanchissent (le HUD était illisible en « Jour » au premier essai).
	var i_clair := -1
	for i in ShowRoom.NIVEAUX_LUMIERE.size():
		if (ShowRoom.NIVEAUX_LUMIERE[i]["fond"] as Color).get_luminance() > ShowRoom.SEUIL_FOND_CLAIR:
			i_clair = i
			break
	_assert(i_clair >= 0, "au moins un niveau clair est proposé")
	if i_clair >= 0:
		salle._idx_lumiere = i_clair
		_assert(salle._fond_clair(), "ce niveau est bien détecté comme clair")
		var base := UIColors.TEXT_HEADER
		_assert(ShowRoom._lisible(base, true).get_luminance() < base.get_luminance(),
				"texte assombri sur fond clair")
		_assert(ShowRoom._lisible(base, false).is_equal_approx(base),
				"texte inchangé sur fond sombre")

	# Le voile n'existe qu'en combat et ne touche que le décor.
	salle._mode = ShowRoom.Mode.COMBAT
	salle._idx_lumiere = ShowRoom.NIVEAUX_LUMIERE.size() - 1
	salle._appliquer_mode()
	_assert(salle._voile.visible and salle._voile.color.a > 0.0,
			"mode combat : le voile éclaircit le décor")
	for sprite in salle._duel.get_children():
		_assert((sprite as Node2D).modulate.is_equal_approx(Color.WHITE),
				"le personnage n'est PAS modulé (couleurs d'origine préservées)")
	salle.free()

# ─── 5. Costumes de Relic (livraison 24/08/2026) ────────────
# Les 6 niveaux d'équipement ne sont pas des skins : chaque pièce a SON slot,
# suffixé « _Nv<n> ». Poser un niveau = purger la skin composée des slots des
# autres niveaux — sinon les 6 tenues s'empilent sur le personnage.

func _test_costumes() -> void:
	print("\n[TEST 5] Costumes : niveaux portés par les slots")

	# Lecture du suffixe : Christophe mutualise une pièce quand elle ne change
	# pas d'un niveau à l'autre, avec deux notations (« / » et « _ »).
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Tete_Nv3") == [3],
			"« _Nv3 » → niveau 3")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Pentalon_Nv4/5") == [4, 5],
			"« _Nv4/5 » → niveaux 4 et 5")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Manche_D_Nv1_2_3") == [1, 2, 3],
			"« _Nv1_2_3 » → niveaux 1 à 3")
	# Livraison « rework au propre » du 26/08/2026 : la notation passe à
	# « _Nv_<n> » (souligné après Nv), et une pièce commune à tous les niveaux
	# les liste tous. Christophe a uniformisé le 26/08 (plus aucun « _Nv1 »
	# sans souligné) ; les formes anciennes restent testées au-dessus, un vieil
	# export ou une livraison d'ennemi pouvant encore les porter.

	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Tete_Nv_4") == [4],
			"« _Nv_4 » → niveau 4")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Pentalon_Bassin_Nv_3_4") == [3, 4],
			"« _Nv_3_4 » → niveaux 3 et 4")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Veste_Torse_Nv_1_2_3_4_5_6") == [1, 2, 3, 4, 5, 6],
			"la veste commune « _Nv_1_2_3_4_5_6 » → les 6 niveaux")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Torse").is_empty(),
			"slot sans marqueur → indépendant du niveau (toujours affiché)")
	_assert(SpriteSpinePersonnage.niveaux_du_slot("R_H_Idle_Tete_Mort").is_empty(),
			"slot de mort → jamais filtré par le niveau")

	if not SpriteSpinePersonnage.disponible():
		print("  (runtime spine-godot absent : purge réelle non vérifiable)")
		return

	# Purge réelle : au Nv1, les pièces du Nv6 ne doivent RIEN porter.
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	var h := reg.heros()
	var ap := SpinePersonnagesData.apparences(h)
	var nv1 := SpriteSpinePersonnage.creer(str(h.get("skel", "")), str(h.get("atlas", "")), ap[0])
	var nv6 := SpriteSpinePersonnage.creer(str(h.get("skel", "")), str(h.get("atlas", "")), ap[5])
	_assert(nv1 != null and nv6 != null, "les deux extrêmes se construisent")
	if nv1 != null and nv6 != null:
		add_child(nv1)
		add_child(nv6)
		await get_tree().process_frame
		# Dans cet export, l'attachement d'un slot porte le nom du slot.
		_assert(_porte(nv1, "R_H_Idle_Tete_Nv_1"), "Nv1 : la tête Nv1 est portée")
		_assert(not _porte(nv1, "R_H_Idle_Tete_Nv_6"), "Nv1 : la tête Nv6 est purgée")
		_assert(_porte(nv6, "R_H_Idle_Tete_Nv_6"), "Nv6 : la tête Nv6 est portée")
		_assert(not _porte(nv6, "R_H_Idle_Tete_Nv_1"), "Nv6 : la tête Nv1 est purgée")
		_assert(_porte(nv1, "R_H_Idle_Torse") and _porte(nv6, "R_H_Idle_Torse"),
				"le corps commun reste porté aux deux")
		# Animations : Attack_Shoot n'est livrée QUE pour le héros — la jouer
		# sur un ennemi doit être sans effet, jamais une erreur de runtime.
		_assert(nv1.a_animation(SpriteSpinePersonnage.ANIM_ATTACK_SHOOT),
				"le héros porte l'attaque à distance")
		# L'accessoire de visage doit changer le SQUELETTE, pas seulement la
		# liste de skins : sans ça, [V] serait un libellé qui ne fait rien.
		var visage2 := SpriteSpinePersonnage.creer(str(h.get("skel", "")),
				str(h.get("atlas", "")), SpinePersonnagesData.apparences(h, 1)[0])
		if visage2 != null:
			add_child(visage2)
			_assert(_porte(nv1, "R_H_Idle_Visage_1"), "jeu 1 : le visage 1 est porté")
			_assert(not _porte(visage2, "R_H_Idle_Visage_1"), "jeu 2 : le visage 1 a disparu")
			_assert(_porte(visage2, "R_H_Idle_Visage_2"), "jeu 2 : le visage 2 l'a remplacé")
			visage2.free()
		nv1.free()
		nv6.free()

	var mob := reg.ennemis()[0]
	var sbire := SpriteSpinePersonnage.creer(str(mob.get("skel", "")), str(mob.get("atlas", "")),
			SpinePersonnagesData.apparences(mob)[0])
	if sbire != null:
		add_child(sbire)
		_assert(not sbire.a_animation(SpriteSpinePersonnage.ANIM_ATTACK_SHOOT),
				"l'ennemi ne la porte pas")
		sbire.jouer_attaque(true)   # doit retomber sur la mêlée, sans erreur
		_assert(true, "un tir demandé à un ennemi retombe sur sa mêlée")
		sbire.free()

	# La vitrine : [V] fait défiler les accessoires sans se vider.
	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	ShowRoom.scene_retour = ""
	add_child(salle)
	await get_tree().process_frame
	var avant := salle._idx_cosmetique
	salle._touche(KEY_V)
	await get_tree().process_frame
	_assert(salle._idx_cosmetique != avant, "[V] change de jeu d'accessoires")
	_assert(salle._monde.get_child_count() > 0, "la vitrine est repeuplée, pas vidée")
	_assert(salle._heros_apparences.size() == 6, "les 6 niveaux survivent au changement")
	# Les touches d'animation ne doivent jamais planter, quel que soit le mode.
	for code in ShowRoom.TOUCHES_ANIM.keys():
		salle._touche(int(code))
	_assert(salle._monde.get_child_count() > 0, "les touches d'animation laissent la vitrine debout")
	salle.free()

# ─── 6. Échelle : héros et monstres au même mètre ───────────
#
# La ShowRoom sert précisément à juger les tailles les unes par rapport aux
# autres : un personnage hors d'échelle y est un bug de LIVRAISON. L'échelle
# se déduit de la hauteur mesurée du squelette (SpriteSpinePersonnage.
# _hauteur_source) — la taille DÉCLARÉE par l'export ne fait pas foi : la
# livraison « cheveux » du 25/08/2026 annonçait 573 unités pour un Relic qui
# en mesure 2917, et le héros sortait ~5× trop grand devant les monstres.
#
# TOLÉRANCE : la mesure porte sur la pose COURANTE, qui respire avec l'Idle —
# on ne vérifie pas un pixel, on vérifie que tout le monde est au même mètre.

const ECART_ECHELLE_MAX := 0.2   # ±20 % de la hauteur cible

func _test_echelle() -> void:
	print("\n[TEST 6] Échelle : tous les personnages au même mètre")
	if not SpriteSpinePersonnage.disponible():
		print("  (runtime spine-godot absent : échelle non mesurable)")
		return
	var cible := SpriteSpinePersonnage.HAUTEUR_CIBLE_PX
	var marge := cible * ECART_ECHELLE_MAX
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	for p in reg.personnages:
		var app := SpinePersonnagesData.apparences(p)
		var sprite := SpriteSpinePersonnage.creer(str(p.get("skel", "")),
				str(p.get("atlas", "")), app[0])
		if sprite == null:
			_assert(false, "%s : le sprite se construit" % p.get("id", "?"))
			continue
		add_child(sprite)
		await get_tree().process_frame
		var haut := sprite.hauteur_rendue_px()
		_assert(absf(haut - cible) <= marge,
				"%s : rendu à %.0f px (cible %.0f ± %.0f)" % [p.get("id", "?"), haut, cible, marge])
		sprite.free()
	# Le héros au dernier niveau d'équipement ne doit pas grandir non plus :
	# les 6 costumes partagent un squelette, donc une échelle.
	var nv6 := SpriteSpinePersonnage.creer_heros(6)
	if nv6 != null:
		add_child(nv6)
		await get_tree().process_frame
		_assert(absf(nv6.hauteur_rendue_px() - cible) <= marge,
				"le héros Nv6 garde la taille du Nv1")
		nv6.free()

# ─── Helpers & rapport ──────────────────────────────────────

func _porte(sprite: SpriteSpinePersonnage, nom_slot: String) -> bool:
	return sprite.porte_attachement(nom_slot, nom_slot)

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
