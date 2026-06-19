# ============================================================
# StatStacker — Empilement ADDITIF des bonus % en une stat finale.
#
# Règle universelle (verrouillée — « Référentiel des statistiques de combat »),
# valable pour CHAQUE stat (ATK, DEF, PV, crit, vitesse, toutes) :
#
#     stat_finale = stat_nue × (1 + Σ bonus%)
#
# Tous les bonus EN POURCENTAGE de TOUTES les sources (passifs de village,
# nœuds d'équipement / Forge, bonus de Maîtrise, modificateurs de cycle…) sont
# SOMMÉS puis appliqués UNE SEULE FOIS. JAMAIS de produit séquentiel :
#   ✗ stat × 1,16 × 1,09 × 1,43   (multiplicatif → emballement)
#   ✓ stat × (1 + 0,16 + 0,09 + 0,43)
# Conséquence : l'ordre d'acquisition des bonus ne change JAMAIS le résultat.
#
# Point unique clampable : `_capped()`. Un plafond PAR STAT s'ajoute ici en une
# ligne (ex. « Σ bonus DEF capé à +80 % ») sans toucher aucune source. v1 : aucun
# cap actif.
#
# Classe utilitaire statique (class_name, PAS un autoload) — même convention que
# Balance / UIHelpers. Usage : StatStacker.final_stat(base, [0.16, 0.09], "atk").
# ============================================================
class_name StatStacker

# Stat finale d'une stat nue après empilement additif des bonus %.
# `bonus_pcts` : fractions (0.16 = +16 %), toutes sources confondues, dans
# n'importe quel ordre. `stat_key` : identifie la stat pour un éventuel cap.
static func final_stat(base: float, bonus_pcts: Array, stat_key: String = "") -> float:
	return base * (1.0 + _capped(sum_pcts(bonus_pcts), stat_key))

# Somme brute d'une liste de bonus % (sans cap). Exposée pour les sources qui
# accumulent un total avant de le passer à final_stat.
static func sum_pcts(bonus_pcts: Array) -> float:
	var total := 0.0
	for p in bonus_pcts:
		total += float(p)
	return total

# Point d'extension UNIQUE pour un plafond par stat. v1 : identité (aucun cap).
# Pour capper une stat, ajouter une ligne, ex. :
#   if stat_key == "def": return minf(total, Balance.DEF_BONUS_CAP)
static func _capped(total: float, _stat_key: String) -> float:
	return total
