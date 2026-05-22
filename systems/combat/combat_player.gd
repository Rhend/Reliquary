# ============================================================
# CombatPlayer — Lecteur cosmétique d'une séquence de combat.
#
# 1. AdventureSystem appelle start_combat() avec l'ennemi et les HP courants.
# 2. CombatPlayer délègue à CombatResolver (résolution VIT-based instantanée).
# 3. Les steps sont joués un par un à cadence GameSettings.combat_speed.
# 4. Chaque step émet step_started / step_ended pour piloter l'UI.
# 5. En fin de séquence, combat_finished est émis ET relayé via EventBus.
# ============================================================
extends Node

const TICK_DURATION:    float = 0.16   # secondes par tick (VIT=20 → attaque toutes les 5 ticks = 0.8 s)
const MIN_STEP_DURATION: float = 0.20  # durée minimale entre deux steps pour que l'animation soit lisible

# Émis au début de chaque step, avant l'attente — l'UI doit déclencher les animations ici.
signal step_started(step: CombatStep)
# Émis à la fin du délai d'un step — l'UI peut clore les animations ici.
signal step_ended(step: CombatStep)
# Émis une fois la séquence entière jouée. winner vaut "hero" ou "enemy".
signal combat_finished(winner: String)

# ─── État runtime ────────────────────────────────────────────

var _steps:            Array      = []   # séquence de CombatStep produite par CombatResolver
var _index:            int        = 0    # index du step en cours de lecture
var _prev_tick:        int        = 0    # tick du dernier step joué — sert à calculer le délai entre steps
var _timer:            Timer             # timer one-shot qui cadence le playback
var _current_hero_hp:  float      = 0.0 # HP héro mis à jour au fil des steps (pour EventBus et fin de combat)
var _current_enemy_hp: float      = 0.0 # HP ennemi mis à jour au fil des steps
var _enemy_dict:       Dictionary = {}  # données brutes de l'ennemi combattu (transmises à combat_ended)

# Vrai si le timer est actif, c'est-à-dire qu'un combat est en cours de lecture.
var is_playing: bool:
	get: return _timer != null and not _timer.is_stopped()

# ═══════════════════════════════════════════════════════════
# Initialise le timer interne de playback.
func _ready() -> void:
	_timer          = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Lance un nouveau combat contre l'ennemi donné depuis les HP courants du héro.
# modifier_bonuses est un dictionnaire de multiplicateurs fourni par AdventureSystem (ex: atk_mult, def_mult).
func start_combat(enemy: Dictionary, current_hp: float,
		modifier_bonuses: Dictionary) -> void:
	var passives := PassiveSystem.get_combat_bonuses()
	var equip    := GameData.get_equipment_bonuses()
	var cid      := GameData.player.get("active_creature_id", "") as String
	var stats    := GameData.get_effective_stats(cid)

	var h_atk: float = (
		float(stats.get("atk", 0))
		+ float(passives.get("atk_bonus", 0.0))
		+ float(equip.get("atk", 0.0))
	) * float(modifier_bonuses.get("atk_mult", 1.0))
	var h_atk_mastery: float = GameData.get_mastery_combat_bonus(enemy.get("id", ""))
	h_atk += h_atk_mastery

	var h_def: float = (
		float(stats.get("def", 0))
		+ float(passives.get("def_bonus", 0.0))
		+ float(equip.get("def", 0.0))
	) * float(modifier_bonuses.get("def_mult", 1.0))
	var h_vit: float = float(stats.get("vit", 20))

	var e_hp := float(enemy.get("hp", 50))

	var hero_stats := {
		"hp":  current_hp,
		"atk": h_atk,
		"def": h_def,
		"vit": h_vit,
	}
	var enemy_stats := {
		"hp":  e_hp,
		"atk": float(enemy.get("atk", 8)),
		"def": float(enemy.get("def", 2)),
		"vit": float(enemy.get("vit", 20)),
	}

	_enemy_dict       = enemy
	_current_hero_hp  = current_hp
	_current_enemy_hp = e_hp
	_steps            = CombatResolver.resolve(hero_stats, enemy_stats)
	_index            = 0
	_prev_tick        = 0

	EventBus.combat_started.emit(cid, enemy, current_hp, e_hp)
	_play_next()

# Interrompt le playback immédiatement (ex: changement de scène en cours de combat).
func stop() -> void:
	if _timer:
		_timer.stop()

# ═══════════════════════════════════════════════════════════
#  Boucle de playback
# ═══════════════════════════════════════════════════════════

# Joue le step courant, calcule son délai et démarre le timer.
# Appelé récursivement via _on_timer jusqu'à épuisement des steps.
func _play_next() -> void:
	if _index >= _steps.size():
		_finish(_determine_winner())
		return

	var step: CombatStep = _steps[_index]

	if step.attacker == "hero":
		_current_enemy_hp = float(step.target_hp_after)
	else:
		_current_hero_hp = float(step.target_hp_after)

	step_started.emit(step)
	EventBus.combat_turn.emit(
		step.attacker, float(step.damage), _current_hero_hp, _current_enemy_hp
	)

	var ticks    := maxi(step.tick_time - _prev_tick, 1)
	_prev_tick    = step.tick_time
	var duration := float(ticks) * TICK_DURATION * GameSettings.combat_speed
	_timer.wait_time = maxf(duration, MIN_STEP_DURATION)
	_timer.start()

# Appelé à l'expiration du timer — clôt le step en cours et passe au suivant.
func _on_timer() -> void:
	step_ended.emit(_steps[_index])
	_index += 1
	_play_next()

# Clôt le combat : émet les signaux de fin avec le vainqueur et les HP résiduels.
func _finish(winner: String) -> void:
	combat_finished.emit(winner)
	EventBus.combat_ended.emit({
		"victory":               winner == "hero",
		"remaining_creature_hp": _current_hero_hp,
		"enemy":                 _enemy_dict
	})

# Détermine le vainqueur à partir du dernier step ou des HP résiduels.
func _determine_winner() -> String:
	if _steps.is_empty():
		return "hero"
	var last: CombatStep = _steps.back()
	if last.is_killing_blow:
		return "hero" if last.attacker == "hero" else "enemy"
	return "hero" if _current_enemy_hp <= _current_hero_hp else "enemy"
