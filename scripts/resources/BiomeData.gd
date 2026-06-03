class_name BiomeData
extends Resource

@export var id:                         String               = ""
@export var nom_affichage_fr:           String               = ""
@export var nom_affichage_en:           String               = ""
@export var lore_fr:                    String               = ""
@export var maitrise_actuelle:          Enums.Maitrise       = Enums.Maitrise.COMMUN
@export var xp_maitrise_actuelle:       float                = 0.0
@export var xp_maitrise_palier_suivant: float                = 0.0
@export var slot_equipement_associe:    Enums.SlotEquipement = Enums.SlotEquipement.ARME
@export var biome_secondaire_id:        String               = ""
@export var est_decouvert:              bool                 = false
@export var mecanique_forte_id:         String               = ""
@export var mecanique_forte_activee:    bool                 = false
@export var creature_surface:           CreatureData         = null
@export var creature_profondeur:        CreatureData         = null
@export var creature_unique:            CreatureData         = null
@export var creature_unique_vaincue:    bool                 = false
@export var pieges:                     Array[PiegeData]     = []
@export var benedictions:               Array[BenedictionData] = []
@export var ingredients_drop:           Array[IngredientData]  = []
@export var ingredient_unique:          IngredientData       = null
@export var event_table:                Dictionary           = {"creature": 0.7, "benediction": 0.15, "trap": 0.15}
