class_name PassifUniqueData
extends Resource

@export var id:                         String         = ""
@export var nom_affichage_fr:           String         = ""
@export var nom_affichage_en:           String         = ""
@export var noms_par_palier_fr:         Dictionary     = {}
@export var noms_par_palier_en:         Dictionary     = {}
@export var lore_fr:                    String         = ""
@export var lore_en:                    String         = ""
# Lore par palier de Maîtrise (sinon hérite du palier inférieur ; vide → lore_*).
@export var lore_par_palier_fr:         Dictionary     = {}
@export var lore_par_palier_en:         Dictionary     = {}
@export var biome_source_id:            String         = ""
@export var est_debloque:               bool           = false
@export var maitrise_actuelle:          Enums.Maitrise = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       float          = 0.0
@export var xp_maitrise_palier_suivant: float          = 0.0
@export var effet_par_palier:           Dictionary     = {}
