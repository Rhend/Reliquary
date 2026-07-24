# ============================================================
# ButinConfigData — Réglages du BUTIN d'expédition (chantier 14).
#
# Les matériaux droppés par une run : la ressource FRÉQUENTE et la ressource
# RARE du biome du Lieu (`BiomeData.ressource_frequente_id` /
# `ressource_rare_id` — la rare EST l'ingrédient des keystones de Forge).
# Quantités et chances par PALIER de profondeur (le palier gagne ici son
# premier effet mécanique : plus profond = plus rentable) — valeurs
# PROVISOIRES, à calibrer au simulateur d'équilibrage.
#
# Contrat d'application (ExpeRun) :
#   • chaque VICTOIRE de combat : par ennemi vaincu, quantité fréquente tirée
#     dans [qte_frequente.x ; qte_frequente.y] + jet de rare (chance_rare) ;
#   • chaque COFFRE : paquet fréquent bonus [coffre_frequente.x ; .y] ;
#   • BOSS d'assaut vaincu : rare GARANTIE ×qte_rare_boss (re-kill compris —
#     l'assaut rejouable est la source fiable d'ingrédients de Forge) ;
#   • tout est ACCUMULÉ dans la run et crédité à la SORTIE seulement
#     (extraction/complétion — défaite = rien, mêmes rails que l'Euren).
# ============================================================
class_name ButinConfigData
extends Resource

# palier_id → Vector2i(min, max) : quantité de ressource fréquente par
# ennemi vaincu. Palier absent → Vector2i.ZERO (aucun drop).
@export var qte_frequente_par_palier: Dictionary = {
	"palier_peripherie": Vector2i(1, 2),
	"palier_enceinte":   Vector2i(2, 3),
	"palier_noyau":      Vector2i(3, 5),
	"palier_assaut":     Vector2i(3, 5),
}
# palier_id → chance [0;1] de ressource rare par ennemi vaincu.
@export var chance_rare_par_palier: Dictionary = {
	"palier_peripherie": 0.08,
	"palier_enceinte":   0.18,
	"palier_noyau":      0.30,
	"palier_assaut":     0.30,
}
@export var qte_rare: int = 1              # quantité par jet de rare réussi
@export var qte_rare_boss: int = 2         # rare GARANTIE au boss d'assaut
# palier_id → Vector2i(min, max) : paquet fréquent bonus d'un COFFRE
# (en plus de ses consommables de run).
@export var coffre_frequente_par_palier: Dictionary = {
	"palier_peripherie": Vector2i(2, 3),
	"palier_enceinte":   Vector2i(3, 5),
	"palier_noyau":      Vector2i(4, 7),
	"palier_assaut":     Vector2i(4, 7),
}

func qte_frequente(palier_id: String) -> Vector2i:
	return qte_frequente_par_palier.get(palier_id, Vector2i.ZERO)

func chance_rare(palier_id: String) -> float:
	return float(chance_rare_par_palier.get(palier_id, 0.0))

func coffre_frequente(palier_id: String) -> Vector2i:
	return coffre_frequente_par_palier.get(palier_id, Vector2i.ZERO)
