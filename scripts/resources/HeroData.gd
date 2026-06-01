# ============================================================
# HeroData — Resource du Héro unique.
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
@export var passifs_par_palier:         Dictionary = {}
@export var maitrise_actuelle:          int        = 0
@export var xp_maitrise_actuelle:       float      = 0.0
@export var xp_maitrise_palier_suivant: float      = 0.0
