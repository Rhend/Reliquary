extends Node
# ============================================================
# TestInventaire — inventaire de l'Atelier (14/10/2026) : stock persistant
# de consommables (StockConsommables), fabrication (Euren + matériaux),
# équiper / déséquiper (GameData). Quitte avec un code ≠ 0 en cas d'échec.
# ============================================================

var _fail: Array[String] = []
var _nb_ok := 0

func _ready() -> void:
	# JAMAIS d'écriture de sauvegarde dans un test (règle projet).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST INVENTAIRE DE L'ATELIER ===\n")
	var avant: Dictionary = GameData.player.duplicate(true)
	_test_catalogue_et_stock()
	_test_run()
	_test_craft()
	_test_equipement()
	_test_panneau()
	GameData.player = avant
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

func _test_catalogue_et_stock() -> void:
	print("[1] Catalogue + stock")
	GameData.player["consommables"] = {}
	var cat := StockConsommables.catalogue()
	_check("catalogue : la Bombe est connue", cat.has("consommable_bombe"))
	_check("catalogue : le Nano-soigneur est connu", cat.has("consommable_nano_soigneur"))
	_check("stock vide au départ", StockConsommables.total() == 0)
	StockConsommables.ajouter("consommable_bombe", 3)
	_check("ajouter ×3", StockConsommables.quantite("consommable_bombe") == 3)
	_check("retirer ×2 → reste 1", StockConsommables.retirer("consommable_bombe", 2)
			and StockConsommables.quantite("consommable_bombe") == 1)
	_check("retirer plus que possédé refusé", not StockConsommables.retirer("consommable_bombe", 5)
			and StockConsommables.quantite("consommable_bombe") == 1)
	_check("retirer le dernier supprime la clé", StockConsommables.retirer("consommable_bombe", 1)
			and not StockConsommables.contenu().has("consommable_bombe"))

func _test_run() -> void:
	print("\n[2] Run : tout le stock part, la sortie normale le remplace")
	GameData.player["consommables"] = {"consommable_bombe": 2, "consommable_nano_soigneur": 1}
	var inv := StockConsommables.pour_la_run()
	_check("3 consommables partent en run", inv.size() == 3)
	_check("un id inconnu est ignoré", (func() -> bool:
			GameData.player["consommables"]["id_inexistant"] = 4
			return StockConsommables.pour_la_run().size() == 3).call())
	var reste: Array = [StockConsommables.definition("consommable_bombe")]
	StockConsommables.enregistrer_fin_de_run(reste)
	_check("sortie normale : le stock devient le reste de la run",
			StockConsommables.quantite("consommable_bombe") == 1
			and StockConsommables.quantite("consommable_nano_soigneur") == 0)

func _test_craft() -> void:
	print("\n[3] Fabrication")
	var bombe := StockConsommables.definition("consommable_bombe")
	GameData.player["consommables"] = {}
	GameData.player["euren"] = 0.0
	GameData.player["resources"] = {}
	_check("sans moyens : impossible", not StockConsommables.peut_fabriquer(bombe)
			and not StockConsommables.fabriquer(bombe))
	GameData.player["euren"] = bombe.cout_euren
	GameData.player["resources"] = bombe.cout_materiaux.duplicate()
	_check("avec les moyens : possible", StockConsommables.peut_fabriquer(bombe))
	_check("fabriquer réussit", StockConsommables.fabriquer(bombe))
	_check("1 Bombe au stock", StockConsommables.quantite("consommable_bombe") == 1)
	_check("Euren débité", ProgressionHeros.euren() == 0.0)
	var rid: String = bombe.cout_materiaux.keys()[0]
	_check("matériaux débités", int(GameData.player["resources"].get(rid, 0)) == 0)

func _test_equipement() -> void:
	print("\n[4] Équiper / déséquiper")
	var slot := "arme"
	var piece := str(GameData.player["equipped"].get(slot, ""))
	if piece == "":
		# Partie non initialisée dans ce contexte : on la dote comme une neuve.
		GameData.appliquer_equipement_depart()
		piece = str(GameData.player["equipped"].get(slot, ""))
	_check("précondition : une arme est portée", piece != "")
	if piece == "":
		return
	_check("déséquiper", GameData.desequiper(slot)
			and str(GameData.player["equipped"][slot]) == ""
			and GameData.equipement_en_reserve().has(piece))
	_check("déséquiper un slot vide refusé", not GameData.desequiper(slot))
	_check("équiper depuis la réserve", GameData.equiper(piece)
			and str(GameData.player["equipped"][slot]) == piece
			and not GameData.equipement_en_reserve().has(piece))
	_check("équiper une pièce non possédée refusé", not GameData.equiper("equipment_inexistant"))

# ─── 5. Panneau (clics simulés) ──────────────────────────────

func _test_panneau() -> void:
	print("\n[5] Panneau : onglets, sélection, fabriquer, équiper/déséquiper")
	GameData.player["voies_ouvertes"] = 1   # Atelier ouvert
	GameData.player["consommables"] = {}
	GameData.player["euren"] = 100.0
	GameData.player["resources"] = {"res_ferraille": 10, "res_puce": 5}
	if str(GameData.player["equipped"].get("arme", "")) == "":
		GameData.appliquer_equipement_depart()
	var v := Village.new()
	var st: Dictionary = v.panel_ui_state()
	v.rp_content = VBoxContainer.new()
	# Onglet Consommables → la Bombe est listée.
	_clic_onglet(v, Translations.T("inv.tab.conso"))
	_check("onglet Consommables mémorisé", int(st.get("onglet", -1)) == 2)
	_rebuild(v)
	var cat := StockConsommables.catalogue()
	var nom_bombe := Translations.resource_name(cat["consommable_bombe"], "consommable_bombe")
	var case_bombe := _bouton(v.rp_content, func(b: Button) -> bool:
			return b.tooltip_text == nom_bombe)
	_check("la Bombe a sa case", case_bombe != null)
	if case_bombe != null:
		case_bombe.pressed.emit()
		_check("sélection mémorisée", str(st.get("sel", "")) == "conso:consommable_bombe")
	_rebuild(v)
	var fab := _bouton(v.rp_content, func(b: Button) -> bool:
			return b.text == Translations.T("inv.fabriquer"))
	_check("bouton Fabriquer présent et actif", fab != null and not fab.disabled)
	if fab != null:
		fab.pressed.emit()
		_check("Fabriquer ajoute 1 Bombe au stock",
				StockConsommables.quantite("consommable_bombe") == 1)
	# Équipement : déséquiper puis rééquiper depuis la réserve.
	_clic_onglet(v, Translations.T("inv.tab.equip"))
	st["sel"] = "slot:arme"
	_rebuild(v)
	var piece := str(GameData.player["equipped"]["arme"])
	var des := _bouton(v.rp_content, func(b: Button) -> bool:
			return b.text == Translations.T("inv.desequiper"))
	_check("bouton Déséquiper pour l'arme portée", des != null)
	if des != null:
		des.pressed.emit()
		_check("arme déséquipée → réserve", GameData.equipement_en_reserve().has(piece))
	st["sel"] = "res:" + piece
	_rebuild(v)
	var equ := _bouton(v.rp_content, func(b: Button) -> bool:
			return b.text == Translations.T("inv.equiper"))
	_check("bouton Équiper pour la pièce en réserve", equ != null)
	if equ != null:
		equ.pressed.emit()
		_check("pièce rééquipée", str(GameData.player["equipped"]["arme"]) == piece)
	# Recherche : un terme sans résultat vide la grille des consommables.
	_clic_onglet(v, Translations.T("inv.tab.conso"))
	st["recherche"] = "zzzzzz"
	_rebuild(v)
	_check("recherche sans résultat → message « aucun objet »",
			_a_label(v.rp_content, Translations.T("inv.vide")))
	v.rp_content.free()
	v.free()

func _rebuild(v: Village) -> void:
	for c in v.rp_content.get_children():
		v.rp_content.remove_child(c)
		c.free()
	ForgePanel.build(v)

func _clic_onglet(v: Village, texte: String) -> void:
	_rebuild(v)
	var b := _bouton(v.rp_content, func(x: Button) -> bool: return x.text == texte)
	if b != null:
		b.pressed.emit()

func _bouton(n: Node, filtre: Callable) -> Button:
	if n is Button and filtre.call(n):
		return n
	for c in n.get_children():
		var r := _bouton(c, filtre)
		if r != null:
			return r
	return null

func _a_label(n: Node, texte: String) -> bool:
	if n is Label and (n as Label).text == texte:
		return true
	for c in n.get_children():
		if _a_label(c, texte):
			return true
	return false

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
