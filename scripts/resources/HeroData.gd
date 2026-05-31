class_name HeroData
extends Resource

@export var id:                String     = ""
@export var nom_affichage_fr:  String     = ""
@export var nom_affichage_en:  String     = ""
@export var atk:               int        = 0
@export var def:               int        = 0
@export var hp:                int        = 0
@export var vit:               int        = 0
@export var atk_par_tier:      int        = 0
@export var def_par_tier:      int        = 0
@export var hp_par_tier:       int        = 0
@export var vit_par_tier:      int        = 0
@export var passifs_par_palier: Dictionary = {}
@export var maitrise_actuelle:          int   = 0
@export var xp_maitrise_actuelle:       float = 0.0
@export var xp_maitrise_palier_suivant: float = 0.0
