# ============================================================
# StatutCtbData — Paramètres d'un statut DoT du moteur CTB (hook générique
# data-driven, Rework Combat chantier 1).
#
# Un statut s'empile en STACKS PARALLÈLES sur une cible : chaque stack a sa
# propre durée (en ACTIVATIONS de la cible) et ses dégâts par tick figés à la
# pose (% de l'ATK finale du poseur). Les stacks simultanés cumulent
# ADDITIVEMENT leurs dégâts à chaque tick ; la durée de chaque stack est
# décrémentée à chaque tick.
#
# Timing (Enums.TimingStatut) : Saignement tique au DÉBUT de l'activation de
# la cible ; Poison et Brûlure à la FIN. Seul le Poison a des valeurs au
# chantier 1 (data/combat_ctb/statut_poison.tres) — Brûlure et Saignement :
# hook posé, aucune valeur (ne rien inventer).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="StatutCtbData" ...]
# ============================================================
class_name StatutCtbData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""

# Moment du tick relatif à l'activation de la CIBLE (début ou fin).
@export var timing: Enums.TimingStatut = Enums.TimingStatut.FIN_ACTIVATION

# Dégâts d'UN stack par tick, en fraction de l'ATK finale du POSEUR
# (0.05 = 5 %), figés au moment de la pose du stack.
@export var degats_pct_atk: float = 0.0

# Nombre maximum de stacks simultanés sur une même cible.
# Au-delà : le stack le plus ancien est remplacé.
@export var stacks_max: int = 1

# Durée de vie d'UN stack, en activations de la cible (1 tick par activation).
@export var duree_activations: int = 1

func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
