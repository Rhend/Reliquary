# ============================================================
# CombatResolver — Résolution instantanée d'un combat VIT-based.
#
# Chaque entité accumule +VIT par tick dans sa jauge d'action.
# Quand jauge >= GAUGE_THRESHOLD, l'entité attaque et la jauge
# revient à 0. En cas d'égalité simultanée, le Héro agit en premier.
#
# Usage : CombatResolver.resolve(hero_stats, enemy_stats) → Array[CombatStep]
# Les deux dictionnaires attendent les clés : hp, atk, def, vit.
# ============================================================
class_name CombatResolver

const GAUGE_THRESHOLD: float = 100.0  # valeur à atteindre pour déclencher une attaque
const CRIT_CHANCE:     float = 0.10   # probabilité de coup critique (10 %)
const CRIT_MULTIPLIER: float = 2.0    # multiplicateur de dégâts sur un coup critique
const MAX_STEPS:       int   = 500    # garde-fou anti-boucle infinie

# Résout un combat complet entre le héro et un ennemi.
# Retourne un tableau ordonné de CombatStep prêts à être joués par CombatPlayer.
#
# options acceptés :
#   "ambush" (bool)  — tour ennemi gratuit avant le cycle VIT normal (Forêt Sombre)
#   "poison" (bool)  — poison appliqué à chaque attaque héro, tick après chaque attaque ennemie (Marécage Putride)
static func resolve(hero_stats: Dictionary, enemy_stats: Dictionary,
		options: Dictionary = {}) -> Array:
	var steps: Array = []

	var h_hp  := float(hero_stats.get("hp",  100))
	var h_atk := float(hero_stats.get("atk", 10))
	var h_def := float(hero_stats.get("def", 5))
	var h_vit := maxf(float(hero_stats.get("vit", 20)), 1.0)  # minimum 1 pour éviter une division par zéro

	var e_hp  := float(enemy_stats.get("hp",  50))
	var e_atk := float(enemy_stats.get("atk", 8))
	var e_def := float(enemy_stats.get("def", 2))
	var e_vit := maxf(float(enemy_stats.get("vit", 20)), 1.0)

	var use_ambush: bool  = options.get("ambush", false)
	var use_poison: bool  = options.get("poison", false)
	var poison_dmg_per_stack: float = h_atk * 0.05  # 5 % ATK héro par stack

	var poison_stacks:     int = 0
	var poison_turns_left: int = 0

	# ── Tour d'embuscade (Forêt Sombre) ─────────────────────────
	# L'ennemi attaque une fois avant que les jauges VIT ne démarrent.
	if use_ambush:
		var ambush_step := _make_step("enemy", e_atk, e_def, h_atk, h_def, h_hp)
		ambush_step.tick_time = 0
		ambush_step.is_ambush = true
		h_hp = float(ambush_step.target_hp_after)
		steps.append(ambush_step)
		if h_hp <= 0.0:
			return steps

	var h_gauge := 0.0      # jauge d'action du héro (se remplit de +h_vit par tick)
	var e_gauge := 0.0      # jauge d'action de l'ennemi
	var current_tick := 0   # compteur de ticks absolus depuis le début du combat

	while h_hp > 0.0 and e_hp > 0.0 and steps.size() < MAX_STEPS:
		current_tick += 1
		h_gauge += h_vit
		e_gauge += e_vit

		# Le héro a la priorité si les deux jauges atteignent le seuil au même tick
		if h_gauge >= GAUGE_THRESHOLD:
			h_gauge -= GAUGE_THRESHOLD
			var step := _make_step("hero", h_atk, h_def, e_atk, e_def, e_hp)
			step.tick_time = current_tick
			e_hp = float(step.target_hp_after)
			steps.append(step)

			# Poison : chaque attaque héro incrémente les stacks (max 3) et remet la durée à 3
			if use_poison and e_hp > 0.0:
				poison_stacks     = mini(poison_stacks + 1, 3)
				poison_turns_left = 3

			if e_hp <= 0.0:
				break

		if e_gauge >= GAUGE_THRESHOLD and h_hp > 0.0:
			e_gauge -= GAUGE_THRESHOLD
			var step := _make_step("enemy", e_atk, e_def, h_atk, h_def, h_hp)
			step.tick_time = current_tick
			h_hp = float(step.target_hp_after)
			steps.append(step)

			# Tick de poison après chaque attaque ennemie
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

	return steps

# Crée un CombatStep pour une attaque donnée.
# _own_def et _enemy_atk sont réservés pour de futurs mécanismes
# (réflexion de dégâts, contre-attaque) ; ils n'interviennent pas dans le calcul actuel.
static func _make_step(
		attacker:    String,
		atk:         float,
		_own_def:    float,   # réservé — futur: contre-attaque / réflexion
		_enemy_atk:  float,   # réservé — futur: contre-attaque / réflexion
		target_def:  float,
		target_hp:   float
	) -> CombatStep:

	var is_crit  := randf() < CRIT_CHANCE
	var base_dmg := maxf(atk - target_def, 1.0)                          # minimum 1 dégât
	var damage   := base_dmg * (CRIT_MULTIPLIER if is_crit else 1.0)
	var new_hp   := maxf(target_hp - damage, 0.0)

	var step := CombatStep.new()
	step.attacker        = attacker
	step.damage          = int(damage)
	step.target_hp_after = int(new_hp)
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	return step
