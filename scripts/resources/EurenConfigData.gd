# ============================================================
# EurenConfigData — Gains d'EUREN (monnaie commune à toutes les zones,
# actée 06/07/2026) par ennemi vaincu. Rework Combat, chantier 6.
# TOUTES les valeurs sont PROVISOIRES, à calibrer.
#
# euren par ennemi = base_par_ennemi × multiplicateur du PALIER DE MAÎTRISE
# de la créature. Le calcul vit ici (config), PAS dans les données créatures :
# aucun champ Euren n'existe au bestiaire (il sera remplacé).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="EurenConfigData" ...]
# ============================================================
class_name EurenConfigData
extends Resource

@export var base_par_ennemi := 10.0   # provisoire, à calibrer

# Palier de Maîtrise (0 Commun … 5 Unique) → multiplicateur.
# Progression simple provisoire, à calibrer.
@export var multiplicateurs_par_palier: Dictionary = {
	0: 1.0, 1: 2.0, 2: 3.0, 3: 4.0, 4: 5.0, 5: 6.0,
}

# Gain pour un ennemi au palier donné (palier inconnu → ×1).
func gain_pour_palier(palier: int) -> float:
	return base_par_ennemi * float(multiplicateurs_par_palier.get(palier, 1.0))
