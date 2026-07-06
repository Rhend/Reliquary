# ============================================================
# ExpeRun — Déroulé d'UNE expédition sur carte de nœuds (Rework Combat,
# chantiers 2-3) : navigation free-roam, brouillard de guerre, enchaînement
# des étages, extraction, et COMBATS CTB RÉELS sur les nœuds Combat et
# Attaque surprise (contenu du « ? »). Coffre / Bénédiction / Piège restent
# des STUBS (log + signal typé + marquage résolu).
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
	_log("═ Expédition : %s — palier %s (×%.1f), %d étages — Avatar PV %d" % [
			lieu_id, palier.nom_journal(), palier.multiplicateur, config.nb_etages,
			int(roundf(pv_avatar))])
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
# Coffre / Bénédiction / Piège restent des stubs (chantiers suivants).
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
	_resoudre_stub(nd)

# Marquage résolu + compteurs + signal typé (local + EventBus). Pour un nœud
# gagné au combat, `recap_combat` enrichit le payload (clé "combat") pour le
# futur chantier loot/XP.
func _resoudre_stub(nd: ExpeNoeud, recap_combat: Dictionary = {}) -> void:
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
	if not recap_combat.is_empty():
		data["combat"] = recap_combat
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
	av.pv = minf(pv_avatar, av.pv)   # PV persistants — aucune régénération
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
		defaite = true
		_log("☠ Défaite au nœud %d — fin d'expédition immédiate" % nd.id)
		_terminer(false)
		return
	_log("✔ Victoire au nœud %d — PV Avatar : %d" % [nd.id, int(roundf(pv_avatar))])
	_resoudre_stub(nd, {
		"embuscade":       embuscade,
		"nb_activations":  recap["nb_activations"],
		"ennemis_vaincus": recap["ennemis_vaincus"],
	})

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
	var recap := _recap(extraction)
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
