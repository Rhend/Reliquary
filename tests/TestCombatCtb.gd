extends Node
# Tests unitaires du moteur CTB (Rework Combat — chantier 1).
# Déterministes : crit forcé à 0.0 / 1.0, RNG seedée, VIT choisies pour
# contrôler l'ordre de la file. Vérifie : file CTB (cadence, égalités,
# réarmement à VIT courante), formule de dégâts, stats finales additives,
# hook DoT (timings début/fin, stacks, durées), signaux de fin, garde-fou.

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TEST COMBAT CTB ===\n")
	_test_file_cadence_vit_double()
	_test_egalite_avantage_joueur()
	_test_rearmement_vit_courante()
	_test_degats_formule()
	_test_crit_deterministe()
	_test_stats_finales_additives()
	_test_poison_timing_fin_et_duree()
	_test_poison_stacks_max_et_additifs()
	_test_saignement_hook_timing_debut()
	_test_mort_dot_debut_annule_activation()
	_test_action_non_implementee()
	_test_defaite_signaux()
	_test_victoire_signaux_et_recap()
	_test_garde_fou()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

# ─── Helpers ────────────────────────────────────────────────

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

# Combattant de test SANS critique (déterminisme par défaut).
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

func _statut(id: String, timing: Enums.TimingStatut, pct: float,
		stacks_max: int, duree: int) -> StatutCtbData:
	var s := StatutCtbData.new()
	s.id = id
	s.nom_affichage_fr = id
	s.timing = timing
	s.degats_pct_atk = pct
	s.stacks_max = stacks_max
	s.duree_activations = duree
	return s

# Moteur 1 avatar vs N ennemis, prêt à dérouler.
func _moteur(avatar_ov: Dictionary, ennemis_ov: Array) -> CtbMoteur:
	var m := CtbMoteur.new()
	m.rng.seed = 1337
	m.ajouter(_data("avatar", avatar_ov), Enums.CampCtb.JOUEUR)
	for i in ennemis_ov.size():
		m.ajouter(_data("ennemi_%d" % (i + 1), ennemis_ov[i]), Enums.CampCtb.ADVERSE)
	m.demarrer()
	return m

# Joue les `n` prochaines activations en action_auto ; renvoie l'ordre
# (ids des combattants activés, mort-au-début comprise via le journal).
func _derouler(m: CtbMoteur, n: int) -> Array:
	var ordre: Array = []
	while ordre.size() < n and not m.termine:
		var avant := m.nb_activations
		var c := m.activer_suivant()
		if m.nb_activations > avant:
			ordre.append(c.data.id if c != null else "(consommée)")
		if c != null:
			m.jouer(m.action_auto(c))
	return ordre

# ─── Tests : file CTB ───────────────────────────────────────

# VIT double → deux activations pour une (horloges 25/50/75/100 vs 100).
func _test_file_cadence_vit_double() -> void:
	print("[TEST] File CTB — cadence VIT double")
	var m := _moteur({"vit": 40.0, "pv_max": 1000.0, "atk": 1.0},
			[{"vit": 10.0, "pv_max": 1000.0, "atk": 1.0}])
	var ordre := _derouler(m, 5)
	_assert(ordre == ["avatar", "avatar", "avatar", "avatar", "ennemi_1"],
			"VIT 40 vs 10 : 4 activations avatar (25/50/75/100) avant l'ennemi (100... égalité au 4e)",
			str(ordre))

# Égalité d'horloge stricte : Avatar d'abord, puis ennemis dans l'ordre de liste.
func _test_egalite_avantage_joueur() -> void:
	print("\n[TEST] Égalité d'horloge — avantage camp joueur")
	var m := _moteur({"vit": 20.0, "pv_max": 1000.0, "atk": 1.0},
			[{"vit": 20.0, "pv_max": 1000.0, "atk": 1.0},
			 {"vit": 20.0, "pv_max": 1000.0, "atk": 1.0}])
	var ordre := _derouler(m, 6)
	_assert(ordre == ["avatar", "ennemi_1", "ennemi_2", "avatar", "ennemi_1", "ennemi_2"],
			"VIT égales : avatar, puis ennemis dans l'ordre de liste (deux vagues)", str(ordre))

# Le réarmement utilise la VIT COURANTE : un buff VIT posé en cours de combat
# agit dès le réarmement suivant.
func _test_rearmement_vit_courante() -> void:
	print("\n[TEST] Réarmement à la VIT courante (buff en cours de combat)")
	var m := _moteur({"vit": 10.0, "pv_max": 1000.0, "atk": 1.0},
			[{"vit": 20.0, "pv_max": 1000.0, "atk": 1.0}])
	var ennemi := m.combattants[1]
	_assert(absf(ennemi.horloge - 50.0) < 0.001, "horloge initiale ennemie = K/VIT = 50")
	ennemi.ajouter_bonus_pct("vit", 1.0)   # VIT finale ×2 (20 → 40)
	var c := m.activer_suivant()           # ennemi (50 < avatar 100)
	_assert(c == ennemi, "l'ennemi s'active en premier (50 < 100)")
	m.jouer(m.action_auto(c))
	_assert(absf(ennemi.horloge - 75.0) < 0.001,
			"réarmement avec la VIT bufée : 50 + 1000/40 = 75", "horloge=%.2f" % ennemi.horloge)

# ─── Tests : dégâts & stats ─────────────────────────────────

# dégâts = ATK × (1 − 0.5 × DEF / (DEF + 40)) : 20 vs DEF 40 → 15.
func _test_degats_formule() -> void:
	print("\n[TEST] Formule de dégâts héritée")
	var m := _moteur({"atk": 20.0, "vit": 40.0}, [{"def": 40.0, "pv_max": 50.0, "vit": 10.0}])
	var c := m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(m.combattants[1].pv - 35.0) < 0.001,
			"20 ATK vs 40 DEF : 20 × (1 − 0.5×40/80) = 15 dégâts (PV 50 → 35)",
			"pv=%.1f" % m.combattants[1].pv)

# Crit forcé à 100 % : dégâts × CritMult.
func _test_crit_deterministe() -> void:
	print("\n[TEST] Critique déterministe (100 %)")
	var m := _moteur({"atk": 20.0, "vit": 40.0, "crit_chance": 1.0, "crit_multiplier": 2.0},
			[{"def": 0.0, "pv_max": 100.0, "vit": 10.0}])
	var c := m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(m.combattants[1].pv - 60.0) < 0.001,
			"crit 100 % : 20 × 2.0 = 40 dégâts (PV 100 → 60)", "pv=%.1f" % m.combattants[1].pv)

# stat finale = stat nue × (1 + Σ bonus%), cumul additif.
func _test_stats_finales_additives() -> void:
	print("\n[TEST] Stats finales — cumul additif")
	var m := _moteur({"atk": 20.0, "vit": 40.0}, [{"def": 0.0, "pv_max": 100.0, "vit": 10.0}])
	var av := m.avatar()
	av.ajouter_bonus_pct("atk", 0.16)
	av.ajouter_bonus_pct("atk", 0.09)
	_assert(absf(av.stat_finale("atk") - 25.0) < 0.001,
			"20 × (1 + 0.16 + 0.09) = 25 (additif, pas multiplicatif)")
	var c := m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(m.combattants[1].pv - 75.0) < 0.001,
			"dégâts avec ATK finale : 25 (PV 100 → 75)", "pv=%.1f" % m.combattants[1].pv)

# ─── Tests : statuts DoT ────────────────────────────────────

# Poison (.tres) : tick à la FIN de l'activation de la cible, 5 % ATK poseur,
# durée 2 activations puis expiration.
func _test_poison_timing_fin_et_duree() -> void:
	print("\n[TEST] Poison — timing FIN + durée en activations")
	var poison: StatutCtbData = load("res://data/combat_ctb/statut_poison.tres")
	_assert(poison.timing == Enums.TimingStatut.FIN_ACTIVATION, "poison.tres : timing = FIN")
	# Ennemi rapide (agit 3× avant l'avatar) pour isoler ses ticks.
	var m := _moteur({"atk": 100.0, "vit": 5.0, "pv_max": 1000.0},
			[{"vit": 40.0, "pv_max": 50.0, "atk": 1.0}])
	var ennemi := m.combattants[1]
	m.appliquer_statut(ennemi, poison, m.avatar())   # 5 % × 100 ATK = 5 / tick
	var c := m.activer_suivant()                     # ennemi (25 < 200)
	_assert(absf(ennemi.pv - 50.0) < 0.001, "aucun tick au DÉBUT de l'activation (timing FIN)")
	m.jouer(m.action_auto(c))
	_assert(absf(ennemi.pv - 45.0) < 0.001, "tick 1 à la FIN : 5 dégâts (PV 50 → 45)",
			"pv=%.1f" % ennemi.pv)
	c = m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(ennemi.pv - 40.0) < 0.001, "tick 2 : 5 dégâts (PV 45 → 40)")
	_assert(ennemi.statuts.is_empty(), "stack expiré après 2 activations (durée .tres)")
	c = m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(ennemi.pv - 40.0) < 0.001, "3e activation : plus aucun tick")

# Stacks parallèles additifs, plafond 3 (le plus ancien remplacé au-delà).
func _test_poison_stacks_max_et_additifs() -> void:
	print("\n[TEST] Poison — stacks max 3, cumul additif")
	var poison: StatutCtbData = load("res://data/combat_ctb/statut_poison.tres")
	var m := _moteur({"atk": 100.0, "vit": 5.0, "pv_max": 1000.0},
			[{"vit": 40.0, "pv_max": 200.0, "atk": 1.0}])
	var ennemi := m.combattants[1]
	for i in 4:   # 4 poses → plafonné à 3 stacks
		m.appliquer_statut(ennemi, poison, m.avatar())
	_assert(ennemi.statuts.size() == 3, "4 poses → 3 stacks (max .tres)")
	var c := m.activer_suivant()
	m.jouer(m.action_auto(c))
	_assert(absf(ennemi.pv - 185.0) < 0.001,
			"tick additif : 3 × 5 = 15 dégâts (PV 200 → 185)", "pv=%.1f" % ennemi.pv)

# Hook générique : un statut synthétique en timing DÉBUT (futur Saignement)
# tique AVANT l'action de la cible.
func _test_saignement_hook_timing_debut() -> void:
	print("\n[TEST] Hook timing DÉBUT (Saignement — sans valeurs officielles)")
	var saignement := _statut("test_saignement", Enums.TimingStatut.DEBUT_ACTIVATION, 0.10, 1, 2)
	var m := _moteur({"atk": 100.0, "vit": 5.0, "pv_max": 1000.0},
			[{"vit": 40.0, "pv_max": 50.0, "atk": 1.0}])
	var ennemi := m.combattants[1]
	m.appliquer_statut(ennemi, saignement, m.avatar())   # 10 % × 100 = 10 / tick
	var c := m.activer_suivant()
	_assert(absf(ennemi.pv - 40.0) < 0.001,
			"tick au DÉBUT de l'activation, avant l'action (PV 50 → 40)", "pv=%.1f" % ennemi.pv)
	_assert(c == ennemi, "la cible agit ensuite normalement (survivante)")
	m.jouer(m.action_auto(c))

# Mort au tick DÉBUT → activation consommée (pas d'action), le combat continue.
func _test_mort_dot_debut_annule_activation() -> void:
	print("\n[TEST] Mort au tick DÉBUT — activation consommée")
	var saignement := _statut("test_saignement", Enums.TimingStatut.DEBUT_ACTIVATION, 1.0, 1, 2)
	var m := _moteur({"atk": 100.0, "vit": 5.0, "pv_max": 1000.0},
			[{"vit": 40.0, "pv_max": 50.0, "atk": 20.0},
			 {"vit": 10.0, "pv_max": 50.0, "atk": 1.0}])
	var e1 := m.combattants[1]
	var pv_avatar_avant: float = m.avatar().pv
	m.appliquer_statut(e1, saignement, m.avatar())   # 100 % × 100 = 100 ≥ 50 PV
	var c := m.activer_suivant()                     # e1 : meurt au début
	_assert(c == null, "activer_suivant() → null (activation consommée)")
	_assert(not e1.est_vivant(), "la cible est morte au tick DÉBUT")
	_assert(not m.termine, "le combat continue (un 2e ennemi vit)")
	_assert(absf(m.avatar().pv - pv_avatar_avant) < 0.001,
			"aucune action jouée par le mourant (PV avatar intacts)")

# ─── Tests : actions & fins ─────────────────────────────────

# Compétence/Objet : architecture prévue, sans contenu → activation perdue,
# horloge réarmée (aucun dégât).
func _test_action_non_implementee() -> void:
	print("\n[TEST] Action Compétence — prévue mais sans contenu (chantier 1)")
	var m := _moteur({"vit": 40.0, "pv_max": 100.0}, [{"vit": 10.0, "pv_max": 50.0}])
	var c := m.activer_suivant()
	var horloge_avant := c.horloge
	m.jouer({"type": Enums.ActionCtb.COMPETENCE})
	_assert(absf(m.combattants[1].pv - 50.0) < 0.001, "aucun dégât infligé")
	_assert(c.horloge > horloge_avant, "l'activation est consommée (horloge réarmée)")

# Défaite : PV Avatar à 0 → signaux local + EventBus, fin immédiate.
func _test_defaite_signaux() -> void:
	print("\n[TEST] Défaite — signaux")
	var m := _moteur({"pv_max": 10.0, "atk": 1.0, "vit": 10.0},
			[{"atk": 500.0, "vit": 40.0, "pv_max": 1000.0}])
	var locale := [false]
	var bus := [false]
	m.defaite.connect(func(r: Dictionary) -> void: locale[0] = not r["victoire"])
	var cb := func(r: Dictionary) -> void: bus[0] = not r["victoire"]
	EventBus.ctb_defaite.connect(cb)
	m.derouler_auto()
	EventBus.ctb_defaite.disconnect(cb)
	_assert(m.termine and not m.victoire_joueur, "combat terminé en défaite")
	_assert(locale[0], "signal local `defaite` émis avec recap")
	_assert(bus[0], "EventBus.ctb_defaite émis")
	_assert(not m.avatar().est_vivant(), "PV Avatar à 0")

# Victoire : tous ennemis à 0 → signaux + recap complet.
func _test_victoire_signaux_et_recap() -> void:
	print("\n[TEST] Victoire — signaux + recap")
	var m := _moteur({"atk": 500.0, "vit": 40.0},
			[{"pv_max": 30.0, "vit": 10.0, "atk": 1.0}, {"pv_max": 30.0, "vit": 10.0, "atk": 1.0}])
	var recaps := []
	m.victoire.connect(func(r: Dictionary) -> void: recaps.append(r))
	var cb := func(r: Dictionary) -> void: recaps.append(r)
	EventBus.ctb_victoire.connect(cb)
	m.derouler_auto()
	EventBus.ctb_victoire.disconnect(cb)
	_assert(m.termine and m.victoire_joueur, "combat terminé en victoire")
	_assert(recaps.size() == 2, "signaux local + EventBus émis une fois chacun")
	if recaps.size() == 2:
		var r: Dictionary = recaps[0]
		_assert(r["victoire"] and r["nb_activations"] > 0 and r["pv_restants"].has("avatar"),
				"recap : victoire / nb_activations / pv_restants")
		var vaincus: Array = r["ennemis_vaincus"]
		_assert(vaincus.size() == 2 and vaincus[0] is CombattantCtbData \
				and vaincus[0].id == "ennemi_1" and vaincus[1].id == "ennemi_2",
				"recap : ennemis_vaincus = données des 2 tués (références .tres)")

# Garde-fou : combat sans issue (gros PV, dégâts plancher) → arrêt propre.
func _test_garde_fou() -> void:
	print("\n[TEST] Garde-fou MAX_ACTIVATIONS")
	var m := _moteur({"pv_max": 100000.0, "atk": 1.0, "def": 500.0},
			[{"pv_max": 100000.0, "atk": 1.0, "def": 500.0}])
	m.derouler_auto()
	_assert(not m.termine and m.nb_activations >= CtbMoteur.MAX_ACTIVATIONS,
			"arrêt après %d activations sans vainqueur" % CtbMoteur.MAX_ACTIVATIONS)

# ─── Rapport ────────────────────────────────────────────────

func _print_report() -> void:
	var fails: int = _results.filter(func(r): return not r["ok"]).size()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d échec(s)" % fails)
	if fails == 0:
		print("  ✓ moteur CTB conforme")
	print("════════════════════════════════\n")
