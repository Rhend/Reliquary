class_name PassifData
extends Resource

# Passif générique (ex-data/passives/*.json migré en .tres).
# Les clés reproduisent l'ancien JSON pour ne rien changer côté consommateurs :
# id, name, type, base_stats, tier_effects, passive_slots.
@export var id:                         String     = ""
@export var name:                       String     = ""
@export var type:                       String     = ""
@export var base_stats:                 Dictionary = {}
@export var tier_effects:               Array      = []
@export var passive_slots:              Array      = []
# Progression de Maîtrise (source de vérité runtime, comme les autres entités).
@export var maitrise_actuelle:          int        = 0
@export var xp_maitrise_actuelle:       float      = 0.0
@export var xp_maitrise_palier_suivant: float      = 0.0
