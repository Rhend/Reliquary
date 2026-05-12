# ============================================================
# CombatResolver — Résolution instantanée d'un combat.
#
# Calcule toute la séquence d'échanges en une frame.
# Aucun signal, aucun timer, aucun effet de bord.
# Premier attaquant : le Héro (pas d'initiative variable pour l'instant).
# ============================================================
class_name CombatResolver

const DAMAGE_VARIANCE: float = 0.10
const HERO_MIN_DAMAGE: float  = 1.0
const ENEMY_MIN_DAMAGE: float = 1.0
const MAX_STEPS: int          = 300   # garde-fou anti-boucle infinie

static func resolve(
		hero_atk:  float, hero_def:  float, hero_hp:  float,
		enemy_atk: float, enemy_def: float, enemy_hp: float
	) -> Array[CombatStep]:

	var steps: Array[CombatStep] = []
	var h_hp := hero_hp
	var e_hp := enemy_hp

	while h_hp > 0.0 and e_hp > 0.0 and steps.size() < MAX_STEPS:
		# ── Tour du Héro ─────────────────────────────────────
		var h_dmg := _calc(hero_atk, enemy_def, HERO_MIN_DAMAGE)
		e_hp = maxf(e_hp - h_dmg, 0.0)
		var s1 := CombatStep.new()
		s1.attacker        = "hero"
		s1.damage          = int(h_dmg)
		s1.target_hp_after = int(e_hp)
		s1.is_killing_blow = (e_hp <= 0.0)
		steps.append(s1)
		if e_hp <= 0.0:
			break

		# ── Riposte de l'ennemi ───────────────────────────────
		var e_dmg := _calc(enemy_atk, hero_def, ENEMY_MIN_DAMAGE)
		h_hp = maxf(h_hp - e_dmg, 0.0)
		var s2 := CombatStep.new()
		s2.attacker        = "enemy"
		s2.damage          = int(e_dmg)
		s2.target_hp_after = int(h_hp)
		s2.is_killing_blow = (h_hp <= 0.0)
		steps.append(s2)

	return steps

static func _calc(atk: float, def: float, min_dmg: float) -> float:
	return maxf(atk * randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE) - def, min_dmg)
