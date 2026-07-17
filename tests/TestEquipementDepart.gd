extends Node
# ============================================================
# TestEquipementDepart — Équipement de départ (Rework Combat, chantier 13) :
#   • config data-driven lisible (ids existants, noms non vides, Commun,
#     slots distincts) — jamais d'équipement inventé,
#   • PARTIE NEUVE (aucune sauvegarde) → chaque slot COUVERT équipé en
#     Commun via SaveManager.load_save ; slots placeholders (Ceinture /
#     Bouclier / Talisman, sans contenu) laissés vides — documenté,
#   • stats CTB du héros de partie neuve : le pont existant reflète
#     l'équipement SANS modification (deltas exacts arme/armure/anneau),
#   • sauvegarde EXISTANTE : la dotation ne s'applique JAMAIS (un état
#     sans équipement le reste) ; l'équipement de départ persisté SURVIT
#     au rechargement (l'ancien rattrapage reconcile, qui l'aurait repris
#     biome < Peu Commun, est supprimé).
#
# ⚠ Écrit réellement la sauvegarde (le cycle partie neuve → save → reload
# est l'objet) — protocole : fichiers réels mis de côté puis restaurés.
# ============================================================

const SAUV := "user://IdleEvolutionSave.json"
const META := SaveManager.META_PATH
const FICHIERS: Array[String] = [SAUV, SAUV + ".bak", META, META + ".bak"]

# Slots attendus COUVERTS par la dotation VS (slot_key → equipment_id) et
# slots placeholders attendus VIDES (aucun équipement Commun existant).
const ATTENDU_EQUIPE := {
	"arme":   "equipment_arme",
	"anneau": "equipment_anneau",
	"armure": "equipment_armure",
}
const ATTENDU_VIDE: Array[String] = ["ceinture", "bouclier", "talisman"]

var _results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_proteger()
	_run_all()
	_restaurer()
	_print_report()
	var has_failure: bool = _results.any(func(r): return not r["ok"])
	get_tree().quit(1 if has_failure else 0)

func _run_all() -> void:
	print("\n=== TEST ÉQUIPEMENT DE DÉPART (chantier 13) ===\n")
	_test_config()
	_test_partie_neuve()
	_test_pont_ctb()
	_test_survie_au_rechargement()
	_test_sauvegarde_existante_intacte()

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

# Retire tout l'équipement (état « sans dotation » pour les comparaisons).
func _tout_desequiper() -> void:
	for k: String in GameData.player["equipped"]:
		GameData.player["equipped"][k] = ""

# ─── 1. Config de dotation ──────────────────────────────────

func _test_config() -> void:
	print("[TEST 1] Config : ids existants, Commun, noms non vides, slots uniques")
	var ids: Array = GameData.EQUIPEMENT_DEPART.equipement_ids
	_assert(ids.size() == 3, "3 équipements de départ (les Commun existants du VS)",
			"obtenu %d" % ids.size())
	var slots_vus := {}
	for eid: String in ids:
		var e := GameData.get_entity(eid)
		if e.is_empty():
			_fail("équipement « %s » existant" % eid)
			continue
		_assert(e.get("entity_type", "") == Enums.EntityType.EQUIPMENT
				and str(e.get("nom_affichage_fr", "")) != ""
				and int(e.get("maitrise_actuelle", 0)) == 0,
				"« %s » : équipement réel, nom non vide, rareté Commun (T0)" % eid)
		slots_vus[int(e.get("slot", -1))] = true
	_assert(slots_vus.size() == ids.size(), "un slot DISTINCT par équipement")

# ─── 2. Partie neuve : dotation appliquée par load_save ─────

func _test_partie_neuve() -> void:
	print("\n[TEST 2] Partie neuve (aucun fichier) → slots couverts équipés en Commun")
	_assert(not FileAccess.file_exists(SAUV), "aucune sauvegarde (fichiers protégés)")
	SaveManager.load_save()
	for slot_key: String in ATTENDU_EQUIPE:
		var eid := str(GameData.player["equipped"].get(slot_key, ""))
		_assert(eid == str(ATTENDU_EQUIPE[slot_key]),
				"slot %s → %s" % [slot_key, ATTENDU_EQUIPE[slot_key]], "obtenu « %s »" % eid)
		_assert(bool(GameData.get_entity(str(ATTENDU_EQUIPE[slot_key])).get("est_debloque", false)),
				"%s débloqué" % ATTENDU_EQUIPE[slot_key])
	# Slots sans équipement Commun existant (placeholders sans contenu) :
	# ils restent VIDES — signalé, jamais inventé (règle du chantier).
	for slot_key: String in ATTENDU_VIDE:
		_assert(str(GameData.player["equipped"].get(slot_key, "x")) == "",
				"slot %s vide (placeholder sans équipement Commun — documenté)" % slot_key)

# ─── 3. Pont CTB : les stats du héros incluent la dotation ──

func _test_pont_ctb() -> void:
	print("\n[TEST 3] Pont CTB : stats de partie neuve avec équipement (sans modif du pont)")
	var avec := CtbPont.combattant_depuis_heros()
	_assert(avec != null, "combattant héros construit (précondition)")
	var equips: Dictionary = GameData.player["equipped"].duplicate()
	_tout_desequiper()
	var sans := CtbPont.combattant_depuis_heros()
	GameData.player["equipped"] = equips
	if avec == null or sans == null:
		return
	# Deltas exacts au palier Commun (T0 des .tres) : Lame de Pierre +3 ATK,
	# Carapace des Marais +2 DEF +15 PV, Anneau de Forêt +10 % VIT.
	_assert(is_equal_approx(avec.atk, sans.atk + 3.0), "ATK : +3 (Lame de Pierre T0)",
			"avec %f, sans %f" % [avec.atk, sans.atk])
	_assert(is_equal_approx(avec.def, sans.def + 2.0), "DEF : +2 (Carapace T0)",
			"avec %f, sans %f" % [avec.def, sans.def])
	_assert(is_equal_approx(avec.pv_max, sans.pv_max + 15.0), "PV : +15 (Carapace T0)",
			"avec %f, sans %f" % [avec.pv_max, sans.pv_max])
	_assert(is_equal_approx(avec.vit, sans.vit * 1.10), "VIT : ×1.10 (Anneau T0)",
			"avec %f, sans %f" % [avec.vit, sans.vit])

# ─── 4. La dotation persistée survit au rechargement ────────

func _test_survie_au_rechargement() -> void:
	print("\n[TEST 4] Save + reload : l'équipement de départ n'est PAS repris")
	# Biomes à Commun (T0) : l'ancien rattrapage reconcile aurait DÉSÉQUIPÉ
	# ici (« biome < Peu Commun → équipement repris ») — il est supprimé.
	_assert(int(GameData.get_entity("biome_montagne").get("maitrise_actuelle", 0)) == 0,
			"biome de l'arme à Commun (précondition du piège reconcile)")
	SaveManager.sauvegarder_maintenant()
	_tout_desequiper()
	SaveManager.recharger()
	_assert(str(GameData.player["equipped"].get("arme", "")) == "equipment_arme"
			and str(GameData.player["equipped"].get("armure", "")) == "equipment_armure"
			and str(GameData.player["equipped"].get("anneau", "")) == "equipment_anneau",
			"équipement de départ toujours équipé après save + reload")
	_assert(bool(GameData.get_entity("equipment_arme").get("est_debloque", false)),
			"est_debloque persiste au round-trip")

# ─── 5. Sauvegarde existante : jamais re-dotée ──────────────

func _test_sauvegarde_existante_intacte() -> void:
	print("\n[TEST 5] Sauvegarde existante SANS équipement → reload n'ajoute rien")
	# Simule une partie en cours dépouillée (ex. sauvegarde d'avant-chantier) :
	# tout retiré puis SAUVÉ — l'état du fichier fait foi.
	_tout_desequiper()
	for eid: String in GameData.EQUIPEMENT_DEPART.equipement_ids:
		GameData.get_entity(eid)["est_debloque"] = false
	SaveManager.sauvegarder_maintenant()
	SaveManager.recharger()
	for slot_key: String in ATTENDU_EQUIPE:
		_assert(str(GameData.player["equipped"].get(slot_key, "x")) == "",
				"slot %s reste vide (dotation JAMAIS appliquée à une partie existante)" % slot_key)
	_assert(not bool(GameData.get_entity("equipment_arme").get("est_debloque", true)),
			"est_debloque=false du fichier respecté")

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
