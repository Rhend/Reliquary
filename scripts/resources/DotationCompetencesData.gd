# ============================================================
# DotationCompetencesData — Dotation de COMPÉTENCES du héros (chantier 16).
#
# Même philosophie que l'équipement de départ (ch.13) : la liste vit en
# .tres (`data/progression/competences_heros.tres`), appliquée par CtbPont
# au combattant TRANSITOIRE du héros à chaque construction — jamais écrite
# dans un .tres du bestiaire ni dans la sauvegarde. Provisoire : à terme,
# des compétences pourront venir de la Forge/équipements ; cette dotation
# restera la base commune.
# ============================================================
class_name DotationCompetencesData
extends Resource

@export var competences: Array[CompetenceCtbData] = []
