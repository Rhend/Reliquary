# ============================================================
# ExpeCombatConfigData — Paramètres des COMBATS d'une expédition
# (Rework Combat, chantier 3). Toutes les valeurs sont PROVISOIRES,
# à calibrer. Séparé d'ExpeCarteConfigData (génération de la carte) :
# ces réglages concernent la résolution des nœuds, pas leur disposition.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ExpeCombatConfigData" ...]
# ============================================================
class_name ExpeCombatConfigData
extends Resource

# Nombre d'ennemis d'un combat : nb → poids relatif du tirage pondéré.
# Provisoire : 1 → 50 %, 2 → 35 %, 3 → 15 %. Le moteur CTB est N-vs-N :
# ajouter une clé suffit pour ouvrir un format à 4+ (contenu à créer).
@export var poids_nb_ennemis: Dictionary = {1: 0.5, 2: 0.35, 3: 0.15}

# Attaque surprise (contenu du « ? ») : la PREMIÈRE horloge de chaque
# combattant du camp joueur est multipliée par ce malus (provisoire, ×1.5) ;
# le réarmement suivant est normal.
@export var malus_horloge_embuscade := 1.5
