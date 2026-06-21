# ============================================================
# CombatStep — Instantané d'une attaque dans la résolution de combat.
#
# Produit par CombatResolver et consommé par CombatPlayer pour
# animer la séquence de combat étape par étape.
# ============================================================
class_name CombatStep extends Resource

@export var attacker:        String = "hero"  # Enums.Actor.HERO | .ENEMY — qui attaque ce tour
@export var damage:          int    = 0        # dégâts infligés (ATK - DEF, minimum 1)
@export var target_hp_after: int    = 0        # PV de la cible après ce coup
@export var is_killing_blow: bool   = false    # vrai si ce coup amène la cible à 0 PV
@export var is_crit:         bool   = false    # vrai si coup critique (×CRIT_MULTIPLIER dégâts)
@export var time_sec:        float  = 0.0      # instant réel (secondes) auquel ce coup se produit dans la simulation ATB
@export var is_ambush:            bool = false  # vrai pour le tour gratuit d'embuscade (Forêt Sombre)
@export var is_poison:            bool = false  # vrai pour un tick de poison biome (Marécage Putride) — frappe le HÉROS (attacker = ENEMY), damage = dégâts subis
@export var shield_absorbed:      int  = 0     # dégâts absorbés par le bouclier d'urgence ce step
@export var is_shield_proc:       bool = false  # le bouclier d'urgence vient de s'activer ce step
@export var shield_value:         int  = 0     # PV du bouclier au moment de l'activation
@export var is_passive_poison:    bool = false  # vrai pour un tick de poison passif (Contact Venimeux)
@export var passive_poison_proc:  bool = false  # Contact Venimeux a proc sur ce coup héros
@export var is_lethal_ignored:    bool = false  # coup létal annulé par la Palissade T5 (PV ramenés à 1 au lieu de 0)
