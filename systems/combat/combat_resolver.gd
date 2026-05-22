# ============================================================
# CombatResolver — Résolution instantanée d'un combat VIT-based.
#
# Chaque entité accumule +VIT par tick dans sa jauge d'action.
# Quand jauge >= GAUGE_THRESHOLD, l'entité attaque et la jauge revient à 0.
# En cas d'égalité simultanée, le Héro agit en premier.
# ============================================================
class_name CombatResolver

const GAUGE_THRESHOLD:  float = 100.0
const CRIT_CHANCE:      float = 0.10
const CRIT_MULTIPLIER:  float = 2.0
const MAX_STEPS:        int   = 500

# hero_stats et enemy_stats : dictionnaires avec clés hp, atk, def, vit
static func resolve(hero_stats: Dictionary, enemy_stats: Dictionary) -> Array:
	var steps: Array = []

	var h_hp  := float(hero_stats.get("hp",  100))
	var h_atk := float(hero_stats.get("atk", 10))
	var h_def := float(hero_stats.get("def", 5))
	var h_vit := maxf(float(hero_stats.get("vit", 20)), 1.0)

	var e_hp  := float(enemy_stats.get("hp",  50))
	var e_atk := float(enemy_stats.get("atk", 8))
	var e_def := float(enemy_stats.get("def", 2))
	var e_vit := maxf(float(enemy_stats.get("vit", 20)), 1.0)

	var h_gauge := 0.0
	var e_gauge := 0.0
	var current_tick := 0

	while h_hp > 0.0 and e_hp > 0.0 and steps.size() < MAX_STEPS:
		current_tick += 1
		h_gauge += h_vit
		e_gauge += e_vit

		# Héro a priorité si les deux jauges atteignent le seuil simultanément
		if h_gauge >= GAUGE_THRESHOLD:
			h_gauge -= GAUGE_THRESHOLD
			var step := _make_step("hero", h_atk, h_def, e_atk, e_def, e_hp)
			step.tick_time = current_tick
			e_hp = float(step.target_hp_after)
			steps.append(step)
			if e_hp <= 0.0:
				break

		if e_gauge >= GAUGE_THRESHOLD and h_hp > 0.0:
			e_gauge -= GAUGE_THRESHOLD
			var step := _make_step("enemy", e_atk, e_def, h_atk, h_def, h_hp)
			step.tick_time = current_tick
			h_hp = float(step.target_hp_after)
			steps.append(step)

	return steps

static func _make_step(
		attacker: String,
		atk: float, _own_def: float,
		_enemy_atk: float, target_def: float,
		target_hp: float
	) -> CombatStep:

	var is_crit := randf() < CRIT_CHANCE
	var base_dmg := maxf(atk - target_def, 1.0)
	var damage := base_dmg * (CRIT_MULTIPLIER if is_crit else 1.0)
	var new_hp := maxf(target_hp - damage, 0.0)

	var step := CombatStep.new()
	step.attacker        = attacker
	step.damage          = int(damage)
	step.target_hp_after = int(new_hp)
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	return step
