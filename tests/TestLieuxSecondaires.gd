extends Node
# ============================================================
# TestLieuxSecondaires — Lieux secondaires révélés par les voies (ch.17).
#
# Couvre : les 3 entités (Collines / Ville Fantôme / Cimetière) présentes et
# NON découvertes en partie neuve ; les zones du gabarit Excel portent les
# 4 ids distincts (fini les doublons biome_montagne) ; l'ouverture des
# voies 2-4 révèle le bon Lieu dans l'ordre (voie 1 = Atelier, voie 5 =
# rien) ; les Lieutenants d'assaut sont mappés ; le butin (ch.14) et la
# mécanique forte héritée (ch.15) fonctionnent sur un Lieu secondaire ;
# l'affichage des voies annonce le Lieu.
# Quitte avec un code ≠ 0 en cas d'échec (intégrable en CI).
# ============================================================

const LIEUX_SECONDAIRES: Array[String] = [
	"biome_colline", "biome_ville_fantome", "biome_cimetiere",
]

var _fail: Array[String] = []
var _nb_ok := 0

func _ready() -> void:
	# JAMAIS d'écriture de sauvegarde dans un test (règle projet).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	print("\n=== TEST LIEUX SECONDAIRES (chantier 17) ===\n")
	_test_entites()
	_test_zones_gabarit()
	_test_revelation_par_voies()
	_test_destinations()
	_test_butin_et_mecanique()
	_test_affichage_voies()
	_test_panneau_expeditions()
	print("\n════════════════════════════════")
	print("RÉSULTAT : %d OK, %d échec(s)" % [_nb_ok, _fail.size()])
	for f in _fail:
		print("  ✗ " + f)
	print("════════════════════════════════")
	get_tree().quit(0 if _fail.is_empty() else 1)

# ─── 1. Entités ──────────────────────────────────────────────

func _test_entites() -> void:
	print("[1] Entités : présentes, NON découvertes, arbre des branches")
	for id in LIEUX_SECONDAIRES:
		var e := GameData.get_entity(id)
		_check("« %s » existe et a un nom" % id,
				not e.is_empty() and str(e.get("nom_affichage_fr", "")) != "")
		_check("« %s » non découvert en partie neuve" % id,
				not bool(e.get("est_decouvert", true)))
		_check("« %s » a ses ressources de butin" % id,
				str(e.get("ressource_frequente_id", "")) != ""
				and str(e.get("ressource_rare_id", "")) != ""
				and not GameData.get_entity(str(e.get("ressource_frequente_id"))).is_empty()
				and not GameData.get_entity(str(e.get("ressource_rare_id"))).is_empty())
	_check("arbre : Forêt → Collines",
			str(GameData.get_entity("biome_foret").get("biome_secondaire_id", "")) == "biome_colline")
	_check("arbre : Montagne → Ville Fantôme",
			str(GameData.get_entity("biome_montagne").get("biome_secondaire_id", "")) == "biome_ville_fantome")
	_check("arbre : Marécage → Cimetière",
			str(GameData.get_entity("biome_marecage").get("biome_secondaire_id", "")) == "biome_cimetiere")

# ─── 2. Zones du gabarit ─────────────────────────────────────

func _test_zones_gabarit() -> void:
	print("\n[2] Gabarit : 6 zones, 6 ids — plus aucun doublon biome_montagne")
	var m := HoloXlsxMap.new()
	_check("gabarit chargé", m.charger(HoloMap3D.CHEMIN_GABARIT_DEFAUT))
	var ids: Array[String] = []
	for z: Dictionary in m.zones:
		ids.append(str(z["id"]))
	_check("6 zones à ID", ids.size() == 6)
	for id in ["biome_foret", "biome_marecage", "biome_montagne",
			"biome_colline", "biome_ville_fantome", "biome_cimetiere"]:
		_check("zone « %s » : exactement une" % id, ids.count(id) == 1)
	# Chaque id de zone correspond à une entité réelle (règle : ne pas inventer).
	for id in ids:
		_check("zone « %s » → entité réelle" % id, not GameData.get_entity(id).is_empty())

# ─── 3. Révélation par les voies ─────────────────────────────

func _test_revelation_par_voies() -> void:
	print("\n[3] Voies : 2 → Collines, 3 → Ville Fantôme, 4 → Cimetière, 5 → rien")
	# 5 Sceaux (5 Lieutenants distincts détruits) pour ouvrir 5 voies.
	for lieu in ["biome_foret", "biome_marecage", "biome_montagne",
			"biome_colline", "biome_ville_fantome"]:
		GameData.marquer_lieutenant_vaincu(lieu)
	_check("5 Sceaux possédés", GameData.nb_sceaux() == 5)

	_check("voie 1 ouverte (Atelier)", GameData.ouvrir_voie_suivante()
			and GameData.atelier_ouvert())
	_check("voie 1 : aucun Lieu révélé",
			not bool(GameData.get_entity("biome_colline").get("est_decouvert", false)))
	_check("voie 2 → Collines révélées", GameData.ouvrir_voie_suivante()
			and bool(GameData.get_entity("biome_colline").get("est_decouvert", false)))
	_check("voie 2 : Ville Fantôme toujours cachée",
			not bool(GameData.get_entity("biome_ville_fantome").get("est_decouvert", false)))
	_check("voie 3 → Ville Fantôme révélée", GameData.ouvrir_voie_suivante()
			and bool(GameData.get_entity("biome_ville_fantome").get("est_decouvert", false)))
	_check("voie 4 → Cimetière révélé", GameData.ouvrir_voie_suivante()
			and bool(GameData.get_entity("biome_cimetiere").get("est_decouvert", false)))
	var decouverts_avant := _nb_lieux_decouverts()
	_check("voie 5 ouverte (placeholder)", GameData.ouvrir_voie_suivante())
	_check("voie 5 : rien de plus révélé", _nb_lieux_decouverts() == decouverts_avant)

func _nb_lieux_decouverts() -> int:
	var n := 0
	for id in LIEUX_SECONDAIRES:
		if bool(GameData.get_entity(id).get("est_decouvert", false)):
			n += 1
	return n

# ─── 4. Destinations (assauts) ───────────────────────────────

func _test_destinations() -> void:
	print("\n[4] Destinations : Lieutenant mappé pour chaque Lieu secondaire")
	var dest: ExpeDestinationsData = load("res://data/expedition/destinations.tres")
	for id in LIEUX_SECONDAIRES:
		_check("lieutenant de « %s »" % id, dest.lieutenant_pour(id) != null)
		_check("pool de « %s » (défaut accepté)" % id, dest.pool_pour(id) != null)

# ─── 5. Butin (ch.14) + mécanique héritée (ch.15) ────────────

func _test_butin_et_mecanique() -> void:
	print("\n[5] Un Lieu secondaire droppe SES ressources et hérite de la mécanique")
	var run := _run("biome_colline", "palier_enceinte")
	var res := run._ressources_du_lieu()
	_check("Collines : fréquente = dent de gobelin", res["freq"] == "res_dent_gobelin")
	_check("Collines : rare = défense de sanglier", res["rare"] == "res_defense_sanglier")
	_check("Collines : mécanique héritée de la Forêt (ambush)",
			run.mecanique_active() == "ambush")
	var run2 := _run("biome_cimetiere", "palier_noyau")
	_check("Cimetière : mécanique héritée du Marécage (poison)",
			run2.mecanique_active() == "poison")
	_check("Cimetière : rare = relique funéraire (ingrédient de Forge)",
			run2._ressources_du_lieu()["rare"] == "res_relique_funeraire")
	var run3 := _run("biome_ville_fantome", "palier_peripherie")
	_check("Ville Fantôme @ Périphérie : mécanique inactive (gate ch.15)",
			run3.mecanique_active() == "")

# ─── 6. Affichage des voies ──────────────────────────────────

func _test_affichage_voies() -> void:
	print("\n[6] VoiesPanel : la voie annonce le Lieu qu'elle ouvre")
	_check("voie 2 nommée d'après les Collines",
			VoiesPanel._nom_voie(2).contains(Translations.entity_name(
					GameData.get_entity("biome_colline"), "biome_colline")))
	_check("voie 5 reste générique",
			VoiesPanel._nom_voie(5) == Translations.T("voies.nom_generique"))
	_check("voie 1 reste l'Atelier",
			VoiesPanel._nom_voie(1) == Translations.T("voies.nom_atelier"))

# ─── 7. Panneau Expéditions avec un Lieu secondaire découvert ──

# Régression : un biome SANS créature propre (clé présente, valeur null)
# faisait crasher AdventurePanel.build via get_biome_entity_pools — le
# panneau s'arrêtait avant les biomes suivants.
func _test_panneau_expeditions() -> void:
	print("\n[7] Panneau Expéditions : un Lieu secondaire découvert ne casse rien")
	var pools := MasteryRegistry.get_biome_entity_pools("biome_colline")
	_check("pools d'un Lieu sans créature : vides, sans erreur",
			(pools["creatures"] as Array).is_empty()
			and (pools["traps"] as Array).is_empty())
	var v := Village.new()
	v.rp_content = VBoxContainer.new()
	AdventurePanel.build(v)
	# Une carte de biome = un SelectionGlow (liseré de sélection) : le panneau
	# doit en porter UNE PAR BIOME DÉCOUVERT (3 VS + 3 secondaires révélés
	# au test [3]) — le build n'a pas avorté en chemin.
	var nb_decouverts := 0
	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") == Enums.EntityType.BIOME \
				and bool(e.get("est_decouvert", false)):
			nb_decouverts += 1
	_check("6 biomes découverts à ce stade", nb_decouverts == 6)
	_check("une carte par biome découvert (build complet, sans crash)",
			_compter_glows(v.rp_content) == nb_decouverts)
	v.rp_content.free()
	v.free()

func _compter_glows(racine: Node) -> int:
	var n := 1 if racine is SelectionGlow else 0
	for c in racine.get_children():
		n += _compter_glows(c)
	return n

# ─── Helpers ─────────────────────────────────────────────────

func _run(lieu: String, palier_id: String) -> ExpeRun:
	var cfg := ExpeCarteConfigData.new()
	var cc := ExpeCombatConfigData.new()
	var a := CombattantCtbData.new()
	a.id = "avatar_test"
	a.nom_affichage_fr = "Avatar de test"
	a.pv_max = 1000.0
	a.atk = 100.0
	a.vit = 10.0
	var r := ExpeRun.new(cfg, load("res://data/expedition/%s.tres" % palier_id),
			lieu, 17, a, load("res://data/expedition/pool_defaut.tres"), cc)
	r.demarrer()
	return r

func _check(nom: String, ok: bool) -> void:
	if ok:
		_nb_ok += 1
		print("  ✓ " + nom)
	else:
		_fail.append(nom)
		print("  ✗ " + nom)
