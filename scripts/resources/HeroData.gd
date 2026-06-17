# ============================================================
# HeroData — Resource du Héros unique.
#
# IMPORTANT : les stats de combat du héros (ATK/DEF/PV/VIT) NE sont PAS
# stockées ici. Elles proviennent des tables par palier de Balance.gd
# (HERO_*_PER_TIER), source de vérité unique — cf. GameData.get_effective_stats().
# Ce Resource ne porte que l'identité et la progression de Maîtrise.
# ============================================================
class_name HeroData
extends Resource

@export var id:                         String     = ""
@export var nom_affichage_fr:           String     = ""
@export var nom_affichage_en:           String     = ""
@export var noms_par_palier_fr:         Dictionary = {}
@export var noms_par_palier_en:         Dictionary = {}
@export var lore_fr:                    String     = ""
@export var lore_en:                    String     = ""
# Lore par palier de Maîtrise (sinon hérite du palier inférieur ; vide → lore_*).
@export var lore_par_palier_fr:         Dictionary = {}
@export var lore_par_palier_en:         Dictionary = {}
@export var passifs_par_palier:         Dictionary = {}
@export var crit_chance:                float      = 0.20
@export var crit_multiplier:            float      = 1.8
@export var maitrise_actuelle:          int        = 0
@export var xp_maitrise_actuelle:       float      = 0.0
@export var xp_maitrise_palier_suivant: float      = 0.0
