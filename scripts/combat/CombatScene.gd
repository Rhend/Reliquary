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
var _summary:      Control       # overlay de résumé de fin de cycle
var _summary_vbox: VBoxContainer # contenu de l'overlay summary

# Info bar
var _xp_value_label: Label          # label XP gagné ce cycle
var _buffs_vbox:     VBoxContainer  # liste des bonus actifs (passifs + équipement)
var _equip_vbox:     VBoxContainer  # liste des objets équipés

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:   float = 0.0   # XP accumulée depuis le début du cycle en cours
var _prev_tick:  int   = 0     # tick du dernier step vu — synchronise l'action bar avec CombatPlayer
var _navigating: bool  = false # garde-fou contre les doubles appels à change_scene_to_file

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
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_info_bar())
	root.add_child(_build_circles_area())
	root.add_child(_build_footer())

	_summary = _build_summary_overlay()
	add_child(_summary)
	_summary.hide()

# ── Circles ────────────────────────────────────────────────

# Crée la zone centrale contenant les deux CombatCircle côte à côte.
func _build_circles_area() -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 60)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hbox)

	_hero_circle  = CombatCircle.new()
	_enemy_circle = CombatCircle.new()
	hbox.add_child(_hero_circle)
	hbox.add_child(_enemy_circle)

	return center

# ── Footer ─────────────────────────────────────────────────

# Crée le bouton "Mettre fin à l'expédition" coloré selon le tier du héro actif.
func _build_footer() -> Control:
	var tcolor := _hero_tier_color()

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 8)

	_flee_btn = Button.new()
	_flee_btn.text = "⚔  Mettre fin à l'expédition"
	_flee_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flee_btn.custom_minimum_size   = Vector2(0, 48)
	_flee_btn.add_theme_font_size_override("font_size", 16)
	_flee_btn.add_theme_color_override("font_color", tcolor)
	var s_n := StyleBoxFlat.new()
	s_n.bg_color     = Color(tcolor.r, tcolor.g, tcolor.b, 0.14)
	s_n.border_color = tcolor
	s_n.set_border_width_all(2)
	s_n.set_corner_radius_all(6)
	_flee_btn.add_theme_stylebox_override("normal", s_n)
	var s_h := s_n.duplicate() as StyleBoxFlat
	s_h.bg_color = Color(tcolor.r, tcolor.g, tcolor.b, 0.30)
	_flee_btn.add_theme_stylebox_override("hover", s_h)
	_flee_btn.pressed.connect(_on_flee_pressed)
	m.add_child(_flee_btn)
	return m

# ── Info bar : XP | Effets actifs | Équipement ─────────────

# Crée la rangée de trois panels en haut de scène.
func _build_info_bar() -> Control:
	var tcolor := _hero_tier_color()

	var outer := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		outer.add_theme_constant_override(side, 8)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	outer.add_child(hbox)

	hbox.add_child(_build_info_panel("◆  XP CE CYCLE",   tcolor, func(vb): _build_xp_section(vb)))
	hbox.add_child(_build_info_panel("◆  EFFETS ACTIFS", tcolor, func(vb): _build_buffs_section(vb)))
	hbox.add_child(_build_info_panel("◆  ÉQUIPEMENT",    tcolor, func(vb): _build_equip_section(vb)))

	return outer

# Construit un panel avec header coloré tier + séparateur + contenu fourni par builder.
# Même DA que _passive_card / _adv_biome_card dans Village.gd.
func _build_info_panel(title: String, tcolor: Color, builder: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = Color(tcolor.r, tcolor.g, tcolor.b, 0.07)
	sbox.border_color = Color(tcolor.r, tcolor.g, tcolor.b, 0.60)
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sbox)

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 8)
	panel.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	m.add_child(vbox)

	# Titre — même style que _section_header du Village
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", tcolor)
	vbox.add_child(title_lbl)

	var line := ColorRect.new()
	line.color = Color(tcolor.r, tcolor.g, tcolor.b, 0.38)
	line.custom_minimum_size     = Vector2(0, 1)
	line.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	vbox.add_child(line)

	builder.call(vbox)
	return panel

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

# ── Summary overlay ────────────────────────────────────────

# Construit l'overlay de fin de cycle (centré, semi-transparent).
func _build_summary_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(UIColors.BG_DARK, 0.85)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 320)
	var style := StyleBoxFlat.new()
	style.bg_color = UIColors.BG_CARD
	style.border_color = Color(UIColors.TEXT_HEADER, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left",   20)
	margins.add_theme_constant_override("margin_right",  20)
	margins.add_theme_constant_override("margin_top",    20)
	margins.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margins)

	_summary_vbox = VBoxContainer.new()
	_summary_vbox.add_theme_constant_override("separation", 10)
	margins.add_child(_summary_vbox)

	return overlay

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

# ═══════════════════════════════════════════════════════════
#  Handlers signaux
# ═══════════════════════════════════════════════════════════

# Réinitialise l'UI au démarrage d'une nouvelle aventure (reset XP, buffs, équipement, cercle héro).
func _on_adventure_started(_biome_id: String) -> void:
	_summary.hide()
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
		"benediction":
			var bene := event_data.get("effect", {}) as Dictionary
			_enemy_circle.setup(
				bene.get("name", "Bénédiction"), 1.0, 1.0, 0,
				CombatCircle.EntityType.BENEDICTION, false
			)
		"creature":
			# handled by _on_combat_started
			pass

# Initialise les deux cercles au début d'un combat et remet les barres d'action à zéro.
func _on_combat_started(creature_id: String, enemy: Dictionary,
		hero_hp: float, enemy_hp: float) -> void:
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
	_hero_circle.action_progress  = 0.0
	_enemy_circle.action_progress = 0.0
	if result.get("victory", false):
		_hero_circle.celebrate()
		_enemy_circle.die()
		# AdventureSystem._on_combat_ended s'exécute en premier (connecté avant CombatScene)
		# donc _cycle_xp est déjà mis à jour quand on arrive ici.
		_cycle_xp = AdventureSystem._cycle_xp
		_update_xp_label()
	else:
		_enemy_circle.celebrate()
		var tw := create_tween()
		tw.tween_property(_hero_circle, "modulate", Color(0.45, 0.45, 0.45, 0.55), 0.5)

# Met à jour le cercle héro lors d'un soin en cours d'aventure.
func _on_heal_applied(amount: float, new_hp: float) -> void:
	_hero_circle.update_hp(new_hp)
	_hero_circle.receive_heal(int(amount))

# Affiche l'overlay de résumé à la fin du cycle et désactive le bouton Fuir.
func _on_cycle_ended(result: Dictionary) -> void:
	_flee_btn.disabled = true
	_cycle_xp = float(result.get("xp_total", 0.0))
	_update_xp_label()
	_show_summary(result)

# Déclenche la navigation vers le village quand AdventureSystem stoppe l'aventure.
func _on_adventure_stopped() -> void:
	_navigate_to_village()

# Demande à AdventureSystem de stopper l'aventure en cours.
func _on_flee_pressed() -> void:
	AdventureSystem.stop_adventure()

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
	_clear_vbox(_buffs_vbox)

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
			UIColors.TYPE_EVENT_POS if val > 0 else UIColors.LOG_DEFEAT)
		_buffs_vbox.add_child(lbl)

	if not found:
		_add_none_label(_buffs_vbox)

# Reconstruit la liste des objets équipés dans _equip_vbox.
func _rebuild_equip() -> void:
	if not _equip_vbox:
		return
	_clear_vbox(_equip_vbox)

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
		_add_none_label(_equip_vbox)

# ═══════════════════════════════════════════════════════════
#  Résumé de fin de cycle
# ═══════════════════════════════════════════════════════════

# Peuple et affiche l'overlay de résumé ; navigation automatique après 6 s.
func _show_summary(result: Dictionary) -> void:
	_clear_vbox(_summary_vbox)

	var victory: bool = result.get("victory", false)

	var title := Label.new()
	title.text               = "VICTOIRE !" if victory else "DÉFAITE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color",
		UIColors.TYPE_EVENT_POS if victory else UIColors.LOG_DEFEAT)
	_summary_vbox.add_child(title)

	_summary_vbox.add_child(HSeparator.new())
	_add_stat("XP gagnée",       "%d" % int(result.get("xp_total",    0)))
	_add_stat("Combats gagnés",   "%d" % int(result.get("combats_won", 0)))
	_add_stat("Meilleur combo",   "×%d" % int(result.get("combo_max",  0)))
	_add_stat("Objets récupérés", "%d" % int(result.get("loot_total",  0)))
	_summary_vbox.add_child(HSeparator.new())

	var btn := Button.new()
	btn.text = "Retour au Village"
	btn.pressed.connect(_navigate_to_village)
	_summary_vbox.add_child(btn)

	get_tree().create_timer(6.0).timeout.connect(_navigate_to_village)
	_summary.show()

# Ajoute une ligne label/valeur dans _summary_vbox.
func _add_stat(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	row.add_child(val)
	_summary_vbox.add_child(row)

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

# Retourne la couleur tier du héro actif — utilisée pour teinter panels et boutons.
func _hero_tier_color() -> Color:
	var cid  := GameData.player.get("active_creature_id", "") as String
	var tier := int(GameData.get_entity(cid).get("current_tier", 0))
	return UIColors.tier_color(tier)

# Vide tous les enfants d'un VBoxContainer et libère leur mémoire.
func _clear_vbox(vbox: VBoxContainer) -> void:
	for c in vbox.get_children():
		c.queue_free()

# Ajoute un label "Aucun" en TEXT_MUTED dans le VBoxContainer donné.
func _add_none_label(vbox: VBoxContainer) -> void:
	var lbl := Label.new()
	lbl.text = "Aucun"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(lbl)

# ═══════════════════════════════════════════════════════════
#  Navigation
# ═══════════════════════════════════════════════════════════

# Navigue vers le village. Le guard _navigating empêche les appels multiples
# (timer auto + bouton + signal adventure_stopped peuvent déclencher simultanément).
func _navigate_to_village() -> void:
	if _navigating:
		return
	_navigating = true
	get_tree().change_scene_to_file("res://scenes/Village.tscn")
