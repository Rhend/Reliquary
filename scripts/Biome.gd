# ============================================================
# Biome.gd — Scène d'aventure / combat.
#
# Mise en page :
#   [Titre du biome + indicateur XP biome]
#   [Bandeau modificateur de cycle]
#   [Carte Héro]      [Carte Ennemi + indicateur de tour]
#   [Bandeau événement courant]
#   [Journal des 8 derniers événements  — auto-scroll]
#   [Bouton Quitter]
#
# Effets visuels (FX) :
#   • Dégâts flottants  : labels qui montent et s'estompent
#   • Soins flottants   : labels verts "+N PV"
#   • Flash HP          : barre flashe blanc à l'impact
#   • Flash carte       : teinte rouge/verte sur la carte touchée
#   • Tween HP          : cubic ease-out sur 0.28 s
#   • Couleur HP        : 4 niveaux pour le héro, 3 inversés pour l'ennemi
#   • Indicateur tour   : "⚔ VOTRE TOUR" / "↩ ENNEMI RIPOSTE"
#   • Pulse combo       : label combo s'illumine à chaque incrément
#   • Pulse luck        : bandeau luck clignote en doré
#   • Flash victoire    : carte héro pulse en vert doré
#   • Fondu de scène    : cubic ease-in/out 0.30-0.40 s
#   • Résumé de cycle   : overlay avec countdown
# ============================================================
extends Control

# ─── Cartes de combat ───────────────────────────────────────

var _c_card:      PanelContainer   # Carte héro (pour flash modulate)
var _e_card:      PanelContainer   # Carte ennemi (pour flash modulate)

# ─── Héro (carte gauche) ────────────────────────────────────

var _c_hp_bar:    ProgressBar
var _c_hp_label:  Label
var _c_hp_style:  StyleBoxFlat
var _c_hp_tween:  Tween
var _c_atk_flash: Label
var _combo_label: Label

# ─── Ennemi (carte droite) ──────────────────────────────────

var _e_name_label:     Label
var _e_stats_label:    Label
var _e_hp_bar:         ProgressBar
var _e_hp_label:       Label
var _e_hp_style:       StyleBoxFlat
var _e_hp_tween:       Tween
var _e_atk_flash:      Label
var _turn_indicator:   Label   # Indique le tour actif pendant un combat

# ─── Éléments partagés ──────────────────────────────────────

var _event_label:    Label
var _modifier_label: Label
var _biome_xp_label: Label
var _luck_label:     Label
var _log_vbox:       VBoxContainer
var _scroll_log:     ScrollContainer   # Référence pour l'auto-scroll
var _fx_overlay:     Control
var _fade_rect:      ColorRect

# ─── État interne ────────────────────────────────────────────

var _enemy_max_hp:       float  = 0.0
var _current_enemy_name: String = "Ennemi"

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_build_ui()

	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_turn.connect(_on_combat_turn)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.modifier_activated.connect(_on_modifier_activated)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.luck_boosted.connect(_on_luck_boosted)
	EventBus.xp_gained.connect(_on_xp_gained)

	# Restaure le modificateur si l'aventure était déjà en cours au chargement
	if not AdventureSystem.current_modifier.is_empty():
		_on_modifier_activated(AdventureSystem.current_modifier)

# ═══════════════════════════════════════════════════════════
#  Construction de l'interface
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.10, 0.08)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_header(root)
	_build_modifier_row(root)

	var cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 14)
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards_row)

	_build_creature_card(cards_row)
	_build_enemy_card(cards_row)

	_build_event_banner(root)
	_build_event_log(root)

	var exit_btn = Button.new()
	exit_btn.text = "Quitter le cycle"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	root.add_child(exit_btn)

	# Overlay FX par-dessus tout le contenu
	_fx_overlay = Control.new()
	_fx_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_overlay)

	# Overlay de fondu — dernier enfant pour être au-dessus des FX
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	# Fondu d'entrée : noir → transparent
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.40)

# ─── En-tête : nom du biome + XP ────────────────────────────

func _build_header(parent: Node) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	var biome = GameData.get_entity(GameData.player.get("active_biome_id", ""))
	var title = Label.new()
	title.text = biome.get("name", "Biome").to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	var xp_panel = PanelContainer.new()
	xp_panel.custom_minimum_size = Vector2(190, 0)
	hbox.add_child(xp_panel)

	var xp_m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		xp_m.add_theme_constant_override(side, 6)
	xp_panel.add_child(xp_m)

	_biome_xp_label = Label.new()
	_biome_xp_label.add_theme_font_size_override("font_size", 11)
	_biome_xp_label.add_theme_color_override("font_color", UIColors.TYPE_BIOME)
	xp_m.add_child(_biome_xp_label)
	_update_biome_xp_label()

# ─── Bandeau modificateur + luck ────────────────────────────

func _build_modifier_row(parent: Node) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	_modifier_label = Label.new()
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.add_theme_font_size_override("font_size", 13)
	_modifier_label.add_theme_color_override("font_color", UIColors.MODIFIER_ACTIVE)
	_modifier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modifier_label.visible = false
	row.add_child(_modifier_label)

	_luck_label = Label.new()
	_luck_label.text    = ""
	_luck_label.visible = false
	_luck_label.add_theme_font_size_override("font_size", 12)
	_luck_label.add_theme_color_override("font_color", UIColors.LOG_LOOT)
	row.add_child(_luck_label)

# ─── Carte héro ─────────────────────────────────────────────

func _build_creature_card(parent: Node) -> void:
	_c_card = PanelContainer.new()
	_c_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_c_card)

	var m    = _pad(_c_card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var creature_id   = GameData.player.get("active_creature_id", "")
	var creature      = GameData.get_entity(creature_id)
	var equip_bonuses = GameData.get_equipment_bonuses()
	var eff_stats     = GameData.get_effective_stats(creature_id)
	var passives      = PassiveSystem.get_combat_bonuses()
	var max_hp        = float(eff_stats.get("hp", 100)) + equip_bonuses.get("hp", 0.0) \
						+ passives.get("hp_bonus", 0.0)
	var initial_hp    = AdventureSystem.current_hp if AdventureSystem.is_running else max_hp

	_h1(vbox, creature.get("name", "Héro").to_upper())
	vbox.add_child(HSeparator.new())

	_c_hp_label      = Label.new()
	_c_hp_label.text = "PV : %.0f / %.0f" % [initial_hp, max_hp]
	vbox.add_child(_c_hp_label)

	_c_hp_style = _fill_style(UIColors.hero_hp(initial_hp / max_hp if max_hp > 0.0 else 1.0))
	_c_hp_bar   = _make_bar(_c_hp_style, max_hp, initial_hp)
	vbox.add_child(_c_hp_bar)

	var stats_lbl = Label.new()
	stats_lbl.text = "ATK %d   DEF %d   PV %d" % [
		int(eff_stats.get("atk", 0)) + int(equip_bonuses.get("atk", 0)) + int(passives.get("atk_bonus", 0.0)),
		int(eff_stats.get("def", 0)) + int(passives.get("def_bonus", 0.0)),
		int(max_hp)
	]
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(stats_lbl)

	var parts: Array = []
	for slot in ["weapon", "shield", "boots", "armor"]:
		var item = GameData.get_entity(GameData.player.get("equipped", {}).get(slot, ""))
		if not item.is_empty():
			parts.append(item.get("name", ""))
	var equip_line = Label.new()
	equip_line.text = "  ".join(PackedStringArray(parts)) if not parts.is_empty() else "Aucun équipement"
	equip_line.add_theme_font_size_override("font_size", 11)
	equip_line.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
	equip_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(equip_line)

	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 15)
	_combo_label.add_theme_color_override("font_color", UIColors.COMBO_COLOR)
	_combo_label.visible = false
	vbox.add_child(_combo_label)

	vbox.add_child(_spacer())

	_c_atk_flash = _flash_label("ATTAQUE !", Color(1.0, 0.92, 0.05))
	vbox.add_child(_c_atk_flash)

# ─── Carte ennemi ────────────────────────────────────────────

func _build_enemy_card(parent: Node) -> void:
	_e_card = PanelContainer.new()
	_e_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_e_card)

	var m    = _pad(_e_card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	_e_name_label      = Label.new()
	_e_name_label.text = "EN ATTENTE..."
	_e_name_label.add_theme_font_size_override("font_size", 18)
	_e_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_name_label)

	# Indicateur de tour — visible seulement pendant un combat
	_turn_indicator = Label.new()
	_turn_indicator.text    = ""
	_turn_indicator.visible = false
	_turn_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_indicator.add_theme_font_size_override("font_size", 11)
	_turn_indicator.add_theme_color_override("font_color", UIColors.STAT_ATK)
	vbox.add_child(_turn_indicator)

	vbox.add_child(HSeparator.new())

	_e_hp_label      = Label.new()
	_e_hp_label.text = "PV : —"
	vbox.add_child(_e_hp_label)

	_e_hp_style = _fill_style(UIColors.ENEMY_HIGH)
	_e_hp_bar   = _make_bar(_e_hp_style, 100.0, 0.0)
	vbox.add_child(_e_hp_bar)

	_e_stats_label      = Label.new()
	_e_stats_label.text = ""
	_e_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_e_stats_label.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(_e_stats_label)

	vbox.add_child(_spacer())

	_e_atk_flash = _flash_label("RIPOSTE !", Color(1.0, 0.20, 0.05))
	vbox.add_child(_e_atk_flash)

# ─── Bandeau événement ───────────────────────────────────────

func _build_event_banner(parent: Node) -> void:
	var card = PanelContainer.new()
	parent.add_child(card)
	var m = _pad(card, 12)
	_event_label = Label.new()
	_event_label.text = "En attente du premier événement..."
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_child(_event_label)

# ─── Journal ─────────────────────────────────────────────────

func _build_event_log(parent: Node) -> void:
	var panel = PanelContainer.new()
	parent.add_child(panel)
	var m     = _pad(panel, 8)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	m.add_child(outer)

	var header = Label.new()
	header.text = "JOURNAL"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	outer.add_child(header)

	_scroll_log = ScrollContainer.new()
	_scroll_log.custom_minimum_size    = Vector2(0, 96)
	_scroll_log.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll_log)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_scroll_log.add_child(_log_vbox)

# ═══════════════════════════════════════════════════════════
#  Handlers de signaux
# ═══════════════════════════════════════════════════════════

func _on_combat_started(_creature_id: String, enemy: Dictionary,
		creature_hp: float, enemy_hp: float) -> void:
	_current_enemy_name = enemy.get("name", "Ennemi")
	_enemy_max_hp       = enemy_hp

	_e_name_label.text   = _current_enemy_name.to_upper()
	_e_stats_label.text  = "ATK %d   DEF %d" % [enemy.get("atk", 0), enemy.get("def", 0)]
	_e_hp_style.bg_color = UIColors.enemy_hp(1.0)
	_e_hp_bar.max_value  = _enemy_max_hp
	_e_hp_bar.value      = _enemy_max_hp
	_e_hp_label.text     = "PV : %.0f / %.0f" % [_enemy_max_hp, _enemy_max_hp]

	_set_creature_hp(creature_hp)
	_set_turn_indicator("creature")

	_set_event_banner("combat", "Combat contre %s !" % _current_enemy_name)
	_add_log_entry("⚔ %s  (PV %d)" % [_current_enemy_name, int(enemy_hp)], UIColors.LOG_COMBAT)

func _on_combat_turn(attacker: String, damage: float,
		creature_hp: float, enemy_hp: float) -> void:
	var c_name = GameData.get_entity(
		GameData.player.get("active_creature_id", "")).get("name", "Héro")

	if attacker == "creature":
		_set_enemy_hp(enemy_hp)
		_set_event_banner("combat", "%s inflige %.0f dégâts — PV ennemi : %.0f" % [
			c_name, damage, maxf(enemy_hp, 0.0)
		])
		_flash(_c_atk_flash)
		_spawn_damage_number(_e_hp_bar, "-%.0f" % damage, UIColors.DMG_BY_HERO)
		_flash_card(_e_card, Color(1.4, 0.6, 0.6))   # ennemi reçoit un coup
		_set_turn_indicator("enemy")
	else:
		_set_creature_hp(creature_hp)
		_set_event_banner("combat", "%s riposte : %.0f dégâts — PV restants : %.0f" % [
			_current_enemy_name, damage, maxf(creature_hp, 0.0)
		])
		_flash(_e_atk_flash)
		_spawn_damage_number(_c_hp_bar, "-%.0f" % damage, UIColors.DMG_BY_ENEMY)
		_flash_card(_c_card, Color(1.4, 0.6, 0.6))   # héro reçoit un coup
		_set_turn_indicator("creature")

func _on_combat_ended(result: Dictionary) -> void:
	var enemy_name = result.get("enemy", {}).get("name", "l'ennemi")
	_turn_indicator.visible = false

	if result.get("victory", false):
		_set_event_banner("positive", "Victoire contre %s !" % enemy_name)
		_add_log_entry("✓ Victoire vs %s" % enemy_name, UIColors.LOG_VICTORY)
		_flash_card_victory()
	else:
		_set_event_banner("trap", "Défaite contre %s..." % enemy_name)
		_add_log_entry("✗ Défaite vs %s" % enemy_name, UIColors.LOG_DEFEAT)

	_set_creature_hp(result.get("remaining_creature_hp", 0.0))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"positive":
			var effect = event_data.get("effect", {})
			_set_event_banner("positive", effect.get("name", "Événement positif"))
			_add_log_entry("✦ " + effect.get("name", "Événement positif"), UIColors.LOG_EVENT)
			_clear_enemy_display()

		"trap":
			var trap    = event_data.get("trap", {})
			var ignored = event_data.get("ignored", false)
			if ignored:
				_set_event_banner("", "Piège ignoré : %s  (Fantôme)" % trap.get("name","?"))
				_event_label.add_theme_color_override("font_color", UIColors.LOG_IGNORED)
				_add_log_entry("◌ Piège ignoré : %s" % trap.get("name","?"), UIColors.LOG_IGNORED)
			else:
				_set_event_banner("trap", "Piège : %s  (−%.0f PV)" % [
					trap.get("name","?"), trap.get("damage",0.0)
				])
				_add_log_entry("▲ %s  −%.0f PV" % [
					trap.get("name","?"), trap.get("damage",0.0)
				], UIColors.LOG_TRAP)
				_flash_card(_c_card, Color(1.2, 0.5, 0.5))
			_clear_enemy_display()
			_set_creature_hp(AdventureSystem.current_hp)

func _on_cycle_ended(result: Dictionary) -> void:
	var victory = result.get("victory", false)
	_add_log_entry(
		"— Cycle terminé : %s" % ("Victoire !" if victory else "Défaite"),
		UIColors.LOG_VICTORY if victory else UIColors.LOG_DEFEAT
	)
	# Petite pause pour que le joueur lise le dernier log avant la transition.
	await get_tree().create_timer(0.6).timeout
	_fade_to("res://scenes/cycle/CycleSummaryScreen.tscn")

func _on_loot_dropped(drops: Array, enemy_name: String) -> void:
	var parts: Array = []
	for d in drops:
		parts.append("%s ×%d" % [d.get("name", "?"), d.get("qty", 1)])
	_add_log_entry("★ [%s] %s" % [enemy_name, ", ".join(PackedStringArray(parts))],
		UIColors.LOG_LOOT)

func _on_modifier_activated(modifier: Dictionary) -> void:
	var m_name = modifier.get("name", "—")
	var m_desc = modifier.get("desc", "")
	if m_name == "—" or m_name == "":
		_modifier_label.visible = false
		return
	_modifier_label.text    = "%s  —  %s" % [m_name, m_desc]
	_modifier_label.visible = true
	_modifier_label.modulate.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_OUT)
	tw.tween_property(_modifier_label, "modulate:a", 1.0, 0.50)

func _on_combo_changed(count: int) -> void:
	if count > 1:
		var bonus_pct = int((count - 1) * 5)
		_combo_label.text    = "COMBO  x%d  (+%d%% ATK)" % [count, bonus_pct]
		_combo_label.visible = true
		_combo_label.modulate = UIColors.COMBO_COLOR * 1.8
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_combo_label, "modulate", Color.WHITE, 0.40)
	else:
		_combo_label.visible = false

func _on_heal_applied(amount: float, new_hp: float) -> void:
	_set_creature_hp(new_hp)
	_spawn_damage_number(_c_hp_bar, "+%.0f PV" % amount, UIColors.HEAL_COLOR)
	_flash_card(_c_card, Color(0.6, 1.4, 0.7))   # teinte verte douce au soin

func _on_luck_boosted(cycle_luck: int) -> void:
	_luck_label.text    = "✦ Luck +%d" % cycle_luck
	_luck_label.visible = true
	_luck_label.modulate = UIColors.LOG_LOOT * 1.5
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_luck_label, "modulate", Color.WHITE, 0.6)

func _on_xp_gained(entity_id: String, _amount: float) -> void:
	if entity_id == GameData.player.get("active_biome_id", ""):
		_update_biome_xp_label()

func _on_exit_pressed() -> void:
	AdventureSystem.stop_adventure()
	_fade_to("res://scenes/cycle/CycleSummaryScreen.tscn")

# ═══════════════════════════════════════════════════════════
#  Indicateur XP du biome
# ═══════════════════════════════════════════════════════════

func _update_biome_xp_label() -> void:
	if _biome_xp_label == null:
		return
	var biome_id = GameData.player.get("active_biome_id", "")
	var biome    = GameData.get_entity(biome_id)
	if biome.is_empty():
		return
	var tier      = biome.get("current_tier", 0)
	var xp        = biome.get("current_xp",   0.0)
	var next_idx  = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max    = float(GameData.xp_thresholds[next_idx])
	var tier_name = GameData.get_tier_name(tier)
	_biome_xp_label.text = "%s  XP %.0f/%.0f" % [tier_name, xp, xp_max]

# ═══════════════════════════════════════════════════════════
#  Indicateur de tour
# ═══════════════════════════════════════════════════════════

# Affiche qui est en train d'attaquer ("creature" = héro attaque, "enemy" = ennemi attaque).
func _set_turn_indicator(next_attacker: String) -> void:
	if _turn_indicator == null:
		return
	_turn_indicator.visible = true
	if next_attacker == "creature":
		_turn_indicator.text = "⚔ VOTRE TOUR"
		_turn_indicator.add_theme_color_override("font_color", UIColors.STAT_ATK)
	else:
		_turn_indicator.text = "↩ ENNEMI RIPOSTE"
		_turn_indicator.add_theme_color_override("font_color", UIColors.DMG_BY_ENEMY)

# ═══════════════════════════════════════════════════════════
#  Gestion des barres HP
# ═══════════════════════════════════════════════════════════

func _set_creature_hp(hp: float) -> void:
	var val       = maxf(hp, 0.0)
	var decreased = val < _c_hp_bar.value

	_c_hp_label.text = "PV : %.0f / %.0f" % [val, _c_hp_bar.max_value]

	if _c_hp_tween:
		_c_hp_tween.kill()
	_c_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_c_hp_tween.tween_property(_c_hp_bar, "value", val, 0.28)

	var pct       = val / _c_hp_bar.max_value if _c_hp_bar.max_value > 0.0 else 1.0
	var new_color = UIColors.hero_hp(pct)

	if decreased:
		# Flash blanc → couleur cible
		_c_hp_style.bg_color = Color(1.0, 1.0, 1.0, 0.90)
		var flash = create_tween()
		flash.tween_property(_c_hp_style, "bg_color", new_color, 0.20)
	else:
		_c_hp_style.bg_color = new_color

func _set_enemy_hp(hp: float) -> void:
	var val       = maxf(hp, 0.0)
	var decreased = val < _e_hp_bar.value

	_e_hp_label.text = "PV : %.0f / %.0f" % [val, _enemy_max_hp]

	if _e_hp_tween:
		_e_hp_tween.kill()
	_e_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_e_hp_tween.tween_property(_e_hp_bar, "value", val, 0.28)

	var pct       = val / _enemy_max_hp if _enemy_max_hp > 0.0 else 1.0
	var new_color = UIColors.enemy_hp(pct)

	if decreased:
		_e_hp_style.bg_color = Color(1.0, 1.0, 1.0, 0.90)
		var flash = create_tween()
		flash.tween_property(_e_hp_style, "bg_color", new_color, 0.20)
	else:
		_e_hp_style.bg_color = new_color

func _clear_enemy_display() -> void:
	_e_name_label.text      = "—"
	_e_stats_label.text     = ""
	_e_hp_label.text        = "PV : —"
	_e_hp_bar.value         = 0.0
	_turn_indicator.visible = false

# ═══════════════════════════════════════════════════════════
#  Effets visuels
# ═══════════════════════════════════════════════════════════

# Flash de modulation sur une carte (teinte colorée brève → retour blanc).
func _flash_card(card: Control, tint: Color) -> void:
	if card == null:
		return
	var tw = create_tween()
	tw.tween_property(card, "modulate", tint, 0.05)
	tw.tween_property(card, "modulate", Color.WHITE, 0.28).set_ease(Tween.EASE_OUT)

# Pulse victoire : vert doré sur la carte héro, 2 fois.
func _flash_card_victory() -> void:
	if _c_card == null:
		return
	var tw = create_tween()
	tw.tween_property(_c_card, "modulate", UIColors.VICTORY_GLOW * 1.6, 0.12)
	tw.tween_property(_c_card, "modulate", Color.WHITE, 0.30).set_ease(Tween.EASE_OUT)
	tw.tween_property(_c_card, "modulate", UIColors.VICTORY_GLOW * 1.3, 0.10)
	tw.tween_property(_c_card, "modulate", Color.WHITE, 0.45).set_ease(Tween.EASE_OUT)

func _spawn_damage_number(anchor_bar: ProgressBar, text: String, color: Color) -> void:
	var rect  = anchor_bar.get_global_rect()
	var start = Vector2(rect.get_center().x - 18.0, rect.position.y - 8.0)

	var lbl = Label.new()
	lbl.text     = text
	lbl.position = start
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_fx_overlay.add_child(lbl)

	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", start.y - 65.0, 0.85) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85) \
		.set_ease(Tween.EASE_IN).set_delay(0.28)
	tw.chain().tween_callback(lbl.queue_free)

func _flash(lbl: Label) -> void:
	var tw = create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.04)
	tw.tween_interval(0.28)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45)

func _add_log_entry(text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_vbox.add_child(lbl)
	while _log_vbox.get_child_count() > 8:
		var old = _log_vbox.get_child(0)
		_log_vbox.remove_child(old)
		old.queue_free()

	# Défile automatiquement vers le bas — valeur arbitrairement grande
	# car le moteur n'a pas encore mis en page le nouveau label au moment de l'appel.
	if _scroll_log != null:
		_scroll_log.call_deferred("set", "scroll_vertical", 999999)

# Met à jour le bandeau d'événement avec la couleur du type.
func _set_event_banner(event_type: String, text: String) -> void:
	var info = UIColors.event_banner(event_type)
	_event_label.text = str(info[0]) + text
	_event_label.add_theme_color_override("font_color", info[1])

func _fade_to(scene_path: String) -> void:
	_fade_rect.color.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.30)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ═══════════════════════════════════════════════════════════
#  Utilitaires constructeurs UI
# ═══════════════════════════════════════════════════════════

func _fill_style(color: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color                   = color
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left  = 4
	return s

func _make_bar(fill: StyleBoxFlat, max_val: float, val: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.min_value           = 0.0
	bar.max_value           = max_val
	bar.value               = val
	bar.show_percentage     = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.add_theme_stylebox_override("fill", fill)

	var bg = StyleBoxFlat.new()
	bg.bg_color                   = UIColors.BG_BAR
	bg.corner_radius_top_left     = 4
	bg.corner_radius_top_right    = 4
	bg.corner_radius_bottom_right = 4
	bg.corner_radius_bottom_left  = 4
	bar.add_theme_stylebox_override("background", bg)
	return bar

func _pad(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

func _h1(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

func _spacer() -> Control:
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

func _flash_label(text: String, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text     = text
	lbl.modulate = Color(color.r, color.g, color.b, 0.0)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl
