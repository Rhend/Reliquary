# ============================================================
# CombatResolver — Résolution d'un combat ATB horodaté en secondes réelles.
#
# `vit` exprime une cadence d'attaques par SECONDE (aps = vit / Balance.VIT_PER_APS).
# Chaque combattant accumule `aps` dans sa jauge d'action au fil du temps simulé ;
# il frappe quand la jauge atteint Balance.ATTACK_GAUGE (= 1 attaque), puis le
# seuil est retiré (le surplus est conservé → aucune fraction de cadence perdue).
# Chaque CombatStep porte son instant réel (time_sec, en secondes).
#
# Simultanéité : si les deux atteignent leur seuil à moins de
# Balance.SIMULTANEITY_EPS secondes l'un de l'autre, le HÉROS frappe en premier.
# Conséquence assumée : un combattant rapide (aps 1,3) peut frapper deux fois
# avant qu'un lent (aps 0,7) ne frappe une fois.
#
# Usage : CombatResolver.resolve(hero_stats, enemy_stats) → Array[CombatStep]
# hero_stats attend : hp, hp_max, atk, def, vit.
# enemy_stats attend : hp, atk, def, vit.
#
# Options supplémentaires (options dict) :
#   "ambush"         (bool)   — tour ennemi gratuit avant le cycle VIT
#   "poison"         (bool)   — poison biome (Marécage Putride), horloge temps réel
#   "endurcissement" (bool)   — dégâts héros −20 % (Montagne Rare+)
#   "passive_poison" (dict)   — config poison on-hit (Contact Venimeux Rare+)
# ============================================================
class_name CombatResolver

# Équilibrage centralisé dans Balance.gd (jauge, critique, dégâts min,
# poison de biome temps réel).
const MAX_STEPS: int = 500  # garde-fou anti-boucle infinie (non-balance)

static func resolve(hero_stats: Dictionary, enemy_stats: Dictionary,
		options: Dictionary = {}) -> Array:
	var steps: Array = []

	var h_hp     := float(hero_stats.get("hp",     100))
	var h_hp_max := float(hero_stats.get("hp_max", h_hp))  # pour les conditions de PV (Élan)
	var h_atk    := float(hero_stats.get("atk",    10))
	var h_def    := float(hero_stats.get("def",    5))
	# vit brute → cadence en attaques/seconde (référentiel ATB temps réel).
	var h_aps    := maxf(float(hero_stats.get("vit", 20)) / Balance.VIT_PER_APS, Balance.APS_MIN)
	var h_crit_chance: float = float(hero_stats.get("crit_chance",     Balance.CRIT_CHANCE))
	var h_crit_mult:   float = float(hero_stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER))

	var e_hp  := float(enemy_stats.get("hp",  50))
	var e_atk := float(enemy_stats.get("atk", 8))
	var e_def := float(enemy_stats.get("def", 2))
	var e_aps := maxf(float(enemy_stats.get("vit", 20)) / Balance.VIT_PER_APS, Balance.APS_MIN)
	var e_crit_chance: float = float(enemy_stats.get("crit_chance",     Balance.CRIT_CHANCE))
	var e_crit_mult:   float = float(enemy_stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER))

	# ── Options mécaniques ─────────────────────────────────────
	var use_ambush: bool = options.get("ambush", false)

	# Jauge ATB de DÉPART du héros (Tour de Guet) : fraction 0..1 du seuil d'une
	# attaque. > 0 → le héros frappe plus tôt (atténue l'embuscade, ou avance le
	# 1er coup sur toute expédition au palier Tour T5).
	var hero_gauge_start: float = clampf(float(options.get("hero_gauge_start", 0.0)), 0.0, 1.0)

	# Filet « 1er coup létal annulé » (Palissade T5) : le premier coup qui amènerait
	# le héros à 0 PV le laisse à 1 PV à la place. Usage UNIQUE — décrémenté ici
	# pour la durée du combat ; la consommation à l'échelle de l'EXPÉDITION est
	# gérée par AdventureSystem (qui ne le repasse plus une fois utilisé).
	var lethal_avail: bool = options.get("ignore_lethal", false)

	# Rail de modification de vitesse : listes de modificateurs {factor, additive,
	# start, duration} par combattant. factor = multiplicatif (défaut 1,0),
	# additive = +att/s (défaut 0,0). duration < 0 → permanent sur le combat ;
	# sinon fenêtre temporaire de `duration` secondes à partir de `start`.
	# N'importe quel effet (bénédiction, piège, équipement, biome, passif) peut
	# pousser un modificateur ici — aucune mécanique codée en dur.
	var h_mods: Array = options.get("hero_speed_mods",  [])
	var e_mods: Array = options.get("enemy_speed_mods", [])

	# Endurcissement biome (Montagne). Le contre-mitigation de Forge (Fendoir) ne
	# s'applique QUE sous Endurcissement : dégâts héros ×(1 + counter) dans ce cas.
	var use_endurcissement:   bool  = options.get("endurcissement", false)
	var endur_counter:        float = float(options.get("endurcissement_counter_pct", 0.0))
	var endurcissement_mult:  float = (1.0 - Balance.MONTAGNE_ENDURCISSEMENT_REDUCTION) * (1.0 + endur_counter) if use_endurcissement else 1.0

	# Nœuds de Forge sur les coups du héros : ignore une fraction de la DEF ennemie
	# (Briseur de garde), et bonus d'ATK conditionnel selon les PV (Élan).
	var hero_def_ignore: float = clampf(float(options.get("hero_def_ignore_pct", 0.0)), 0.0, 1.0)
	var cond_atk_list:   Array  = options.get("cond_atk_hp_above", [])

	# Poison biome (Marécage Putride) — mécanique HOSTILE : le marais toxique
	# empoisonne le HÉROS (et non l'inverse). Chaque coup ennemi applique un STACK
	# de venin ; une horloge GLOBALE temps réel (par cible) ronge ensuite les PV du
	# héros tous les BIOME_POISON_TICK_INTERVAL secondes, des dégâts proportionnels
	# au nombre de stacks vivants à l'instant du tic. Dégâts basés sur l'ATK de
	# l'ennemi (sa morsure venimeuse). Source : Référentiel des statistiques de combat.
	var use_poison:           bool  = options.get("poison", false)
	var poison_dmg_per_stack: float = e_atk * Balance.BIOME_POISON_DMG_PCT
	# Stacks vivants = liste des instants d'EXPIRATION (application + STACK_DURATION).
	var poison_stack_expiries: Array = []
	# Prochain tic de l'horloge globale (INF = horloge arrêtée, aucun stack vivant).
	var poison_next_tick: float = INF
	# Atténuation du venin de biome (Jardin T2) : N stacks effectifs en moins.
	var poison_stack_reduction: int = int(options.get("poison_stack_reduction", 0))

	# Poison passif (Contact Venimeux Rare+)
	var pp_cfg          := options.get("passive_poison", {}) as Dictionary
	var use_passive_poison: bool  = not pp_cfg.is_empty()
	var pp_chance:       float = float(pp_cfg.get("chance",          0.0))
	var pp_dmg_per_turn: float = float(pp_cfg.get("damage_per_turn", 0.0))
	var pp_duration:     int   = int(pp_cfg.get("duration_turns",    2))
	# Tableau de poisons indépendants : [{damage: float, turns: int}]
	var passive_poisons: Array = []

	# ── Embuscade (Forêt Sombre) : jauge ennemie pleine au départ ──
	# Plus de « tour gratuit » hors cycle : la créature démarre sa jauge ATB au
	# seuil d'une attaque, donc elle frappe à t = 0 (avant le héros). Exprimé
	# proprement dans le modèle de jauge temps réel. Cohérent avec la simultanéité
	# (jauge ennemie pleine → e_dt = 0 < h_dt → l'ennemi garde l'initiative).
	var h_gauge  := Balance.ATTACK_GAUGE * hero_gauge_start
	var e_gauge: float = Balance.ATTACK_GAUGE if use_ambush else 0.0
	var sim_time := 0.0
	var ambush_pending := use_ambush   # marque le 1er coup ennemi comme is_ambush (tag visuel)

	# ── Boucle ATB horodatée en secondes ───────────────────────
	# Jauge d'action en ATTAQUES (seuil Balance.ATTACK_GAUGE). À chaque itération,
	# on avance jusqu'au PROCHAIN événement : soit un combattant atteint son seuil
	# (il frappe, surplus conservé), soit une frontière de modificateur de vitesse
	# est franchie (l'aps change, pas de frappe). L'aps effectif intègre le rail
	# de vitesse (_effective_aps). Sur quasi-égalité (≤ SIMULTANEITY_EPS), le héros
	# est prioritaire — l'ennemi frappe alors à l'itération suivante (dt ≈ 0).
	while h_hp > 0.0 and e_hp > 0.0 and steps.size() < MAX_STEPS:
		var h_aps_t := _effective_aps(h_aps, h_mods, sim_time)
		var e_aps_t := _effective_aps(e_aps, e_mods, sim_time)
		# Secondes avant que chacun n'atteigne le seuil d'une attaque (à aps courant).
		var h_dt := (Balance.ATTACK_GAUGE - h_gauge) / h_aps_t
		var e_dt := (Balance.ATTACK_GAUGE - e_gauge) / e_aps_t
		var hero_first := h_dt <= e_dt + Balance.SIMULTANEITY_EPS
		var strike_dt := h_dt if hero_first else e_dt

		# Événements « avance seule » (pas de frappe) : frontière de modificateur de
		# vitesse (l'aps change) OU tic de l'horloge de poison de biome. On prend le
		# plus proche ; s'il précède la prochaine frappe, on avance le temps/les jauges
		# jusque-là puis on recommence (recalcul des aps après une frontière, dégâts
		# de venin après un tic).
		var bnd_t := minf(_next_mod_boundary(h_mods, sim_time), _next_mod_boundary(e_mods, sim_time))
		var bnd_dt := bnd_t - sim_time
		var poison_dt := poison_next_tick - sim_time if poison_next_tick < INF else INF
		var adv_is_poison := poison_dt < bnd_dt
		var adv_dt := poison_dt if adv_is_poison else bnd_dt
		if adv_dt < strike_dt - 1.0e-9:
			sim_time += adv_dt
			h_gauge  += h_aps_t * adv_dt
			e_gauge  += e_aps_t * adv_dt
			if adv_is_poison:
				# ── Tic de l'horloge de poison de biome (cible = héros) ──
				# Dégâts = % ATK source × stacks VIVANTS à cet instant (≤ MAX),
				# atténués par le Jardin (T2). Le venin ignore tout (mécanique hostile).
				var living := 0
				for ex in poison_stack_expiries:
					if float(ex) >= sim_time - 1.0e-9:
						living += 1
				var eff_stacks := maxi(mini(living, Balance.BIOME_POISON_MAX_STACKS) - poison_stack_reduction, 0)
				if eff_stacks > 0 and h_hp > 0.0:
					var pdmg     := float(eff_stacks) * poison_dmg_per_stack
					var new_h_hp := maxf(h_hp - pdmg, 0.0)
					var p_step   := CombatStep.new()
					p_step.is_poison       = true
					p_step.attacker        = Enums.Actor.ENEMY   # dégâts subis par le héros
					p_step.damage          = int(maxf(roundf(pdmg), 1.0))
					p_step.target_hp_after = int(roundf(new_h_hp))
					p_step.is_killing_blow = (new_h_hp <= 0.0)
					p_step.time_sec        = sim_time
					# Filet anti-mort (Palissade T5) : le venin létal laisse le héros à 1 PV.
					if lethal_avail and new_h_hp <= 0.0:
						new_h_hp                 = 1.0
						p_step.target_hp_after   = 1
						p_step.is_killing_blow   = false
						p_step.is_lethal_ignored = true
						lethal_avail             = false
					steps.append(p_step)
					h_hp = new_h_hp
				# Retirer les stacks dont c'était le dernier tic, puis replanifier
				# l'horloge (ou l'arrêter s'il ne reste aucun stack vivant).
				var still_alive: Array = []
				for ex in poison_stack_expiries:
					if float(ex) > sim_time + 1.0e-9:
						still_alive.append(ex)
				poison_stack_expiries = still_alive
				poison_next_tick = sim_time + Balance.BIOME_POISON_TICK_INTERVAL if not poison_stack_expiries.is_empty() else INF
			continue

		# Avance le temps simulé et les deux jauges (l'un atteint pile le seuil).
		sim_time += strike_dt
		h_gauge  += h_aps_t * strike_dt
		e_gauge  += e_aps_t * strike_dt

		if hero_first:
			# ── Tour héros ───────────────────────────────────────
			h_gauge -= Balance.ATTACK_GAUGE
			# ATK conditionnelle (Élan : +% si PV > seuil) évaluée sur les PV courants.
			var h_atk_eff := h_atk
			if h_hp_max > 0.0 and not cond_atk_list.is_empty():
				var hp_frac := h_hp / h_hp_max
				for c: Dictionary in cond_atk_list:
					if hp_frac > float(c.get("hp_frac", 1.0)):
						h_atk_eff *= (1.0 + float(c.get("pct", 0.0)))
			# DEF ennemie ignorée d'une fraction (Briseur de garde).
			var step := _make_hero_step(h_atk_eff, e_def * (1.0 - hero_def_ignore), e_hp, h_crit_chance, h_crit_mult, endurcissement_mult)
			step.time_sec = sim_time
			e_hp = float(step.target_hp_after)
			steps.append(step)

			# Poison passif : roll de proc sur chaque coup héros
			if use_passive_poison and e_hp > 0.0 and pp_chance > 0.0:
				if randf() < pp_chance:
					passive_poisons.append({"damage": pp_dmg_per_turn, "turns": pp_duration})
					step.passive_poison_proc = true

			if e_hp <= 0.0:
				break
		else:
			# ── Tour ennemi ──────────────────────────────────────
			e_gauge -= Balance.ATTACK_GAUGE
			var step := _make_enemy_step(e_atk, h_def, h_hp, e_crit_chance, e_crit_mult)
			step.time_sec = sim_time
			# Le tout premier coup ennemi sous Embuscade est tagué is_ambush (frappe
			# à t = 0 via la jauge pleine). Tag visuel seulement, coup normal.
			if ambush_pending:
				step.is_ambush = true
				ambush_pending = false
			h_hp     = float(step.target_hp_after)
			# Filet anti-mort (Palissade T5) : ce coup létal laisse le héros à 1 PV.
			if lethal_avail and h_hp <= 0.0:
				h_hp                   = 1.0
				step.target_hp_after   = 1
				step.is_killing_blow   = false
				step.is_lethal_ignored = true
				lethal_avail           = false
			steps.append(step)

			# Poison biome (Marécage) : le coup ennemi APPLIQUE un stack de venin sur
			# le héros (durée de vie propre) et démarre l'horloge globale si besoin.
			# Les dégâts ne tombent QU'aux tics de l'horloge (cf. branche d'avance
			# ci-dessus). Mécanique HOSTILE : la cible est le héros.
			if use_poison and h_hp > 0.0:
				poison_stack_expiries.append(sim_time + Balance.BIOME_POISON_STACK_DURATION)
				# Plafond de stacks : retirer le plus ancien (expiration la plus proche).
				if poison_stack_expiries.size() > Balance.BIOME_POISON_MAX_STACKS:
					poison_stack_expiries.sort()
					poison_stack_expiries.pop_front()
				# Démarrer l'horloge globale si elle est à l'arrêt.
				if poison_next_tick == INF:
					poison_next_tick = sim_time + Balance.BIOME_POISON_TICK_INTERVAL

			if h_hp <= 0.0:
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
					p_step.time_sec          = sim_time
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

# ─── Rail de vitesse : aps effectif & frontières de fenêtres ──

# aps effectif d'un combattant à l'instant `t` : base × produit des facteurs
# multiplicatifs actifs + somme des bonus additifs actifs. Un modificateur est
# actif si t ∈ [start, start+duration) (duration < 0 = permanent). Planché à APS_MIN.
static func _effective_aps(base_aps: float, mods: Array, t: float) -> float:
	var mult := 1.0
	var add  := 0.0
	for m: Dictionary in mods:
		if _mod_active(m, t):
			mult *= float(m.get("factor", 1.0))
			add  += float(m.get("additive", 0.0))
	return maxf(base_aps * mult + add, Balance.APS_MIN)

static func _mod_active(m: Dictionary, t: float) -> bool:
	var start: float = float(m.get("start", 0.0))
	var dur:   float = float(m.get("duration", -1.0))
	if t < start - 1.0e-9:
		return false
	return dur < 0.0 or t < start + dur

# Instant de la prochaine frontière de fenêtre (début ou fin d'un modificateur)
# strictement après `t`, ou INF si aucune. Sert à découper le temps en tranches
# d'aps constant pour une accumulation de jauge exacte.
static func _next_mod_boundary(mods: Array, t: float) -> float:
	var next := INF
	for m: Dictionary in mods:
		var start: float = float(m.get("start", 0.0))
		var dur:   float = float(m.get("duration", -1.0))
		if start > t + 1.0e-9:
			next = minf(next, start)
		if dur >= 0.0:
			var end_t := start + dur
			if end_t > t + 1.0e-9:
				next = minf(next, end_t)
	return next

# ─── Factories de steps ─────────────────────────────────────

# Step héros : dégâts simples sur l'ennemi (pas de bouclier côté ennemi).
# Atténuation par la DEF via Balance.mitigated_damage (réduction monotone saturante),
# puis crit / endurcissement en multiplicateurs. Arrondi entier au moment
# d'appliquer aux PV (recommandation du référentiel ; cohérent avec les ticks
# de poison qui arrondissent déjà). Plancher MIN_DAMAGE garanti après crit/mult.
static func _make_hero_step(atk: float, target_def: float, target_hp: float,
		crit_chance: float, crit_mult: float, dmg_mult: float = 1.0) -> CombatStep:
	var is_crit := randf() < crit_chance
	var raw     := Balance.mitigated_damage(atk, target_def) * (crit_mult if is_crit else 1.0) * dmg_mult
	var damage  := int(roundf(maxf(raw, Balance.MIN_DAMAGE)))
	var new_hp  := maxf(target_hp - float(damage), 0.0)

	var step := CombatStep.new()
	step.attacker        = Enums.Actor.HERO
	step.damage          = damage
	step.target_hp_after = int(roundf(new_hp))
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	return step

# Step ennemi : dégâts simples sur le héros (DEF = seul levier défensif).
static func _make_enemy_step(atk: float, target_def: float,
		target_hp: float, crit_chance: float, crit_mult: float) -> CombatStep:
	var is_crit  := randf() < crit_chance
	var raw      := Balance.mitigated_damage(atk, target_def) * (crit_mult if is_crit else 1.0)
	var damage   := int(roundf(maxf(raw, Balance.MIN_DAMAGE)))
	var new_hp   := maxf(target_hp - float(damage), 0.0)

	var step := CombatStep.new()
	step.attacker        = Enums.Actor.ENEMY
	step.damage          = damage
	step.target_hp_after = int(roundf(new_hp))
	step.is_killing_blow = (new_hp <= 0.0)
	step.is_crit         = is_crit
	return step
