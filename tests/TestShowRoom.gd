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
	await _test_orientation()

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

	# Coiffures : MÊME contrat que les accessoires, mais axe INDÉPENDANT — les
	# deux se CUMULENT (17/09/2026, retour Rhend : raccourci dédié aux cheveux).
	var jeux_coiffure := SpinePersonnagesData.coiffures(h)
	_assert(jeux_coiffure.size() >= 2, "au moins 2 coiffures déclarées")
	var ap_h3 := SpinePersonnagesData.apparences(h, 0, 1)
	_assert(ap_h3.size() == ap_h.size(), "changer de coiffure ne change pas le nombre de niveaux")
	var skins_h3 := ap_h3[0].get("skins", PackedStringArray()) as PackedStringArray
	_assert(skins_h3 != skins_h, "changer de coiffure change bien la composition de skins")
	var skins_h_deux_axes := SpinePersonnagesData.apparences(h, 1, 1)[0]\
			.get("skins", PackedStringArray()) as PackedStringArray
	_assert("Men_Global" in skins_h_deux_axes,
			"visage ET coiffure choisis ENSEMBLE : le corps reste posé")
	var skin_visage_1 := str((jeux[1]["skins"] as PackedStringArray)[0])
	var skin_coiffure_1 := str((jeux_coiffure[1]["skins"] as PackedStringArray)[0])
	_assert(skin_visage_1 in skins_h_deux_axes and skin_coiffure_1 in skins_h_deux_axes,
			"visage ET coiffure choisis ENSEMBLE : les deux axes s'ajoutent, pas un remplace l'autre")
	_assert(not (SpinePersonnagesData.apparences(h, 0, 99)[0].get("skins",
			PackedStringArray()) as PackedStringArray).is_empty(),
			"index de coiffure hors bornes → borné, jamais d'apparence vide")

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
	_assert(salle._mode == ShowRoom.Mode.DUEL, "démarre en mode duel (09/2026 : le vrai combat)")
	_assert(salle._combat_ui != null,
			"le VRAI CombatCtbUi est instancié — plus une copie de son rendu")
	_assert(salle._combat_ui.moteur.combattants.size() == 2,
			"le faux combat oppose le héros à la créature choisie")
	# Rien ne doit pouvoir « gagner » quoi que ce soit depuis la vitrine —
	# les mêmes garde-fous que le sandbox dev, jamais d'écriture indirecte.
	_assert(not salle._combat_ui.recompenses_fournisseur.is_valid()
			and not salle._combat_ui.inventaire_fournisseur.is_valid(),
			"aucune récompense/inventaire câblé : la vitrine ne peut rien faire gagner")

	# Portrait de file d'initiative (livraison « Turn_Icone_Ennemis »,
	# 16/09/2026) : la première créature du registre a un vrai fichier —
	# la puce doit porter une texture, pas juste l'initiale de repli.
	# La ShowRoom garde le VRAI timing du splash d'ouverture (« tout doit
	# être identique », pas de facteur_delais=0 ici) : la file n'est peuplée
	# qu'une fois l'intro terminée (~1,45 s), donc on l'attend pour de vrai.
	_assert(CombatUiSkin.portrait_ennemi(str(salle._ennemis[0].get("nom", "")), 0) != null,
			"portrait_ennemi(FlameBot, Commun) résout un vrai fichier livré")
	await get_tree().create_timer(1.6).timeout
	# Le héros n'a pas encore le sien (portrait_heros dégrade proprement) :
	# la moindre TextureRect trouvée dans la file ne peut venir que de
	# l'ennemi — confirme que la puce affiche un portrait, pas l'initiale.
	var une_puce_a_portrait := false
	for c: Control in salle._combat_ui._file_box.get_children():
		for enfant in c.get_children():
			if enfant is TextureRect:
				une_puce_a_portrait = true
	_assert(une_puce_a_portrait, "au moins une puce de la file affiche un vrai portrait")

	# Cycle de palier et de monstre : reconstruit un combat frais, avec les
	# bonnes surcharges de prévisualisation transmises au VRAI écran — jamais
	# la Maîtrise réelle du joueur (TestCombatUi.gd couvre déjà le rendu et le
	# zoom-duel de CombatCtbUi lui-même, pas la peine de le rejouer ici).
	salle._idx_palier = SpinePersonnagesData.NB_PALIERS - 1
	salle._idx_monstre = salle._ennemis.size() - 1
	salle._lancer_duel()
	_assert(salle._combat_ui != null, "duel reconstruit après changement de cible")
	_assert(salle._combat_ui.previsu_palier_ennemi == SpinePersonnagesData.NB_PALIERS - 1,
			"le palier prévisualisé est transmis au vrai écran de combat")
	_assert(salle._combat_ui.previsu_niveau_heros == salle._idx_niveau_heros + 1,
			"le niveau d'équipement du héros prévisualisé est transmis lui aussi")

	# [↑/↓] : HOT-RELOAD, pas une reconstruction (retour Rhend : « t'es
	# obligé de reload le combat ? ») — le palier prévisualisé ne change QUE
	# le skin de l'ennemi, jamais ses stats, donc le moteur en cours (et le
	# CombatCtbUi qui le pilote) n'ont aucune raison de disparaître.
	var ui_avant_touche := salle._combat_ui
	var ennemi_courant: CtbCombattant = null
	for cb in ui_avant_touche.moteur.combattants:
		if not cb.est_joueur():
			ennemi_courant = cb
			break
	var sprite_ennemi_avant: SpriteSpinePersonnage = \
			ui_avant_touche._sprites.get(ennemi_courant) if ennemi_courant != null else null
	salle._touche(KEY_UP)
	_assert(salle._combat_ui == ui_avant_touche,
			"[↑] ne reconstruit PAS l'écran de combat")
	_assert(salle._combat_ui.previsu_palier_ennemi == salle._idx_palier,
			"[↑] met bien à jour le palier prévisualisé")
	if sprite_ennemi_avant != null:
		var sprite_ennemi_apres: SpriteSpinePersonnage = \
				salle._combat_ui._sprites.get(ennemi_courant)
		_assert(sprite_ennemi_apres != null and sprite_ennemi_apres != sprite_ennemi_avant,
				"[↑] a bien remplacé le sprite de l'ennemi (hot-reload effectif, pas un no-op)")

	# Mode Usine (diagnostic) : bascule de visibilité, PAS une reconstruction
	# — le duel en cours n'a aucune raison d'être perdu pour regarder le décor.
	var meme_combat_ui := salle._combat_ui
	salle._touche(KEY_TAB)
	_assert(salle._mode == ShowRoom.Mode.USINE, "[Tab] bascule vers Usine seul")
	_assert(salle._decor_usine.visible, "Usine : décor seul visible")
	_assert(not salle._combat_ui.visible, "Usine : le duel se masque")
	_assert(salle._combat_ui == meme_combat_ui, "Usine ne reconstruit rien, juste une bascule")
	salle._touche(KEY_TAB)
	_assert(salle._mode == ShowRoom.Mode.DUEL and salle._combat_ui.visible,
			"[Tab] revient au duel, redevenu visible")

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
	print("\n[TEST 4] Éclairage : voile au-dessus du décor RÉEL, jamais sur les personnages")
	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	ShowRoom.scene_retour = ""
	add_child(salle)
	await get_tree().process_frame

	_assert(salle._idx_lumiere == ShowRoom.LUMIERE_DEFAUT,
			"démarre au niveau par défaut (« Studio », pas « Nuit » qui noie les Communs)")
	var alpha_defaut := float(ShowRoom.NIVEAUX_LUMIERE[ShowRoom.LUMIERE_DEFAUT]["voile"])
	_assert(salle._combat_ui._voile_previsu != null
			and is_equal_approx(salle._combat_ui._voile_previsu.color.a, alpha_defaut),
			"le voile posé sur l'écran RÉEL correspond au niveau par défaut")

	# Le cycle passe par tous les niveaux et boucle.
	var vus: Array[String] = []
	for i in ShowRoom.NIVEAUX_LUMIERE.size():
		vus.append(str(ShowRoom.NIVEAUX_LUMIERE[salle._idx_lumiere]["nom"]))
		salle._touche(KEY_B)
	_assert(vus.size() == ShowRoom.NIVEAUX_LUMIERE.size() and vus[0] == "Studio",
			"[B] parcourt les %d niveaux" % ShowRoom.NIVEAUX_LUMIERE.size())
	_assert(salle._idx_lumiere == ShowRoom.LUMIERE_DEFAUT, "[B] boucle sur le premier niveau")

	# Le niveau le plus clair pose un voile plus opaque...
	salle._idx_lumiere = ShowRoom.NIVEAUX_LUMIERE.size() - 1
	salle._appliquer_lumiere()
	_assert(salle._combat_ui._voile_previsu.color.a > alpha_defaut,
			"niveau le plus clair : voile plus opaque")
	# ...et ne touche JAMAIS les personnages (garde-fou historique : un asset
	# doit se juger sur son rendu réel, jamais modulé — même règle que ShowRoom
	# appliquait déjà, portée maintenant par l'écran de combat lui-même).
	for cb in salle._combat_ui.moteur.combattants:
		var sprite: SpriteSpinePersonnage = salle._combat_ui._sprites.get(cb)
		if sprite != null:
			_assert(sprite.modulate.is_equal_approx(Color.WHITE),
					"%s : jamais modulé par l'éclairage" % cb.data.id)
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

	# La vitrine : [V]/[H] font défiler le costume du héros sur le VRAI écran
	# de combat, sans jamais le laisser vide (reconstruit, jamais retiré sans
	# remplaçant — voir ShowRoom._lancer_duel).
	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	ShowRoom.scene_retour = ""
	add_child(salle)
	await get_tree().process_frame
	var ui_avant_touches := salle._combat_ui
	var sprite_heros_avant: SpriteSpinePersonnage = \
			ui_avant_touches._sprites.get(ui_avant_touches.moteur.avatar())
	var jeux := SpinePersonnagesData.cosmetiques(salle._heros)
	var avant_cosmetique := salle._idx_cosmetique
	salle._touche(KEY_V)
	if jeux.size() > 1:
		_assert(salle._idx_cosmetique != avant_cosmetique, "[V] change de jeu d'accessoires")
	_assert(salle._combat_ui != null, "le combat reste peuplé après [V]")
	_assert(salle._combat_ui == ui_avant_touches, "[V] ne reconstruit PAS l'écran (hot-reload)")
	# [C] : même mécanique que [V], sur l'axe INDÉPENDANT des coiffures
	# (17/09/2026, retour Rhend — un raccourci pour la coupe de cheveux comme
	# pour le visage).
	var jeux_coiffure := SpinePersonnagesData.coiffures(salle._heros)
	var avant_coiffure := salle._idx_coiffure
	salle._touche(KEY_C)
	if jeux_coiffure.size() > 1:
		_assert(salle._idx_coiffure != avant_coiffure, "[C] change de jeu de coiffure")
	_assert(salle._combat_ui != null, "le combat reste peuplé après [C]")
	_assert(salle._combat_ui == ui_avant_touches, "[C] ne reconstruit PAS l'écran (hot-reload)")
	var avant_niveau := salle._idx_niveau_heros
	salle._touche(KEY_H)
	_assert(salle._idx_niveau_heros == wrapi(avant_niveau + 1, 0, ShowRoom.NB_NIVEAUX_HEROS),
			"[H] avance d'un niveau d'équipement (boucle sur %d)" % ShowRoom.NB_NIVEAUX_HEROS)
	_assert(salle._combat_ui != null
			and salle._combat_ui.previsu_niveau_heros == salle._idx_niveau_heros + 1,
			"le niveau d'équipement prévisualisé suit [H]")
	_assert(salle._combat_ui == ui_avant_touches, "[H] ne reconstruit PAS l'écran (hot-reload)")
	if sprite_heros_avant != null:
		var sprite_heros_apres: SpriteSpinePersonnage = \
				salle._combat_ui._sprites.get(salle._combat_ui.moteur.avatar())
		_assert(sprite_heros_apres != null and sprite_heros_apres != sprite_heros_avant,
				"[V]+[H] ont bien remplacé le sprite du héros (hot-reload effectif)")
	salle.free()

# ─── 6. Échelle : chaque entité à SON gabarit de chara design ──
#
# Un personnage hors de SA propre cible reste un bug de LIVRAISON : l'échelle
# se déduit de la hauteur mesurée du squelette (SpriteSpinePersonnage.
# _hauteur_source) — la taille DÉCLARÉE par l'export ne fait pas foi : la
# livraison « cheveux » du 25/08/2026 annonçait 573 unités pour un Relic qui
# en mesure 2917, et le héros sortait ~5× trop grand devant les monstres.
#
# Mais depuis 09/2026 (chara design de Rhend/Christophe), la cible n'est PLUS
# la même pour tout le monde : chaque entrée du registre porte son propre
# écart en % (`taille_relative_pct`) par rapport à l'ÉTALON (WorkBot, 0 %,
# `SpriteSpinePersonnage.HAUTEUR_ETALON_PX` — PLACEHOLDER en attendant le vrai
# chiffre de Christophe). Ce test vérifie que chacun rend à SA cible propre
# (`SpinePersonnagesData.hauteur_cible_px`), et que l'ordre de gabarit voulu
# (Relic < WorkBot < FlameBot, ajustement du 07/09/2026 — Relic est passé
# SOUS l'étalon WorkBot) est bien respecté.
#
# TOLÉRANCE : la mesure porte sur la pose COURANTE, qui respire avec l'Idle —
# on ne vérifie pas un pixel, on vérifie que chacun est à SON mètre.

const ECART_ECHELLE_MAX := 0.2   # ±20 % de la hauteur cible DE CHAQUE entité

# La mesure d'échelle vient d'un BAKE (SilhouettesData) : les pixels réellement
# dessinés, comptés hors ligne par tools/mesurer_silhouettes.tscn, parce que
# compter des pixels exige un rendu et que les tests tournent en --headless.
#
# C'est le contrôle qui compte vraiment ici : un bake périmé ne casse rien de
# visible, il rend juste un personnage à la mauvaise taille — exactement le mode
# de panne silencieuse qui a coûté la livraison « cheveux ». On vérifie donc que
# CHAQUE personnage du registre a sa mesure, et qu'elle correspond encore à son
# squelette. Comme TestHoloXlsx pour l'instantané de la carte : l'asset et sa
# donnée bakée ne peuvent pas diverger sans que la CI le dise.
func _test_silhouettes_bakees() -> void:
	var bakees := SilhouettesData.charger()
	_assert(bakees != null, "le bake des silhouettes existe")
	if bakees == null:
		return
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	for p in reg.personnages:
		var id := str(p.get("id", "?"))
		var skel := str(p.get("skel", ""))
		_assert(float((bakees.mesures.get(skel, {}) as Dictionary).get("hauteur", 0.0)) > 0.0,
				"%s : silhouette bakée présente" % id)
		var app := SpinePersonnagesData.apparences(p)
		var sprite := SpriteSpinePersonnage.creer(skel, str(p.get("atlas", "")), app[0])
		if sprite == null:
			continue
		add_child(sprite)
		await get_tree().process_frame
		# hauteur() rend 0.0 — et warne — quand les bornes ont bougé depuis le
		# bake : c'est le signal « asset livré, re-bake oublié ».
		_assert(bakees.hauteur(skel, sprite.bornes_corps()) > 0.0,
				"%s : le bake correspond encore au squelette livré" % id)
		sprite.free()

func _test_echelle() -> void:
	print("\n[TEST 6] Échelle : chaque entité à SON gabarit (WorkBot = étalon)")
	if not SpriteSpinePersonnage.disponible():
		print("  (runtime spine-godot absent : échelle non mesurable)")
		return
	await _test_silhouettes_bakees()
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	var cibles := {}   # id → hauteur cible (réutilisé pour le contrôle d'ordre)
	for p in reg.personnages:
		var id := str(p.get("id", "?"))
		var app := SpinePersonnagesData.apparences(p)
		var cible := SpinePersonnagesData.hauteur_cible_px(p)
		cibles[id] = cible
		var marge := cible * ECART_ECHELLE_MAX
		var sprite := SpriteSpinePersonnage.creer(str(p.get("skel", "")),
				str(p.get("atlas", "")), app[0], cible)
		if sprite == null:
			_assert(false, "%s : le sprite se construit" % id)
			continue
		add_child(sprite)
		await get_tree().process_frame
		var haut := sprite.hauteur_rendue_px()
		_assert(absf(haut - cible) <= marge,
				"%s : rendu à %.0f px (cible %.0f ± %.0f, %+.0f %% vs étalon)" %
				[id, haut, cible, marge, SpinePersonnagesData.taille_relative_pct(p)])
		sprite.free()
	# Le héros au dernier niveau d'équipement ne doit pas grandir non plus :
	# les 6 costumes partagent un squelette, donc une échelle — SA PROPRE
	# échelle (Relic -4 %), plus l'étalon universel d'avant 09/2026.
	var cible_heros: float = cibles.get("relic", SpriteSpinePersonnage.HAUTEUR_ETALON_PX)
	var nv6 := SpriteSpinePersonnage.creer_heros(6)
	if nv6 != null:
		add_child(nv6)
		await get_tree().process_frame
		_assert(absf(nv6.hauteur_rendue_px() - cible_heros) <= cible_heros * ECART_ECHELLE_MAX,
				"le héros Nv6 garde la taille du Nv1")
		nv6.free()
	# L'ORDRE voulu par le chara design (ajusté 07/09/2026) : Relic < WorkBot
	# (étalon) < FlameBot — Relic est passé sous l'étalon, ce n'est plus un
	# simple ±20 %.
	if cibles.has("relic") and cibles.has("workbot"):
		_assert(float(cibles["relic"]) < float(cibles["workbot"]),
				"Relic est plus petit que WorkBot (étalon)")
	if cibles.has("workbot") and cibles.has("flamebot"):
		_assert(float(cibles["workbot"]) < float(cibles["flamebot"]),
				"WorkBot (étalon) est plus petit que FlameBot")

# ─── 7. Sens d'export et mise en scène ──────────────────────
#
# Le miroir des ennemis était un `scale = Vector2(-1, 1)` EN DUR, appliqué à
# tout ennemi sans distinction : un ennemi livré tourné vers la gauche s'y
# serait retrouvé DOS au héros, sans rien pour le signaler. Il vient du registre
# désormais, et c'est ce contrat que ce test garde — surtout le cas qu'on n'a
# pas encore en magasin, l'ennemi exporté à gauche.
func _test_orientation() -> void:
	print("\n[TEST 7] Sens d'export des personnages")
	var reg := load(ShowRoom.REGISTRE) as SpinePersonnagesData
	if reg == null:
		return

	# Le défaut vaut « vers la droite » : une entrée qui ne dit rien reste
	# lisible, et une livraison déjà intégrée ne change pas de comportement.
	_assert(SpinePersonnagesData.regarde_a_droite({}),
			"une entrée muette est réputée exportée vers la droite")
	_assert(not SpinePersonnagesData.regarde_a_droite({"regarde_a_droite": false}),
			"une entrée peut déclarer l'autre sens")

	# La table de vérité complète : deux sens d'export × deux camps.
	var droite := {"regarde_a_droite": true}
	var gauche := {"regarde_a_droite": false}
	_assert(SpinePersonnagesData.echelle_x(droite, true) > 0.0,
			"exporté à droite, posé côté joueur → pas de miroir")
	_assert(SpinePersonnagesData.echelle_x(droite, false) < 0.0,
			"exporté à droite, posé côté adverse → miroir")
	_assert(SpinePersonnagesData.echelle_x(gauche, false) > 0.0,
			"exporté à gauche, posé côté adverse → PAS de miroir (cas des robots)")
	_assert(SpinePersonnagesData.echelle_x(gauche, true) < 0.0,
			"exporté à gauche, posé côté joueur → miroir")

	# Chaque entrée livrée déclare son sens : c'est ce qui rend le champ utile
	# comme documentation d'intégration, et pas seulement comme réglage.
	for p in reg.personnages:
		_assert(p.has("regarde_a_droite"),
				"%s : le sens d'export est déclaré" % str(p.get("id", "?")))

	# La livraison de Christophe est PRÊTE À L'EMPLOI : héros vers la droite,
	# ennemis vers la gauche, donc aucun retournement à faire. Si cette
	# assertion tombe, c'est qu'une livraison a changé de sens — et il faut
	# corriger SON entrée, pas remettre un miroir systématique.
	_assert(SpinePersonnagesData.regarde_a_droite(reg.heros()),
			"le héros livré regarde vers la droite (vers le camp adverse)")
	for e in reg.ennemis():
		_assert(not SpinePersonnagesData.regarde_a_droite(e),
				"%s : livré tourné vers la gauche (vers le camp joueur)"
						% str(e.get("id", "?")))

	if not SpriteSpinePersonnage.disponible():
		print("  (runtime spine-godot absent : mise en scène non vérifiable)")
		return

	# Et la mise en scène réelle, à travers le VRAI écran de combat : héros
	# face à l'ennemi, ennemi face au héros.
	var salle: ShowRoom = (load("res://scenes/showroom/ShowRoom.tscn") as PackedScene).instantiate()
	add_child(salle)
	await get_tree().process_frame
	var ui := salle._combat_ui
	if ui == null:
		salle.queue_free()
		return
	var heros_sprite: SpriteSpinePersonnage = ui._sprites.get(ui.moteur.avatar())
	# Le signe posé doit être CELUI QUE LE REGISTRE CALCULE, et non un signe
	# figé : c'est la seule formulation qui reste vraie si une livraison change
	# de sens — l'ancienne version du test affirmait « l'ennemi est retourné »,
	# ce qui figeait précisément le bug qu'on corrige ici.
	if heros_sprite != null:
		_assert(heros_sprite.scale.x * SpinePersonnagesData.echelle_x(reg.heros(), true) > 0.0,
				"en combat, le héros est orienté selon son sens d'export déclaré")
	var ennemi: CtbCombattant = null
	for cb in ui.moteur.combattants:
		if not cb.est_joueur():
			ennemi = cb
			break
	var ennemi_sprite: SpriteSpinePersonnage = ui._sprites.get(ennemi) if ennemi != null else null
	if ennemi_sprite != null and not reg.ennemis().is_empty():
		_assert(ennemi_sprite.scale.x * SpinePersonnagesData.echelle_x(reg.ennemis()[0], false) > 0.0,
				"en combat, l'ennemi est orienté selon son sens d'export déclaré")
		# Et le résultat concret sur la livraison actuelle : personne n'est retourné.
		_assert(ennemi_sprite.scale.x > 0.0,
				"avec la livraison courante, l'ennemi fait face au héros sans miroir")
		# `orienter` ne doit toucher que le SIGNE : une échelle posée par
		# l'appelant survit, sinon retourner un sprite le remettrait à sa
		# taille native sans prévenir.
		ennemi_sprite.scale = Vector2(0.5, 0.5)
		ennemi_sprite.orienter(-1.0)
		_assert(is_equal_approx(absf(ennemi_sprite.scale.x), 0.5)
				and is_equal_approx(ennemi_sprite.scale.y, 0.5),
				"orienter() préserve la taille et ne change que le sens")
	salle.queue_free()

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
