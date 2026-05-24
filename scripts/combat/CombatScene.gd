# ============================================================
# CombatScene — Scène principale de combat.
#
# Layout :
#   InfoBar : XP cycle | Effets actifs | Équipement  (haut)
#   Circles : HeroCircle ←→ EnemyCircle (grands, DA village)
#   Footer  : bouton "Mettre fin à l'expédition"
#
# La barre d'action est dessinée directement dans CombatCircle
# via action_progress (0..1). CombatScene la pilote via tween.
# ============================================================
class_name CombatScene extends Control

# ─── Nœuds ───────────────────────────────────────────────────
var _hero_circle:  CombatCircle  # cercle du héro actif
var _enemy_circle: CombatCircle  # cercle de l'ennemi / piège / événement courant
var _flee_btn:     Button        # bouton "Mettre fin à l'expédition"

# Info bar
var _xp_value_label: Label          # label XP gagné ce cycle
var _buffs_vbox:     VBoxContainer  # liste des bonus actifs (passifs + équipement)
var _equip_vbox:     VBoxContainer  # liste des objets équipés

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:   float = 0.0   # XP accumulée depuis le début du cycle en cours
var _prev_tick:  int   = 0     # tick du dernier step vu — synchronise l'action bar avec CombatPlayer
var _navigating: bool  = false # garde-fou contre les doubles appels à change_scene_to_file

# ─── Idle (entre événements) ─────────────────────────────────
var _idle_label:   Label = null  # label "En exploration..." visible si attente > 1.2 s
var _idle_active:  bool  = false # vrai pendant l'état d'attente entre deux événements
var _idle_tw:      Tween = null  # tween du fade-in du label idle

# ─── Combat ───────────────────────────────────────────────────
var _combat_label: Label = null  # label "En combat..." affiché pendant un duel

# ─── Bonus Strike ─────────────────────────────────────────────
var _strike_widget: BonusStrikeWidget = null  # compteur de strikes en overlay top-right

# ═══════════════════════════════════════════════════════════
# Construit l'UI et connecte tous les signaux au démarrage.
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_signals()

# ═══════════════════════════════════════════════════════════
#  Construction de l'UI
# ═══════════════════════════════════════════════════════════

# Assemble les trois zones : info bar, cercles, footer + overlay summary.
func _build_ui() -> void:
	var root := UIHelpers.fullscreen_root(self)
	root.add_child(_build_info_bar())
	root.add_child(_build_circles_area())
	root.add_child(_build_footer())
	_build_strike_widget()

# ── Circles ────────────────────────────────────────────────

# Crée la zone centrale : cercles côte à côte + label idle en dessous.
func _build_circles_area() -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	_combat_label = Label.new()
	_combat_label.text = "En combat..."
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_label.add_theme_font_size_override("font_size", 17)
	_combat_label.add_theme_color_override("font_color", Color.WHITE)
	_combat_label.modulate.a = 0.0
	_combat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_combat_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 60)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	_hero_circle  = CombatCircle.new()
	_enemy_circle = CombatCircle.new()
	hbox.add_child(_hero_circle)
	hbox.add_child(_enemy_circle)

	_idle_label = Label.new()
	_idle_label.text = "En exploration..."
	_idle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle_label.add_theme_font_size_override("font_size", 17)
	_idle_label.add_theme_color_override("font_color", Color.WHITE)
	_idle_label.modulate.a = 0.0
	_idle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_idle_label)

	return center

# ── Footer ─────────────────────────────────────────────────

# Crée le bouton "Mettre fin à l'expédition" coloré selon le tier du héro actif.
func _build_footer() -> Control:
	var tcolor := _hero_tier_color()

	var m := UIHelpers.margin_of(8)

	_flee_btn = Button.new()
	_flee_btn.text                   = "⚔  Mettre fin à l'expédition"
	_flee_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_flee_btn.custom_minimum_size    = Vector2(0, 48)
	_flee_btn.add_theme_font_size_override("font_size", 16)
	_flee_btn.add_theme_color_override("font_color", tcolor)
	_flee_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	_flee_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	_flee_btn.pressed.connect(_on_flee_pressed)
	m.add_child(_flee_btn)
	return m

# ── Info bar : XP | Effets actifs | Équipement ─────────────

# Crée la rangée de trois panels en haut de scène.
func _build_info_bar() -> Control:
	var tcolor := _hero_tier_color()

	var outer := UIHelpers.margin_of(8)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	outer.add_child(hbox)

	hbox.add_child(UIHelpers.info_panel("◆  XP CE CYCLE",   tcolor, func(vb): _build_xp_section(vb)))
	hbox.add_child(UIHelpers.info_panel("◆  EFFETS ACTIFS", tcolor, func(vb): _build_buffs_section(vb)))
	hbox.add_child(UIHelpers.info_panel("◆  ÉQUIPEMENT",    tcolor, func(vb): _build_equip_section(vb)))

	return outer

# Crée le label XP du cycle dans le panel correspondant.
func _build_xp_section(parent: VBoxContainer) -> void:
	_xp_value_label = Label.new()
	_xp_value_label.text = "0 XP"
	_xp_value_label.add_theme_font_size_override("font_size", 22)
	_xp_value_label.add_theme_color_override("font_color", UIColors.FILTER_ON)
	parent.add_child(_xp_value_label)

# Crée le VBoxContainer des buffs actifs (rempli dynamiquement par _rebuild_buffs).
func _build_buffs_section(parent: VBoxContainer) -> void:
	_buffs_vbox = VBoxContainer.new()
	_buffs_vbox.add_theme_constant_override("separation", 2)
	parent.add_child(_buffs_vbox)

# Crée le VBoxContainer de l'équipement (rempli dynamiquement par _rebuild_equip).
func _build_equip_section(parent: VBoxContainer) -> void:
	_equip_vbox = VBoxContainer.new()
	_equip_vbox.add_theme_constant_override("separation", 2)
	parent.add_child(_equip_vbox)

# ═══════════════════════════════════════════════════════════
#  Connexions signaux
# ═══════════════════════════════════════════════════════════

# Branche tous les signaux EventBus et CombatPlayer nécessaires à la scène.
func _connect_signals() -> void:
	EventBus.adventure_started.connect(_on_adventure_started)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.adventure_stopped.connect(_on_adventure_stopped)
	CombatPlayer.step_started.connect(_on_step_started)
	CombatPlayer.step_ended.connect(_on_step_ended)
	EventBus.bonus_strike_broken.connect(_on_bonus_strike_broken)

# ═══════════════════════════════════════════════════════════
#  Handlers signaux
# ═══════════════════════════════════════════════════════════

# Réinitialise l'UI au démarrage d'une nouvelle aventure (reset XP, buffs, équipement, cercle héro).
func _on_adventure_started(_biome_id: String) -> void:
	_stop_idle_state()
	_flee_btn.disabled = false
	_cycle_xp = 0.0
	_update_xp_label()
	_rebuild_buffs()
	_rebuild_equip()

	var creature_id := GameData.player.get("active_creature_id", "") as String
	var creature    := GameData.get_entity(creature_id)
	var hero_tier   := int(creature.get("current_tier", 0))
	_hero_circle.setup(
		creature.get("name", "Héro"),
		AdventureSystem.current_hp, AdventureSystem.current_hp,
		hero_tier, CombatCircle.EntityType.CREATURE, true
	)

# Met à jour le cercle ennemi selon le type d'événement résolu (piège, positif, combat).
func _on_event_resolved(event_data: Dictionary) -> void:
	_stop_idle_state()
	match event_data.get("type", ""):
		"trap":
			var trap := event_data.get("trap", {}) as Dictionary
			_enemy_circle.setup(
				trap.get("name", "Piège"), 1.0, 1.0, 0,
				CombatCircle.EntityType.TRAP, false
			)
			if not event_data.get("ignored", false):
				var dmg := int(trap.get("damage", 0))
				_hero_circle.update_hp(AdventureSystem.current_hp)
				_hero_circle.take_damage(dmg, false)
			_start_idle_state()
		"benediction":
			var bene := event_data.get("effect", {}) as Dictionary
			_enemy_circle.setup(
				bene.get("name", "Bénédiction"), 1.0, 1.0, 0,
				CombatCircle.EntityType.BENEDICTION, false
			)
			_start_idle_state()
		"creature":
			# handled by _on_combat_started
			pass

# Initialise les deux cercles au début d'un combat et remet les barres d'action à zéro.
func _on_combat_started(creature_id: String, enemy: Dictionary,
		hero_hp: float, enemy_hp: float) -> void:
	_stop_idle_state()
	if _combat_label:
		_combat_label.modulate.a = 1.0
	var creature  := GameData.get_entity(creature_id)
	var hero_tier := int(creature.get("current_tier", 0))
	_hero_circle.setup(
		creature.get("name", "Héro"), hero_hp, hero_hp,
		hero_tier, CombatCircle.EntityType.CREATURE, true
	)
	_enemy_circle.setup(
		enemy.get("name", "Ennemi"), enemy_hp, enemy_hp,
		int(enemy.get("tier", 0)), CombatCircle.EntityType.CREATURE, false
	)
	_hero_circle.action_progress  = 0.0
	_enemy_circle.action_progress = 0.0
	_flee_btn.disabled = false
	_prev_tick = 0

# Met à jour les HP de la cible et anime la barre d'action de l'attaquant sur la durée du step.
func _on_step_started(step: CombatStep) -> void:
	if step.attacker == "hero":
		_enemy_circle.update_hp(float(step.target_hp_after))
		_enemy_circle.take_damage(step.damage, step.is_crit)
	else:
		_hero_circle.update_hp(float(step.target_hp_after))
		_hero_circle.take_damage(step.damage, step.is_crit)

	# Anime la barre d'action du cercle attaquant, calée sur les ticks VIT réels
	var ticks := maxi(step.tick_time - _prev_tick, 1)
	_prev_tick = step.tick_time
	var step_dur := maxf(float(ticks) * CombatPlayer.TICK_DURATION * GameSettings.combat_speed,
			CombatPlayer.MIN_STEP_DURATION)
	var attacker_circle := _hero_circle if step.attacker == "hero" else _enemy_circle
	attacker_circle.action_progress = 0.0
	var tw := create_tween()
	tw.tween_property(attacker_circle, "action_progress", 1.0, step_dur).set_ease(Tween.EASE_IN)

# Remet les barres d'action à zéro entre les steps.
func _on_step_ended(_step: CombatStep) -> void:
	_hero_circle.action_progress  = 0.0
	_enemy_circle.action_progress = 0.0

# Déclenche celebrate/die sur les cercles selon le résultat et met à jour le label XP.
func _on_combat_ended(result: Dictionary) -> void:
	if _combat_label:
		_combat_label.modulate.a = 0.0
	_hero_circle.action_progress  = 0.0
	_enemy_circle.action_progress = 0.0
	if result.get("victory", false):
		_hero_circle.celebrate()
		_enemy_circle.die()
		# AdventureSystem._on_combat_ended s'exécute en premier (connecté avant CombatScene)
		# donc _cycle_xp est déjà mis à jour quand on arrive ici.
		_cycle_xp = AdventureSystem._cycle_xp
		_update_xp_label()
		# Démarre l'idle après la fin de l'animation celebrate (~0.65s)
		get_tree().create_timer(0.7).timeout.connect(_start_idle_state, CONNECT_ONE_SHOT)
	else:
		_enemy_circle.celebrate()
		var tw := create_tween()
		tw.tween_property(_hero_circle, "modulate", Color(0.45, 0.45, 0.45, 0.55), 0.5)

# Met à jour le cercle héro lors d'un soin en cours d'aventure.
func _on_heal_applied(amount: float, new_hp: float) -> void:
	_hero_circle.update_hp(new_hp)
	_hero_circle.receive_heal(int(amount))

# Navigue vers le résumé de fin de cycle quand le cycle se termine naturellement.
func _on_cycle_ended(result: Dictionary) -> void:
	_stop_idle_state()
	_flee_btn.disabled = true
	_cycle_xp = float(result.get("xp_total", 0.0))
	_update_xp_label()
	_navigate_to_summary()

# Navigue vers le résumé quand le joueur arrête l'expédition manuellement.
func _on_adventure_stopped() -> void:
	_stop_idle_state()
	_navigate_to_summary()

# Demande à AdventureSystem de stopper l'aventure en cours.
func _on_flee_pressed() -> void:
	AdventureSystem.stop_adventure()

# ═══════════════════════════════════════════════════════════
#  Bonus Strike
# ═══════════════════════════════════════════════════════════

# Positionne le widget circulaire en overlay top-right de la scène.
func _build_strike_widget() -> void:
	_strike_widget              = BonusStrikeWidget.new()
	_strike_widget.anchor_left  = 1.0
	_strike_widget.anchor_right = 1.0
	_strike_widget.anchor_top   = 0.0
	_strike_widget.anchor_bottom = 0.0
	_strike_widget.offset_left   = -(BonusStrikeWidget.SIZE + 12.0)
	_strike_widget.offset_right  = -12.0
	_strike_widget.offset_top    = 12.0
	_strike_widget.offset_bottom = 12.0 + BonusStrikeWidget.SIZE
	add_child(_strike_widget)

# Affiche un flash "STRIKE BRISÉ !" centré, puis disparaît.
func _on_bonus_strike_broken() -> void:
	var lbl := Label.new()
	lbl.text = "STRIKE BRISÉ !"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", UIColors.LOG_DEFEAT)
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 0.88, 0.14)
	tw.tween_interval(0.42)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.32)
	tw.tween_callback(lbl.queue_free)

# ═══════════════════════════════════════════════════════════
#  Idle entre événements
# ═══════════════════════════════════════════════════════════

# Démarre la pulsation du cercle héro et programme l'apparition du label si gap > 1.2s.
func _start_idle_state() -> void:
	_idle_active = true
	_hero_circle.start_idle()
	get_tree().create_timer(1.2).timeout.connect(_on_idle_label_timer, CONNECT_ONE_SHOT)

# Arrête la pulsation et cache immédiatement le label.
func _stop_idle_state() -> void:
	_idle_active = false
	_hero_circle.stop_idle()
	if _idle_tw:
		_idle_tw.kill()
		_idle_tw = null
	if _idle_label:
		_idle_label.modulate.a = 0.0

# Appelée après le seuil de 1.2s — affiche le label si l'état idle est toujours actif.
func _on_idle_label_timer() -> void:
	if not _idle_active or not _idle_label:
		return
	_idle_tw = create_tween()
	_idle_tw.tween_property(_idle_label, "modulate:a", 0.6, 0.4)

# ═══════════════════════════════════════════════════════════
#  Info bar — mise à jour
# ═══════════════════════════════════════════════════════════

# Rafraîchit le label XP avec la valeur courante de _cycle_xp.
func _update_xp_label() -> void:
	if _xp_value_label:
		_xp_value_label.text = "%d XP" % int(_cycle_xp)

# Reconstruit la liste des bonus actifs (passifs + équipement) dans _buffs_vbox.
func _rebuild_buffs() -> void:
	if not _buffs_vbox:
		return
	UIHelpers.clear_children(_buffs_vbox)

	var bonuses := PassiveSystem.get_combat_bonuses()
	var equip   := GameData.get_equipment_bonuses()

	var rows := [
		["ATK", float(bonuses.get("atk_bonus", 0.0)) + float(equip.get("atk", 0.0))],
		["DEF", float(bonuses.get("def_bonus", 0.0))],
		["PV",  float(bonuses.get("hp_bonus",  0.0)) + float(equip.get("hp", 0.0))],
	]
	var found := false
	for row in rows:
		var val: float = float(row[1])
		if val == 0.0:
			continue
		found = true
		var lbl := Label.new()
		var sign := "+" if val > 0 else ""
		lbl.text = str(row[0]) + " " + sign + str(int(val))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color",
			UIColors.LOG_VICTORY if val > 0 else UIColors.LOG_DEFEAT)
		_buffs_vbox.add_child(lbl)

	if not found:
		_buffs_vbox.add_child(UIHelpers.none_label(13))

# Reconstruit la liste des objets équipés dans _equip_vbox.
func _rebuild_equip() -> void:
	if not _equip_vbox:
		return
	UIHelpers.clear_children(_equip_vbox)

	var equipped: Dictionary = GameData.player.get("equipped", {})
	var found := false
	for slot in equipped:
		var item_id: String = equipped[slot]
		if item_id == "":
			continue
		var item := GameData.get_entity(item_id)
		if item.is_empty():
			continue
		found = true
		var lbl := Label.new()
		lbl.text = item.get("name", item_id)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
		_equip_vbox.add_child(lbl)

	if not found:
		_equip_vbox.add_child(UIHelpers.none_label(13))

# ═══════════════════════════════════════════════════════════
#  Résumé de fin de cycle
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

# Retourne la couleur tier du héro actif — utilisée pour teinter panels et boutons.
func _hero_tier_color() -> Color:
	var cid  := GameData.player.get("active_creature_id", "") as String
	var tier := int(GameData.get_entity(cid).get("current_tier", 0))
	return UIColors.tier_color(tier)

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

# Navigue vers le résumé de fin de cycle. Le guard _navigating empêche les
# appels multiples (adventure_cycle_ended + adventure_stopped peuvent co-déclencher).
func _navigate_to_summary() -> void:
	if _navigating:
		return
	_navigating = true
	get_tree().change_scene_to_file("res://scenes/cycle/CycleSummaryScreen.tscn")
