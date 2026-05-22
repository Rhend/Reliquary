# ============================================================
# CombatStep — Instantané d'une attaque dans la résolution de combat.
#
# Produit par CombatResolver et consommé par CombatPlayer pour
# animer la séquence de combat étape par étape.
# ============================================================
class_name CombatStep extends Resource

@export var attacker:        String = "hero"  # "hero" | "enemy" — qui attaque ce tour
@export var damage:          int    = 0        # dégâts infligés (ATK - DEF, minimum 1)
@export var target_hp_after: int    = 0        # PV de la cible après ce coup
@export var is_killing_blow: bool   = false    # vrai si ce coup amène la cible à 0 PV
@export var is_crit:         bool   = false    # vrai si coup critique (×CRIT_MULTIPLIER dégâts)
@export var tick_time:       int    = 0        # tick absolu auquel ce coup se produit dans la simulation
