class_name CreatureData
extends Resource

@export var id:                         String             = ""
@export var nom_affichage_fr:           String             = ""
@export var nom_affichage_en:           String             = ""
# Noms par palier de Maîtrise (clé int = palier ; palier absent → hérite du
# palier inférieur défini le plus proche ; dict vide → nom_affichage_*).
@export var noms_par_palier_fr:         Dictionary         = {}
@export var noms_par_palier_en:         Dictionary         = {}
@export var lore_fr:                    String             = ""
@export var lore_en:                    String             = ""
@export var est_unique:                 bool               = false
@export var zone_associee:              Enums.Zone         = Enums.Zone.SURFACE
@export var biome_id:                   String             = ""
@export var maitrise_actuelle:          Enums.Maitrise     = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       float              = 0.0
@export var xp_maitrise_palier_suivant: float              = 0.0
@export var stats_par_palier:           Dictionary         = {}
@export var ingredients_drop_ids:       Array[String]      = []
@export var loot_table:                 Array              = []
@export var passif_debloque_id:         String             = ""
@export var crit_chance:                float              = 0.20
@export var crit_multiplier:            float              = 1.8
