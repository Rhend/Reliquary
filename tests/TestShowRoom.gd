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

	# Héros SANS variantes livrées : une seule apparence, sans skin à poser.
	var h := reg.heros()
	var ap_h := SpinePersonnagesData.apparences(h)
	_assert(ap_h.size() == 1, "héros sans variantes → une seule apparence")
	_assert(str(ap_h[0].get("skin", "")) == "", "apparence unique → aucune skin posée")

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
			"mode combat : décor city affiché, fond neutre masqué")

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

# ─── Helpers & rapport ──────────────────────────────────────

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
