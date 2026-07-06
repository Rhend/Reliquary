# ============================================================
# ExpeRun — Déroulé d'UNE expédition sur carte de nœuds (Rework Combat,
# chantier 2) : navigation free-roam, brouillard de guerre, enchaînement
# des étages, extraction. RÉSOLUTION DES NŒUDS = STUBS (log + signal typé
# + marquage résolu) — le branchement sur le moteur CTB viendra après.
#
# Une expédition = 1 Lieu + 1 palier de profondeur (PalierProfondeurData,
# multiplicateur de difficulté qui CIRCULE dans les signaux sans effet réel
# au chantier 2) + cfg.nb_etages étages générés à la volée (ExpeCarte).
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
# expe_etage_termine / expe_terminee).
# ============================================================
class_name ExpeRun
extends RefCounted

signal noeud_resolu(data: Dictionary)
signal etage_termine(data: Dictionary)
signal terminee(recap: Dictionary)

var config: ExpeCarteConfigData
var palier: PalierProfondeurData
var lieu_id := ""

var rng := RandomNumberGenerator.new()   # seedable → run reproductible
var etage := 1
var carte: ExpeCarte
var position_joueur := 0
var choix_ouvert := false                # sur la Fin d'étage : Extraire / Continuer
var est_terminee := false
var journal: PackedStringArray = []

# Compteurs pour le recap : type de nœud (int) → nb résolus, + contenus de « ? ».
var _resolus_par_type: Dictionary = {}
var _mysteres_par_contenu: Dictionary = {}

func _init(cfg: ExpeCarteConfigData, p: PalierProfondeurData, lieu: String, graine := 0) -> void:
	config = cfg
	palier = p
	lieu_id = lieu
	if graine != 0:
		rng.seed = graine

# ─── Cycle de vie ────────────────────────────────────────────

func demarrer() -> void:
	_log("═ Expédition : %s — palier %s (×%.1f), %d étages" % [
			lieu_id, palier.nom_journal(), palier.multiplicateur, config.nb_etages])
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
# Refuse : expédition finie, nœud non adjacent. Retourne true si le pas a eu lieu.
func deplacer_vers(nid: int) -> bool:
	if est_terminee or not nid in carte.noeud(position_joueur).voisins:
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

# Résolution STUB d'un nœud non résolu : tirage du « ? » le cas échéant,
# signal typé (local + EventBus), log, marquage inerte. Rien d'autre.
func _resoudre(nd: ExpeNoeud) -> void:
	nd.resolu = true
	if nd.type == Enums.TypeNoeud.MYSTERE:
		nd.contenu_mystere = _tirer_mystere()
	var data := {
		"type":            nd.type,
		"contenu_mystere": nd.contenu_mystere,
		"lieu_id":         lieu_id,
		"palier_id":       palier.id,
		"multiplicateur":  palier.multiplicateur,
		"etage":           etage,
		"noeud_id":        nd.id,
	}
	_resolus_par_type[nd.type] = int(_resolus_par_type.get(nd.type, 0)) + 1
	if nd.contenu_mystere >= 0:
		_mysteres_par_contenu[nd.contenu_mystere] = \
				int(_mysteres_par_contenu.get(nd.contenu_mystere, 0)) + 1
	_log("  ▣ Résolution stub : %s%s (étage %d, ×%.1f)" % [
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
	_log("═ %s — recap : %s" % ["EXTRACTION" if extraction else "EXPÉDITION BOUCLÉE", str(recap)])
	terminee.emit(recap)
	EventBus.expe_terminee.emit(recap)

# Recap de fin d'expédition. Le loot/XP réels viendront des chantiers de
# résolution ; ici : parcours et compteurs de stubs.
func _recap(extraction: bool) -> Dictionary:
	return {
		"lieu_id":              lieu_id,
		"palier_id":            palier.id,
		"multiplicateur":       palier.multiplicateur,
		"extraction":           extraction,                      # true = sortie volontaire
		"complete":             not extraction,                  # dernier étage bouclé
		"etage_atteint":        etage,
		"noeuds_resolus":       _resolus_par_type.duplicate(),   # TypeNoeud → nb
		"mysteres_resolus":     _mysteres_par_contenu.duplicate(),  # ContenuMystere → nb
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
