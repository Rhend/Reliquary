class_name PassifUniqueData
extends Resource

@export var id:                         String         = ""
@export var nom_affichage_fr:           String         = ""
@export var nom_affichage_en:           String         = ""
@export var lore_fr:                    String         = ""
@export var biome_source_id:            String         = ""
@export var est_debloque:               bool           = false
@export var maitrise_actuelle:          Enums.Maitrise = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       float          = 0.0
@export var xp_maitrise_palier_suivant: float          = 0.0
@export var effet_par_palier:           Dictionary     = {}
