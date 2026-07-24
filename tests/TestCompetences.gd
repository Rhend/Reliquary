extends Node
# ============================================================
# TestCompetences — Compétences du héros en combat CTB (chantier 16).
#
# Couvre : résolution moteur (ATTAQUE_MULT via le pipeline complet — crit,
# règles de Lieu, Défendre, plancher — et SOIN_PCT_PV_MAX clampé), cycle de
# COOLDOWN en activations du lanceur (posé à l'usage, décrément à
# l'ouverture de ses activations), garde-fous (compétence non possédée /
# en recharge = activation perdue, jamais de crash), dotation du héros
# (CtbPont), boutons de l'écran de combat (présents, grisés en recharge,
# absents pour un combattant sans compétence), événements UI.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

const FRAPPE: CompetenceCtbData = preload("res://data/combat_ctb/competences/frappe_lourde.tres")
const SOUFFLE: CompetenceCtbData = preload("res://data/combat_ctb/competences/second_souffle.tres")

var _fail: Array[String] = []
var _nb_ok := 0

func _ready() -> void:
	# JAMAIS d'écriture de sauvegarde dans un test (règle projet).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST COMPÉTENCES CTB (chantier 16) ===\n")
	_test_attaque_mult()
	_test_soin()
	_test_cooldown()
	_test_garde_fous()
	_test_dotation_heros()
	await _test_ui()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── 1. ATTAQUE_MULT ─────────────────────────────────────────

func _test_attaque_mult() -> void:
	print("[1] ATTAQUE_MULT : pipeline complet × valeur")
	# ATK 10, DEF 0, ×1.6 → 16.
	var m := _moteur(10.0, [_frappe(1.6, 0)])
	m.activer_suivant()
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": m.avatar().data.competences[0],
			"cible": _ennemi_de(m)})
	_check("dégâts = 16 (10 × 1.6)", _degats_subis(m) == 16)
	# Règle de Lieu ×0.8 puis compétence ×1.6 : 10 × 1.6 × 0.8 = 12.8 → 13.
	var m2 := _moteur(10.0, [_frappe(1.6, 0)])
	m2.modif_degats_camp[Enums.CampCtb.JOUEUR] = 0.8
	m2.activer_suivant()
	m2.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": m2.avatar().data.competences[0],
			"cible": _ennemi_de(m2)})
	_check("compose avec les règles de Lieu (13)", _degats_subis(m2) == 13)
	# L'événement « attaque » standard est émis (l'UI du duel s'y branche).
	var m3 := _moteur(10.0, [_frappe(2.0, 0)])
	var types: Array[String] = []
	m3.evenement.connect(func(e: Dictionary) -> void: types.append(str(e.get("type", ""))))
	m3.activer_suivant()
	m3.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": m3.avatar().data.competences[0],
			"cible": _ennemi_de(m3)})
	_check("événements competence + attaque émis",
			types.has("competence") and types.has("attaque"))

# ─── 2. SOIN_PCT_PV_MAX ──────────────────────────────────────

func _test_soin() -> void:
	print("\n[2] SOIN_PCT_PV_MAX : rend valeur × pv_max, clampé")
	var m := _moteur(10.0, [_soin(0.25, 0)])
	m.avatar().pv = 40.0   # blessé (pv_max 100)
	var soins: Array = []
	m.evenement.connect(func(e: Dictionary) -> void:
		if str(e.get("type", "")) == "soin":
			soins.append(e))
	m.activer_suivant()
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": m.avatar().data.competences[0]})
	_check("40 → 65 PV (+25 % de 100)", is_equal_approx(m.avatar().pv, 65.0))
	_check("événement soin émis (+25)", soins.size() == 1
			and is_equal_approx(float(soins[0]["soin"]), 25.0))
	# Clamp au pv_max.
	var m2 := _moteur(10.0, [_soin(0.25, 0)])
	m2.avatar().pv = 90.0
	m2.activer_suivant()
	m2.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": m2.avatar().data.competences[0]})
	_check("clampé à pv_max (90 → 100)", is_equal_approx(m2.avatar().pv, 100.0))

# ─── 3. Cooldown en activations du lanceur ───────────────────

func _test_cooldown() -> void:
	print("\n[3] Cooldown : posé à l'usage, décrément à CHAQUE activation du lanceur")
	var m := _moteur(1.0, [_soin(0.10, 2)])
	var comp: CompetenceCtbData = m.avatar().data.competences[0]
	var av := m.avatar()
	_check("prête au départ", av.competence_prete(comp))
	m.activer_suivant()   # héros (VIT 100 : agit d'abord)
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": comp})
	_check("après usage : en recharge (2)", not av.competence_prete(comp)
			and av.cooldown_restant(comp) == 2)
	# Activation suivante du héros : décrément → 1, toujours en recharge.
	_activer_jusqua(m, av)
	m.jouer({"type": Enums.ActionCtb.DEFENDRE})
	_check("activation 1 : recharge → 1", av.cooldown_restant(comp) == 1)
	# 2e activation : décrément → 0, PRÊTE.
	_activer_jusqua(m, av)
	_check("activation 2 : prête à nouveau", av.competence_prete(comp))
	m.jouer({"type": Enums.ActionCtb.DEFENDRE})

func _activer_jusqua(m: CtbMoteur, qui: CtbCombattant) -> void:
	var garde := 0
	while garde < 20:
		garde += 1
		var c := m.activer_suivant()
		if c == qui or c == null:
			return
		m.jouer(m.action_auto(c))

# ─── 4. Garde-fous ───────────────────────────────────────────

func _test_garde_fous() -> void:
	print("\n[4] Garde-fous : non possédée / en recharge = activation perdue, sans crash")
	var m := _moteur(1.0, [_soin(0.10, 3)])
	var av := m.avatar()
	var etrangere := _frappe(2.0, 0)
	m.activer_suivant()
	var pv_avant := _ennemi_de(m).pv
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": etrangere,
			"cible": _ennemi_de(m)})
	_check("compétence non possédée → aucun effet", is_equal_approx(_ennemi_de(m).pv, pv_avant))
	# En recharge : usage → rien (PV inchangés), cooldown non re-posé.
	var comp: CompetenceCtbData = av.data.competences[0]
	_activer_jusqua(m, av)
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": comp})
	av.pv = 50.0
	_activer_jusqua(m, av)
	m.jouer({"type": Enums.ActionCtb.COMPETENCE, "competence": comp})   # recharge (2)
	_check("en recharge → aucun soin", is_equal_approx(av.pv, 50.0))
	_check("cooldown poursuit son décompte", av.cooldown_restant(comp) == 2)

# ─── 5. Dotation du héros (CtbPont) ──────────────────────────

func _test_dotation_heros() -> void:
	print("\n[5] Dotation : le héros du pont porte les compétences du .tres")
	var h := CtbPont.combattant_depuis_heros()
	_check("pont héros disponible", h != null)
	if h == null:
		return
	var ids: Array[String] = []
	for c: CompetenceCtbData in h.competences:
		ids.append(c.id)
	_check("dotation appliquée (frappe lourde + second souffle)",
			ids.has("comp_frappe_lourde") and ids.has("comp_second_souffle"))
	_check("le bestiaire reste sans compétence",
			CtbPont.combattant_depuis_entite("creature_foret_surface").competences.is_empty())

# ─── 6. Écran de combat : boutons ────────────────────────────

func _test_ui() -> void:
	print("\n[6] Écran de combat : boutons présents / grisés en recharge / absents")
	get_tree().root.size = Vector2i(1280, 720)
	var m := _moteur(1.0, [_frappe(1.6, 3), _soin(0.25, 4)])
	var ui := CombatCtbUi.new(m, false)
	ui.facteur_delais = 0.0
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame   # _boucle : tour du héros (VIT 100) ouvert
	var btns := _boutons_competences(ui)
	_check("2 boutons de compétence au tour du héros", btns.size() == 2)
	_check("aucun grisé (tout est prêt)", btns.all(
			func(b: Button) -> bool: return not b.disabled))
	# Lancer le soin → au tour suivant du héros, il est grisé avec compteur.
	var idx_soin := -1
	for i in btns.size():
		if btns[i].text.begins_with("Second"):
			idx_soin = i
	_check("bouton du soin identifiable", idx_soin >= 0)
	if idx_soin >= 0:
		btns[idx_soin].pressed.emit()   # sans cible requise → action validée
		for i in 8:
			await get_tree().process_frame   # l'ennemi joue, retour au héros
		var btns2 := _boutons_competences(ui)
		var grises := btns2.filter(func(b: Button) -> bool: return b.disabled)
		_check("au tour suivant : le soin est grisé avec compteur",
				grises.size() == 1 and grises[0].text.contains("("))
	ui.queue_free()
	await get_tree().process_frame
	# Combattant SANS compétence : aucun bouton (absent, pas grisé).
	var m2 := _moteur(1.0, [])
	var ui2 := CombatCtbUi.new(m2, false)
	ui2.facteur_delais = 0.0
	add_child(ui2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("sans compétence : aucun bouton", _boutons_competences(ui2).is_empty())
	ui2.queue_free()
	await get_tree().process_frame

func _boutons_competences(ui: CombatCtbUi) -> Array[Button]:
	var out: Array[Button] = []
	for b in ui._btns_competences:
		out.append(b as Button)
	return out

# ─── Helpers ─────────────────────────────────────────────────

# Héros VIT 100 (agit d'abord), ennemi VIT 10 — DEF 0, crit 0 partout.
func _moteur(atk_ennemi: float, comps: Array[CompetenceCtbData]) -> CtbMoteur:
	var m := CtbMoteur.new()
	m.rng.seed = 5
	var h := CombattantCtbData.new()
	h.id = "heros_test"
	h.nom_affichage_fr = "Héros"
	h.pv_max = 100.0
	h.atk = 10.0
	h.def = 0.0
	h.vit = 100.0
	h.crit_chance = 0.0
	h.competences = comps
	m.ajouter(h, Enums.CampCtb.JOUEUR)
	var e := CombattantCtbData.new()
	e.id = "ennemi_test"
	e.nom_affichage_fr = "Ennemi"
	e.pv_max = 500.0
	e.atk = atk_ennemi
	e.def = 0.0
	e.vit = 10.0
	e.crit_chance = 0.0
	m.ajouter(e, Enums.CampCtb.ADVERSE)
	m.demarrer()
	return m

func _frappe(valeur: float, cooldown: int) -> CompetenceCtbData:
	var c := CompetenceCtbData.new()
	c.id = "test_frappe"
	c.nom_affichage_fr = "Frappe test"
	c.effet = Enums.EffetCompetence.ATTAQUE_MULT
	c.valeur = valeur
	c.cooldown = cooldown
	return c

func _soin(valeur: float, cooldown: int) -> CompetenceCtbData:
	var c := CompetenceCtbData.new()
	c.id = "test_soin"
	c.nom_affichage_fr = "Second souffle test"
	c.nom_affichage_en = "Second Wind test"
	c.effet = Enums.EffetCompetence.SOIN_PCT_PV_MAX
	c.valeur = valeur
	c.cooldown = cooldown
	return c

func _ennemi_de(m: CtbMoteur) -> CtbCombattant:
	for c in m.combattants:
		if not c.est_joueur():
			return c
	return null

func _degats_subis(m: CtbMoteur) -> int:
	var e := _ennemi_de(m)
	return int(roundf(e.data.pv_max - e.pv))

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
