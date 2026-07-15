# ============================================================
# ConfigCtbData — Réglages GLOBAUX du moteur de combat CTB
# (Rework Combat, chantier 5). Valeurs PROVISOIRES, à calibrer.
#
# Distinct d'ExpeCombatConfigData (réglages des combats d'UNE expédition :
# nombre d'ennemis, embuscade) : ici vivent les règles du moteur lui-même,
# quel que soit le contexte qui l'invoque. Instance de référence :
# data/combat_ctb/config_ctb.tres (chargée par défaut par CtbMoteur —
# remplaçable avant demarrer(), ex. tests).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ConfigCtbData" ...]
# ============================================================
class_name ConfigCtbData
extends Resource

# Action DÉFENDRE : fraction des dégâts d'ATTAQUE retranchée au défenseur
# (0.5 = −50 %), de sa mise en garde jusqu'à sa PROCHAINE activation.
# Les ticks de DoT ne sont PAS réduits (dégâts figés à la pose — règle actée).
# Ordre d'application (contractuel, testé) :
#   ATK → mitigation DEF → critique → Défendre → plancher MIN_DAMAGE → arrondi.
@export var defendre_reduction_degats := 0.5
