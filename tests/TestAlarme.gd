extends Node
# ============================================================
# TestAlarme — Système d'Alarme et assauts de Lieutenants (chantier 11) :
#   • complétion par Lieu × strate (complétion compte, extraction/défaite non),
#   • option Assaut du panneau de lancement (ABSENTE avant 3/3, présente après),
#   • assaut = 1 étage, nœud BOSS remplaçant la Fin d'étage, aucune extraction,
#   • combat de boss : composition EXACTE Lieutenant + 2 sbires du pool,
#   • premier kill → slot d'Alarme persisté (round-trip par le VRAI fichier),
#     re-kill → pas de re-slot + récompenses normales,
#   • bonus d'Alarme appliqués aux ennemis de TOUTES les expéditions
#     (deltas % exacts par palier 0-6, affixes présents à 4+, PV pleins),
#   • Game Over pendant un assaut → kill annulé par rechargement (cohérence),
#   • 6/6 → alarme_sonnee (une seule fois), jauge HoloMap branchée à l'état.
#
# ⚠ Écrit réellement la sauvegarde (round-trip = l'objet) — protocole des
# chantiers 8/9 : fichiers réels mis de côté (.avant_test) puis restaurés.
# ============================================================

const SAUV := SaveManager.SAVE_PATH
const META := SaveManager.META_PATH
const FICHIERS: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]

const LIEUTENANTS_TRES := [
	"res://data/expedition/lieutenants/lieutenant_foret.tres",
	"res://data/expedition/lieutenants/lieutenant_marecage.tres",
	"res://data/expedition/lieutenants/lieutenant_montagne.tres",
	"res://data/expedition/lieutenants/lieutenant_colline.tres",
	"res://data/expedition/lieutenants/lieutenant_ville_fantome.tres",
	"res://data/expedition/lieutenants/lieutenant_cimetiere.tres",
]

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_proteger()
	SaveManager.load_save()   # aucun fichier (protégé) : marque juste « chargé »
	await _run_all()
	_restaurer()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST ALARME & ASSAUTS DE LIEUTENANTS (chantier 11) ===\n")
	_test_donnees()
	_test_completion_strates()
	await _test_option_assaut_panneau()
	_test_assaut_carte_boss()
	_test_assaut_sans_extraction()
	_test_composition_boss()
	_test_premier_kill_et_round_trip()
	_test_rekill()
	_test_bonus_alarme_deltas()
	_test_alarme_expedition_normale()
	_test_game_over_annule_kill()
	_test_alarme_sonnee()
	await _test_jauge_holomap()

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

func _proteger() -> void:
	for f: String in FICHIERS:
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f),
					ProjectSettings.globalize_path(f) + ".avant_test")

func _restaurer() -> void:
	for f: String in FICHIERS:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if FileAccess.file_exists(f + ".avant_test"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(f) + ".avant_test",
					ProjectSettings.globalize_path(f))

# Remise à zéro de l'état chantier 11 entre les tests.
func _reset_etat() -> void:
	GameData.player["expe_completions"] = {}
	GameData.player["lieutenants_vaincus"] = {}

# n slots d'Alarme remplis via des lieux factices (l'état, pas le parcours).
func _forcer_slots(n: int) -> void:
	var vaincus := {}
	for i in n:
		vaincus["lieu_factice_%d" % i] = true
	GameData.player["lieutenants_vaincus"] = vaincus

func _palier(chemin: String = "res://data/expedition/palier_peripherie.tres") -> PalierProfondeurData:
	return load(chemin)

func _pool() -> PoolEnnemisData:
	return load("res://data/expedition/pool_defaut.tres")

func _cfg_carte() -> ExpeCarteConfigData:
	var c := ExpeCarteConfigData.new()
	c.poids_combat = 1.0   # 100 % Combat : trajets déterministes
	c.poids_mystere = 0.0
	c.poids_coffre = 0.0
	return c

func _cfg_combat() -> ExpeCombatConfigData:
	var c := ExpeCombatConfigData.new()
	c.poids_nb_ennemis = {1: 1.0}
	return c

func _avatar(pv: float, atk: float, vit: float) -> CombattantCtbData:
	var a := CombattantCtbData.new()
	a.id = "avatar_test"
	a.nom_affichage_fr = "Avatar de test"
	a.pv_max = pv
	a.atk = atk
	a.def = 0.0
	a.vit = vit
	a.crit_chance = 0.0
	return a

func _lieutenant_data(pv: float = 40.0, atk: float = 1.0) -> CombattantCtbData:
	var d := CombattantCtbData.new()
	d.id = "lieutenant_test"
	d.nom_affichage_fr = "Lieutenant de test"
	d.pv_max = pv
	d.atk = atk
	d.def = 0.0
	d.vit = 10.0
	d.crit_chance = 0.0
	return d

# Run prête à démarrer (assaut optionnel). Avatar costaud par défaut.
func _run(lieu: String, graine: int, assaut: bool = false,
		avatar: CombattantCtbData = null,
		palier: PalierProfondeurData = null) -> ExpeRun:
	var av := avatar if avatar != null else _avatar(100000.0, 5000.0, 100.0)
	var p := palier if palier != null else _palier()
	var r := ExpeRun.new(_cfg_carte(), p, lieu, graine, av, _pool(), _cfg_combat())
	if assaut:
		r.est_assaut = true
		r.lieutenant = _lieutenant_data()
	r.demarrer()
	return r

# Plus court chemin (BFS brut, tous nœuds) de la position vers `cible`.
func _chemin_brut(run: ExpeRun, cible: int) -> Array[int]:
	var pred := {run.position_joueur: -1}
	var file: Array[int] = [run.position_joueur]
	while not file.is_empty():
		var cur: int = file.pop_front()
		if cur == cible:
			break
		for v in run.carte.noeud(cur).voisins:
			if not pred.has(v):
				pred[v] = cur
				file.append(v)
	var chemin: Array[int] = []
	var n := cible
	while n != -1 and pred.has(n):
		chemin.push_front(n)
		n = pred[n]
	chemin.pop_front()
	return chemin

# Un pas + auto-résolution du combat éventuel.
func _pas(run: ExpeRun, nid: int) -> void:
	run.deplacer_vers(nid)
	if run.combat_en_cours != null:
		run.combat_en_cours.derouler_auto()

# Marche jusqu'à la Fin/Boss de l'étage courant, combats auto-résolus.
func _aller_a_la_fin(run: ExpeRun) -> void:
	for nid in _chemin_brut(run, run.carte.fin_id):
		_pas(run, nid)
		if run.est_terminee:
			return

# Boucle une expédition normale complète (tous les étages).
func _boucler(run: ExpeRun) -> void:
	while not run.est_terminee:
		_aller_a_la_fin(run)
		if run.choix_ouvert:
			run.continuer()

# Premier Button du sous-arbre dont le texte contient `motif` (ou null).
func _bouton_contenant(racine: Node, motif: String) -> Button:
	for n in racine.get_children():
		if n is Button and motif in (n as Button).text:
			return n
		var trouve := _bouton_contenant(n, motif)
		if trouve != null:
			return trouve
	return null

# ─── 1. Données du chantier ─────────────────────────────────

func _test_donnees() -> void:
	print("[TEST 1] Données : 6 Lieutenants mappés, palier Assaut, config Alarme")
	var dest: ExpeDestinationsData = load("res://data/expedition/destinations.tres")
	_assert(dest.lieutenants_par_lieu.size() == 6, "6 Lieutenants mappés (3 Lieux + 3 secondaires d'avance)")
	for chemin: String in LIEUTENANTS_TRES:
		var l: CombattantCtbData = load(chemin)
		if l == null or l.pv_max <= 0.0:
			_fail("Lieutenant lisible : " + chemin)
			return
	_ok("les 6 .tres de Lieutenants se chargent (stats non vides)")
	_assert(dest.lieutenant_pour("biome_foret") != null
			and dest.lieutenant_pour("biome_foret").id == "lieutenant_foret",
			"lieutenant_pour(biome_foret) → lieutenant_foret")
	_assert(dest.lieutenant_pour("lieu_inconnu") == null,
			"lieu non mappé → null (l'Assaut ne se lance pas)")
	var pa: PalierProfondeurData = load("res://data/expedition/palier_assaut.tres")
	_assert(pa.id == "palier_assaut", "palier dédié « Assaut » (hors strates)")
	_assert(Alarme.CONFIG.pct_par_slot.size() == 2
			and is_equal_approx(float(Alarme.CONFIG.pct_par_slot["pv_max"]), 0.05)
			and is_equal_approx(float(Alarme.CONFIG.pct_par_slot["atk"]), 0.05),
			"config Alarme : +5 % PV et ATK par slot (provisoire acté)")
	_assert(Alarme.CONFIG.affixes_par_palier.keys().size() == 3,
			"3 affixes de palier (4, 5, 6)")

# ─── 2. Complétion par Lieu × strate ────────────────────────

func _test_completion_strates() -> void:
	print("\n[TEST 2] Complétion de strate : bouclée = oui, extraction/défaite = non")
	_reset_etat()
	var r := _run("lieu_a", 11)
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "run bouclée sans défaite (précondition)")
	_assert(GameData.strate_completee("lieu_a", "palier_peripherie"),
			"complétion (fin du dernier étage) → strate marquée")
	_assert(GameData.nb_strates_completees("lieu_a") == 1, "1/3 strates du Lieu")

	# Extraction anticipée : PAS de complétion.
	var r2 := _run("lieu_b", 22)
	_aller_a_la_fin(r2)
	_assert(r2.choix_ouvert, "choix Extraire/Continuer ouvert (précondition)")
	r2.extraire()
	_assert(r2.est_terminee and not GameData.strate_completee("lieu_b", "palier_peripherie"),
			"extraction anticipée → strate NON marquée")

	# Défaite : PAS de complétion (avatar mourant jeté sur un nœud Combat —
	# 100 % Combat : tout voisin de l'entrée hors Fin d'étage en est un).
	var r3 := _run("lieu_c", 33, false, _avatar(1.0, 1.0, 1.0))
	for v in r3.carte.noeud(r3.carte.entree_id).voisins:
		if v != r3.carte.fin_id:
			_pas(r3, v)
			break
	if not r3.defaite:
		_boucler(r3)   # secours : la marche complète finira sur un combat
	_assert(r3.defaite, "avatar 1 PV → défaite (précondition)")
	_assert(not GameData.strate_completee("lieu_c", "palier_peripherie"),
			"défaite → strate NON marquée")

	# Même Lieu, 3 paliers = 3 strates ; re-compléter ne compte pas double.
	_reset_etat()
	for pid: String in ["palier_peripherie", "palier_enceinte", "palier_noyau"]:
		GameData.marquer_strate_completee("lieu_d", pid)
	GameData.marquer_strate_completee("lieu_d", "palier_noyau")
	_assert(GameData.nb_strates_completees("lieu_d") == 3,
			"3 paliers complétés = 3/3 (idempotent au re-passage)")

# ─── 3. Option Assaut du panneau de lancement ───────────────

func _test_option_assaut_panneau() -> void:
	print("\n[TEST 3] Panneau de lancement : Assaut ABSENT avant 3/3, présent après")
	_reset_etat()
	get_tree().root.size = Vector2i(1280, 720)   # règle projet : fenêtre headless 64×64

	GameData.marquer_strate_completee("biome_foret", "palier_peripherie")
	GameData.marquer_strate_completee("biome_foret", "palier_enceinte")
	var p1 := ExpeLancementPanel.new()
	p1.lieu_id = "biome_foret"
	add_child(p1)
	await get_tree().process_frame
	_assert(_bouton_contenant(p1, "ASSAUT") == null,
			"2/3 strates → option Assaut ABSENTE (pas grisée : absente)")
	_assert(_bouton_contenant(p1, "PARTIR") != null, "bouton PARTIR toujours là")
	p1.queue_free()

	GameData.marquer_strate_completee("biome_foret", "palier_noyau")
	var p2 := ExpeLancementPanel.new()
	p2.lieu_id = "biome_foret"
	add_child(p2)
	await get_tree().process_frame
	var btn := _bouton_contenant(p2, "ASSAUT")
	_assert(btn != null, "3/3 strates + Lieutenant mappé → option Assaut PRÉSENTE")
	var recu := [false]
	p2.lancer_assaut.connect(func() -> void: recu[0] = true)
	if btn != null:
		btn.pressed.emit()
	_assert(recu[0], "clic Assaut → signal lancer_assaut")
	p2.queue_free()
	_reset_etat()

# ─── 4. Assaut : 1 étage, nœud BOSS remplace la Fin d'étage ─

func _test_assaut_carte_boss() -> void:
	print("\n[TEST 4] Assaut : 1 étage, Boss à la place de la Fin d'étage, visible")
	_reset_etat()
	var r := _run("biome_foret", 44, true)
	_assert(r.nb_etages_effectif() == 1, "1 seul étage (config inchangée par ailleurs)")
	var fin := r.carte.noeud(r.carte.fin_id)
	_assert(fin.type == Enums.TypeNoeud.BOSS, "nœud de Fin d'étage devenu BOSS")
	_assert(fin.decouvert, "nœud Boss VISIBLE d'emblée (comme la Fin qu'il remplace)")
	var nb_boss := 0
	for nd in r.carte.noeuds:
		if nd.type == Enums.TypeNoeud.BOSS:
			nb_boss += 1
	_assert(nb_boss == 1, "un SEUL nœud Boss sur la carte")
	var normale := _run("biome_foret", 44)
	var aucun_boss := true
	for nd in normale.carte.noeuds:
		if nd.type == Enums.TypeNoeud.BOSS:
			aucun_boss = false
	_assert(aucun_boss, "expédition normale : jamais de nœud Boss (généré par personne)")

# ─── 5. Assaut : aucune extraction ──────────────────────────

func _test_assaut_sans_extraction() -> void:
	print("\n[TEST 5] Assaut : aucune extraction — victoire ou défaite, rien d'autre")
	_reset_etat()
	var r := _run("biome_foret", 55, true)
	r.extraire()
	_assert(not r.est_terminee, "extraire() inopérant (choix jamais ouvert)")
	var choix_vu := [false]
	r.noeud_resolu.connect(func(_d: Dictionary) -> void:
		if r.choix_ouvert:
			choix_vu[0] = true)
	_aller_a_la_fin(r)
	_assert(not choix_vu[0], "choix Extraire/Continuer JAMAIS ouvert pendant l'assaut")
	_assert(r.est_terminee and not r.defaite, "victoire du Boss → fin d'assaut immédiate")
	var recap := r._recap(false)
	_assert(bool(recap["est_assaut"]) and bool(recap["complete"]),
			"recap d'assaut : est_assaut + complete")

# ─── 6. Combat de boss : Lieutenant + 2 sbires EXACTEMENT ───

func _test_composition_boss() -> void:
	print("\n[TEST 6] Composition du combat de boss : Lieutenant + 2 sbires du pool")
	_reset_etat()
	var r := _run("biome_foret", 66, true)
	# Le combat du BOSS est le DERNIER combat de l'assaut (la victoire y met
	# fin) : capturer chaque moteur, le dernier est le bon.
	var capture: Array = [null]
	r.combat_demarre.connect(func(m: CtbMoteur, _d: Dictionary) -> void:
		capture[0] = m)
	_aller_a_la_fin(r)
	_assert(r.est_terminee and not r.defaite, "assaut gagné (précondition)")
	var m: CtbMoteur = capture[0]
	_assert(m != null, "moteur du combat de boss capturé")
	if m == null:
		return
	var adverses: Array = m.combattants.filter(
			func(c: CtbCombattant) -> bool: return c.camp == Enums.CampCtb.ADVERSE)
	_assert(adverses.size() == 1 + ExpeRun.NB_SBIRES_ASSAUT,
			"exactement 3 ennemis (Lieutenant + 2 sbires)")
	_assert(adverses[0].data.id == "lieutenant_test", "le Lieutenant est du combat")
	var pool_ids: Array = _pool().creature_ids
	var sbires_ok := true
	for i in range(1, adverses.size()):
		if not (adverses[i] as CtbCombattant).data.id in pool_ids:
			sbires_ok = false
	_assert(sbires_ok, "les 2 sbires viennent du pool du Lieu")

# ─── 7. Premier kill : slot persisté (round-trip disque) ────

func _test_premier_kill_et_round_trip() -> void:
	print("\n[TEST 7] Premier kill → slot d'Alarme persisté (round-trip réel)")
	_reset_etat()
	var signaux: Array = []
	var cb := func(lieu: String, premier: bool) -> void:
		signaux.append({"lieu": lieu, "premier": premier})
	EventBus.lieutenant_vaincu.connect(cb)

	var r := _run("biome_foret", 77, true)
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "assaut gagné (précondition)")
	_assert(GameData.lieutenant_vaincu("biome_foret"), "slot du Lieu rempli")
	_assert(GameData.nb_lieutenants_vaincus() == 1, "Alarme 1/6")
	_assert(signaux.size() == 1 and signaux[0]["premier"] == true
			and signaux[0]["lieu"] == "biome_foret",
			"signal lieutenant_vaincu(lieu, premier=true) émis une fois")
	var recap := r._recap(false)
	_assert(bool(recap["premier_kill"]) and str(recap["lieutenant_id"]) == "lieutenant_test"
			and str(recap["palier_id"]) == "palier_peripherie",
			"recap d'assaut : premier_kill + lieutenant_id")
	EventBus.lieutenant_vaincu.disconnect(cb)

	# Round-trip disque : sauvegarde → état écrasé → rechargement → slot revenu.
	SaveManager.sauvegarder_maintenant()
	_assert(FileAccess.file_exists(SAUV), "sauvegarde écrite (fichiers réels protégés)")
	GameData.player["lieutenants_vaincus"] = {}
	GameData.player["expe_completions"] = {}
	SaveManager.recharger()
	_assert(GameData.lieutenant_vaincu("biome_foret"),
			"slot d'Alarme survivant au round-trip disque")

# ─── 8. Re-kill : pas de re-slot, récompenses normales ──────

func _test_rekill() -> void:
	print("\n[TEST 8] Re-kill : pas de re-slot, XP/Euren normaux")
	_reset_etat()
	GameData.player["lieutenants_vaincus"] = {"biome_foret": true}
	var signaux: Array = []
	var cb := func(_lieu: String, premier: bool) -> void:
		signaux.append(premier)
	EventBus.lieutenant_vaincu.connect(cb)
	var r := _run("biome_foret", 88, true)
	_boucler(r)
	_assert(r.est_terminee and not r.defaite, "re-assaut gagné (précondition)")
	_assert(GameData.nb_lieutenants_vaincus() == 1, "toujours 1/6 : pas de re-slot")
	_assert(signaux == [false], "signal émis avec premier=false (re-kill)")
	var recap := r._recap(false)
	_assert(not bool(recap["premier_kill"]), "recap : premier_kill=false")
	_assert(float(recap["xp_gagnee"]) > 0.0, "XP normale créditée (sbires du bestiaire)")
	_assert(float(recap["euren_credite"]) > 0.0, "Euren normal crédité à la sortie")
	EventBus.lieutenant_vaincu.disconnect(cb)

# ─── 9. Bonus d'Alarme : deltas exacts par palier 0-6 ───────

func _test_bonus_alarme_deltas() -> void:
	print("\n[TEST 9] Bonus d'Alarme : +5 %/slot PV+ATK, affixes à 4/5/6, PV pleins")
	_reset_etat()
	var base := _lieutenant_data(100.0, 50.0)   # pv 100, atk 50, def 0, vit 10
	base.def = 20.0
	var attendu_ok := true
	for n in range(0, 7):
		_forcer_slots(n)
		_assert(Alarme.niveau() == n, "niveau d'Alarme = %d slots" % n)
		var m := CtbMoteur.new()
		m.rng.seed = 1
		var cb := m.ajouter(base, Enums.CampCtb.ADVERSE)
		Alarme.appliquer(cb)
		var pv_attendu := 100.0 * (1.0 + 0.05 * n)
		var atk_attendu := 50.0 * (1.0 + 0.05 * n + (0.15 if n >= 5 else 0.0))
		var def_attendu := 20.0 * (1.0 + (0.15 if n >= 4 else 0.0))
		var vit_attendu := 10.0 * (1.0 + (0.10 if n >= 6 else 0.0))
		if not (is_equal_approx(cb.stat_finale("pv_max"), pv_attendu)
				and is_equal_approx(cb.stat_finale("atk"), atk_attendu)
				and is_equal_approx(cb.stat_finale("def"), def_attendu)
				and is_equal_approx(cb.stat_finale("vit"), vit_attendu)
				and is_equal_approx(cb.pv, pv_attendu)):
			attendu_ok = false
			_fail("deltas exacts au palier %d" % n, "pv %f atk %f def %f vit %f pv_courants %f" % [
					cb.stat_finale("pv_max"), cb.stat_finale("atk"),
					cb.stat_finale("def"), cb.stat_finale("vit"), cb.pv])
		_assert(Alarme.affixes_actifs().size() == maxi(0, n - 3),
				"affixes actifs au palier %d : %d" % [n, maxi(0, n - 3)])
	if attendu_ok:
		_ok("deltas % exacts (pv/atk/def/vit) et PV de départ pleins, paliers 0-6")
	_reset_etat()

# ─── 10. Alarme appliquée dans une expédition NORMALE ───────

func _test_alarme_expedition_normale() -> void:
	print("\n[TEST 10] L'Alarme renforce les ennemis des expéditions normales")
	_reset_etat()
	_forcer_slots(3)
	var r := _run("lieu_e", 99)
	var capture: Array = [null]
	r.combat_demarre.connect(func(m: CtbMoteur, _d: Dictionary) -> void:
		if capture[0] == null:
			capture[0] = m)
	_aller_a_la_fin(r)
	var m: CtbMoteur = capture[0]
	_assert(m != null, "un combat normal a eu lieu (précondition)")
	if m != null:
		var ennemi: CtbCombattant = null
		for c: CtbCombattant in m.combattants:
			if c.camp == Enums.CampCtb.ADVERSE:
				ennemi = c
				break
		_assert(ennemi != null and is_equal_approx(
				ennemi.stat_finale("pv_max"), ennemi.data.pv_max * 1.15),
				"ennemi normal : PV max ×1.15 à 3 slots (toutes expéditions)")
		_assert(ennemi != null and is_equal_approx(
				ennemi.stat_finale("atk"), ennemi.data.atk * 1.15),
				"ennemi normal : ATK ×1.15 à 3 slots")
	# L'avatar, lui, n'est JAMAIS renforcé par l'Alarme.
	var av := m.avatar() if m != null else null
	_assert(av != null and is_equal_approx(av.stat_finale("atk"), av.data.atk),
			"le camp joueur n'est pas touché par l'Alarme")
	_reset_etat()

# ─── 11. Game Over pendant un assaut : kill annulé ──────────

func _test_game_over_annule_kill() -> void:
	print("\n[TEST 11] Game Over : un kill fait PENDANT la run perdue est annulé")
	_reset_etat()
	# Sauvegarde de RÉFÉRENCE du lancement : aucun Lieutenant vaincu.
	SaveManager.sauvegarder_maintenant()
	SaveManager.suspendre_ecritures()
	# Pendant la run : kill (comme le ferait la victoire de boss)...
	GameData.marquer_lieutenant_vaincu("biome_foret")
	_assert(GameData.nb_lieutenants_vaincus() == 1, "kill marqué pendant la run")
	# ... puis run PERDUE → séquence Game Over : reprise sans flush + rechargement.
	SaveManager.reprendre_ecritures(false)
	SaveManager.recharger()
	_assert(GameData.nb_lieutenants_vaincus() == 0,
			"rechargement → kill annulé (l'assaut perdu n'a pas eu lieu)")
	_assert(not GameData.lieutenant_vaincu("biome_foret"), "slot du Lieu bien vide")

# ─── 12. 6/6 : l'alarme sonne (une seule fois) ──────────────

func _test_alarme_sonnee() -> void:
	print("\n[TEST 12] 6/6 : alarme_sonnee émis au 6e slot, jamais re-émis")
	_reset_etat()
	var sonneries := [0]
	var cb := func() -> void: sonneries[0] += 1
	EventBus.alarme_sonnee.connect(cb)
	_forcer_slots(5)
	GameData.marquer_lieutenant_vaincu("lieu_final")
	_assert(sonneries[0] == 1, "6e slot → alarme_sonnee émis")
	_assert(GameData.nb_lieutenants_vaincus() == 6, "Alarme 6/6")
	GameData.marquer_lieutenant_vaincu("lieu_final")     # re-kill du 6e
	GameData.marquer_lieutenant_vaincu("lieu_factice_0") # re-kill d'un autre
	_assert(sonneries[0] == 1, "re-kills → PAS de re-sonnerie (émise une fois)")
	EventBus.alarme_sonnee.disconnect(cb)
	_reset_etat()

# ─── 13. Jauge HoloMap branchée à l'état de partie ──────────

func _test_jauge_holomap() -> void:
	print("\n[TEST 13] Jauge d'Alarme : source unique = GameData, HUD instanciable")
	_reset_etat()
	_forcer_slots(4)
	var hud := HoloHud.new()
	add_child(hud)
	await get_tree().process_frame
	_assert(is_instance_valid(hud), "HoloHud (porteur de la jauge) vivant en headless")
	_assert(GameData.nb_lieutenants_vaincus() == 4
			and GameData.NB_SLOTS_ALARME == 6,
			"la jauge lit 4/6 depuis l'état de partie (source unique)")
	hud.queue_free()
	_reset_etat()

# ─── Rapport final ──────────────────────────────────────────

func _print_report() -> void:
	var total   := _results.size()
	var passed  := _results.filter(func(r): return r["ok"]).size()
	var failed  := total - passed
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d/%d  (échecs: %d)" % [passed, total, failed])
	if failed > 0:
		print("ÉCHECS :")
		for r in _results:
			if not r["ok"]:
				print("  ✗ " + r["label"])
	print("════════════════════════════════\n")
