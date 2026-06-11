# ============================================================
# CombatScene — Scène de combat (refonte UI).
#
# Layout :
#   Zone combat : colonne Héros (gauche) ↔ colonne Ennemi (droite),
#                 séparées par un séparateur diagonal "VS".
#                 Chaque colonne : nom · double anneau (cooldown + PV)
#                 · pill d'action · pills d'états.
#   Feed passifs : bande de pills transitoires.
#   Journal      : log filtrable par onglets (Tout/Héros/Monstre/…).
#   Barre de bas : "XP ce cycle — X"  ·  bouton fin d'expédition.
#
# La logique de combat (CombatPlayer / CombatResolver / AdventureSystem)
# n'est pas modifiée : la scène ne fait que présenter les signaux.
# ============================================================
class_name CombatScene extends Control

# ─── Journal de combat (DÉSACTIVÉ) ───────────────────────────
# Jugé peu utile au playtest : l'espace qu'il occupait est rendu à la
# zone de combat (les anneaux s'agrandissent automatiquement).
# Tout le code du journal est conservé et compile toujours :
# remettre LOG_ENABLED à true suffit pour le réactiver.
const LOG_ENABLED := false

# ─── Filtres du journal ──────────────────────────────────────
const LOG_TAB_KEYS: Array[String] = ["all", "hero", "monster", "attack", "defense", "heal", "status"]

# ─── Nœuds racine ────────────────────────────────────────────
var _shaker: Control          # conteneur décalé pour le shake d'écran
var _hero_bg:     BiomeBackground   # fond ambiance Ville (côté héros, gauche)
var _creature_bg: BiomeBackground   # fond ambiance biome (côté créature, droite)

# ─── Colonnes combattants ────────────────────────────────────
var _hero_ring:   CombatRing
var _enemy_ring:  CombatRing
var _hero_name:   Label
var _enemy_name:  Label
var _hero_name_style:  StyleBoxFlat   # bordure de la plaque de nom (teintée)
var _enemy_name_style: StyleBoxFlat
var _hero_name_chip:   Control
var _enemy_name_chip:  Control
var _hero_action: Label
var _enemy_action: Label
var _hero_states: HBoxContainer
var _enemy_states: HBoxContainer

# ─── Feed passifs ────────────────────────────────────────────
var _feed_box: HBoxContainer

# ─── Journal ─────────────────────────────────────────────────
var _log_vbox:    VBoxContainer
var _log_entries: Array = []          # [{node: RichTextLabel, tags: Array}]
var _log_filter:  String = "all"
var _tab_buttons: Dictionary = {}     # nom → Button

# ─── Barre de bas ────────────────────────────────────────────
var _xp_label: Label
var _flee_btn: Button

# ─── Overlays (zone + Unique) ────────────────────────────────
var _zone_label:   Label   = null
var _unique_panel: Control = null

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:    float = 0.0
var _navigating:  bool  = false
var _hero_shield: float = 0.0

# ─── Polish combat ──────────────────────────────────────────
var _danger_pulse_tween: Tween   = null   # pulse PV critique (item 5)
var _shield_state_pill:  Control = null   # pill bouclier bleue  (item 8)
var _poison_state_pill:  Control = null   # pill venin violette  (item 8)
var _mechanic_label:     Label   = null   # badge mécanique forte permanente (item 4)
var _stinger:            Control = null   # bandeau d'événement piège/bénédiction

# ═══════════════════════════════════════════════════════════
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_signals()

# ═══════════════════════════════════════════════════════════
#  Construction de l'UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UIColors.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_shaker = Control.new()
	_shaker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shaker)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	_shaker.add_child(root)

	root.add_child(_build_combat_area())
	root.add_child(_build_feed())
	if LOG_ENABLED:
		root.add_child(_build_log())
	root.add_child(_build_bottom_bar())

	_build_zone_label()
	_build_mechanic_label()

# ── Zone de combat : fonds animés + 2 colonnes + séparateur diagonal ──
# Les fonds (Ville côté héros, biome côté créature) sont CONFINÉS à cette zone
# (pas derrière le journal). clip_contents borne le rendu ; la diagonale du
# shader s'aligne donc sur le séparateur VS de cette même zone.
func _build_combat_area() -> Control:
	var area := Control.new()
	area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size   = Vector2(0, 320)
	area.clip_contents = true

	var zone := int(AdventureSystem.zone_courante)

	# Côté héros (gauche) : ambiance Ville. add_child d'abord (→ _ready crée le
	# material), puis configuration.
	_hero_bg = BiomeBackground.new()
	area.add_child(_hero_bg)
	_hero_bg.apply_preset("city")
	_hero_bg.set_split(1)
	_hero_bg.set_zone(zone)

	# Côté créature (droite) : ambiance du biome de l'expédition.
	var biome_id := AdventureSystem.current_biome_id
	if biome_id == "":
		biome_id = GameData.player.get("active_biome_id", "") as String
	_creature_bg = BiomeBackground.new()
	area.add_child(_creature_bg)
	_creature_bg.apply_preset(BiomeBackground.preset_for_biome(biome_id))
	_creature_bg.set_split(2)
	_creature_bg.set_zone(zone)

	# Colonnes par-dessus les fonds. Héros (gauche) | séparateur 80px | Ennemi (droite).
	# Le séparateur VS prend la couleur d'accent du biome exploré (ambiance).
	var vs := CombatVS.new()
	vs.accent_color = BiomeBackground.accent_for_biome(biome_id)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_build_column(true))
	hbox.add_child(vs)
	hbox.add_child(_build_column(false))
	area.add_child(hbox)
	return area

# Construit une colonne combattant ; renseigne les références membres.
func _build_column(is_hero: bool) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	# Respiration : décolle la plaque de nom du bord haut de la zone.
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 16)
	col.add_child(top_pad)

	# Plaque de nom : capsule sombre bordée à la couleur du combattant —
	# lisible quel que soit le fond animé derrière.
	var name_center := CenterContainer.new()
	col.add_child(name_center)
	var name_chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color     = Color(0.04, 0.05, 0.09, 0.88)
	chip_style.border_color = Color(1, 1, 1, 0.15)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(9)
	name_chip.add_theme_stylebox_override("panel", chip_style)
	name_center.add_child(name_chip)
	var name_m := MarginContainer.new()
	name_m.add_theme_constant_override("margin_left", 14)
	name_m.add_theme_constant_override("margin_right", 14)
	name_m.add_theme_constant_override("margin_top", 4)
	name_m.add_theme_constant_override("margin_bottom", 5)
	name_chip.add_child(name_m)

	var name_lbl := Label.new()
	name_lbl.text = "—"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	name_m.add_child(name_lbl)

	# L'anneau absorbe la hauteur disponible de la colonne : sans le journal,
	# la zone de combat est plus haute et l'anneau s'agrandit (rayons adaptatifs).
	var ring := CombatRing.new()
	ring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(ring)

	# Pill d'action : PanelContainer + Label (on garde la référence au Label).
	# Masquée par défaut — aucune capsule visible hors d'une action chargée.
	var action_box := PanelContainer.new()
	action_box.visible = false
	action_box.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.12, 0.50, 1, 8))
	var action := Label.new()
	action.text = "—"
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.add_theme_font_size_override("font_size", 14)
	action.add_theme_constant_override("outline_size", 3)
	action.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	action.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	action_box.add_child(action)
	var action_center := CenterContainer.new()
	action_center.add_child(action_box)
	col.add_child(action_center)

	var states := HBoxContainer.new()
	states.alignment = BoxContainer.ALIGNMENT_CENTER
	states.add_theme_constant_override("separation", 4)
	col.add_child(states)

	if is_hero:
		_hero_name = name_lbl; _hero_ring = ring; _hero_action = action; _hero_states = states
		_hero_name_style = chip_style; _hero_name_chip = name_chip
	else:
		_enemy_name = name_lbl; _enemy_ring = ring; _enemy_action = action; _enemy_states = states
		_enemy_name_style = chip_style; _enemy_name_chip = name_chip
	return col

# Teinte la bordure d'une plaque de nom à la couleur du combattant
# et fait « pop » la plaque (nouvelle rencontre).
func _present_name(chip: Control, style: StyleBoxFlat, color: Color) -> void:
	style.border_color = Color(color.r, color.g, color.b, 0.75)
	chip.pivot_offset = chip.size * 0.5
	chip.scale = Vector2(0.7, 0.7)
	chip.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(chip, "modulate:a", 1.0, 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Feed passifs ───────────────────────────────────────────
func _build_feed() -> Control:
	var feed_wrap := CenterContainer.new()
	feed_wrap.custom_minimum_size = Vector2(0, 28)
	_feed_box = HBoxContainer.new()
	_feed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_feed_box.add_theme_constant_override("separation", 6)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_wrap.add_child(_feed_box)
	return feed_wrap

# ── Journal à onglets ──────────────────────────────────────
func _build_log() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.custom_minimum_size = Vector2(0, 180)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	outer.add_child(tabs)
	var tab_labels := Translations.log_tabs()
	for i in LOG_TAB_KEYS.size():
		var key := LOG_TAB_KEYS[i]
		var b := Button.new()
		b.text = tab_labels[i]
		b.toggle_mode = true
		b.button_pressed = (key == _log_filter)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var is_active := (key == _log_filter)
		var tc := UIColors.FILTER_ON if is_active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color",         tc)
		b.add_theme_color_override("font_pressed_color", UIColors.FILTER_ON)
		b.add_theme_color_override("font_hover_color",   Color(1, 1, 1, 0.75))
		b.add_theme_stylebox_override("normal",   UIHelpers.card_style(tc, 0.0 if not is_active else 0.12, 0.0 if not is_active else 0.50, 1 if is_active else 0, 4))
		b.add_theme_stylebox_override("pressed",  UIHelpers.card_style(UIColors.FILTER_ON, 0.12, 0.50, 1, 4))
		b.add_theme_stylebox_override("hover",    UIHelpers.card_style(UIColors.TEXT_MUTED, 0.08, 0.30, 0, 4))
		b.pressed.connect(_set_filter.bind(key))
		tabs.add_child(b)
		_tab_buttons[key] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var panel := PanelContainer.new()
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.CARD_NEUTRAL, 0.05, 0.30, 1, 4))
	outer.add_child(panel)
	var m := UIHelpers.margin_of(6)
	panel.add_child(m)
	m.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_log_vbox)
	return outer

# ── Barre de bas ───────────────────────────────────────────
func _build_bottom_bar() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	_xp_label = Label.new()
	_xp_label.text = Translations.T("combat.xp_label")
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_label.add_theme_font_size_override("font_size", 15)
	_xp_label.add_theme_color_override("font_color", UIColors.FILTER_ON)
	vbox.add_child(_xp_label)

	var tcolor := _hero_tier_color()
	_flee_btn = Button.new()
	_flee_btn.text = Translations.T("combat.end_btn")
	_flee_btn.custom_minimum_size = Vector2(0, 42)
	_flee_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flee_btn.add_theme_font_size_override("font_size", 15)
	_flee_btn.add_theme_color_override("font_color", tcolor)
	_flee_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	_flee_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	_flee_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(_flee_btn)
	_flee_btn.pressed.connect(_on_flee_pressed)

	var flee_margin := MarginContainer.new()
	flee_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flee_margin.add_theme_constant_override("margin_left",  5)
	flee_margin.add_theme_constant_override("margin_right", 5)
	flee_margin.add_theme_constant_override("margin_bottom", 4)
	flee_margin.add_child(_flee_btn)
	vbox.add_child(flee_margin)
	return vbox

# ── Helpers UI ─────────────────────────────────────────────

# Description lisible de l'effet d'une bénédiction (pour le tooltip).
# Effets supportés par AdventureSystem : "heal" et "xp_bonus".
func _benediction_desc(effet: String, valeur: int) -> String:
	match effet:
		Enums.BlessEffect.HEAL:     return Translations.T("combat.bless.heal") % valeur
		Enums.BlessEffect.XP_BONUS: return Translations.T("combat.bless.xp")   % valeur
		_:                          return effet if effet != "" else Translations.T("combat.bless.unknown")

# ═══════════════════════════════════════════════════════════
#  Signaux
# ═══════════════════════════════════════════════════════════

func _connect_signals() -> void:
	EventBus.adventure_started.connect(_on_adventure_started)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.creature_unique_vaincue.connect(_on_creature_unique_vaincue)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.adventure_stopped.connect(_on_adventure_stopped)
	EventBus.entity_ready_to_evolve.connect(_on_entity_ready_to_evolve)
	CombatPlayer.step_started.connect(_on_step_started)
	CombatPlayer.step_ended.connect(_on_step_ended)

# ═══════════════════════════════════════════════════════════
#  Handlers
# ═══════════════════════════════════════════════════════════

func _on_adventure_started(_biome_id: String) -> void:
	_flee_btn.disabled = false
	_cycle_xp = 0.0
	_update_xp_label()
	_update_zone_label(AdventureSystem.zone_courante)
	if AdventureSystem.zone_courante == Enums.Zone.ABYSSE:
		_show_unique_indicator()

	var c      := GameData.get_entity("hero")
	var htier  := int(c.get("maitrise_actuelle", 0))
	var hname  := (c.get("nom_affichage_fr", c.get("name", "Héros")) as String)
	_hero_name.text = hname.to_upper()
	_hero_ring.setup(UIColors.tier_color(htier))
	_hero_ring.set_hp(AdventureSystem.current_hp, AdventureSystem.current_hp)
	_hero_ring.enter_combat()
	_present_name(_hero_name_chip, _hero_name_style, UIColors.tier_color(htier))
	_hide_action(_hero_action)

	# Tooltip JRPG sur le héros (stats effectives avec équipement)
	var hstats := GameData.get_effective_stats("hero")
	var heqp   := GameData.get_equipment_bonuses()
	var htt    := Translations.T("combat.tt_stats") % [
		GameData.get_tier_name(htier),
		int(AdventureSystem.current_hp),
		int(hstats.get("atk", 0)) + int(heqp.get("atk", 0)),
		int(hstats.get("def", 0)) + int(heqp.get("def", 0))]
	UIHelpers.register_tooltip(_hero_name, hname, htt, UIColors.tier_color(htier),
			c.get("lore_fr", "") as String)

	# Colonne ennemi en attente (vide) jusqu'au premier événement.
	_enemy_name.text = "—"
	_enemy_ring.setup(UIColors.TEXT_MUTED)
	_enemy_ring.set_hp(0, 1)
	_hide_action(_enemy_action)

	if _mechanic_label:
		_mechanic_label.visible = false
	match BiomeMechanics.active_mechanic:
		"ambush":
			var ac := Color(1.0, 0.42, 0.10)
			_push_feed(Translations.mech_name("ambush"), ac)
			_show_mechanic_label("⚡ " + Translations.mech_name("ambush"), ac)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("ambush"),
					Translations.mech_desc("ambush"), ac)
		"poison":
			var pc := Color(0.62, 0.15, 0.78)
			_push_feed(Translations.mech_name("poison"), pc)
			_show_mechanic_label("☠ " + Translations.mech_name("poison"), pc)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("poison"),
					Translations.mech_desc("poison"), pc)
		"endurcissement":
			var ec := Color(0.80, 0.55, 0.25)
			_push_feed(Translations.mech_name("endurcissement"), ec)
			_show_mechanic_label("🗻 " + Translations.mech_name("endurcissement"), ec)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("endurcissement"),
					Translations.mech_desc("endurcissement"), ec)

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"trap":
			var trap := event_data.get("trap", {}) as Dictionary
			var tname := trap.get("nom_affichage_fr", "Piège") as String
			_enemy_name.text = tname.to_upper()
			_enemy_ring.setup(UIColors.TYPE_TRAP)
			_enemy_ring.set_hp(1, 1)
			_enemy_ring.enter_combat()
			_present_name(_enemy_name_chip, _enemy_name_style, UIColors.TYPE_TRAP)
			_hide_action(_enemy_action)
			var tdmg := int(trap.get("damage", 0))
			var trap_tt := Translations.T("combat.trap_tt") % tdmg
			var ignored := event_data.get("ignored", false) as bool
			if ignored:
				trap_tt += Translations.T("combat.trap_ignored")
			UIHelpers.register_tooltip(_enemy_name, tname, trap_tt, UIColors.TYPE_TRAP)
			var trap_detail := Translations.T("combat.stinger.ignored") if ignored \
					else Translations.T("combat.stinger.trap_dmg") % tdmg
			_show_event_stinger(Translations.T("combat.stinger.trap"), tname,
					trap_detail, UIColors.TYPE_TRAP, not ignored)
			if not ignored:
				_hero_ring.update_hp(AdventureSystem.current_hp)
				_hero_ring.damage(tdmg, false)
				_check_danger_pulse()
				_add_log("[color=%s]%s[/color] inflige [color=%s]-%d[/color]"
						% [_hex(UIColors.TIER_EPIQUE), tname, _hex(UIColors.LOG_DEFEAT), tdmg],
						["monster", "attack", "status"])
		"benediction":
			var bene := event_data.get("effect", {}) as Dictionary
			var bname := bene.get("nom_affichage_fr", "Bénédiction") as String
			_enemy_name.text = bname.to_upper()
			_enemy_ring.setup(UIColors.TYPE_BENEDICTION)
			_enemy_ring.set_hp(1, 1)
			_enemy_ring.enter_combat()
			_present_name(_enemy_name_chip, _enemy_name_style, UIColors.TYPE_BENEDICTION)
			_hide_action(_enemy_action)
			var beff   := bene.get("effet", "") as String
			var bval   := int(bene.get("valeur", 0))
			var bdesc  := _benediction_desc(beff, bval)
			UIHelpers.register_tooltip(_enemy_name, bname,
				Translations.T("combat.bless_tt") % bdesc,
				UIColors.TYPE_BENEDICTION)
			_show_event_stinger(Translations.T("combat.stinger.bless"), bname,
					bdesc, UIColors.TYPE_BENEDICTION, false)
			_add_log("[color=%s]%s[/color]" % [_hex(UIColors.TYPE_BENEDICTION), bname], ["status"])

func _on_combat_started(hero_id: String, enemy: Dictionary,
		hero_hp: float, enemy_hp: float) -> void:
	var c        := GameData.get_entity(hero_id)
	var htier    := int(c.get("maitrise_actuelle", 0))
	var hero_max := AdventureSystem.get_max_hp()
	_hero_name.text = (c.get("nom_affichage_fr", c.get("name", "Héros")) as String).to_upper()
	_hero_ring.setup(UIColors.tier_color(htier))
	_hero_ring.set_hp(hero_hp, hero_max)

	var ename      := enemy.get("name", "Ennemi") as String
	var etier      := int(enemy.get("tier", 0))
	var etier_name := GameData.get_tier_name(etier)
	_enemy_name.text = ename.to_upper()
	_enemy_ring.setup(UIColors.tier_color(etier))
	_enemy_ring.set_hp(enemy_hp, enemy_hp)
	# Arrivée de la rencontre : pop élastique de l'anneau + de la plaque.
	_enemy_ring.enter_combat()
	_present_name(_enemy_name_chip, _enemy_name_style, UIColors.tier_color(etier))

	# Tooltip JRPG sur le nom de l'ennemi : rang + stats
	var ett := Translations.T("combat.tt_stats") % [
		etier_name,
		int(enemy_hp),
		int(enemy.get("atk", 0)),
		int(enemy.get("def", 0))]
	var enemy_entity := GameData.get_entity(enemy.get("id", ""))
	UIHelpers.register_tooltip(_enemy_name, ename, ett, UIColors.tier_color(etier),
			enemy_entity.get("lore_fr", "") as String)

	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_hero_shield = 0.0
	_stop_danger_pulse()
	_clear_state_pills()
	_flee_btn.disabled = false
	_add_log(Translations.T("combat.appears") \
			% ("[color=%s]%s[/color]" % [_hex(Color(1.0, 0.8, 0.2)), ename]), ["monster"])

# Début du cooldown : on affiche l'INTENTION de l'attaquant et on lance la
# charge de son anneau. Aucun dégât appliqué ici — l'attaque atterrit à la
# fin du cooldown (_on_step_ended). Pendant ce temps, l'autre entité n'affiche
# rien (pill masquée).
func _on_step_started(step: CombatStep) -> void:
	# Tick de poison : instantané, pas d'action chargée ni d'intention affichée.
	if step.is_poison or step.is_passive_poison:
		return

	var is_hero := step.attacker == "hero"
	var ring := _hero_ring if is_hero else _enemy_ring
	var lbl  := _hero_action if is_hero else _enemy_action
	var base_col := UIColors.STAT_ATK if is_hero else UIColors.TYPE_TRAP
	_show_action(lbl, Translations.T("combat.action.crit") if step.is_crit else Translations.T("combat.action.attack"),
			UIColors.FILTER_ON if step.is_crit else base_col)
	ring.set_cooldown(0.0)
	# La charge de l'anneau dure exactement un step côté CombatPlayer :
	# l'attaque atterrit visuellement quand l'anneau est plein.
	var tw := create_tween()
	tw.tween_method(ring.set_cooldown, 0.0, 1.0, CombatPlayer.step_duration).set_ease(Tween.EASE_IN)

# Fin du cooldown : l'attaque atterrit. On applique les dégâts/soins/états,
# on réinitialise les anneaux et on masque les pills d'action.
func _on_step_ended(step: CombatStep) -> void:
	if step.is_poison or step.is_passive_poison:
		_enemy_ring.update_hp(float(step.target_hp_after))
		_enemy_ring.poison(step.damage)
		var poison_tag := Translations.T("combat.poison") if step.is_poison else Translations.T("combat.venom")
		_add_log("[color=%s]%s[/color] [color=%s]-%d[/color]"
				% [_hex(UIColors.TIER_EPIQUE), poison_tag, _hex(UIColors.LOG_DEFEAT), step.damage],
				["status", "attack"])
		if step.is_killing_blow:
			_kill_impact(_enemy_ring)
	elif step.attacker == "hero":
		_enemy_ring.update_hp(float(step.target_hp_after))
		_enemy_ring.damage(step.damage, step.is_crit)
		if step.is_crit:
			_screen_shake(1.7)
		if step.is_killing_blow:
			_kill_impact(_enemy_ring)
		_log_attack(_hero_name.text, step.damage, step.is_crit, ["hero", "attack"])
		if step.passive_poison_proc:
			_add_log("[color=%s]%s[/color]" % [_hex(UIColors.TIER_EPIQUE), Translations.T("combat.venom_contact")], ["status"])
			_update_poison_pill(true)
	else:
		if step.shield_absorbed > 0:
			_hero_shield = maxf(_hero_shield - float(step.shield_absorbed), 0.0)
			_update_shield_pill(int(_hero_shield))
			_add_log("[color=%s]%s[/color]"
					% [_hex(Color(0.3, 0.7, 1.0)), Translations.T("combat.shield_absorb") % step.shield_absorbed], ["defense", "status"])
		if step.damage > 0:
			_hero_ring.update_hp(float(step.target_hp_after))
			_hero_ring.damage(step.damage, step.is_crit)
			if step.is_crit:
				_screen_shake(1.7)
			if step.is_killing_blow:
				_kill_impact(_hero_ring)
			_check_danger_pulse()
		elif step.shield_absorbed > 0:
			_hero_ring.update_hp(float(step.target_hp_after))
		if step.is_shield_proc:
			_hero_shield = float(step.shield_value)
			_push_feed(Translations.T("combat.shield_pill") % step.shield_value, Color(0.3, 0.7, 1.0))
			_update_shield_pill(int(_hero_shield))
			_add_log("[color=%s]%s[/color]" % [_hex(Color(0.3, 0.7, 1.0)), Translations.T("combat.shield_proc")], ["defense", "status"])
		_log_attack(_enemy_name.text, step.damage, step.is_crit, ["monster", "attack"])

	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)

func _on_combat_ended(result: Dictionary) -> void:
	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_stop_danger_pulse()
	_clear_state_pills()
	if result.get("victory", false):
		_hero_ring.celebrate()
		_enemy_ring.fade_defeated()
		# La plaque du vaincu s'éteint avec lui (la prochaine rencontre la ravive).
		create_tween().tween_property(_enemy_name_chip, "modulate:a", 0.35, 0.5)
		_cycle_xp = AdventureSystem.get_cycle_xp()
		_update_xp_label()
		_add_log("[color=%s]%s[/color]" % [_hex(UIColors.LOG_VICTORY), Translations.T("combat.victory")], ["hero"])
	else:
		_enemy_ring.celebrate()
		_hero_ring.fade_defeated()
		create_tween().tween_property(_hero_name_chip, "modulate:a", 0.35, 0.5)
		_add_log("[color=%s]%s[/color]" % [_hex(Color(1.0, 0.5, 0.2)), Translations.T("combat.defeat")], ["monster"])


func _on_heal_applied(amount: float, new_hp: float) -> void:
	_hero_ring.update_hp(new_hp)
	_hero_ring.heal(int(amount))
	_push_feed(Translations.T("combat.regen") % int(amount), UIColors.HEAL_COLOR)
	_add_log("[color=%s]%s[/color]" % [_hex(UIColors.HEAL_COLOR), Translations.T("combat.regen") % int(amount)], ["heal"])
	_check_danger_pulse()

func _on_cycle_ended(result: Dictionary) -> void:
	_flee_btn.disabled = true
	_cycle_xp = float(result.get("xp_total", 0.0))
	_update_xp_label()
	_navigate_to_summary()

func _on_adventure_stopped() -> void:
	_navigate_to_summary()

func _on_flee_pressed() -> void:
	AdventureSystem.stop_adventure()

# ═══════════════════════════════════════════════════════════
#  Animation cooldown / shake / feed
# ═══════════════════════════════════════════════════════════

# ─── Stinger d'événement (piège / bénédiction) ──────────────
# Bandeau central impossible à rater : flash plein écran teinté +
# slam-in (scale TRANS_BACK), maintien ~AFFICHAGE_EVENEMENT, fondu.
# Résout « je ne vois jamais les pièges/bénédictions » : sans journal,
# le seul indice était le nom dans la colonne ennemie pendant 2,5 s.
func _show_event_stinger(title: String, name_txt: String, detail: String,
		color: Color, danger: bool) -> void:
	if is_instance_valid(_stinger):
		_stinger.queue_free()

	# Flash plein écran teinté (rouge danger / vert bénédiction).
	var flash := ColorRect.new()
	flash.color = Color(color.r, color.g, color.b, 0.18)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 90
	add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	ftw.tween_callback(flash.queue_free)

	# Bandeau centré dans le tiers haut de la zone de combat.
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.anchor_bottom = 0.58
	holder.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	holder.z_index       = 95
	add_child(holder)
	_stinger = holder

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.04, 0.05, 0.09, 0.94)
	ps.border_color = Color(color.r, color.g, color.b, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.shadow_color = Color(color.r, color.g, color.b, 0.35)
	ps.shadow_size  = 16
	panel.add_theme_stylebox_override("panel", ps)
	holder.add_child(panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)

	var kind_lbl := Label.new()
	kind_lbl.text = title
	kind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_lbl.add_theme_font_size_override("font_size", 12)
	kind_lbl.add_theme_color_override("font_color", color.lightened(0.25))
	vb.add_child(kind_lbl)

	var name_lbl := Label.new()
	name_lbl.text = name_txt.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	vb.add_child(name_lbl)

	if detail != "":
		var detail_lbl := Label.new()
		detail_lbl.text = detail
		detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_lbl.add_theme_font_size_override("font_size", 17)
		detail_lbl.add_theme_color_override("font_color", color.lightened(0.30))
		detail_lbl.add_theme_constant_override("outline_size", 4)
		detail_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		vb.add_child(detail_lbl)

	if danger:
		_screen_shake()

	# Slam-in → maintien → fondu de sortie.
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_callback(func() -> void:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(1.35, 1.35)
	)
	tw.set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# set_parallel(false) : tout ce qui suit redevient séquentiel (chain()
	# ne chaînerait que le tweener suivant, le fondu partirait trop tôt).
	tw.set_parallel(false)
	tw.tween_interval(maxf(Balance.AFFICHAGE_EVENEMENT - 0.3, 0.6))
	tw.tween_property(holder, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)

# Shake d'écran : translation X/Y amortie sur ~350ms puis retour.
# strength : 1.0 = coup normal, ~1.7 = critique (plus ample + vertical).
func _screen_shake(strength: float = 1.0) -> void:
	var tw := create_tween()
	var amps := [5.0, -5.0, 4.0, -3.0]
	for a: float in amps:
		tw.tween_property(_shaker, "position",
				Vector2(a * strength, -a * 0.45 * (strength - 0.6)),
				0.35 / float(amps.size())).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_shaker, "position", Vector2.ZERO, 0.05)

# Ajoute un pill transitoire dans le feed (pop-in, disparaît après ~2s).
func _push_feed(text: String, color: Color) -> void:
	if not _feed_box:
		return
	var box := PanelContainer.new()
	var style := UIHelpers.card_style(color, 0.26, 0.90, 1, 9)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 2
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_color_override("font_color", color.lightened(0.30))
	box.add_child(lbl)
	_feed_box.add_child(box)
	# Pop-in (pivot connu une fois la taille calculée).
	box.scale = Vector2(0.5, 0.5)
	box.resized.connect(func() -> void:
		box.pivot_offset = box.size * 0.5
	, CONNECT_ONE_SHOT)
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	# Suppression garantie via un SceneTreeTimer indépendant du Tween.
	get_tree().create_timer(2.6).timeout.connect(box.queue_free)

# ═══════════════════════════════════════════════════════════
#  Journal
# ═══════════════════════════════════════════════════════════

# Affiche l'intention d'action (capsule visible). Le parent du label est la capsule.
func _show_action(lbl: Label, text: String, color: Color) -> void:
	lbl.text = text
	lbl.add_theme_color_override("font_color", color.lightened(0.30))
	var box := lbl.get_parent()
	if box is PanelContainer:
		# Capsule bien visible : fond plus dense, bordure franche, padding.
		var style := UIHelpers.card_style(color, 0.30, 0.95, 1, 9)
		style.content_margin_left   = 12
		style.content_margin_right  = 12
		style.content_margin_top    = 3
		style.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", style)
		box.visible = true
		# Pop d'annonce : la capsule claque à chaque intention d'action.
		var bc := box as Control
		bc.pivot_offset = bc.size * 0.5
		bc.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(bc, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Masque entièrement la capsule d'action : aucun résidu visible hors action.
func _hide_action(lbl: Label) -> void:
	var box := lbl.get_parent()
	if box is PanelContainer:
		box.visible = false

# Ajoute une entrée de log (la plus récente en haut), taguée pour le filtre.
# No-op tant que LOG_ENABLED est false (journal non construit).
func _add_log(bbcode: String, tags: Array) -> void:
	if not LOG_ENABLED:
		return
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content    = true
	rt.scroll_active  = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 12)
	rt.text = bbcode
	_log_vbox.add_child(rt)
	_log_vbox.move_child(rt, 0)
	_log_entries.push_front({"node": rt, "tags": tags})
	rt.visible = _matches_filter(tags)

func _log_attack(attacker_name: String, dmg: int, is_crit: bool, tags: Array) -> void:
	var is_hero_attacker := "hero" in tags
	var prefix   := "[color=%s]%s[/color] " % [
		_hex(Color(0.55, 0.36, 0.97) if is_hero_attacker else Color(0.86, 0.15, 0.15)),
		"⚔" if is_hero_attacker else "🗡"
	]
	var name_part := "[color=%s]%s[/color]" % [_hex(UIColors.LOG_IGNORED), attacker_name]
	var dmg_part: String
	if is_crit:
		dmg_part = "[b][color=%s]★ %d[/color][/b]" % [_hex(UIColors.FILTER_ON), dmg]
	else:
		dmg_part = "[color=%s]-%d[/color]" % [_hex(UIColors.LOG_DEFEAT), dmg]
	_add_log("%s%s → %s" % [prefix, name_part, dmg_part], tags)

func _set_filter(tab: String) -> void:
	_log_filter = tab
	for tab_name: String in _tab_buttons:
		var b: Button = _tab_buttons[tab_name]
		var active := (tab_name == tab)
		b.button_pressed = active
		var tc := UIColors.FILTER_ON if active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color", tc)
		b.add_theme_stylebox_override("normal", UIHelpers.card_style(tc, 0.12 if active else 0.0, 0.50 if active else 0.0, 1 if active else 0, 4))
	for entry: Dictionary in _log_entries:
		entry["node"].visible = _matches_filter(entry["tags"])

func _matches_filter(tags: Array) -> bool:
	return _log_filter == "all" or _log_filter in tags

# ═══════════════════════════════════════════════════════════
#  Zone + Créature Unique (overlays conservés)
# ═══════════════════════════════════════════════════════════

func _build_zone_label() -> void:
	_zone_label = Label.new()
	_zone_label.anchor_left = 0.0; _zone_label.anchor_right = 1.0
	_zone_label.anchor_top = 0.0;  _zone_label.anchor_bottom = 0.0
	_zone_label.offset_top = 6;    _zone_label.offset_bottom = 30
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_zone_label)

func _build_mechanic_label() -> void:
	_mechanic_label = Label.new()
	_mechanic_label.anchor_left  = 1.0; _mechanic_label.anchor_right  = 1.0
	_mechanic_label.anchor_top   = 0.0; _mechanic_label.anchor_bottom = 0.0
	_mechanic_label.offset_left  = -170; _mechanic_label.offset_right = -6
	_mechanic_label.offset_top   = 6;    _mechanic_label.offset_bottom = 30
	_mechanic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mechanic_label.add_theme_font_size_override("font_size", 13)
	_mechanic_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_mechanic_label.visible = false
	add_child(_mechanic_label)

func _update_zone_label(zone: Enums.Zone) -> void:
	if not _zone_label:
		return
	var idx   := clampi(int(zone), 0, 2)
	var color := UIColors.zone_color(idx)
	_zone_label.text = "◆ " + Translations.zone_name(idx)
	_zone_label.add_theme_color_override("font_color", color)
	UIHelpers.register_tooltip(_zone_label, Translations.zone_name(idx),
			Translations.zone_tooltip(idx), color)

func _show_unique_indicator() -> void:
	if _unique_panel != null:
		return
	var biome := GameData.get_entity(AdventureSystem.current_biome_id)
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return
	var nom            := unique.get("nom_affichage_fr", "???") as String
	var already_beaten := biome.get("creature_unique_vaincue", false) as bool
	var color          := UIColors.ZONE_ABYSSE

	_unique_panel = PanelContainer.new()
	_unique_panel.anchor_left = 0.5; _unique_panel.anchor_right = 0.5
	_unique_panel.anchor_top = 0.0;  _unique_panel.anchor_bottom = 0.0
	_unique_panel.offset_left = -150; _unique_panel.offset_right = 150
	_unique_panel.offset_top = 34;    _unique_panel.offset_bottom = 96
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.06, 0.90) if already_beaten else Color(0.18, 0.0, 0.0, 0.90)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_unique_panel.add_theme_stylebox_override("panel", style)
	add_child(_unique_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_unique_panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = Translations.T("combat.unique_beaten" if already_beaten else "combat.unique_watches") % nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED if already_beaten else color)
	vb.add_child(lbl)
	var btn := Button.new()
	btn.text = Translations.T("combat.unique_refight" if already_beaten else "combat.unique_fight") % nom
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(color, 0.15, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(color, 0.30, 1.0, 1, 4))
	btn.pressed.connect(AdventureSystem.start_unique_combat)
	vb.add_child(btn)

func _hide_unique_indicator() -> void:
	if _unique_panel and is_instance_valid(_unique_panel):
		_unique_panel.queue_free()
	_unique_panel = null

func _on_creature_unique_vaincue(_biome_id: String, ingredient_id: String, passif_id: String) -> void:
	_hide_unique_indicator()
	_show_unique_indicator()  # reconstruit avec état "déjà vaincu" + bouton réaffronter
	var ingr := GameData.get_entity(ingredient_id).get("nom_affichage_fr", ingredient_id) as String
	var passif := GameData.get_entity(passif_id).get("nom_affichage_fr", passif_id) as String
	_add_log("[color=%s]%s[/color]"
			% [_hex(Color(1.0, 0.8, 0.2)), Translations.T("combat.unique_slain") % [ingr, passif]], ["hero"])

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

func _update_xp_label() -> void:
	if not _xp_label:
		return
	_xp_label.text = Translations.T("combat.xp_label_fmt") % int(_cycle_xp)
	# Petit pop à chaque gain : le compteur vit au rythme du cycle.
	_xp_label.pivot_offset = _xp_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(_xp_label, "scale", Vector2(1.12, 1.12), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_xp_label, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hero_tier_color() -> Color:
	return UIColors.tier_color(int(GameData.get_entity("hero").get("maitrise_actuelle", 0)))

# Convertit une couleur en chaîne hex "#rrggbb" pour le BBCode.
func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

func _navigate_to_summary() -> void:
	if _navigating:
		return
	_navigating = true
	UIHelpers.fade_to_scene(self, "res://scenes/cycle/CycleSummaryScreen.tscn")

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 4 (badge mécanique forte)
# ═══════════════════════════════════════════════════════════

func _show_mechanic_label(text: String, color: Color) -> void:
	if not _mechanic_label:
		return
	_mechanic_label.text = text
	_mechanic_label.add_theme_color_override("font_color", color)
	_mechanic_label.visible = true

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 5 (pulse PV danger ≤30 %)
# ═══════════════════════════════════════════════════════════

func _check_danger_pulse() -> void:
	var max_hp := AdventureSystem.get_max_hp()
	if max_hp <= 0.0:
		return
	var ratio := AdventureSystem.current_hp / max_hp
	if ratio <= 0.30 and AdventureSystem.current_hp > 0.0:
		if not _danger_pulse_tween or not _danger_pulse_tween.is_running():
			_start_danger_pulse()
	else:
		_stop_danger_pulse()

func _start_danger_pulse() -> void:
	if _danger_pulse_tween:
		_danger_pulse_tween.kill()
	_danger_pulse_tween = create_tween().set_loops()
	_danger_pulse_tween.tween_property(_hero_ring, "modulate:a", 0.45, 0.35).set_trans(Tween.TRANS_SINE)
	_danger_pulse_tween.tween_property(_hero_ring, "modulate:a", 1.0,  0.35).set_trans(Tween.TRANS_SINE)

func _stop_danger_pulse() -> void:
	if _danger_pulse_tween:
		_danger_pulse_tween.kill()
		_danger_pulse_tween = null
	if _hero_ring:
		_hero_ring.modulate.a = 1.0

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 6 (flash coup fatal)
# ═══════════════════════════════════════════════════════════

func _kill_impact(ring: CombatRing) -> void:
	var tw := create_tween()
	tw.tween_property(ring, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.06)
	tw.tween_property(ring, "modulate", Color.WHITE, 0.40).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 8 (pills d'état colorées)
# ═══════════════════════════════════════════════════════════

func _clear_state_pills() -> void:
	if _hero_states:
		for child in _hero_states.get_children():
			child.queue_free()
	if _enemy_states:
		for child in _enemy_states.get_children():
			child.queue_free()
	_shield_state_pill = null
	_poison_state_pill = null

func _update_shield_pill(value: int) -> void:
	var color := Color(0.3, 0.7, 1.0)
	if value <= 0:
		if _shield_state_pill and is_instance_valid(_shield_state_pill):
			_shield_state_pill.queue_free()
		_shield_state_pill = null
		return
	if _shield_state_pill == null or not is_instance_valid(_shield_state_pill):
		_shield_state_pill = _make_state_pill_node("🛡 %d" % value, color)
		if _hero_states:
			_hero_states.add_child(_shield_state_pill)
	else:
		(_shield_state_pill.get_child(0) as Label).text = "🛡 %d" % value

func _update_poison_pill(active: bool) -> void:
	var color := Color(0.62, 0.15, 0.78)
	if not active:
		if _poison_state_pill and is_instance_valid(_poison_state_pill):
			_poison_state_pill.queue_free()
		_poison_state_pill = null
		return
	if _poison_state_pill == null or not is_instance_valid(_poison_state_pill):
		_poison_state_pill = _make_state_pill_node(Translations.T("combat.venom_pill"), color)
		if _enemy_states:
			_enemy_states.add_child(_poison_state_pill)

func _make_state_pill_node(text: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.18, 0.70, 1, 6))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	box.add_child(lbl)
	return box

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 9 (notification d'évolution)
# ═══════════════════════════════════════════════════════════

func _on_entity_ready_to_evolve(entity_id: String) -> void:
	if not AdventureSystem.is_running:
		return
	var entity := GameData.get_entity(entity_id)
	var nom    := entity.get("nom_affichage_fr", entity.get("name", entity_id)) as String
	var tier   := int(entity.get("maitrise_actuelle", 0))
	_push_feed(Translations.T("combat.ready_evolve") % nom, UIColors.tier_color(mini(tier + 1, 5)))
