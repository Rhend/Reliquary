# ============================================================
# CombatResolver — Résolution instantanée d'un combat VIT-based.
#
# Chaque entité accumule +VIT par tick dans sa jauge d'action.
# Quand jauge >= GAUGE_THRESHOLD, l'entité attaque et la jauge
# revient à 0. En cas d'égalité simultanée, le Héro agit en premier.
#
# Usage : CombatResolver.resolve(hero_stats, enemy_stats) → Array[CombatStep]
# hero_stats attend : hp, hp_max, atk, def, vit.
# enemy_stats attend : hp, atk, def, vit.
#
# Options supplémentaires (options dict) :
#   "ambush"         (bool)   — tour ennemi gratuit avant le cycle VIT
#   "poison"         (bool)   — poison biome (Marécage Putride)
#   "passive_shield" (dict)   — config bouclier d'urgence (Résilience Rare+)
#   "passive_poison" (dict)   — config poison on-hit (Contact Venimeux Rare+)
# ============================================================
class_name CombatResolver

const GAUGE_THRESHOLD: float = 100.0
const CRIT_CHANCE:     float = 0.10
const CRIT_MULTIPLIER: float = 2.0
const MAX_STEPS:       int   = 500

static func resolve(hero_stats: Dictionary, enemy_stats: Dictionary,
		options: Dictionary = {}) -> Array:
	var steps: Array = []

	var h_hp     := float(hero_stats.get("hp",     100))
	var h_hp_max := float(hero_stats.get("hp_max", h_hp))  # pour le seuil du bouclier
	var h_atk    := float(hero_stats.get("atk",    10))
	var h_def    := float(hero_stats.get("def",    5))
	var h_vit    := maxf(float(hero_stats.get("vit", 20)), 1.0)

	var e_hp  := float(enemy_stats.get("hp",  50))
	var e_atk := float(enemy_stats.get("atk", 8))
	var e_def := float(enemy_stats.get("def", 2))
	var e_vit := maxf(float(enemy_stats.get("vit", 20)), 1.0)

	# ── Options mécaniques ─────────────────────────────────────
	var use_ambush: bool = options.get("ambush", false)

	# Poison biome (Marécage Putride)
	var use_poison:           bool  = options.get("poison", false)
	var poison_dmg_per_stack: float = h_atk * 0.05
	var poison_stacks:        int   = 0
	var poison_turns_left:    int   = 0

	# Bouclier d'urgence (Résilience Rare+)
	var shield_cfg       := options.get("passive_shield", {}) as Dictionary
	var h_shield:        float = 0.0
	var shield_available: bool = false
	var shield_threshold: float = 0.30
	var shield_value_pct: float = 0.0
	if not shield_cfg.is_empty() and shield_cfg.get("available", false):
		shield_available  = true
		shield_threshold  = float(shield_cfg.get("threshold", 0.30))
		shield_value_pct  = float(shield_cfg.get("value_pct", 0.15))

	# Poison passif (Contact Venimeux Rare+)
	var pp_cfg          := options.get("passive_poison", {}) as Dictionary
	var use_passive_poison: bool  = not pp_cfg.is_empty()
	var pp_chance:       float = float(pp_cfg.get("chance",          0.0))
	var pp_dmg_per_turn: float = float(pp_cfg.get("damage_per_turn", 0.0))
	var pp_duration:     int   = int(pp_cfg.get("duration_turns",    2))
	# Tableau de poisons indépendants : [{damage: float, turns: int}]
	var passive_poisons: Array = []

	# ── Tour d'embuscade (Forêt Sombre) ─────────────────────────
	if use_ambush:
		var ambush_step := _make_enemy_step(e_atk, h_def, h_hp, h_shield)
		ambush_step.tick_time = 0
		ambush_step.is_ambush = true
		h_hp     = float(ambush_step.target_hp_after)
		h_shield = maxf(h_shield - float(ambush_step.shield_absorbed), 0.0)
		steps.append(ambush_step)
		if h_hp <= 0.0:
			return steps
		# Vérifier activation bouclier post-embuscade
		if shield_available and h_hp_max > 0.0 and h_hp / h_hp_max < shield_threshold:
			h_shield         = h_hp_max * shield_value_pct
			shield_available = false
			ambush_step.is_shield_proc = true
			ambush_step.shield_value   = int(h_shield)

	var h_gauge    := 0.0
	var e_gauge    := 0.0
	var current_tick := 0

	while h_hp > 0.0 and e_hp > 0.0 and steps.size() < MAX_STEPS:
		current_tick += 1
		h_gauge += h_vit
		e_gauge += e_vit

		# ── Tour héro ───────────────────────────────────────────
		if h_gauge >= GAUGE_THRESHOLD:
			h_gauge -= GAUGE_THRESHOLD
			var step := _make_hero_step(h_atk, e_def, e_hp)
			step.tick_time = current_tick
			e_hp = float(step.target_hp_after)
			steps.append(step)

			# Poison biome : chaque coup héro incrémente les stacks (max 3)
			if use_poison and e_hp > 0.0:
				poison_stacks     = mini(poison_stacks + 1, 3)
				poison_turns_left = 3

			# Poison passif : roll de proc sur chaque coup héro
			if use_passive_poison and e_hp > 0.0 and pp_chance > 0.0:
				if randf() < pp_chance:
					passive_poisons.append({"damage": pp_dmg_per_turn, "turns": pp_duration})
					step.passive_poison_proc = true

			if e_hp <= 0.0:
				break

		# ── Tour ennemi ─────────────────────────────────────────
		if e_gauge >= GAUGE_THRESHOLD and h_hp > 0.0:
			e_gauge -= GAUGE_THRESHOLD
			var step := _make_enemy_step(e_atk, h_def, h_hp, h_shield)
			step.tick_time = current_tick
			h_hp     = float(step.target_hp_after)
			h_shield = maxf(h_shield - float(step.shield_absorbed), 0.0)
			steps.append(step)

			# Vérifier déclenchement bouclier post-coup ennemi
			if shield_available and h_hp > 0.0 and h_hp_max > 0.0:
				if h_hp / h_hp_max < shield_threshold:
					h_shield         = h_hp_max * shield_value_pct
					shield_available = false
					step.is_shield_proc = true
					step.shield_value   = int(h_shield)

			# Tick poison biome après coup ennemi
			if use_poison and poison_stacks > 0 and e_hp > 0.0:
				var pdmg     := float(poison_stacks) * poison_dmg_per_stack
				var new_e_hp := maxf(e_hp - pdmg, 0.0)
				var p_step   := CombatStep.new()
				p_step.is_poison       = true
				p_step.damage          = int(maxf(roundf(pdmg), 1.0))
				p_step.target_hp_after = int(roundf(new_e_hp))
				p_step.is_killing_blow = (new_e_hp <= 0.0)
				p_step.tick_time       = current_tick
				steps.append(p_step)
				e_hp = new_e_hp

				poison_turns_left -= 1
				if poison_turns_left <= 0:
					poison_stacks     = 0
					poison_turns_left = 0

				if e_hp <= 0.0:
					break

			# Tick de tous les poisons passifs actifs après coup ennemi
			if use_passive_poison and passive_poisons.size() > 0 and e_hp > 0.0:
				var to_remove: Array = []
				for i in passive_poisons.size():
					var pp: Dictionary = passive_poisons[i]
					if e_hp <= 0.0:
						break
					var pdmg     := float(pp["damage"])
					var new_e_hp := maxf(e_hp - pdmg, 0.0)
					var p_step   := CombatStep.new()
					p_step.is_passive_poison = true
					p_step.damage            = int(maxf(roundf(pdmg), 1.0))
					p_step.target_hp_after   = int(roundf(new_e_hp))
					p_step.is_killing_blow   = (new_e_hp <= 0.0)
					p_step.tick_time         = current_tick
					steps.append(p_step)
					e_hp = new_e_hp

					pp["turns"] -= 1
					if pp["turns"] <= 0:
						to_remove.append(i)

				# Retirer les poisons expirés (en ordre décroissant pour préserver les indices)
				for i in range(to_remove.size() - 1, -1, -1):
					passive_poisons.remove_at(to_remove[i])

				if e_hp <= 0.0:
					break

	return steps

# ─── Factories de steps ─────────────────────────────────────

# Step héro : dégâts simples sur l'ennemi (pas de bouclier côté ennemi).
static func _make_hero_step(atk: float, target_def: float, target_hp: float) -> CombatStep:
	var is_crit  := randf() < CRIT_CHANCE
	var base_dmg := maxf(atk - target_def, 1.0)
	var damage   := base_dmg * (CRIT_MULTIPLIER if is_crit else 1.0)
	var new_hp   := maxf(target_hp - damage, 0.0)

	var step := CombatStep.new()
	step.attacker        = "hero"
	step.damage          = int(damage)
	step.target_hp_after = int(new_hp)
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	return step

# Step ennemi : dégâts avec absorption bouclier héro.
# shield_absorbed est mis à jour dans le step ; les HP héro réels = target_hp - (raw - absorbed).
static func _make_enemy_step(atk: float, target_def: float,
		target_hp: float, current_shield: float) -> CombatStep:
	var is_crit  := randf() < CRIT_CHANCE
	var base_dmg := maxf(atk - target_def, 1.0)
	var raw_dmg  := base_dmg * (CRIT_MULTIPLIER if is_crit else 1.0)

	# Absorption bouclier
	var absorbed  := minf(raw_dmg, current_shield)
	var actual_dmg := raw_dmg - absorbed
	var new_hp    := maxf(target_hp - actual_dmg, 0.0)

	var step := CombatStep.new()
	step.attacker        = "enemy"
	step.damage          = int(actual_dmg)   # dégâts réels reçus par les HP
	step.target_hp_after = int(new_hp)
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	step.shield_absorbed = int(absorbed)
	return step
