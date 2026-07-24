# ============================================================
# CompetenceCtbData — Une COMPÉTENCE de combat CTB (chantier 16).
#
# Portée par le COMBATTANT (CombattantCtbData.competences — le héros reçoit
# sa dotation via CtbPont ; un futur ennemi pourrait en porter, l'IA actée
# ne les joue pas). Le cooldown se compte en ACTIVATIONS du lanceur :
# posé à l'usage, décrémenté à l'OUVERTURE de chaque activation du lanceur
# (une compétence à cooldown 3 revient à la 3e activation suivante).
#
# Effets typés (Enums.EffetCompetence — jamais de string magique) :
#   ATTAQUE_MULT    — attaque via le pipeline COMPLET (mitigation DEF, crit,
#                     règles de Lieu, Défendre, plancher) × `valeur`.
#   SOIN_PCT_PV_MAX — rend (valeur × pv_max finale) au lanceur, clampé —
#                     l'outil de gestion des PV persistants entre nœuds.
# ============================================================
class_name CompetenceCtbData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""
@export var lore_fr: String = ""
@export var lore_en: String = ""
@export var effet: Enums.EffetCompetence = Enums.EffetCompetence.ATTAQUE_MULT
# ATTAQUE_MULT : multiplicateur de dégâts ; SOIN_PCT_PV_MAX : fraction de PV max.
@export var valeur: float = 1.5
# Cooldown en ACTIVATIONS du lanceur (0 = utilisable à chaque activation).
@export var cooldown: int = 3

func cible_requise() -> bool:
	return effet == Enums.EffetCompetence.ATTAQUE_MULT

func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
