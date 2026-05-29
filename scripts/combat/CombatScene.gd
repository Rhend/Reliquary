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

# ─── Zone courante ────────────────────────────────────────────
var _zone_label: Label = null   # label "Surface / Profondeur / Abysse"

# ─── Créature Unique ──────────────────────────────────────────
var _unique_panel:   Control = null  # indicateur + bouton en Abysse
var _circles_vbox:   VBoxContainer = null  # référence au vbox des cercles

# ─── Combat ───────────────────────────────────────────────────
var _combat_label: Label = null  # label "En combat..." affiché pendant un duel

# ─── Mécaniques de biome ──────────────────────────────────────
var _ambush_pending: bool  = false  # vrai au lancement si embuscade active, reset après 1er combat
var _ambush_icon:    Label = null   # icône ⚡ sur le cercle ennemi pendant le 1er combat
var _luck_icon:      Label = null   # trèfle 🍀 pulsant (Chance Corsaire), visible tout le cycle

# ─── Bouclier d'urgence (Résilience Rare+) ────────────────────
var _hero_shield: float = 0.0   # PV de bouclier trackés pendant le playback

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

# ── Circles ────────────────────────────────────────────────

# Crée la zone centrale : cercles côte à côte + label idle en dessous.
func _build_circles_area() -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_circles_vbox = VBoxContainer.new()
	_circles_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_circles_vbox.add_theme_constant_override("separation", 12)
	center.add_child(_circles_vbox)
	var vbox := _circles_vbox

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

	_zone_label = Label.new()
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_zone_label)

	return center

# ── Footer ─────────────────────────────────────────────────

# Crée le bouton "Mettre fin à l'expédition" coloré selon le tier du héro actif.
func _build_footer() -> Control:
	var tcolor := _hero_tier_color()

	var m    := UIHelpers.margin_of(8)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	m.add_child(hbox)

	_flee_btn = Button.new()
	_flee_btn.text                   = "⚔  Mettre fin à l'expédition"
	_flee_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_flee_btn.custom_minimum_size    = Vector2(0, 48)
	_flee_btn.add_theme_font_size_override("font_size", 16)
	_flee_btn.add_theme_color_override("font_color", tcolor)
	_flee_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	_flee_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	_flee_btn.pressed.connect(_on_flee_pressed)
	hbox.add_child(_flee_btn)

	var dbg := Button.new()
	dbg.text                = "🛡 14%"
	dbg.custom_minimum_size = Vector2(70, 48)
	dbg.add_theme_font_size_override("font_size", 13)
	dbg.add_theme_color_override("font_color", Color(0.25, 0.60, 1.0))
	dbg.add_theme_stylebox_override("normal", UIHelpers.card_style(Color(0.25, 0.60, 1.0), 0.10, 0.60, 1, 6))
	dbg.add_theme_stylebox_override("hover",  UIHelpers.card_style(Color(0.25, 0.60, 1.0), 0.25, 1.00, 1, 6))
	dbg.pressed.connect(_debug_set_hp_14pct)
	hbox.add_child(dbg)

	return m

func _debug_set_hp_14pct() -> void:
	var max_hp := AdventureSystem.get_max_hp()
	AdventureSystem.current_hp = max_hp * 0.14
	_hero_circle.update_hp(AdventureSystem.current_hp)

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
	EventBus.zone_changee.connect(_on_zone_changee)
	EventBus.creature_unique_vaincue.connect(_on_creature_unique_vaincue)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.adventure_stopped.connect(_on_adventure_stopped)
	CombatPlayer.step_started.connect(_on_step_started)
	CombatPlayer.step_ended.connect(_on_step_ended)

# ═══════════════════════════════════════════════════════════
#  Handlers signaux
# ═══════════════════════════════════════════════════════════

# Réinitialise l'UI au démarrage d'une nouvelle aventure (reset XP, buffs, équipement, cercle héro).
func _on_adventure_started(_biome_id: String) -> void:
	_stop_idle_state()
	_flee_btn.disabled = false
	_cycle_xp = 0.0
	_ambush_pending = false
	_update_xp_label()
	_rebuild_buffs()
	_rebuild_equip()
	_cleanup_luck_icon()
	_update_zone_label(AdventureSystem.zone_courante)

	var creature_id := GameData.player.get("active_creature_id", "") as String
	var creature    := GameData.get_entity(creature_id)
	var hero_tier   := int(creature.get("current_tier", 0))
	_hero_circle.setup(
		creature.get("nom_affichage_fr", creature.get("name", "Héro")),
		AdventureSystem.current_hp, AdventureSystem.current_hp,
		hero_tier, CombatCircle.EntityType.CREATURE, true
	)

	# ── Indicateurs mécaniques de biome ──────────────────────
	var mechanic := BiomeMechanics.active_mechanic
	match mechanic:
		"ambush":
			_ambush_pending = true
			_show_ambush_warning()
		"pirate_luck":
			_build_luck_icon()

# Met à jour le cercle ennemi selon le type d'événement résolu (piège, positif, combat).
func _on_event_resolved(event_data: Dictionary) -> void:
	_stop_idle_state()
	match event_data.get("type", ""):
		"trap":
			var trap := event_data.get("trap", {}) as Dictionary
			_enemy_circle.setup(
				trap.get("nom_affichage_fr", "Piège"), 1.0, 1.0, 0,
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
				bene.get("nom_affichage_fr", "Bénédiction"), 1.0, 1.0, 0,
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
	var creature   := GameData.get_entity(creature_id)
	var hero_tier  := int(creature.get("current_tier", 0))
	var hero_hp_max := AdventureSystem.get_max_hp()
	_hero_circle.setup(
		creature.get("nom_affichage_fr", creature.get("name", "Héro")), hero_hp, hero_hp_max,
		hero_tier, CombatCircle.EntityType.CREATURE, true
	)
	_enemy_circle.setup(
		enemy.get("name", "Ennemi"), enemy_hp, enemy_hp,
		int(enemy.get("tier", 0)), CombatCircle.EntityType.CREATURE, false
	)
	_hero_circle.action_progress  = 0.0
	_enemy_circle.action_progress = 0.0
	_hero_shield = 0.0
	_hero_circle.set_shield(0)
	_flee_btn.disabled = false
	_prev_tick = 0

	# Icône ⚡ sur le premier ennemi du cycle si embuscade active
	_cleanup_ambush_icon()
	if _ambush_pending:
		_ambush_pending = false
		_build_ambush_icon()

# Met à jour les HP de la cible et anime la barre d'action de l'attaquant sur la durée du step.
func _on_step_started(step: CombatStep) -> void:
	# Tick de poison biome : nombres verts, pas de barre d'action
	if step.is_poison:
		_enemy_circle.update_hp(float(step.target_hp_after))
		_enemy_circle.take_poison_damage(step.damage)
		return

	# Tick de poison passif (Contact Venimeux) : idem, légèrement décalé
	if step.is_passive_poison:
		_enemy_circle.update_hp(float(step.target_hp_after))
		_enemy_circle.take_poison_damage(step.damage)
		return

	if step.attacker == "hero":
		_enemy_circle.update_hp(float(step.target_hp_after))
		_enemy_circle.take_damage(step.damage, step.is_crit)
		# Contact Venimeux proc : icône poison sur l'ennemi
		if step.passive_poison_proc:
			_enemy_circle.show_poison_proc()
	else:
		# Coup ennemi : gérer l'absorption bouclier
		if step.shield_absorbed > 0:
			_hero_circle.take_shield_damage(step.shield_absorbed)
			_hero_shield = maxf(_hero_shield - float(step.shield_absorbed), 0.0)
			_hero_circle.set_shield(int(_hero_shield))
		if step.damage > 0:
			_hero_circle.update_hp(float(step.target_hp_after))
			_hero_circle.take_damage(step.damage, step.is_crit)
		elif step.shield_absorbed > 0:
			# Tout absorbé par bouclier : mettre à jour le label HP sans animation dégâts
			_hero_circle.update_hp(float(step.target_hp_after))

		# Bouclier vient de s'activer après ce coup
		if step.is_shield_proc:
			_hero_shield = float(step.shield_value)
			_hero_circle.set_shield(int(_hero_shield))
			_show_shield_banner()

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
	_cleanup_ambush_icon()
	_cleanup_luck_icon()
	_navigate_to_summary()

# Navigue vers le résumé quand le joueur arrête l'expédition manuellement.
func _on_adventure_stopped() -> void:
	_stop_idle_state()
	_cleanup_ambush_icon()
	_cleanup_luck_icon()
	_navigate_to_summary()

# Demande à AdventureSystem de stopper l'aventure en cours.
func _on_flee_pressed() -> void:
	AdventureSystem.stop_adventure()

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
		lbl.text = item.get("nom_affichage_fr", item_id)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
		_equip_vbox.add_child(lbl)

	if not found:
		_equip_vbox.add_child(UIHelpers.none_label(13))

# ═══════════════════════════════════════════════════════════
#  Mécaniques de biome — indicateurs visuels
# ═══════════════════════════════════════════════════════════

# Affiche le bandeau d'avertissement embuscade en haut de l'écran (3 s puis fade).
func _show_ambush_warning() -> void:
	var lbl := Label.new()
	lbl.text = "⚠ Embuscade activée — Premier ennemi frappe en premier"
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.10))
	lbl.custom_minimum_size  = Vector2(0, 36)
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)

# Crée l'icône ⚡ rouge en overlay top-right du cercle ennemi (1er combat).
func _build_ambush_icon() -> void:
	var icon := Label.new()
	icon.text = "⚡"
	icon.add_theme_font_size_override("font_size", 26)
	icon.add_theme_color_override("font_color", Color(1.0, 0.15, 0.10))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var right_x: float = CombatCircle.CIRCLE_RADIUS * 2.0 + CombatCircle.CTRL_PADDING - 28.0
	icon.position = Vector2(right_x, 4.0)
	_enemy_circle.add_child(icon)
	_ambush_icon = icon

func _cleanup_ambush_icon() -> void:
	if _ambush_icon and is_instance_valid(_ambush_icon):
		_ambush_icon.queue_free()
	_ambush_icon = null

# Crée l'icône 🍀 pulsante (Chance Corsaire) en overlay top-right de la scène.
func _build_luck_icon() -> void:
	_cleanup_luck_icon()
	var lbl := Label.new()
	lbl.text = "🍀"
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left   = -92.0
	lbl.offset_right  = -12.0
	lbl.offset_top    = 12.0
	lbl.offset_bottom = 44.0
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_luck_icon = lbl
	_animate_luck_icon()

# Pulsation alpha 0.6 → 1.0 → 0.6 en boucle (1.6 s par cycle).
func _animate_luck_icon() -> void:
	if not _luck_icon or not is_instance_valid(_luck_icon):
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_luck_icon, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_luck_icon, "modulate:a", 0.6, 0.8).set_ease(Tween.EASE_IN_OUT)

func _cleanup_luck_icon() -> void:
	if _luck_icon and is_instance_valid(_luck_icon):
		_luck_icon.queue_free()
	_luck_icon = null

# ── Zone ────────────────────────────────────────────────────

func _on_zone_changee(nouvelle_zone: int) -> void:
	_update_zone_label(nouvelle_zone as Enums.Zone)
	if nouvelle_zone == Enums.Zone.ABYSSE:
		_show_unique_indicator()
	else:
		_hide_unique_indicator()

func _update_zone_label(zone: Enums.Zone) -> void:
	if not _zone_label:
		return
	const NOMS := ["Surface", "Profondeur", "Abysse"]
	const COULEURS := [Color(0.4, 0.7, 1.0), Color(0.6, 0.3, 1.0), Color(1.0, 0.3, 0.2)]
	var idx := clampi(int(zone), 0, 2)
	_zone_label.text = "◆ " + NOMS[idx]
	_zone_label.add_theme_color_override("font_color", COULEURS[idx])

# ── Créature Unique ─────────────────────────────────────────

func _show_unique_indicator() -> void:
	if not _circles_vbox or _unique_panel != null:
		return
	var biome := GameData.get_entity(AdventureSystem.current_biome_id)
	if biome.get("creature_unique_vaincue", false):
		return
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return

	var nom    := unique.get("nom_affichage_fr", "???") as String
	var color  := Color(1.0, 0.3, 0.2)

	_unique_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.18, 0.0, 0.0, 0.90)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_unique_panel.add_theme_stylebox_override("panel", style)

	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	_unique_panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)

	var lbl := Label.new()
	lbl.text = "☠  %s vous observe..." % nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	vb.add_child(lbl)

	var btn := Button.new()
	btn.text = "⚔  Affronter %s" % nom
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(color, 0.15, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(color, 0.30, 1.0, 1, 4))
	btn.pressed.connect(AdventureSystem.start_unique_combat)
	vb.add_child(btn)

	_circles_vbox.add_child(_unique_panel)

func _hide_unique_indicator() -> void:
	if _unique_panel and is_instance_valid(_unique_panel):
		_unique_panel.queue_free()
	_unique_panel = null

func _on_creature_unique_vaincue(biome_id: String, ingredient_id: String, passif_id: String) -> void:
	_hide_unique_indicator()
	_show_unique_victory_banner(biome_id, ingredient_id, passif_id)

func _show_unique_victory_banner(biome_id: String, ingredient_id: String, passif_id: String) -> void:
	var ingr_name  := GameData.get_entity(ingredient_id).get("nom_affichage_fr", ingredient_id) as String
	var passif_name := GameData.get_entity(passif_id).get("nom_affichage_fr", passif_id) as String

	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	banner.add_theme_stylebox_override("panel", style)
	add_child(banner)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 12)
	banner.add_child(vb)

	for line: Array in [
		["✨  CRÉATURE UNIQUE VAINCUE  ✨",   24, Color(1.0, 0.8, 0.2)],
		["Ingrédient obtenu : " + ingr_name,  16, Color(0.6, 1.0, 0.6)],
		["Passif débloqué : " + passif_name,  16, Color(0.5, 0.8, 1.0)],
	]:
		var lbl := Label.new()
		lbl.text = line[0] as String
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", line[1] as int)
		lbl.add_theme_color_override("font_color", line[2] as Color)
		vb.add_child(lbl)

	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)
	tw.tween_callback(banner.queue_free)

# Affiche le bandeau BOUCLIER ! centré sur le cercle héro pendant 1.5s puis fade.
func _show_shield_banner() -> void:
	var lbl := Label.new()
	lbl.text = "BOUCLIER !"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.CYAN)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Overlay bleu sur le cercle héro
	var overlay := ColorRect.new()
	overlay.color        = Color(0.2, 0.5, 1.0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hero_circle.add_child(overlay)

	# Label centré sur le cercle héro
	var w := _hero_circle.custom_minimum_size.x
	var h := _hero_circle.custom_minimum_size.y
	lbl.position         = Vector2(0.0, h * 0.5 - 16.0)
	lbl.custom_minimum_size = Vector2(w, 32.0)
	lbl.modulate.a       = 0.0
	_hero_circle.add_child(lbl)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(overlay, "color:a", 0.5, 0.15)
	tw.tween_property(lbl,     "modulate:a", 1.0, 0.15)
	tw.chain()
	tw.tween_interval(1.5)
	tw.tween_property(overlay, "color:a", 0.0, 0.5)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(overlay.queue_free)
	tw.parallel().tween_callback(lbl.queue_free)

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
