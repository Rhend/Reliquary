class_name PassifData
extends Resource

# Passif générique (ex-data/passives/*.json migré en .tres).
# Les clés reproduisent l'ancien JSON pour ne rien changer côté consommateurs :
# id, name, type, base_stats, tier_effects, passive_slots.
@export var id:                         String     = ""
@export var name:                       String     = ""
@export var nom_affichage_en:           String     = ""
@export var noms_par_palier_fr:         Dictionary = {}
@export var noms_par_palier_en:         Dictionary = {}
@export var lore_fr:                    String     = ""
@export var lore_en:                    String     = ""
# Lore par palier de Maîtrise (sinon hérite du palier inférieur ; vide → lore_*).
@export var lore_par_palier_fr:         Dictionary = {}
@export var lore_par_palier_en:         Dictionary = {}
@export var type:                       String     = ""
@export var base_stats:                 Dictionary = {}
@export var tier_effects:               Array      = []
@export var passive_slots:              Array      = []
# Progression de Maîtrise (source de vérité runtime, comme les autres entités).
@export var maitrise_actuelle:          int        = 0
@export var xp_maitrise_actuelle:       float      = 0.0
@export var xp_maitrise_palier_suivant: float      = 0.0
