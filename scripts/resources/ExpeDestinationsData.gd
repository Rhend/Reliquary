# ============================================================
# ExpeDestinationsData — Rattachement DESTINATION → pool d'ennemis
# (Rework Combat, chantier 8 : branchement au flux de jeu principal).
#
# Une destination = un Lieu de la HoloMap (id d'entité de la zone à ID).
# PROVISOIRE : les 6 Lieux différenciés n'existent pas encore — toutes les
# destinations retombent sur `pool_defaut` tant que `pools_par_lieu` est
# vide. L'architecture est prête : différencier un Lieu = ajouter une entrée
# lieu_id → PoolEnnemisData dans le .tres, sans toucher au code (le contenu
# viendra avec le bestiaire).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ExpeDestinationsData" ...]
# ============================================================
class_name ExpeDestinationsData
extends Resource

# lieu_id (String) → PoolEnnemisData. Vide tant que les Lieux différenciés
# n'existent pas (tout le monde partage pool_defaut).
@export var pools_par_lieu: Dictionary = {}

# Pool de repli pour toute destination sans pool dédié.
@export var pool_defaut: PoolEnnemisData = null

# Pool d'ennemis de la destination : dédié s'il existe, sinon le défaut.
func pool_pour(lieu_id: String) -> PoolEnnemisData:
	var p: PoolEnnemisData = pools_par_lieu.get(lieu_id, null)
	return p if p != null else pool_defaut
