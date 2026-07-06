# ============================================================
# PoolEnnemisData — Pool d'ennemis d'un Lieu d'expédition
# (Rework Combat, chantier 3 : branchement CTB ↔ nœuds).
#
# Référence le BESTIAIRE EXISTANT par id d'entité (les créatures dark
# fantasy de data/creatures/, chargées par GameData) — le remplacement
# progressif par le bestiaire cyberpunk se fera en éditant ces listes,
# sans toucher au code. La conversion vers le format combattant CTB est
# faite au lancement du combat par CtbPont (stats lues telles quelles).
#
# Le rattachement Lieu → pool est fait EN AMONT par le système qui lance
# l'expédition (les Lieux réels n'existent pas encore : le sandbox et les
# tests injectent leur pool directement dans ExpeRun).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="PoolEnnemisData" ...]
# ============================================================
class_name PoolEnnemisData
extends Resource

@export var id: String = ""

# Ids d'entités du bestiaire (GameData) — tirage uniforme AVEC remise par
# slot d'ennemi (un combat à 3 ennemis peut aligner 3 fois la même créature).
@export var creature_ids: Array[String] = []
