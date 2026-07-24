# ============================================================
# MecaniquesBiomesData — Réglages des MÉCANIQUES FORTES de biome en combat
# CTB (chantier 15). Le moteur n'expose que des hooks génériques
# (modif_degats_camp, statut_on_hit_camp, malus d'initiative) : chaque
# mécanique n'est qu'un réglage appliqué par ExpeRun selon le
# `mecanique_forte_id` du biome du Lieu.
#
# GATE : le PALIER DE PROFONDEUR (le tier de biome, ancien gate, est gelé
# depuis le chantier 12). Périphérie = palier d'apprentissage sans
# mécanique ; l'assaut se joue avec l'identité du Lieu au maximum.
#
# Mécaniques actées (aucune autre) :
#   ambush         (Forêt)    — malus d'initiative sur TOUS les combats du
#                               Lieu (réutilise malus_horloge_embuscade) ;
#   poison         (Marécage) — chance de poser statut_poison sur le héros
#                               à chaque coup ennemi ;
#   endurcissement (Montagne) — dégâts d'attaque du camp joueur × mult.
# ============================================================
class_name MecaniquesBiomesData
extends Resource

# Paliers de profondeur où la mécanique forte est ACTIVE.
@export var paliers_actifs: Array[String] = [
	"palier_enceinte", "palier_noyau", "palier_assaut",
]
# Poison (Marécage) : statut posé sur le héros par les coups ennemis.
@export var poison_statut: StatutCtbData
@export_range(0.0, 1.0) var poison_chance: float = 0.35
# Endurcissement (Montagne) : multiplicateur des dégâts d'ATTAQUE du camp
# joueur (0.80 = −20 %, valeur de design MONTAGNE_ENDURCISSEMENT_REDUCTION).
@export var endurcissement_mult: float = 0.80

func active_pour(palier_id: String) -> bool:
	return palier_id in paliers_actifs
