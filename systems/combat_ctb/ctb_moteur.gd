# ============================================================
# CtbMoteur — Moteur de combat TOUR PAR TOUR à file d'initiative continue
# (CTB). Rework Combat, chantier 1 : squelette testable en scène isolée.
#
# L'horloge est un COMPTEUR LOGIQUE pur : aucun temps réel, aucun timer.
# Chaque combattant porte `horloge = K / VIT` (K = Balance.CTB_K) ; celui
# dont l'horloge est la plus basse s'active, agit (1 action), puis réarme :
# `horloge += K / VIT_courante` — les buffs/debuffs VIT agissent dès le
# réarmement suivant. VIT double → deux activations pour une.
# Égalité d'horloge : camp JOUEUR d'abord (Avatar, puis pets dans l'ordre de
# liste), puis ennemis dans l'ordre de liste.
#
# Déroulé d'une activation (l'ordre est contractuel — testé) :
#   1. sélection du combattant (horloge minimale)          → activer_suivant()
#   2. ticks des statuts DÉBUT (Saignement)                  ↳ mort ici =
#      activation consommée : pas d'action, pas de ticks FIN, pas de réarmement
#   3. UNE action (Attaquer / Compétence / Objet)          → jouer(action)
#      — seul ATTAQUER est fonctionnel au chantier 1 ; l'input joueur peut
#      attendre indéfiniment entre activer_suivant() et jouer()
#   4. ticks des statuts FIN (Poison, Brûlure)
#   5. réarmement de l'horloge (VIT courante)
#
# Fins de combat : PV Avatar à 0 → défaite (immédiate, même si des pets
# vivent) ; tous ennemis à 0 → victoire (+ hook post-victoire vide). Les deux
# émettent le signal local ET l'EventBus (ctb_victoire / ctb_defaite).
# La fin de combat interrompt tout (plus aucun tick ni réarmement — arbitrage
# 06/07 : aucun design ne s'appuiera sur des ticks post-victoire).
#
# Règles d'intégration expédition (chantier 3) : statuts PURGÉS en fin de
# combat (_purger_statuts — aucune persistance entre les nœuds) ; PV
# PERSISTANTS entre les nœuds (ExpeRun réinjecte les PV sortants via cb.pv).
# Attaque surprise : malus_horloge_initiale_joueur (×1.5 provisoire, .tres)
# multiplie la PREMIÈRE horloge du camp joueur ; réarmement suivant normal.
#
# Usage (pull-based, prêt pour une UI asynchrone) :
#   var m := CtbMoteur.new()
#   m.ajouter(avatar_data, Enums.CampCtb.JOUEUR)
#   m.ajouter(ennemi_data, Enums.CampCtb.ADVERSE)
#   m.demarrer()
#   while not m.termine:
#       var c := m.activer_suivant()      # null = activation consommée (DoT) ou fin
#       if c != null:
#           m.jouer(m.action_auto(c))     # ou une action choisie par le joueur
#
# Journal lisible dans `journal` (qui joue, valeur d'horloge, dégâts, ticks).
# ============================================================
class_name CtbMoteur
extends RefCounted

signal victoire(recap: Dictionary)
signal defaite(recap: Dictionary)

# Garde-fou anti-boucle infinie pour le déroulé automatique (non-balance).
const MAX_ACTIVATIONS := 500

var k_ctb: float = Balance.CTB_K     # constante d'horloge (exposée pour calibrage)
# Embuscade (attaque surprise) : multiplie la PREMIÈRE horloge de chaque
# combattant du camp JOUEUR (1.0 = pas de malus). À poser AVANT demarrer().
var malus_horloge_initiale_joueur := 1.0
var combattants: Array[CtbCombattant] = []
var rng := RandomNumberGenerator.new()   # seedable → tests déterministes
var journal: PackedStringArray = []
var termine := false
var victoire_joueur := false
var nb_activations := 0

var _actif: CtbCombattant = null     # combattant en cours d'activation (entre suivant/jouer)
var _demarre := false

# ─── Mise en place ────────────────────────────────────────────

# Ajoute un combattant à un camp. L'ordre d'appel fixe l'ordre de liste du
# camp (départage d'égalité) : côté JOUEUR, ajouter l'Avatar EN PREMIER.
func ajouter(d: CombattantCtbData, camp: Enums.CampCtb) -> CtbCombattant:
	assert(not _demarre, "ajouter() avant demarrer()")
	var o := 0
	for c in combattants:
		if c.camp == camp:
			o += 1
	var cb := CtbCombattant.new(d, camp, o)
	combattants.append(cb)
	return cb

# Arme les horloges initiales (K / VIT finale — les bonus posés avant le
# démarrage comptent) et journalise la composition des camps.
func demarrer() -> void:
	assert(not _demarre, "demarrer() une seule fois")
	assert(avatar() != null, "camp joueur vide (Avatar requis)")
	assert(combattants.any(func(c: CtbCombattant) -> bool: return not c.est_joueur()),
			"camp adverse vide")
	_demarre = true
	if malus_horloge_initiale_joueur != 1.0:
		_log("⚡ EMBUSCADE ! Première horloge du camp joueur ×%.1f" %
				malus_horloge_initiale_joueur)
	for c in combattants:
		c.horloge = k_ctb / _vit_sure(c)
		if c.est_joueur():
			c.horloge *= malus_horloge_initiale_joueur
		_log("%s rejoint le combat (%s) — PV %d, horloge initiale %.1f" % [
				c.nom_journal(), "joueur" if c.est_joueur() else "adverse",
				int(roundf(c.pv)), c.horloge])

# ─── Boucle d'activation (pull-based) ─────────────────────────

# Sélectionne le combattant à l'horloge minimale et ouvre son activation
# (ticks DÉBUT compris). Retourne le combattant s'il peut agir ; null si le
# combat est terminé OU si l'activation a été consommée par une mort au tick
# DÉBUT (dans ce cas, vérifier `termine` puis rappeler activer_suivant()).
func activer_suivant() -> CtbCombattant:
	assert(_demarre, "demarrer() d'abord")
	assert(_actif == null, "l'activation précédente n'a pas été jouée (jouer())")
	if termine:
		return null
	var c := _plus_basse_horloge()
	nb_activations += 1
	_log("► %s s'active (horloge %.1f)" % [c.nom_journal(), c.horloge])
	_tick_statuts(c, Enums.TimingStatut.DEBUT_ACTIVATION)
	if termine:
		return null
	if not c.est_vivant():
		# Mort au tick DÉBUT : activation consommée, ni action ni ticks FIN.
		return null
	_actif = c
	return c

# Résout l'action de l'activation en cours, puis les ticks FIN et le
# réarmement d'horloge. action : { "type": Enums.ActionCtb, "cible":
# CtbCombattant (ATTAQUER ; null → première cible vivante du camp opposé) }.
func jouer(action: Dictionary) -> void:
	assert(_actif != null, "aucune activation en cours (activer_suivant())")
	var c := _actif
	_actif = null
	match int(action.get("type", Enums.ActionCtb.ATTAQUER)):
		Enums.ActionCtb.ATTAQUER:
			_resoudre_attaque(c, action.get("cible"))
		_:
			# Compétence / Objet : prévus par l'architecture, sans contenu au
			# chantier 1 (« non découvert = absent ») — l'activation est perdue.
			_log("    %s tente une action non implémentée (chantier 1)" % c.nom_journal())
	if termine:
		return
	_tick_statuts(c, Enums.TimingStatut.FIN_ACTIVATION)
	if termine:
		return
	if c.est_vivant():
		c.horloge += k_ctb / _vit_sure(c)
		_log("    ⟳ %s réarme son horloge → %.1f" % [c.nom_journal(), c.horloge])

# Action par défaut (IA minimale / sandbox) : attaquer la première cible
# vivante du camp opposé.
func action_auto(c: CtbCombattant) -> Dictionary:
	return {"type": Enums.ActionCtb.ATTAQUER, "cible": _premiere_cible(c)}

# Déroule le combat en automatique (toutes les activations en action_auto).
# Garde-fou MAX_ACTIVATIONS contre les combats sans issue.
func derouler_auto() -> void:
	while not termine and nb_activations < MAX_ACTIVATIONS:
		var c := activer_suivant()
		if c != null:
			jouer(action_auto(c))
	if not termine:
		_log("⚠ garde-fou : %d activations sans issue, arrêt" % MAX_ACTIVATIONS)

# ─── Statuts DoT (hook générique data-driven) ────────────────

# Pose un stack de `statut` sur `cible`, dégâts par tick figés à la pose
# (% de l'ATK finale du POSEUR). Au-delà de stacks_max stacks du même statut,
# le stack le plus ancien est remplacé. Les stacks parallèles cumulent
# additivement à chaque tick.
func appliquer_statut(cible: CtbCombattant, statut: StatutCtbData, poseur: CtbCombattant) -> void:
	var memes: Array = cible.statuts.filter(
			func(s: Dictionary) -> bool: return (s["statut"] as StatutCtbData).id == statut.id)
	if memes.size() >= statut.stacks_max:
		cible.statuts.erase(memes[0])   # le plus ancien (ordre de pose)
	cible.statuts.append({
		"statut": statut,
		"degats_par_tick": poseur.stat_finale("atk") * statut.degats_pct_atk,
		"restant": statut.duree_activations,
	})
	var count := mini(memes.size() + 1, statut.stacks_max)
	_log("    ✚ %s posé sur %s par %s (%d stack%s)" % [
			statut.nom_journal(), cible.nom_journal(), poseur.nom_journal(),
			count, "s" if count >= 2 else ""])

# Ticks de tous les statuts de `c` au timing donné : les stacks d'un même
# statut cumulent ADDITIVEMENT (une seule application arrondie par statut),
# puis chaque stack tické perd 1 activation de durée (retiré à 0).
func _tick_statuts(c: CtbCombattant, timing: Enums.TimingStatut) -> void:
	if c.statuts.is_empty() or not c.est_vivant():
		return
	# Regroupement par id de statut (cumul additif des stacks parallèles).
	var par_statut: Dictionary = {}   # id → {"nom": String, "total": float, "stacks": Array}
	for s: Dictionary in c.statuts:
		var sd := s["statut"] as StatutCtbData
		if sd.timing != timing:
			continue
		if not par_statut.has(sd.id):
			par_statut[sd.id] = {"nom": sd.nom_journal(), "total": 0.0, "stacks": []}
		par_statut[sd.id]["total"] += float(s["degats_par_tick"])
		par_statut[sd.id]["stacks"].append(s)
	for id: String in par_statut:
		if not c.est_vivant():
			break
		var grp: Dictionary = par_statut[id]
		var degats := int(maxf(roundf(grp["total"]), Balance.MIN_DAMAGE))
		c.pv = maxf(c.pv - float(degats), 0.0)
		_log("    ▸ %s subit %s ×%d : %d dégâts (PV %d)" % [
				c.nom_journal(), grp["nom"], grp["stacks"].size(), degats, int(roundf(c.pv))])
		for s: Dictionary in grp["stacks"]:
			s["restant"] = int(s["restant"]) - 1
			if int(s["restant"]) <= 0:
				c.statuts.erase(s)
		if not c.est_vivant():
			_log("    ☠ %s succombe à %s" % [c.nom_journal(), grp["nom"]])
	_verifier_fin()

# ─── Résolution d'une attaque ────────────────────────────────

# dégâts = ATK finale × (1 − 0.5 × DEF / (DEF + 40)) via Balance.mitigated_damage
# (formule héritée, provisoire), × CritMult sur jet critique par coup,
# arrondi entier, plancher MIN_DAMAGE. Stats finales = StatStacker (additif).
func _resoudre_attaque(att: CtbCombattant, cible) -> void:
	var cb := cible as CtbCombattant
	if cb == null or not cb.est_vivant():
		cb = _premiere_cible(att)
	if cb == null:
		_log("    %s n'a plus de cible" % att.nom_journal())
		return
	var is_crit := rng.randf() < att.stat_finale("crit_chance")
	var brut := Balance.mitigated_damage(att.stat_finale("atk"), cb.stat_finale("def"))
	if is_crit:
		brut *= att.stat_finale("crit_multiplier")
	var degats := int(roundf(maxf(brut, Balance.MIN_DAMAGE)))
	cb.pv = maxf(cb.pv - float(degats), 0.0)
	_log("    ⚔ %s frappe %s : %d dégâts%s (PV %s : %d)" % [
			att.nom_journal(), cb.nom_journal(), degats,
			" CRITIQUE" if is_crit else "", cb.nom_journal(), int(roundf(cb.pv))])
	if not cb.est_vivant():
		_log("    ☠ %s est vaincu" % cb.nom_journal())
	_verifier_fin()

# ─── Fins de combat ──────────────────────────────────────────

func _verifier_fin() -> void:
	if termine:
		return
	var av := avatar()
	if av != null and not av.est_vivant():
		# Défaite : PV Avatar à 0 — la sanction (perte de ressources, compteur
		# R-XXX) est hors scope chantier 1, seul le signal est posé.
		termine = true
		victoire_joueur = false
		_purger_statuts()
		var recap := _recap()
		_log("═ DÉFAITE — l'Avatar tombe (activation %d)" % nb_activations)
		defaite.emit(recap)
		EventBus.ctb_defaite.emit(recap)
		return
	if combattants.all(func(c: CtbCombattant) -> bool: return c.est_joueur() or not c.est_vivant()):
		termine = true
		victoire_joueur = true
		_purger_statuts()
		var recap := _recap()
		_log("═ VICTOIRE — tous les ennemis sont vaincus (activation %d)" % nb_activations)
		_hook_post_victoire()
		victoire.emit(recap)
		EventBus.ctb_victoire.emit(recap)

# Hook post-victoire VIDE : l'ancien « régen après combat gagné » (et tout
# effet futur de fin de combat gagné) se rebranchera ici.
func _hook_post_victoire() -> void:
	pass

# Statuts PURGÉS en fin de combat (règle actée 06/07) : aucun DoT ne persiste
# entre deux nœuds d'expédition — les PV, eux, persistent (gérés par ExpeRun).
func _purger_statuts() -> void:
	var n := 0
	for c in combattants:
		n += c.statuts.size()
		c.statuts.clear()
	if n > 0:
		_log("    ✦ Statuts purgés en fin de combat (%d stack%s)" % [n, "s" if n >= 2 else ""])

# Recap de fin de combat. `ennemis_vaincus` : références des DONNÉES
# (CombattantCtbData) des combattants adverses tués — le loot et l'XP seront
# calculés EN AVAL par le système d'expédition, hors moteur (arbitrage 06/07).
func _recap() -> Dictionary:
	var pv_restants := {}
	var vaincus: Array[CombattantCtbData] = []
	for c in combattants:
		pv_restants[c.data.id] = c.pv
		if not c.est_joueur() and not c.est_vivant():
			vaincus.append(c.data)
	return {
		"victoire": victoire_joueur,
		"nb_activations": nb_activations,
		"pv_restants": pv_restants,
		"ennemis_vaincus": vaincus,
	}

# ─── Internes ────────────────────────────────────────────────

# Avatar = premier combattant du camp joueur (ordre 0).
func avatar() -> CtbCombattant:
	for c in combattants:
		if c.est_joueur() and c.ordre == 0:
			return c
	return null

# Combattant vivant à l'horloge la plus basse. Égalité (tolérance flottante) :
# camp JOUEUR d'abord (Avatar puis pets par ordre de liste), puis ennemis par
# ordre de liste.
func _plus_basse_horloge() -> CtbCombattant:
	var best: CtbCombattant = null
	for c in combattants:
		if not c.est_vivant():
			continue
		if best == null or c.horloge < best.horloge - 1.0e-9:
			best = c
		elif absf(c.horloge - best.horloge) <= 1.0e-9 and _prio(c) < _prio(best):
			best = c
	return best

func _prio(c: CtbCombattant) -> int:
	return c.ordre + (0 if c.est_joueur() else 1000)

func _premiere_cible(att: CtbCombattant) -> CtbCombattant:
	for c in combattants:
		if c.camp != att.camp and c.est_vivant():
			return c
	return null

func _vit_sure(c: CtbCombattant) -> float:
	return maxf(c.stat_finale("vit"), 0.01)

func _log(ligne: String) -> void:
	journal.append(ligne)
