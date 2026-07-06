# ============================================================
# CombattantCtbData — Stats NUES d'un combattant du moteur CTB
# (Rework Combat, chantier 1 : Avatar + ennemis factices).
#
# Ressource pure de données : le runtime (CtbCombattant) la référence sans
# JAMAIS dupliquer ses champs — il n'y stocke que l'état de combat (PV
# courants, horloge, statuts, bonus %). Les stats finales se calculent à la
# demande : stat_finale = stat_nue × (1 + Σ bonus%) (StatStacker, additif).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="CombattantCtbData" ...]
# ============================================================
class_name CombattantCtbData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""

@export var pv_max: float = 100.0
@export var atk:    float = 10.0
@export var def:    float = 0.0
@export var vit:    float = 20.0   # horloge CTB : prochaine_action = Balance.CTB_K / VIT

@export var crit_chance:     float = 0.05
@export var crit_multiplier: float = 1.8

# Nom pour le JOURNAL DE DEV du moteur (log de vérification, pas une UI).
# Toute UI finale passera par Translations (hors scope chantier 1).
func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
