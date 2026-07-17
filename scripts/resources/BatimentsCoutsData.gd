# ============================================================
# BatimentsCoutsData — Courbe de coût UNIQUE des bâtiments du QG en
# Euren + Modules (Rework économique du QG, chantier 12 — acté 06/07/2026).
# Remplace l'ancienne courbe en ressources silotées par biome
# (Balance.BUILDING_COST_STEPS, supprimée). TOUTES les valeurs sont
# PROVISOIRES, à calibrer (géométrie ×1,6 conservée de l'ancien design).
#
# Index = palier CIBLE (0 = Délabré → T0 … 5 = T4 → T5). Courbe commune à
# tous les bâtiments (la différenciation par impact reste un point ouvert
# hérité). Les Modules entrent à T2, comme la ressource rare avant eux :
# les premiers paliers sont accessibles au farm d'Euren seul, la profondeur
# exige d'aller au bout des étages.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="BatimentsCoutsData" ...]
# ============================================================
class_name BatimentsCoutsData
extends Resource

# Euren requis par palier cible (index 0..5).
@export var euren_par_palier: Array[float] = [100.0, 160.0, 260.0, 420.0, 670.0, 1070.0]

# Modules requis par palier cible (index 0..5).
@export var modules_par_palier: Array[int] = [0, 0, 1, 2, 3, 4]

# Coût du palier cible : { "euren": float, "modules": int }, {} si hors courbe.
func cout(palier_cible: int) -> Dictionary:
	if palier_cible < 0 or palier_cible >= euren_par_palier.size():
		return {}
	return {
		"euren":   float(euren_par_palier[palier_cible]),
		"modules": int(modules_par_palier[palier_cible]) \
				if palier_cible < modules_par_palier.size() else 0,
	}
