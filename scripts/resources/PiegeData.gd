class_name PiegeData
extends Resource

@export var id:               String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""
@export var noms_par_palier_fr: Dictionary = {}
@export var noms_par_palier_en: Dictionary = {}
@export var lore_fr:          String = ""
@export var lore_en:          String = ""
@export var biome_source_id:  String = ""
@export var degats:           int    = 0
@export var inflict_saignement:         bool  = false
@export var maitrise_actuelle:          int   = 0
@export var xp_maitrise_actuelle:       float = 0.0
@export var xp_maitrise_palier_suivant: float = 0.0
