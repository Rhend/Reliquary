# ============================================================
# ExpeRun — Déroulé d'UNE expédition sur carte de nœuds (Rework Combat,
# chantiers 2-3-6-7) : navigation free-roam, brouillard de guerre,
# enchaînement des étages, extraction, COMBATS CTB RÉELS sur les nœuds
# Combat et Attaque surprise, et depuis le chantier 7 résolution RÉELLE de
# TOUS les nœuds (fin des stubs) :
#   • Bénédiction (« ? ») = AFFIXE POSITIF de run ; Piège (« ? ») = AFFIXE
#     NÉGATIF (définitions actées 06/07/2026). Un affixe = bonus % de stats,
#     actif de l'acquisition à la FIN de la run (purge systématique, toutes
#     sorties). Application : ajouté au Σ bonus % du combattant JOUEUR à
#     chaque CRÉATION de combat (déjà recréé à chaque nœud → un affixe
#     acquis en cours de run compte dès le combat suivant). Cumul additif,
#     y compris deux fois le même affixe. PV max modifié en cours de run :
#     PV courants conservés en ABSOLU, clampés si le pv_max effectif descend.
#   • Coffre (nœud direct ou « ? ») = 1-2 CONSOMMABLES de run (inventaire
#     perdu en fin de run, extraction comprise ; cap config, 0 = illimité).
#     Usage EN COMBAT uniquement : action OBJET du moteur — l'inventaire vit
#     ICI (consommer()), le moteur reste agnostique.
# Pools/pondérations : cfg_noeuds (config_noeuds.tres par défaut,
# remplaçable AVANT demarrer() — tests).
#
# Une expédition = 1 Lieu + 1 palier de profondeur (PalierProfondeurData,
# multiplicateur qui CIRCULE dans les signaux SANS effet réel — son mécanisme
# d'effet n'est pas décidé) + 1 avatar (CombattantCtbData) + 1 pool d'ennemis
# (PoolEnnemisData → bestiaire via CtbPont) + 1 config de combat
# (ExpeCombatConfigData : pondération du nombre d'ennemis, malus d'embuscade).
#
# Combat (chantier 3) : entrer sur un nœud Combat — ou un « ? » qui révèle
# une Attaque surprise — SUSPEND la run : `combat_en_cours` porte le CtbMoteur
# démarré (embuscade = première horloge du camp joueur × malus), tout
# déplacement est refusé tant qu'il n'est pas résolu. Le combat est PULL-BASED
# (l'appelant le déroule : derouler_auto() ou activation par activation) ;
# victoire → le nœud est résolu (payload enrichi d'un dict "combat") et la
# run reprend ; défaite → fin d'expédition immédiate (recap defaite=true).
# PV PERSISTANTS entre les nœuds (pv_avatar, pleins au lancement — provisoire,
# aucune régénération) ; statuts purgés en fin de combat (moteur).
#
# Récompenses (chantier 6) : à chaque VICTOIRE de combat, l'XP de niveau du
# héros (xp_reward du bestiaire au palier de Maîtrise courant de la créature,
# lu tel quel) est créditée IMMÉDIATEMENT (ProgressionHeros — la montée de
# niveau en cours de run est voulue ; elle compte au prochain combat, jamais
# à chaud) et l'Euren (base × multiplicateur du palier de la créature,
# data/progression/euren.tres) est ACCUMULÉ dans la run. L'Euren n'est
# crédité qu'à la SORTIE (extraction ou complétion) ; défaite = rien.
# Le multiplicateur de PalierProfondeurData continue de circuler SANS effet
# (mécanisme non décidé) — il ne s'applique pas aux récompenses.
#
# Brouillard : Entrée + Fin d'étage découvertes d'emblée (la Fin avec son
# type — le joueur peut foncer dessus) ; tout autre nœud est ABSENT tant
# qu'un voisin direct n'a pas été visité (révélation par adjacence). Le
# contenu d'un nœud « ? » est tiré à l'ENTRÉE seulement.
#
# Fin d'étage : la PREMIÈRE arrivée résout le nœud (signal etage_termine) ;
# être SUR le nœud ouvre le choix Extraire / Continuer (choix_ouvert) — le
# joueur peut repartir explorer puis revenir, le choix se rouvre (le nœud
# reste inerte : pas de re-résolution). Au dernier étage : fin d'expédition
# immédiate. Signaux : locaux + EventBus (expe_noeud_resolu /
# expe_etage_termine / expe_terminee) ; combat_demarre est local (les fins
# de combat passent déjà par EventBus.ctb_victoire / ctb_defaite).
# ============================================================
class_name ExpeRun
extends RefCounted

# Config Euren globale (pas un paramètre d'expédition — monnaie commune).
const CONFIG_EUREN: EurenConfigData = preload("res://data/progression/euren.tres")
# Contenu des nœuds Bénédiction/Piège/Coffre (chantier 7) — défaut versionné.
const CONFIG_NOEUDS_DEFAUT: ExpeNoeudsConfigData = \
		preload("res://data/expedition/config_noeuds.tres")

signal noeud_resolu(data: Dictionary)
signal etage_termine(data: Dictionary)
signal terminee(recap: Dictionary)
signal combat_demarre(moteur: CtbMoteur, data: Dictionary)

var config: ExpeCarteConfigData
var palier: PalierProfondeurData
var lieu_id := ""
var avatar_data: CombattantCtbData
var pool: PoolEnnemisData
var cfg_combat: ExpeCombatConfigData

var rng := RandomNumberGenerator.new()   # seedable → run reproductible
var etage := 1
var carte: ExpeCarte
var position_joueur := 0
var choix_ouvert := false                # sur la Fin d'étage : Extraire / Continuer
var est_terminee := false
var journal: PackedStringArray = []

# État de combat (chantier 3).
var combat_en_cours: CtbMoteur = null    # non-null = run suspendue sur un nœud
var pv_avatar := 0.0                     # PV persistants entre les nœuds
var defaite := false
var nb_combats := 0

# Récompenses (chantier 6).
var xp_gagnee := 0.0                     # XP de niveau créditée pendant la run (info)
var euren_accumule := 0.0                # Euren de la run (visible, non crédité)
var euren_credite := 0.0                 # Euren réellement crédité à la sortie
var dernier_combat_recompenses: Dictionary = {}   # {xp, euren} du dernier combat gagné

# Nœuds réels (chantier 7) — remplaçable AVANT demarrer() (tests).
var cfg_noeuds: ExpeNoeudsConfigData = CONFIG_NOEUDS_DEFAUT
var affixes: Array[AffixeData] = []              # actifs jusqu'à la fin de la run
var inventaire: Array[ConsommableData] = []      # consommables de run
var _conso_obtenus: Array[ConsommableData] = []  # cumul pour le recap
var _conso_utilises: Array[ConsommableData] = [] # cumul pour le recap

# Compteurs pour le recap : type de nœud (int) → nb résolus, + contenus de « ? ».
var _resolus_par_type: Dictionary = {}
var _mysteres_par_contenu: Dictionary = {}
var _vaincus_cumul: Array[CombattantCtbData] = []

func _init(cfg: ExpeCarteConfigData, p: PalierProfondeurData, lieu: String, graine: int,
		avatar: CombattantCtbData, pool_ennemis: PoolEnnemisData,
		combat_cfg: ExpeCombatConfigData) -> void:
	config = cfg
	palier = p
	lieu_id = lieu
	avatar_data = avatar
	pool = pool_ennemis
	cfg_combat = combat_cfg
	if graine != 0:
		rng.seed = graine

# ─── Cycle de vie ────────────────────────────────────────────

func demarrer() -> void:
	assert(avatar_data != null, "avatar requis (CombattantCtbData)")
	assert(pool != null and not pool.creature_ids.is_empty(), "pool d'ennemis requis")
	assert(cfg_combat != null, "config de combat requise")
	# PV pleins au lancement — provisoire : la gestion hors expédition n'existe pas.
	pv_avatar = avatar_data.pv_max
	_log("═ Expédition : %s — palier %s (×%.1f), %d étages" % [
			lieu_id, palier.nom_journal(), palier.multiplicateur, config.nb_etages])
	_log("  ✦ %s — PV %d, ATK %d, DEF %d, VIT %d, crit %.0f %% ×%.2f" % [
			avatar_data.nom_journal(), int(roundf(avatar_data.pv_max)),
			int(roundf(avatar_data.atk)), int(roundf(avatar_data.def)),
			int(roundf(avatar_data.vit)), avatar_data.crit_chance * 100.0,
			avatar_data.crit_multiplier])
	_nouvel_etage()

# Choix « Continuer » (sur la Fin d'étage, hors dernier étage).
func continuer() -> void:
	if not choix_ouvert or est_terminee:
		return
	choix_ouvert = false
	etage += 1
	_log("▼ Continuer : descente vers l'étage %d" % etage)
	_nouvel_etage()

# Choix « Extraire » (sur la Fin d'étage) : fin d'expédition volontaire.
func extraire() -> void:
	if not choix_ouvert or est_terminee:
		return
	_log("▲ Extraction à l'étage %d" % etage)
	_terminer(true)

# ─── Navigation ──────────────────────────────────────────────

# Déplacement d'UN nœud le long d'une arête (retour en arrière autorisé).
# Refuse : expédition finie, COMBAT EN COURS, nœud non adjacent. Retourne
# true si le pas a eu lieu — un combat peut alors être en attente
# (combat_en_cours != null) : le résoudre avant tout autre déplacement.
func deplacer_vers(nid: int) -> bool:
	if est_terminee or combat_en_cours != null \
			or not nid in carte.noeud(position_joueur).voisins:
		return false
	choix_ouvert = false
	position_joueur = nid
	var nd := carte.noeud(nid)
	_log("→ Déplacement vers le nœud %d (%s)" % [nid, _nom_type(nd)])
	_reveler_voisins(nid)
	if not nd.resolu:
		_resoudre(nd)
	elif nd.type == Enums.TypeNoeud.FIN_ETAGE:
		# Nœud inerte (pas de re-résolution), mais être dessus rouvre le choix.
		choix_ouvert = true
		_log("  ◇ Fin d'étage : choix Extraire / Continuer rouvert")
	return true

# Nœuds actuellement AFFICHABLES (les autres n'existent pas à l'écran).
func noeuds_visibles() -> Array[ExpeNoeud]:
	var out: Array[ExpeNoeud] = []
	for nd in carte.noeuds:
		if nd.decouvert:
			out.append(nd)
	return out

# Nombre d'ennemis du prochain combat — tirage pondéré data-driven
# (cfg_combat.poids_nb_ennemis). Public pour le test statistique.
func tirer_nb_ennemis() -> int:
	var total := 0.0
	for n in cfg_combat.poids_nb_ennemis:
		total += float(cfg_combat.poids_nb_ennemis[n])
	var roll := rng.randf() * maxf(total, 0.0001)
	var cumul := 0.0
	for n in cfg_combat.poids_nb_ennemis:
		cumul += float(cfg_combat.poids_nb_ennemis[n])
		if roll < cumul:
			return int(n)
	return 1

# ─── Internes ────────────────────────────────────────────────

func _nouvel_etage() -> void:
	carte = ExpeCarte.generer(config, rng)
	position_joueur = carte.entree_id
	var entree := carte.noeud(carte.entree_id)
	entree.decouvert = true
	entree.resolu = true          # nœud neutre : jamais déclenché
	# Fin d'étage VISIBLE d'emblée (position et type) — foncer dessus est permis.
	carte.noeud(carte.fin_id).decouvert = true
	_log("─ Étage %d : %d nœuds, entrée %d, fin %d (visible)" % [
			etage, carte.noeuds.size(), carte.entree_id, carte.fin_id])
	_reveler_voisins(carte.entree_id)

# Révélation par adjacence : les voisins directs du nœud visité apparaissent
# avec leur type affiché (« ? » pour un Mystère — contenu tiré à l'entrée).
func _reveler_voisins(nid: int) -> void:
	for v in carte.noeud(nid).voisins:
		var nd := carte.noeud(v)
		if not nd.decouvert:
			nd.decouvert = true
			_log("  ✦ Révélé : nœud %d (%s)" % [v, _nom_type(nd)])

# Résolution d'un nœud non résolu : Combat et Attaque surprise (contenu du
# « ? ») lancent un combat CTB réel — le nœud n'est résolu qu'à la VICTOIRE.
# Bénédiction / Piège / Coffre : résolution RÉELLE (chantier 7).
func _resoudre(nd: ExpeNoeud) -> void:
	if nd.type == Enums.TypeNoeud.MYSTERE and nd.contenu_mystere < 0:
		nd.contenu_mystere = _tirer_mystere()
		_log("  ？ Le mystère se révèle : %s" % _nom_mystere(nd.contenu_mystere))
	if nd.type == Enums.TypeNoeud.COMBAT:
		_lancer_combat(nd, false)
		return
	if nd.type == Enums.TypeNoeud.MYSTERE \
			and nd.contenu_mystere == Enums.ContenuMystere.ATTAQUE_SURPRISE:
		_lancer_combat(nd, true)
		return
	if nd.type == Enums.TypeNoeud.COFFRE \
			or nd.contenu_mystere == Enums.ContenuMystere.COFFRE:
		_resoudre_coffre(nd)
		return
	if nd.contenu_mystere == Enums.ContenuMystere.BENEDICTION:
		_resoudre_affixe(nd, true)
		return
	if nd.contenu_mystere == Enums.ContenuMystere.PIEGE:
		_resoudre_affixe(nd, false)
		return
	_finaliser_noeud(nd)

# Marquage résolu + compteurs + signal typé (local + EventBus). `extra`
# enrichit le payload : "combat" (recap du combat gagné) ou "contenu"
# (affixe obtenu / consommables du coffre — chantier 7).
func _finaliser_noeud(nd: ExpeNoeud, extra: Dictionary = {}) -> void:
	nd.resolu = true
	var data := {
		"type":            nd.type,
		"contenu_mystere": nd.contenu_mystere,
		"lieu_id":         lieu_id,
		"palier_id":       palier.id,
		"multiplicateur":  palier.multiplicateur,
		"etage":           etage,
		"noeud_id":        nd.id,
	}
	data.merge(extra)
	_resolus_par_type[nd.type] = int(_resolus_par_type.get(nd.type, 0)) + 1
	if nd.contenu_mystere >= 0:
		_mysteres_par_contenu[nd.contenu_mystere] = \
				int(_mysteres_par_contenu.get(nd.contenu_mystere, 0)) + 1
	_log("  ▣ Résolu : %s%s (étage %d, ×%.1f)" % [
			_nom_type(nd),
			"" if nd.contenu_mystere < 0 else " → " + _nom_mystere(nd.contenu_mystere),
			etage, palier.multiplicateur])
	noeud_resolu.emit(data)
	EventBus.expe_noeud_resolu.emit(data)
	if nd.type == Enums.TypeNoeud.FIN_ETAGE:
		var fin_data := {"etage": etage, "lieu_id": lieu_id, "palier_id": palier.id}
		etage_termine.emit(fin_data)
		EventBus.expe_etage_termine.emit(fin_data)
		if etage >= config.nb_etages:
			_log("  ◆ Fin d'étage %d (dernier) : fin d'expédition" % etage)
			_terminer(false)
		else:
			choix_ouvert = true
			_log("  ◇ Fin d'étage %d : choix Extraire / Continuer" % etage)

# ─── Combat CTB (chantier 3) ─────────────────────────────────

# Monte et démarre le combat du nœud : avatar (PV persistants réinjectés) vs
# 1-3 ennemis tirés du pool (uniforme avec remise, stats du bestiaire via
# CtbPont). Embuscade : première horloge du camp joueur × malus (.tres).
# La run reste SUSPENDUE tant que l'appelant n'a pas déroulé le moteur.
func _lancer_combat(nd: ExpeNoeud, embuscade: bool) -> void:
	var m := CtbMoteur.new()
	m.rng.seed = rng.randi()   # crits reproductibles dans une run seedée
	var av := m.ajouter(avatar_data, Enums.CampCtb.JOUEUR)
	# Affixes de run (chantier 7) : ajoutés au Σ bonus % du combattant joueur
	# à CHAQUE création de combat (cumul additif, doublons compris).
	for a in affixes:
		for stat: String in a.bonus:
			av.ajouter_bonus_pct(stat, float(a.bonus[stat]))
	# PV persistants — aucune régénération ; clamp au pv_max effectif (affixes).
	av.pv = minf(pv_avatar, av.stat_finale("pv_max"))
	if embuscade:
		m.malus_horloge_initiale_joueur = cfg_combat.malus_horloge_embuscade
	var nb := tirer_nb_ennemis()
	var noms: PackedStringArray = []
	for i in nb:
		var cid: String = pool.creature_ids[rng.randi_range(0, pool.creature_ids.size() - 1)]
		var dc := CtbPont.combattant_depuis_entite(cid)
		if dc == null:
			continue
		m.ajouter(dc, Enums.CampCtb.ADVERSE)
		noms.append(dc.nom_journal())
	_log("⚔ %s au nœud %d : %d ennemi(s) — %s" % [
			"ATTAQUE SURPRISE" if embuscade else "Combat", nd.id, noms.size(),
			", ".join(noms)])
	combat_en_cours = m
	# ⚠ Ne PAS capturer `m` ici : une lambda qui référence le moteur dans son
	# propre signal crée un cycle RefCounted jamais libéré (la connexion du
	# signal qui ne tire pas reste vivante) — _fin_combat lit combat_en_cours.
	m.victoire.connect(func(r: Dictionary) -> void: _fin_combat(r, nd, embuscade),
			CONNECT_ONE_SHOT)
	m.defaite.connect(func(r: Dictionary) -> void: _fin_combat(r, nd, embuscade),
			CONNECT_ONE_SHOT)
	m.demarrer()
	combat_demarre.emit(m, {"noeud_id": nd.id, "etage": etage, "embuscade": embuscade,
			"lieu_id": lieu_id, "palier_id": palier.id,
			"multiplicateur": palier.multiplicateur})

# Fin du combat du nœud : PV sortants mémorisés, vaincus cumulés pour le
# recap. Victoire → le nœud est résolu, la run reprend ; défaite → fin
# d'expédition immédiate (sanction hors scope, seul le signal existe).
func _fin_combat(recap: Dictionary, nd: ExpeNoeud, embuscade: bool) -> void:
	for ligne in combat_en_cours.journal:
		_log("  │ " + ligne)
	nb_combats += 1
	for d: CombattantCtbData in recap["ennemis_vaincus"]:
		_vaincus_cumul.append(d)
	pv_avatar = float(recap["pv_restants"].get(avatar_data.id, 0.0))
	combat_en_cours = null
	if not bool(recap["victoire"]):
		# Défaite : AUCUNE récompense, même pour les ennemis tués dans ce
		# combat (l'XP n'est créditée qu'à la VICTOIRE — arbitrage 06/07).
		dernier_combat_recompenses = {}
		defaite = true
		_log("☠ Défaite au nœud %d — fin d'expédition immédiate" % nd.id)
		_terminer(false)
		return
	_log("✔ Victoire au nœud %d — PV Avatar : %d" % [nd.id, int(roundf(pv_avatar))])
	_crediter_victoire(recap["ennemis_vaincus"])
	_finaliser_noeud(nd, {"combat": {
		"embuscade":       embuscade,
		"nb_activations":  recap["nb_activations"],
		"ennemis_vaincus": recap["ennemis_vaincus"],
	}})

# ─── Nœuds réels : affixes & consommables (chantier 7) ───────

# Bénédiction (positif=true) / Piège : tire un affixe du pool au rng de la
# run, l'active jusqu'à la fin de l'expédition, annonce (journal + payload
# "contenu" pour la popup placeholder de l'appelant).
func _resoudre_affixe(nd: ExpeNoeud, positif: bool) -> void:
	var pool: Array[AffixeData] = cfg_noeuds.affixes_positifs if positif \
			else cfg_noeuds.affixes_negatifs
	if pool.is_empty():
		_log("  ⚠ Pool d'affixes %s vide — nœud sans effet" % ("positif" if positif else "négatif"))
		_finaliser_noeud(nd)
		return
	var affixe: AffixeData = pool[rng.randi_range(0, pool.size() - 1)]
	ajouter_affixe(affixe)
	_log("  %s %s : %s (%s) — jusqu'à la fin de l'expédition" % [
			"✨ Bénédiction" if positif else "☒ Piège subi",
			"obtenue" if positif else "",
			affixe.nom_journal(), affixe.resume()])
	_finaliser_noeud(nd, {"contenu": {"affixe_id": affixe.id, "positif": positif,
			"resume": affixe.resume()}})

# Active un affixe (cumul additif, doublons permis). PV max modifié en cours
# de run : PV courants conservés en ABSOLU, clampés si le pv_max effectif
# descend (règle actée ch.7 — sans trancher le point ouvert des niveaux).
func ajouter_affixe(affixe: AffixeData) -> void:
	affixes.append(affixe)
	var max_effectif := pv_max_effectif()
	if pv_avatar > max_effectif:
		_log("  ▾ PV clampés au nouveau PV max : %d → %d" % [
				int(roundf(pv_avatar)), int(roundf(max_effectif))])
		pv_avatar = max_effectif

# PV max EFFECTIF du combattant joueur : base du transitoire × (1 + Σ affixes
# pv_max) — même empilement additif que le combat (StatStacker).
func pv_max_effectif() -> float:
	var fractions: Array = []
	for a in affixes:
		if a.bonus.has("pv_max"):
			fractions.append(float(a.bonus["pv_max"]))
	return StatStacker.final_stat(avatar_data.pv_max, fractions, "pv_max")

# Coffre (nœud direct ou « ? ») : 1-2 consommables (pondération config) dans
# l'inventaire de run. Cap config (0 = illimité) : l'excédent est PERDU.
func _resoudre_coffre(nd: ExpeNoeud) -> void:
	var obtenus: Array[ConsommableData] = []
	var perdus := 0
	if not cfg_noeuds.pool_consommables.is_empty():
		for i in _tirer_nb_consommables():
			var c: ConsommableData = cfg_noeuds.pool_consommables[
					rng.randi_range(0, cfg_noeuds.pool_consommables.size() - 1)]
			if cfg_noeuds.cap_inventaire > 0 \
					and inventaire.size() >= cfg_noeuds.cap_inventaire:
				perdus += 1
				continue
			inventaire.append(c)
			_conso_obtenus.append(c)
			obtenus.append(c)
	var noms: PackedStringArray = []
	for c in obtenus:
		noms.append(c.nom_journal())
	_log("  🧰 Coffre : %s%s (inventaire : %d)" % [
			", ".join(noms) if not noms.is_empty() else "vide",
			" — %d perdu(s), inventaire plein" % perdus if perdus > 0 else "",
			inventaire.size()])
	var ids: Array[String] = []
	for c in obtenus:
		ids.append(c.id)
	_finaliser_noeud(nd, {"contenu": {"consommable_ids": ids}})

# Nombre de consommables d'un Coffre — tirage pondéré data-driven.
func _tirer_nb_consommables() -> int:
	var total := 0.0
	for n in cfg_noeuds.poids_nb_consommables:
		total += float(cfg_noeuds.poids_nb_consommables[n])
	var roll := rng.randf() * maxf(total, 0.0001)
	var cumul := 0.0
	for n in cfg_noeuds.poids_nb_consommables:
		cumul += float(cfg_noeuds.poids_nb_consommables[n])
		if roll < cumul:
			return int(n)
	return 1

# Retire un consommable de l'inventaire de run (appelé PAR L'UI au moment de
# jouer l'action OBJET — le moteur reste agnostique). false si absent.
func consommer(objet: ConsommableData) -> bool:
	var idx := inventaire.find(objet)
	if idx < 0:
		return false
	inventaire.remove_at(idx)
	_conso_utilises.append(objet)
	_log("  🧪 %s utilisé (inventaire : %d)" % [objet.nom_journal(), inventaire.size()])
	return true

# ─── Récompenses (chantier 6) ────────────────────────────────

# Récompenses d'une victoire : XP de niveau créditée IMMÉDIATEMENT (montée
# de niveau possible en cours de run, journalisée « Niveau x → y »), Euren
# accumulé (crédité à la sortie seulement). Un combattant hors bestiaire
# (ex. avatar de test côté adverse) ne rapporte rien.
func _crediter_victoire(vaincus: Array) -> void:
	var rec := _recompenses_pour(vaincus)
	dernier_combat_recompenses = rec
	if rec["xp"] > 0.0:
		xp_gagnee += float(rec["xp"])
		var niveaux: Dictionary = ProgressionHeros.gagner_xp(float(rec["xp"]))
		_log("  ✧ +%d XP (héros : %d / %d)" % [int(roundf(rec["xp"])),
				int(roundf(ProgressionHeros.xp_totale())),
				int(roundf(ProgressionHeros.seuil_prochain_niveau()))])
		if int(niveaux["apres"]) > int(niveaux["avant"]):
			_log("  ⭐ Niveau %d → %d (compte au prochain combat)" % [
					niveaux["avant"], niveaux["apres"]])
	if rec["euren"] > 0.0:
		euren_accumule += float(rec["euren"])
		_log("  ◈ +%d Euren (run : %d — crédité à la sortie)" % [
				int(roundf(rec["euren"])), int(roundf(euren_accumule))])

# {xp, euren} pour une liste de vaincus (CombattantCtbData). xp_reward est lu
# TEL QUEL au palier de Maîtrise courant de la créature (bestiaire,
# stats_par_palier) ; l'Euren vient de la config (base × mult. de palier) —
# aucun champ Euren au bestiaire (il sera remplacé).
func _recompenses_pour(vaincus: Array) -> Dictionary:
	var xp := 0.0
	var euren := 0.0
	for d: CombattantCtbData in vaincus:
		var entity: Dictionary = GameData.get_entity(d.id)
		if entity.is_empty():
			continue   # hors bestiaire (combattant de test) → rien
		var tier := int(entity.get("maitrise_actuelle", 0))
		xp += float(GameData.stats_at_tier(entity, tier).get("xp_reward", 0.0))
		euren += CONFIG_EUREN.gain_pour_palier(tier)
	return {"xp": xp, "euren": euren}

func _tirer_mystere() -> int:
	var poids := [
		[Enums.ContenuMystere.COFFRE,           config.mystere_poids_coffre],
		[Enums.ContenuMystere.BENEDICTION,      config.mystere_poids_benediction],
		[Enums.ContenuMystere.PIEGE,            config.mystere_poids_piege],
		[Enums.ContenuMystere.ATTAQUE_SURPRISE, config.mystere_poids_attaque_surprise],
	]
	var total := 0.0
	for p: Array in poids:
		total += float(p[1])
	var roll := rng.randf() * maxf(total, 0.0001)
	var cumul := 0.0
	for p: Array in poids:
		cumul += float(p[1])
		if roll < cumul:
			return p[0]
	return Enums.ContenuMystere.COFFRE

func _terminer(extraction: bool) -> void:
	est_terminee = true
	choix_ouvert = false
	# Euren crédité à la SORTIE uniquement : extraction OU complétion.
	# Défaite = rien (comportement correct dès maintenant, même si le futur
	# Game Over/rechargement rendra le point discutable).
	if not defaite and euren_accumule > 0.0:
		euren_credite = euren_accumule
		ProgressionHeros.crediter_euren(euren_credite)
		_log("◈ Euren crédité : %d (total : %d)" % [
				int(roundf(euren_credite)), int(roundf(ProgressionHeros.euren()))])
	var recap := _recap(extraction)
	# Purge systématique (chantier 7) : affixes ET consommables sont « de
	# run » — rien ne persiste, quelle que soit la sortie (le recap garde
	# leurs ids à titre d'information).
	if not affixes.is_empty() or not inventaire.is_empty():
		_log("✦ Purge de fin de run : %d affixe(s), %d consommable(s) perdus" % [
				affixes.size(), inventaire.size()])
	affixes.clear()
	inventaire.clear()
	var issue := "EXTRACTION" if extraction else \
			("DÉFAITE" if defaite else "EXPÉDITION BOUCLÉE")
	_log("═ %s — recap : %s" % [issue, str(recap)])
	terminee.emit(recap)
	EventBus.expe_terminee.emit(recap)

# Recap de fin d'expédition. Le loot/XP réels viendront des chantiers de
# résolution ; les combats y sont agrégés (ennemis_vaincus, nb_combats).
func _recap(extraction: bool) -> Dictionary:
	return {
		"lieu_id":              lieu_id,
		"palier_id":            palier.id,
		"multiplicateur":       palier.multiplicateur,
		"extraction":           extraction,                      # true = sortie volontaire
		"complete":             not extraction and not defaite,  # dernier étage bouclé
		"defaite":              defaite,                         # PV Avatar à 0 en combat
		"etage_atteint":        etage,
		"noeuds_resolus":       _resolus_par_type.duplicate(),   # TypeNoeud → nb
		"mysteres_resolus":     _mysteres_par_contenu.duplicate(),  # ContenuMystere → nb
		"nb_combats":           nb_combats,                      # défaite comprise
		"ennemis_vaincus":      _vaincus_cumul.duplicate(),      # CombattantCtbData cumulés
		# Récompenses (chantier 6) :
		"xp_gagnee":            xp_gagnee,       # XP de niveau créditée pendant la run (info)
		"euren_gagne":          euren_accumule,  # Euren accumulé dans la run
		"euren_credite":        euren_credite,   # réellement crédité (0 si défaite)
		# Nœuds réels (chantier 7) — ids, à titre d'information (tout est purgé) :
		"affixes":              affixes.map(func(a: AffixeData) -> String: return a.id),
		"consommables_obtenus": _conso_obtenus.map(
				func(c: ConsommableData) -> String: return c.id),
		"consommables_utilises": _conso_utilises.map(
				func(c: ConsommableData) -> String: return c.id),
	}

func _nom_type(nd: ExpeNoeud) -> String:
	match nd.type:
		Enums.TypeNoeud.ENTREE:    return "Entrée"
		Enums.TypeNoeud.COMBAT:    return "Combat"
		Enums.TypeNoeud.MYSTERE:   return "?"
		Enums.TypeNoeud.COFFRE:    return "Coffre"
		Enums.TypeNoeud.FIN_ETAGE: return "Fin d'étage"
	return "Inconnu"

func _nom_mystere(c: int) -> String:
	match c:
		Enums.ContenuMystere.COFFRE:           return "Coffre"
		Enums.ContenuMystere.BENEDICTION:      return "Bénédiction"
		Enums.ContenuMystere.PIEGE:            return "Piège"
		Enums.ContenuMystere.ATTAQUE_SURPRISE: return "Attaque surprise"
	return "Inconnu"

func _log(ligne: String) -> void:
	journal.append(ligne)
