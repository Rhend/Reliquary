extends Control

# --- Créature (gauche) ---
var _c_hp_bar:      ProgressBar
var _c_hp_label:    Label
var _c_xp_bar:      ProgressBar
var _c_xp_label:    Label
var _c_tier_label:  Label
var _c_atk_flash:   Label   # "⚔ ATTAQUE !" en flash

# --- Ennemi (droite) ---
var _e_name_label:  Label
var _e_stats_label: Label
var _e_hp_bar:      ProgressBar
var _e_hp_label:    Label
var _e_atk_flash:   Label   # "⚔ RIPOSTE !" en flash

# --- Partagé ---
var _event_label:   Label
var _evolve_btn:    Button

# --- État interne ---
var _enemy_max_hp:   float  = 0.0
var _current_enemy_name: String = "Ennemi"

# ─────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_turn.connect(_on_combat_turn)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.xp_gained.connect(_on_xp_gained)
	EventBus.entity_ready_to_evolve.connect(_on_ready_to_evolve)

# ─────────────────────────────────────────
#  Construction UI
# ─────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.11, 0.09)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# Titre biome
	var biome  = GameData.get_entity(GameData.player.get("active_biome_id", ""))
	var title  = Label.new()
	title.text = biome.get("name", "Biome").to_upper()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Ligne des deux cartes
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	_build_creature_card(row)   # gauche
	_build_enemy_card(row)      # droite

	# Bandeau événement
	_build_event_banner(root)

	# Boutons bas
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	root.add_child(btn_row)

	_evolve_btn          = Button.new()
	_evolve_btn.text     = "★  Évoluer"
	_evolve_btn.disabled = true
	_evolve_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evolve_btn.pressed.connect(_on_evolve_pressed)
	btn_row.add_child(_evolve_btn)

	var exit_btn = Button.new()
	exit_btn.text = "◀  Quitter le cycle"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	btn_row.add_child(exit_btn)

# --- Carte créature (gauche) ---

func _build_creature_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	_h1(vbox, creature.get("name", "Créature").to_upper())
	vbox.add_child(HSeparator.new())

	# PV
	_c_hp_label      = Label.new()
	_c_hp_label.text = "PV : --"
	vbox.add_child(_c_hp_label)

	_c_hp_bar           = ProgressBar.new()
	var max_hp          = float(creature.get("base_stats", {}).get("hp", 100))
	_c_hp_bar.min_value = 0.0
	_c_hp_bar.max_value = max_hp
	_c_hp_bar.value     = AdventureSystem.current_hp if AdventureSystem.is_running else max_hp
	vbox.add_child(_c_hp_bar)

	# XP
	var tier   = creature.get("current_tier", 0)
	var xp     = creature.get("current_xp",   0.0)
	var next_i = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max = float(GameData.xp_thresholds[next_i])

	_c_xp_label      = Label.new()
	_c_xp_label.text = "XP : %.0f / %.0f" % [xp, xp_max]
	vbox.add_child(_c_xp_label)

	_c_xp_bar           = ProgressBar.new()
	_c_xp_bar.min_value = 0.0
	_c_xp_bar.max_value = xp_max
	_c_xp_bar.value     = xp
	vbox.add_child(_c_xp_bar)

	_c_tier_label      = Label.new()
	_c_tier_label.text = "Palier : " + GameData.get_tier_name(tier)
	vbox.add_child(_c_tier_label)

	vbox.add_child(_spacer())

	# Flash "ATTAQUE !"
	_c_atk_flash = _flash_label("⚔  ATTAQUE !", Color(1.0, 0.9, 0.1))
	vbox.add_child(_c_atk_flash)

# --- Carte ennemi (droite) ---

func _build_enemy_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	_e_name_label      = Label.new()
	_e_name_label.text = "EN ATTENTE..."
	_e_name_label.add_theme_font_size_override("font_size", 18)
	_e_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_name_label)

	vbox.add_child(HSeparator.new())

	_e_hp_label      = Label.new()
	_e_hp_label.text = "PV : —"
	vbox.add_child(_e_hp_label)

	_e_hp_bar           = ProgressBar.new()
	_e_hp_bar.min_value = 0.0
	_e_hp_bar.max_value = 100.0
	_e_hp_bar.value     = 0.0
	vbox.add_child(_e_hp_bar)

	_e_stats_label      = Label.new()
	_e_stats_label.text = ""
	_e_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_stats_label)

	vbox.add_child(_spacer())

	# Flash "RIPOSTE !"
	_e_atk_flash = _flash_label("⚔  RIPOSTE !", Color(1.0, 0.4, 0.2))
	vbox.add_child(_e_atk_flash)

# --- Bandeau événement ---

func _build_event_banner(parent: Node) -> void:
	var card = PanelContainer.new()
	parent.add_child(card)

	var m = _pad(card, 12)
	_event_label = Label.new()
	_event_label.text = "En attente du premier événement..."
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_child(_event_label)

# ─────────────────────────────────────────
#  Handlers signaux
# ─────────────────────────────────────────

func _on_combat_started(_creature_id: String, enemy: Dictionary, creature_hp: float, enemy_hp: float) -> void:
	_current_enemy_name = enemy.get("name", "Ennemi")
	_enemy_max_hp       = enemy_hp

	_e_name_label.text  = _current_enemy_name.to_upper()
	_e_stats_label.text = "ATK %d   DEF %d" % [enemy.get("atk", 0), enemy.get("def", 0)]
	_e_hp_bar.max_value = _enemy_max_hp
	_e_hp_bar.value     = _enemy_max_hp
	_e_hp_label.text    = "PV : %.0f / %.0f" % [_enemy_max_hp, _enemy_max_hp]

	_set_creature_hp(creature_hp)
	_event_label.text = "⚔  Combat contre %s !" % _current_enemy_name

func _on_combat_turn(attacker: String, damage: float, creature_hp: float, enemy_hp: float) -> void:
	_set_creature_hp(creature_hp)
	_set_enemy_hp(enemy_hp)

	var creature    = GameData.get_entity(GameData.player.get("active_creature_id", ""))
	var c_name      = creature.get("name", "Créature")

	if attacker == "creature":
		_event_label.text = "⚔ %s inflige %.0f dégâts à %s  —  PV ennemi : %.0f" % [
			c_name, damage, _current_enemy_name, maxf(enemy_hp, 0.0)
		]
		_flash(_c_atk_flash)
	else:
		_event_label.text = "🗡 %s riposte : %.0f dégâts à %s  —  PV restants : %.0f" % [
			_current_enemy_name, damage, c_name, maxf(creature_hp, 0.0)
		]
		_flash(_e_atk_flash)

func _on_combat_ended(result: Dictionary) -> void:
	var enemy_name = result.get("enemy", {}).get("name", "l'ennemi")
	if result.get("victory", false):
		_event_label.text = "✅ Victoire contre %s ! Prochain événement dans 2 s..." % enemy_name
	else:
		_event_label.text = "💀 Défaite contre %s..." % enemy_name
	_set_creature_hp(result.get("remaining_creature_hp", 0.0))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"positive":
			var effect        = event_data.get("effect", {})
			_event_label.text = "✨ " + effect.get("name", "Événement positif")
			_clear_enemy_display()
		"trap":
			var trap          = event_data.get("trap", {})
			_event_label.text = "🪤 Piège : %s  (−%.0f PV)" % [trap.get("name", "?"), trap.get("damage", 0.0)]
			_clear_enemy_display()
			_set_creature_hp(AdventureSystem.current_hp)

func _on_cycle_ended(result: Dictionary) -> void:
	if not result.get("victory", true):
		_event_label.text = "💀 Cycle terminé — retour au village dans 2 s..."
		await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

func _on_xp_gained(entity_id: String, _amount: float) -> void:
	if entity_id == GameData.player.get("active_creature_id", ""):
		_refresh_xp()

func _on_ready_to_evolve(entity_id: String) -> void:
	if entity_id == GameData.player.get("active_creature_id", "") and _evolve_btn:
		_evolve_btn.disabled = false
		_event_label.text    = "★  Évolution disponible !"

func _on_evolve_pressed() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	if MasterySystem.evolve_entity(creature_id):
		_refresh_xp()
		var entity = GameData.get_entity(creature_id)
		_event_label.text = "★ Évolution ! Nouveau palier : " + \
			GameData.get_tier_name(entity.get("current_tier", 0))
	_evolve_btn.disabled = true

func _on_exit_pressed() -> void:
	AdventureSystem.stop_adventure()
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

# ─────────────────────────────────────────
#  Helpers affichage
# ─────────────────────────────────────────

func _set_creature_hp(hp: float) -> void:
	var val          = maxf(hp, 0.0)
	_c_hp_bar.value  = val
	_c_hp_label.text = "PV : %.0f / %.0f" % [val, _c_hp_bar.max_value]

func _set_enemy_hp(hp: float) -> void:
	var val          = maxf(hp, 0.0)
	_e_hp_bar.value  = val
	_e_hp_label.text = "PV : %.0f / %.0f" % [val, _enemy_max_hp]

func _clear_enemy_display() -> void:
	_e_name_label.text  = "—"
	_e_stats_label.text = ""
	_e_hp_label.text    = "PV : —"
	_e_hp_bar.value     = 0.0

func _refresh_xp() -> void:
	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)
	if creature.is_empty():
		return
	var tier   = creature.get("current_tier", 0)
	var xp     = creature.get("current_xp",   0.0)
	var next_i = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max = float(GameData.xp_thresholds[next_i])
	_c_xp_bar.max_value  = xp_max
	_c_xp_bar.value      = xp
	_c_xp_label.text     = "XP : %.0f / %.0f" % [xp, xp_max]
	_c_tier_label.text   = "Palier : " + GameData.get_tier_name(tier)

func _flash(lbl: Label) -> void:
	var tween = create_tween()
	tween.tween_property(lbl, "modulate:a", 1.0, 0.08)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.55)

# ─────────────────────────────────────────
#  Utilitaires constructeurs
# ─────────────────────────────────────────

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
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl
