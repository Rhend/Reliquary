# ============================================================
# PalierProfondeurData — Palier de profondeur d'une expédition
# (Rework Combat, chantier 2) : Périphérie / Enceinte / Noyau.
#
# Modificateur de DIFFICULTÉ de la run, choisi au lancement avec le Lieu.
# Valeurs provisoires (1.0 / 1.5 / 2.0), à calibrer — aucun effet réel tant
# que les nœuds sont des stubs : le multiplicateur CIRCULE dans les signaux
# (expe_noeud_resolu, recap) pour que les chantiers suivants le consomment.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="PalierProfondeurData" ...]
# ============================================================
class_name PalierProfondeurData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""

# Multiplicateur de difficulté appliqué à la run (provisoire, à calibrer).
@export var multiplicateur := 1.0

# Nom pour le journal de dev (l'UI finale passera par Translations).
func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
