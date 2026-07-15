# ============================================================
# ExpeNoeudsConfigData — Contenu des nœuds Bénédiction / Piège / Coffre
# d'une expédition (Rework Combat, chantier 7 : fin des stubs).
# TOUTES les valeurs sont PROVISOIRES, à calibrer.
#
# Pools EXTENSIBLES (un .tres par affixe/consommable) : Bénédiction tire un
# affixe du pool positif, Piège du pool négatif (uniforme, rng de la run) ;
# Coffre tire 1-2 consommables (pondération poids_nb_consommables).
# cap_inventaire : taille max de l'inventaire de run (0 = illimité —
# provisoire) ; un tirage au-delà du cap est PERDU (journalisé).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ExpeNoeudsConfigData" ...]
# ============================================================
class_name ExpeNoeudsConfigData
extends Resource

@export var affixes_positifs: Array[AffixeData] = []
@export var affixes_negatifs: Array[AffixeData] = []
@export var pool_consommables: Array[ConsommableData] = []

# Nombre de consommables d'un Coffre : nb → poids relatif (provisoire).
@export var poids_nb_consommables: Dictionary = {1: 0.6, 2: 0.4}

# 0 = inventaire de run illimité (provisoire, à calibrer).
@export var cap_inventaire := 0
