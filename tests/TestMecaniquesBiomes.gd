extends Node
# ============================================================
# TestMecaniquesBiomes — Mécaniques fortes de biome en combat CTB (ch.15).
#
# Couvre : les deux hooks GÉNÉRIQUES du moteur (modif_degats_camp — ordre
# contractuel APRÈS crit / AVANT Défendre — et statut_on_hit_camp, jet
# seulement si une règle existe), puis le câblage ExpeRun : gate par palier
# de profondeur (Périphérie sans mécanique, Enceinte/Noyau/Assaut avec),
# endurcissement (Montagne), poison (Marécage), embuscade généralisée
# (Forêt), payload `mecanique` de combat_demarre.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

const MECAS: MecaniquesBiomesData = preload("res://data/expedition/mecaniques_biomes.tres")

var _fail: Array[String] = []
var _nb_ok := 0

func _ready() -> void:
	# JAMAIS d'écriture de sauvegarde dans un test (règle projet).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST MÉCANIQUES DE BIOME EN CTB (chantier 15) ===\n")
	_test_moteur_modif_degats()
	_test_moteur_statut_on_hit()
	_test_gate_palier()
	_test_endurcissement_montagne()
	_test_poison_marecage()
	_test_ambush_foret()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── 1-2. Hooks génériques du moteur ─────────────────────────

func _test_moteur_modif_degats() -> void:
	print("[1] Hook modif_degats_camp (ordre : après crit, avant Défendre)")
	# Sans règle : ATK 10 vs DEF 0 → 10.
	_check("sans règle : 10 dégâts", _degats_premier_coup({}) == 10)
	# ×0.8 sur le camp joueur → 8.
	_check("règle ×0.8 (endurcissement) : 8 dégâts",
			_degats_premier_coup({Enums.CampCtb.JOUEUR: 0.8}) == 8)
	# Avec Défendre : 10 × 0.8 (règle) × (1 − réduction) — l'ordre est testé
	# par la valeur composée (réduction lue dans la config du moteur).
	var m := _moteur_1v1(1.0, {Enums.CampCtb.JOUEUR: 0.8})
	var reduc := m.config.defendre_reduction_degats
	var attendu := int(roundf(maxf(10.0 * 0.8 * (1.0 - reduc), Balance.MIN_DAMAGE)))
	# L'ennemi (VIT 11, premier) se met en garde, puis le héros frappe.
	var c1 := m.activer_suivant()
	m.jouer({"type": Enums.ActionCtb.DEFENDRE})
	var c2 := m.activer_suivant()
	m.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": _ennemi_de(m)})
	_check("avec Défendre : %d dégâts (règle PUIS garde)" % attendu,
			int(m.combattants[1].data.pv_max - m.combattants[1].pv) == attendu
			and c1 != null and c2 != null)

func _test_moteur_statut_on_hit() -> void:
	print("\n[2] Hook statut_on_hit_camp (poison on-hit)")
	var statut: StatutCtbData = load("res://data/combat_ctb/statut_poison.tres")
	var evenements: Array = []
	# Chance 1.0 : le coup ENNEMI pose le statut sur le héros.
	var m := _moteur_1v1(3.0, {}, {Enums.CampCtb.ADVERSE: {"statut": statut, "chance": 1.0}})
	m.evenement.connect(func(e: Dictionary) -> void: evenements.append(e))
	m.activer_suivant()   # ennemi (VIT haute)
	m.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": m.avatar()})
	_check("chance 1.0 → statut posé sur le héros", m.avatar().statuts.size() == 1)
	_check("événement statut_pose émis", evenements.any(
			func(e: Dictionary) -> bool: return str(e.get("type", "")) == "statut_pose"))
	# Chance 0.0 : jamais.
	var m0 := _moteur_1v1(3.0, {}, {Enums.CampCtb.ADVERSE: {"statut": statut, "chance": 0.0}})
	m0.activer_suivant()
	m0.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": m0.avatar()})
	_check("chance 0.0 → aucun statut", m0.avatar().statuts.is_empty())
	# Le camp sans règle ne pose rien (le héros frappe, l'ennemi reste sain).
	var mj := _moteur_1v1(3.0, {}, {Enums.CampCtb.ADVERSE: {"statut": statut, "chance": 1.0}})
	mj.activer_suivant()
	mj.jouer({"type": Enums.ActionCtb.DEFENDRE})   # l'ennemi passe
	mj.activer_suivant()
	mj.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": _ennemi_de(mj)})
	_check("camp sans règle → cible saine", _ennemi_de(mj).statuts.is_empty())

# ─── 3. Gate par palier (ExpeRun) ────────────────────────────

func _test_gate_palier() -> void:
	print("\n[3] Gate : Périphérie sans mécanique, Enceinte/Assaut avec")
	_check("Montagne @ Périphérie → aucune",
			_run_lieu("biome_montagne", "palier_peripherie").mecanique_active() == "")
	_check("Montagne @ Enceinte → endurcissement",
			_run_lieu("biome_montagne", "palier_enceinte").mecanique_active() == "endurcissement")
	_check("Montagne @ Noyau → endurcissement",
			_run_lieu("biome_montagne", "palier_noyau").mecanique_active() == "endurcissement")
	_check("Lieu sans biome → aucune",
			_run_lieu("lieu_test", "palier_enceinte").mecanique_active() == "")

# ─── 4-6. Câblage par mécanique ──────────────────────────────

func _test_endurcissement_montagne() -> void:
	print("\n[4] Endurcissement (Montagne) : dégâts du camp joueur × %.2f" % MECAS.endurcissement_mult)
	var run := _run_lieu("biome_montagne", "palier_enceinte")
	var data := _entrer_en_combat(run)
	_check("un combat a démarré", run.combat_en_cours != null)
	if run.combat_en_cours == null:
		return
	_check("hook modif_degats_camp posé sur le camp joueur",
			is_equal_approx(float(run.combat_en_cours.modif_degats_camp.get(
					Enums.CampCtb.JOUEUR, 1.0)), MECAS.endurcissement_mult))
	_check("payload combat_demarre porte la mécanique",
			str(data.get("mecanique", "")) == "endurcissement")
	run.combat_en_cours.derouler_auto()

func _test_poison_marecage() -> void:
	print("\n[5] Poison (Marécage) : statut on-hit du camp adverse")
	var run := _run_lieu("biome_marecage", "palier_enceinte")
	_entrer_en_combat(run)
	_check("un combat a démarré", run.combat_en_cours != null)
	if run.combat_en_cours == null:
		return
	var regle: Dictionary = run.combat_en_cours.statut_on_hit_camp.get(
			Enums.CampCtb.ADVERSE, {})
	_check("hook statut_on_hit posé (statut de la config)",
			regle.get("statut") == MECAS.poison_statut)
	_check("chance de la config", is_equal_approx(float(regle.get("chance", 0.0)),
			MECAS.poison_chance))
	_check("Périphérie : PAS de hook", _hook_poison_absent_en_peripherie())
	run.combat_en_cours.derouler_auto()

func _hook_poison_absent_en_peripherie() -> bool:
	var run := _run_lieu("biome_marecage", "palier_peripherie")
	_entrer_en_combat(run)
	if run.combat_en_cours == null:
		return false
	var absent: bool = run.combat_en_cours.statut_on_hit_camp.is_empty()
	run.combat_en_cours.derouler_auto()
	return absent

func _test_ambush_foret() -> void:
	print("\n[6] Embuscade (Forêt) : initiative retardée sur les combats NORMAUX")
	var run := _run_lieu("biome_foret", "palier_enceinte")
	_entrer_en_combat(run)
	_check("un combat a démarré", run.combat_en_cours != null)
	if run.combat_en_cours == null:
		return
	_check("malus d'initiative appliqué à un combat normal",
			is_equal_approx(run.combat_en_cours.malus_horloge_initiale_joueur,
					run.cfg_combat.malus_horloge_embuscade))
	run.combat_en_cours.derouler_auto()
	var run_p := _run_lieu("biome_foret", "palier_peripherie")
	_entrer_en_combat(run_p)
	if run_p.combat_en_cours != null:
		_check("Périphérie : pas de malus",
				is_equal_approx(run_p.combat_en_cours.malus_horloge_initiale_joueur, 1.0))
		run_p.combat_en_cours.derouler_auto()

# ─── Helpers ─────────────────────────────────────────────────

# Moteur 1v1 : héros ATK 10/VIT 10 vs ennemi ATK `atk_ennemi`/VIT 11 —
# l'ennemi agit en PREMIER puis alternance stricte (K/11 < K/10 < 2K/11),
# DEF 0 partout, crit 0 → dégâts exacts.
func _moteur_1v1(atk_ennemi: float, modif: Dictionary,
		on_hit: Dictionary = {}) -> CtbMoteur:
	var m := CtbMoteur.new()
	m.rng.seed = 7
	m.modif_degats_camp = modif
	m.statut_on_hit_camp = on_hit
	var h := CombattantCtbData.new()
	h.id = "heros_test"
	h.nom_affichage_fr = "Héros"
	h.pv_max = 100.0
	h.atk = 10.0
	h.def = 0.0
	h.vit = 10.0
	h.crit_chance = 0.0
	m.ajouter(h, Enums.CampCtb.JOUEUR)
	var e := CombattantCtbData.new()
	e.id = "ennemi_test"
	e.nom_affichage_fr = "Ennemi"
	e.pv_max = 100.0
	e.atk = atk_ennemi
	e.def = 0.0
	e.vit = 11.0
	e.crit_chance = 0.0
	m.ajouter(e, Enums.CampCtb.ADVERSE)
	m.demarrer()
	return m

# Dégâts du premier coup du HÉROS (l'ennemi attaque d'abord — pas de garde).
func _degats_premier_coup(modif: Dictionary) -> int:
	var m := _moteur_1v1(1.0, modif)
	m.activer_suivant()                              # ennemi (VIT 11)
	m.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": m.avatar()})
	m.activer_suivant()                              # héros
	m.jouer({"type": Enums.ActionCtb.ATTAQUER, "cible": _ennemi_de(m)})
	return int(m.combattants[1].data.pv_max - m.combattants[1].pv)

func _ennemi_de(m: CtbMoteur) -> CtbCombattant:
	for c in m.combattants:
		if not c.est_joueur():
			return c
	return null

func _run_lieu(lieu: String, palier_id: String) -> ExpeRun:
	var cfg := ExpeCarteConfigData.new()
	cfg.poids_combat = 1.0
	cfg.poids_mystere = 0.0
	cfg.poids_coffre = 0.0
	var cc := ExpeCombatConfigData.new()
	cc.poids_nb_ennemis = {1: 1.0}
	var a := CombattantCtbData.new()
	a.id = "avatar_test"
	a.nom_affichage_fr = "Avatar de test"
	a.pv_max = 100000.0
	a.atk = 5000.0
	a.def = 0.0
	a.vit = 10.0
	a.crit_chance = 0.0
	var r := ExpeRun.new(cfg, load("res://data/expedition/%s.tres" % palier_id),
			lieu, 99, a, load("res://data/expedition/pool_defaut.tres"), cc)
	r.demarrer()
	return r

# Avance jusqu'au premier nœud Combat SANS résoudre le combat (inspection du
# moteur monté). Retourne le payload de combat_demarre.
func _entrer_en_combat(run: ExpeRun) -> Dictionary:
	var data: Array = [{}]
	run.combat_demarre.connect(func(_m: CtbMoteur, d: Dictionary) -> void: data[0] = d)
	var garde := 0
	while run.combat_en_cours == null and not run.est_terminee and garde < 50:
		garde += 1
		var suivant := -1
		for v in run.carte.noeud(run.position_joueur).voisins:
			var nd := run.carte.noeud(v)
			if not nd.resolu and nd.type == Enums.TypeNoeud.COMBAT:
				suivant = v
				break
		if suivant < 0:
			for v in run.carte.noeud(run.position_joueur).voisins:
				if not run.carte.noeud(v).resolu:
					suivant = v
					break
		if suivant < 0:
			return data[0]
		run.deplacer_vers(suivant)
	return data[0]

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
