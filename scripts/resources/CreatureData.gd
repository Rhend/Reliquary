class_name CreatureData
extends Resource

@export var id:                         String             = ""
@export var nom_affichage_fr:           String             = ""
@export var nom_affichage_en:           String             = ""
@export var est_unique:                 bool               = false
@export var zone_associee:              Enums.ZoneCreature = Enums.ZoneCreature.SURFACE
@export var biome_id:                   String             = ""
@export var maitrise_actuelle:          Enums.Maitrise     = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       int                = 0
@export var xp_maitrise_palier_suivant: int                = 100
@export var stats_par_palier:           Dictionary         = {}
@export var ingredients_drop_ids:       Array[String]      = []
@export var loot_table:                 Array              = []
@export var passif_debloque_id:         String             = ""
