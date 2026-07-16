# ============================================================
# Alarme — Système d'ALARME de la ville (Rework Combat, chantier 11).
# class_name statique (pattern Balance/ProgressionHeros, PAS un autoload).
#
# Règles actées (06/07/2026) : 6 slots, un par Lieutenant détruit (premier
# kill seulement — état dans GameData.player["lieutenants_vaincus"], la
# sauvegarde de PARTIE) ; tous détruits → l'alarme sonne (signal
# EventBus.alarme_sonnee, déclencheur de fin de jeu). Les paliers d'Alarme
# renforcent TOUS les ennemis de TOUTES les expéditions : bonus % de stats
# par slot + affixes permanents à partir du palier 4 (table data-driven,
# data/expedition/alarme.tres — valeurs provisoires, à calibrer).
#
# Application : appelée par ExpeRun à la CRÉATION de chaque combattant
# ennemi (même endroit que le pont bestiaire) — le moteur CTB reste
# agnostique, exactement comme les affixes de run du joueur.
# ============================================================
class_name Alarme

const CONFIG: AlarmeConfigData = preload("res://data/expedition/alarme.tres")

# Niveau d'Alarme courant = slots remplis (0-6).
static func niveau() -> int:
	return GameData.nb_lieutenants_vaincus()

# Applique les effets du niveau d'Alarme courant à un combattant ENNEMI
# fraîchement créé : Σ bonus % (cumul additif universel — StatStacker).
static func appliquer(cb: CtbCombattant) -> void:
	var n := niveau()
	if n <= 0:
		return
	for stat: String in CONFIG.pct_par_slot:
		cb.ajouter_bonus_pct(stat, float(CONFIG.pct_par_slot[stat]) * float(n))
	for a: AffixeData in affixes_actifs():
		for stat: String in a.bonus:
			cb.ajouter_bonus_pct(stat, float(a.bonus[stat]))

# Affixes permanents ACTIFS au niveau courant (cumulatif : tous les paliers
# atteints) — aussi utilisé par l'UI/les tests.
static func affixes_actifs() -> Array[AffixeData]:
	var out: Array[AffixeData] = []
	var n := niveau()
	var paliers: Array = CONFIG.affixes_par_palier.keys()
	paliers.sort()
	for palier in paliers:
		if n >= int(palier):
			out.append(CONFIG.affixes_par_palier[palier] as AffixeData)
	return out
