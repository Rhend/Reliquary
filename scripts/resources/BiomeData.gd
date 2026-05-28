class_name BiomeData
extends Resource

@export var id:                         String             = ""
@export var nom_affichage_fr:           String             = ""
@export var nom_affichage_en:           String             = ""
@export var maitrise_actuelle:          Enums.Maitrise     = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       int                = 0
@export var xp_maitrise_palier_suivant: int                = 100
@export var slot_equipement_associe:    Enums.SlotEquipement = Enums.SlotEquipement.ARME
@export var biome_secondaire_id:        String             = ""
@export var est_decouvert:              bool               = false
@export var mecanique_forte_id:         String             = ""
@export var mecanique_forte_activee:    bool               = false
@export var creature_surface_id:        String             = ""
@export var creature_profondeur_id:     String             = ""
@export var creature_unique_id:         String             = ""
@export var creature_unique_vaincue:    bool               = false
@export var pieges_ids:                 Array[String]      = []
@export var benedictions_ids:           Array[String]      = []
@export var ingredients_drop_ids:       Array[String]      = []
@export var ingredient_unique_id:       String             = ""
@export var unlock_tier:                int                = 2
@export var base_stats:                 Dictionary         = {}
@export var passive_slots:              Array              = []
