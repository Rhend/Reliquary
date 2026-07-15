extends Node
# Tests de l'ÉCRAN DE COMBAT CTB jouable (Rework Combat — chantier 5).
# Headless : facteur_delais = 0 (aucune pause, fermeture sans clic), boutons
# pressés par signal (pas de picking souris). Vérifie :
#   • boutons Attaquer / Défendre présents — AUCUN bouton Objet ni Compétence
#     (contenu absent, pas grisé) ;
#   • file d'initiative affichée : N_FILE puces, ordre = moteur.prevoir_ordre ;
#   • annonce d'embuscade à l'ouverture ;
#   • combat complet joué via l'UI (Défendre puis Attaquer + choix de cible),
#     issue affichée (VICTOIRE), signal fermee(recap) émis ;
#   • statuts DoT visibles sur la carte du combattant (pill) ;
#   • auto-résolution intacte (derouler_auto sans UI — le mode captures /
#     suites existantes ne passe jamais par l'écran).

var _results: Array = []
var _fermee_recap: Array = []   # recaps reçus via le signal fermee

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TEST UI COMBAT CTB ===\n")
	await _test_ecran_complet()
	_test_auto_resolution_intacte()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _ok(label: String) -> void:
	_results.append({"ok": true,  "label": label})
	print("  ✓ " + label)

func _fail(label: String, detail: String = "") -> void:
	_results.append({"ok": false, "label": label})
	print("  ✗ " + label + (" — " + detail if detail != "" else ""))

func _assert(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_ok(label)
	else:
		_fail(label, detail)

func _data(id: String, overrides: Dictionary = {}) -> CombattantCtbData:
	var d := CombattantCtbData.new()
	d.id = id
	d.nom_affichage_fr = id
	d.pv_max = float(overrides.get("pv_max", 100.0))
	d.atk    = float(overrides.get("atk", 10.0))
	d.def    = float(overrides.get("def", 0.0))
	d.vit    = float(overrides.get("vit", 20.0))
	d.crit_chance     = float(overrides.get("crit_chance", 0.0))
	d.crit_multiplier = float(overrides.get("crit_multiplier", 2.0))
	return d

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

# Tous les boutons du sous-arbre (récursif).
func _boutons(racine: Node, out: Array) -> void:
	for enfant in racine.get_children():
		if enfant is Button:
			out.append(enfant)
		_boutons(enfant, out)

# ─── Écran complet : ouverture → embuscade → actions → issue ──

func _test_ecran_complet() -> void:
	print("[TEST] Écran de combat — ouverture, boutons, file, embuscade")
	var m := CtbMoteur.new()
	m.rng.seed = 1337
	m.malus_horloge_initiale_joueur = 1.5   # embuscade réelle (annonce + horloges)
	var av := m.ajouter(_data("avatar", {"vit": 60.0, "atk": 300.0, "pv_max": 10000.0}),
			Enums.CampCtb.JOUEUR)
	m.ajouter(_data("gob_1", {"vit": 20.0, "atk": 5.0, "pv_max": 30.0}), Enums.CampCtb.ADVERSE)
	m.ajouter(_data("gob_2", {"vit": 10.0, "atk": 5.0, "pv_max": 30.0}), Enums.CampCtb.ADVERSE)
	m.demarrer()

	var ui := CombatCtbUi.new(m, true)
	ui.facteur_delais = 0.0
	add_child(ui)   # _ready → _intro : le voile porte l'annonce d'embuscade

	# Annonce d'embuscade à l'ouverture (voile de transition, avant le fondu).
	var annonce := false
	for enfant in ui._voile_contenu.get_children():
		if enfant is Label and enfant.text == Translations.T("ctb.embuscade"):
			annonce = true
	_assert(annonce, "annonce d'embuscade à l'ouverture du combat")
	ui.fermee.connect(func(r: Dictionary) -> void: _fermee_recap.append(r))
	# Écran d'issue enrichi (chantier 6) : récompenses fournies par l'appelant.
	ui.recompenses_fournisseur = func() -> Dictionary: return {"xp": 30.0, "euren": 20.0}

	# Laisser l'intro passer et la boucle atteindre l'attente d'input joueur.
	await _attendre_tour_joueur(ui)
	_assert(ui._btn_attaquer.visible and ui._btn_defendre.visible,
			"activation joueur : boutons Attaquer et Défendre visibles (moteur en attente)")

	# AUCUN bouton Objet / Compétence : contenu absent, pas grisé.
	var tous: Array = []
	_boutons(ui, tous)
	var interdits: Array = tous.filter(func(b: Button) -> bool:
		var t := b.text.to_lower()
		return t.contains("objet") or t.contains("item") or t.contains("compétence"))
	_assert(interdits.is_empty(), "aucun bouton Objet (ni Compétence) dans l'écran",
			str(interdits.map(func(b: Button) -> String: return b.text)))

	# File d'initiative : N_FILE puces, ordre = prevoir_ordre (noms un à un).
	var predit := m.prevoir_ordre(CombatCtbUi.N_FILE)
	var puces := ui._file_box.get_child_count()
	_assert(puces == CombatCtbUi.N_FILE,
			"file d'initiative : %d puces affichées" % CombatCtbUi.N_FILE, "puces=%d" % puces)
	var ordre_ok := true
	for i in ui._file_box.get_child_count():
		var lbl := _premier_label(ui._file_box.get_child(i))
		if lbl == null or lbl.text != CarteCombattantCtb.nom_ui(predit[i].data):
			ordre_ok = false
	_assert(ordre_ok, "ordre affiché de la file = moteur.prevoir_ordre (N=%d)"
			% CombatCtbUi.N_FILE)

	# Tour 1 : DÉFENDRE via le bouton (joué synchrone sur le signal pressed).
	ui._btn_defendre.pressed.emit()
	_assert("\n".join(m.journal).contains("se met en garde"),
			"action Défendre jouée via le bouton (garde posée au journal du moteur)")
	_assert(av.en_defense or m.nb_activations >= 2,
			"garde visible (ou déjà expirée à sa prochaine activation)")
	await _frames(4)
	print("\n[TEST] Écran de combat — combat complet joué à la main")
	# Jouer jusqu'à la victoire : Attaquer, cible = premier bouton nominatif.
	var garde_fou := 0
	while not m.termine and garde_fou < 400:
		garde_fou += 1
		if ui._btn_attaquer.visible:
			ui._btn_attaquer.pressed.emit()
			await _frames(1)
			# Plusieurs ennemis vivants → rangée de cibles : presser la première.
			var cibles: Array = []
			_boutons(ui._rangee_cibles, cibles)
			for b: Button in cibles:
				if b.text != Translations.T("ctb.annuler"):
					b.pressed.emit()
					break
		await _frames(2)
	_assert(m.termine and m.victoire_joueur,
			"combat complet joué via l'UI jusqu'à la VICTOIRE", "activations=%d" % m.nb_activations)

	# Issue affichée avant le retour à la carte + signal fermee(recap).
	await _frames(6)
	var issue := false
	for enfant in ui._voile_contenu.get_children():
		if enfant is Label and enfant.text == Translations.T("ctb.victoire"):
			issue = true
	_assert(issue, "issue VICTOIRE affichée sur l'écran de fin de bataille")
	var attendu_rec := Translations.T("ctb.recompenses") % [30, 20]
	var rec_visible := false
	for enfant in ui._voile_contenu.get_children():
		if enfant is Label and enfant.text == attendu_rec:
			rec_visible = true
	_assert(rec_visible, "récompenses du combat (XP + Euren) sur l'écran d'issue")
	_assert(_fermee_recap.size() == 1 and bool(_fermee_recap[0]["victoire"]),
			"signal fermee(recap) émis une fois, recap de victoire")
	ui.queue_free()
	await _frames(2)

	# Statuts + garde visibles sur la carte (pills) — widget seul, sans moteur
	# (pas de boucle en attente d'input à abandonner en fin de test).
	print("\n[TEST] Carte de combattant — pills de statut et de garde")
	var poison: StatutCtbData = load("res://data/combat_ctb/statut_poison.tres")
	var cb := CtbCombattant.new(_data("gob", {"pv_max": 100.0}), Enums.CampCtb.ADVERSE, 0)
	cb.statuts.append({"statut": poison, "degats_par_tick": 5.0, "restant": 2})
	cb.statuts.append({"statut": poison, "degats_par_tick": 5.0, "restant": 1})
	cb.en_defense = true
	var carte := CarteCombattantCtb.new(cb)
	add_child(carte)
	await _frames(1)
	carte.rafraichir()
	var texte_pills := _textes_labels(carte)
	_assert(texte_pills.any(func(t: String) -> bool:
			return t.contains("×2") and t.contains(poison.nom_affichage_fr) and t.contains("(2)")),
			"pill de statut : type + stacks (×2) + durée restante max (2 activations)",
			str(texte_pills))
	_assert(texte_pills.any(func(t: String) -> bool:
			return t == Translations.T("ctb.garde_pill")),
			"pill de garde (Défendre) visible sur la carte", str(texte_pills))
	carte.queue_free()
	await _frames(2)

# Attend que la boucle de l'UI ouvre l'attente d'input joueur (boutons
# visibles) — garde-fou en frames pour ne jamais bloquer la CI.
func _attendre_tour_joueur(ui: CombatCtbUi) -> void:
	for _i in 300:
		if ui._btn_attaquer != null and ui._btn_attaquer.visible:
			return
		await get_tree().process_frame

func _premier_label(n: Node) -> Label:
	if n is Label:
		return n
	for enfant in n.get_children():
		var l := _premier_label(enfant)
		if l != null:
			return l
	return null

func _textes_labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for enfant in n.get_children():
		out.append_array(_textes_labels(enfant))
	return out

# ─── Auto-résolution : le mode sans UI reste intact ──────────

func _test_auto_resolution_intacte() -> void:
	print("\n[TEST] Auto-résolution — intacte (captures / suites existantes)")
	var m := CtbMoteur.new()
	m.rng.seed = 99
	m.ajouter(_data("avatar", {"vit": 40.0, "atk": 50.0, "pv_max": 1000.0}),
			Enums.CampCtb.JOUEUR)
	m.ajouter(_data("gob", {"vit": 10.0, "atk": 5.0, "pv_max": 60.0}), Enums.CampCtb.ADVERSE)
	m.demarrer()
	m.derouler_auto()
	_assert(m.termine and m.victoire_joueur,
			"derouler_auto() résout le combat sans écran (aucune UI requise)")

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ écran de combat CTB conforme")
	print("════════════════════════════════\n")
