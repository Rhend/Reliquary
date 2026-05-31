# ============================================================
# CombatScene — Scène de combat (refonte UI).
#
# Layout :
#   Zone combat : colonne Héro (gauche) ↔ colonne Ennemi (droite),
#                 séparées par un séparateur diagonal "VS".
#                 Chaque colonne : nom · double anneau (cooldown + PV)
#                 · pill d'action · pills d'états.
#   Feed passifs : bande de pills transitoires.
#   Journal      : log filtrable par onglets (Tout/Héro/Monstre/…).
#   Barre de bas : "XP ce cycle — X"  ·  bouton fin d'expédition.
#
# La logique de combat (CombatPlayer / CombatResolver / AdventureSystem)
# n'est pas modifiée : la scène ne fait que présenter les signaux.
# ============================================================
class_name CombatScene extends Control

# ─── Filtres du journal ──────────────────────────────────────
const LOG_TABS := ["Tout", "Héro", "Monstre", "Attaque", "Défense", "Soin", "État"]

# ─── Nœuds racine ────────────────────────────────────────────
var _shaker: Control          # conteneur décalé pour le shake d'écran

# ─── Colonnes combattants ────────────────────────────────────
var _hero_ring:   CombatRing
var _enemy_ring:  CombatRing
var _hero_name:   Label
var _enemy_name:  Label
var _hero_action: Label
var _enemy_action: Label
var _hero_states: HBoxContainer
var _enemy_states: HBoxContainer

# ─── Feed passifs ────────────────────────────────────────────
var _feed_box: HBoxContainer

# ─── Journal ─────────────────────────────────────────────────
var _log_vbox:    VBoxContainer
var _log_entries: Array = []          # [{node: RichTextLabel, tags: Array}]
var _log_filter:  String = "Tout"
var _tab_buttons: Dictionary = {}     # nom → Button

# ─── Barre de bas ────────────────────────────────────────────
var _xp_label: Label
var _flee_btn: Button

# ─── Overlays (zone + Unique) ────────────────────────────────
var _zone_label:   Label   = null
var _unique_panel: Control = null

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:    float = 0.0
var _prev_tick:   int   = 0
var _navigating:  bool  = false
var _hero_shield: float = 0.0

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
	root.add_child(_build_log())
	root.add_child(_build_bottom_bar())

	_build_zone_label()

# ── Zone de combat : 2 colonnes + séparateur diagonal ──────
func _build_combat_area() -> Control:
	# Héro (moitié gauche) | séparateur centré 80px | Ennemi (moitié droite).
	# La diagonale est tracée dans le band central et ne déborde pas sur les colonnes.
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.custom_minimum_size   = Vector2(0, 320)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_build_column(true))
	hbox.add_child(CombatVS.new())
	hbox.add_child(_build_column(false))
	return hbox

# Construit une colonne combattant ; renseigne les références membres.
func _build_column(is_hero: bool) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = "—"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	col.add_child(name_lbl)

	var ring := CombatRing.new()
	col.add_child(ring)

	# Pill d'action : PanelContainer + Label (on garde la référence au Label).
	# Masquée par défaut — aucune capsule visible hors d'une action chargée.
	var action_box := PanelContainer.new()
	action_box.visible = false
	action_box.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.12, 0.50, 1, 8))
	var action := Label.new()
	action.text = "—"
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.add_theme_font_size_override("font_size", 12)
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
	else:
		_enemy_name = name_lbl; _enemy_ring = ring; _enemy_action = action; _enemy_states = states
	return col

# ── Feed passifs ───────────────────────────────────────────
func _build_feed() -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(0, 28)
	_feed_box = HBoxContainer.new()
	_feed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_feed_box.add_theme_constant_override("separation", 6)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_feed_box)
	return wrap

# ── Journal à onglets ──────────────────────────────────────
func _build_log() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.custom_minimum_size = Vector2(0, 180)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	outer.add_child(tabs)
	for tab: String in LOG_TABS:
		var b := Button.new()
		b.text = tab
		b.toggle_mode = true
		b.button_pressed = (tab == _log_filter)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_set_filter.bind(tab))
		tabs.add_child(b)
		_tab_buttons[tab] = b

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
	var m := UIHelpers.margin_of(6)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	m.add_child(hbox)

	_xp_label = Label.new()
	_xp_label.text = "XP ce cycle — 0"
	_xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 15)
	_xp_label.add_theme_color_override("font_color", UIColors.FILTER_ON)
	hbox.add_child(_xp_label)

	var tcolor := _hero_tier_color()
	_flee_btn = Button.new()
	_flee_btn.text = "Mettre fin à l'expédition"
	_flee_btn.custom_minimum_size = Vector2(0, 42)
	_flee_btn.add_theme_font_size_override("font_size", 15)
	_flee_btn.add_theme_color_override("font_color", tcolor)
	_flee_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	_flee_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	_flee_btn.pressed.connect(_on_flee_pressed)
	hbox.add_child(_flee_btn)
	return m

# ── Helpers UI ─────────────────────────────────────────────

# Ajoute un pill d'état (infrastructure — aucun état actif pour l'instant).
# title : nom de l'état ; tooltip : description (valeur dynamique à calculer plus tard).
func _add_state_pill(states_box: HBoxContainer, title: String, tooltip: String, color: Color) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.18, 0.70, 1, 6))
	box.tooltip_text = tooltip
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	box.add_child(lbl)
	states_box.add_child(box)

# ═══════════════════════════════════════════════════════════
#  Signaux
# ═══════════════════════════════════════════════════════════

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
#  Handlers
# ═══════════════════════════════════════════════════════════

func _on_adventure_started(_biome_id: String) -> void:
	_flee_btn.disabled = false
	_cycle_xp = 0.0
	_update_xp_label()
	_update_zone_label(AdventureSystem.zone_courante)

	var cid    := GameData.player.get("active_creature_id", "") as String
	var c      := GameData.get_entity(cid)
	var htier  := int(c.get("maitrise_actuelle", 0))
	_hero_name.text = (c.get("nom_affichage_fr", c.get("name", "Héro")) as String).to_upper()
	_hero_ring.setup(UIColors.tier_color(htier))
	_hero_ring.set_hp(AdventureSystem.current_hp, AdventureSystem.current_hp)
	_hide_action(_hero_action)

	# Colonne ennemi en attente (vide) jusqu'au premier événement.
	_enemy_name.text = "—"
	_enemy_ring.setup(UIColors.TEXT_MUTED)
	_enemy_ring.set_hp(0, 1)
	_hide_action(_enemy_action)

	match BiomeMechanics.active_mechanic:
		"ambush":       _push_feed("Embuscade", Color(1.0, 0.42, 0.10))
		"bonne_etoile": _push_feed("Bonne Étoile", Color(0.30, 0.85, 0.40))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"trap":
			var trap := event_data.get("trap", {}) as Dictionary
			var tname := trap.get("nom_affichage_fr", "Piège") as String
			_enemy_name.text = tname.to_upper()
			_enemy_ring.setup(UIColors.TYPE_TRAP)
			_enemy_ring.set_hp(1, 1)
			_hide_action(_enemy_action)
			if not event_data.get("ignored", false):
				var dmg := int(trap.get("damage", 0))
				_hero_ring.update_hp(AdventureSystem.current_hp)
				_hero_ring.damage(dmg, false)
				_add_log("[color=%s]%s[/color] inflige [color=%s]-%d[/color]"
						% [_hex(UIColors.TIER_EPIQUE), tname, _hex(UIColors.LOG_DEFEAT), dmg],
						["Monstre", "Attaque", "État"])
		"benediction":
			var bene := event_data.get("effect", {}) as Dictionary
			var bname := bene.get("nom_affichage_fr", "Bénédiction") as String
			_enemy_name.text = bname.to_upper()
			_enemy_ring.setup(UIColors.TYPE_BENEDICTION)
			_enemy_ring.set_hp(1, 1)
			_hide_action(_enemy_action)
			_add_log("[color=%s]%s[/color]" % [_hex(UIColors.TYPE_BENEDICTION), bname], ["État"])

func _on_combat_started(creature_id: String, enemy: Dictionary,
		hero_hp: float, enemy_hp: float) -> void:
	var c        := GameData.get_entity(creature_id)
	var htier    := int(c.get("maitrise_actuelle", 0))
	var hero_max := AdventureSystem.get_max_hp()
	_hero_name.text = (c.get("nom_affichage_fr", c.get("name", "Héro")) as String).to_upper()
	_hero_ring.setup(UIColors.tier_color(htier))
	_hero_ring.set_hp(hero_hp, hero_max)

	var ename := enemy.get("name", "Ennemi") as String
	_enemy_name.text = ename.to_upper()
	_enemy_ring.setup(UIColors.tier_color(int(enemy.get("tier", 0))))
	_enemy_ring.set_hp(enemy_hp, enemy_hp)

	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_hero_shield = 0.0
	_prev_tick = 0
	_flee_btn.disabled = false
	_add_log("[color=%s]%s[/color] apparaît" % [_hex(Color(1.0, 0.8, 0.2)), ename], ["Monstre"])

# Début du cooldown : on affiche l'INTENTION de l'attaquant et on lance la
# charge de son anneau. Aucun dégât appliqué ici — l'attaque atterrit à la
# fin du cooldown (_on_step_ended). Pendant ce temps, l'autre entité n'affiche
# rien (pill masquée).
func _on_step_started(step: CombatStep) -> void:
	# Durée du step, calée sur le timing réel de CombatPlayer (sync _prev_tick).
	var ticks := maxi(step.tick_time - _prev_tick, 1)
	_prev_tick = step.tick_time
	var dur := maxf(float(ticks) * CombatPlayer.TICK_DURATION * GameSettings.combat_speed,
			CombatPlayer.MIN_STEP_DURATION)

	# Tick de poison : instantané, pas d'action chargée ni d'intention affichée.
	if step.is_poison or step.is_passive_poison:
		return

	var is_hero := step.attacker == "hero"
	var ring := _hero_ring if is_hero else _enemy_ring
	var lbl  := _hero_action if is_hero else _enemy_action
	var base_col := UIColors.STAT_ATK if is_hero else UIColors.TYPE_TRAP
	_show_action(lbl, "Critique !" if step.is_crit else "Attaque",
			UIColors.FILTER_ON if step.is_crit else base_col)
	ring.set_cooldown(0.0)
	var tw := create_tween()
	tw.tween_method(ring.set_cooldown, 0.0, 1.0, dur).set_ease(Tween.EASE_IN)

# Fin du cooldown : l'attaque atterrit. On applique les dégâts/soins/états,
# on réinitialise les anneaux et on masque les pills d'action.
func _on_step_ended(step: CombatStep) -> void:
	if step.is_poison or step.is_passive_poison:
		_enemy_ring.update_hp(float(step.target_hp_after))
		_enemy_ring.poison(step.damage)
		_add_log("[color=%s]Poison[/color] [color=%s]-%d[/color]"
				% [_hex(UIColors.TIER_EPIQUE), _hex(UIColors.LOG_DEFEAT), step.damage],
				["État", "Attaque"])
	elif step.attacker == "hero":
		_enemy_ring.update_hp(float(step.target_hp_after))
		_enemy_ring.damage(step.damage, step.is_crit)
		if step.is_crit:
			_screen_shake()
		_log_attack(_hero_name.text, step.damage, step.is_crit, ["Héro", "Attaque"])
		if step.passive_poison_proc:
			_add_log("[color=%s]Contact Venimeux[/color]" % _hex(UIColors.TIER_EPIQUE), ["État"])
	else:
		if step.shield_absorbed > 0:
			_hero_shield = maxf(_hero_shield - float(step.shield_absorbed), 0.0)
			_add_log("[color=%s]Bouclier absorbe %d[/color]"
					% [_hex(Color(0.3, 0.7, 1.0)), step.shield_absorbed], ["Défense", "État"])
		if step.damage > 0:
			_hero_ring.update_hp(float(step.target_hp_after))
			_hero_ring.damage(step.damage, step.is_crit)
			if step.is_crit:
				_screen_shake()
		elif step.shield_absorbed > 0:
			_hero_ring.update_hp(float(step.target_hp_after))
		if step.is_shield_proc:
			_hero_shield = float(step.shield_value)
			_push_feed("Bouclier +%d" % step.shield_value, Color(0.3, 0.7, 1.0))
			_add_log("[color=%s]Bouclier d'urgence activé[/color]" % _hex(Color(0.3, 0.7, 1.0)), ["Défense", "État"])
		_log_attack(_enemy_name.text, step.damage, step.is_crit, ["Monstre", "Attaque"])

	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)

func _on_combat_ended(result: Dictionary) -> void:
	_hero_ring.set_cooldown(0.0)
	_enemy_ring.set_cooldown(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	if result.get("victory", false):
		_hero_ring.celebrate()
		_enemy_ring.fade_defeated()
		_cycle_xp = AdventureSystem._cycle_xp
		_update_xp_label()
		_add_log("[color=%s]Victoire[/color]" % _hex(UIColors.LOG_VICTORY), ["Héro"])
	else:
		_enemy_ring.celebrate()
		_hero_ring.fade_defeated()
		_add_log("[color=%s]Défaite[/color]" % _hex(Color(1.0, 0.8, 0.2)), ["Monstre"])

func _on_heal_applied(amount: float, new_hp: float) -> void:
	_hero_ring.update_hp(new_hp)
	_hero_ring.heal(int(amount))
	_push_feed("Régénération +%d" % int(amount), UIColors.HEAL_COLOR)
	_add_log("[color=%s]Soin +%d[/color]" % [_hex(UIColors.HEAL_COLOR), int(amount)], ["Soin"])

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

# Shake d'écran : translateX ±5px sur ~350ms puis retour.
func _screen_shake() -> void:
	var tw := create_tween()
	var amps := [5.0, -5.0, 4.0, -3.0]
	for a: float in amps:
		tw.tween_property(_shaker, "position:x", a, 0.35 / float(amps.size())).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_shaker, "position:x", 0.0, 0.05)

# Ajoute un pill transitoire dans le feed (disparaît après ~2s).
func _push_feed(text: String, color: Color) -> void:
	if not _feed_box:
		return
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.16, 0.70, 1, 8))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	box.add_child(lbl)
	_feed_box.add_child(box)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	# Suppression garantie via un SceneTreeTimer indépendant du Tween.
	get_tree().create_timer(2.5).timeout.connect(box.queue_free)

# ═══════════════════════════════════════════════════════════
#  Journal
# ═══════════════════════════════════════════════════════════

# Affiche l'intention d'action (capsule visible). Le parent du label est la capsule.
func _show_action(lbl: Label, text: String, color: Color) -> void:
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	var box := lbl.get_parent()
	if box is PanelContainer:
		box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.12, 0.50, 1, 8))
		box.visible = true

# Masque entièrement la capsule d'action : aucun résidu visible hors action.
func _hide_action(lbl: Label) -> void:
	var box := lbl.get_parent()
	if box is PanelContainer:
		box.visible = false

# Ajoute une entrée de log (la plus récente en haut), taguée pour le filtre.
func _add_log(bbcode: String, tags: Array) -> void:
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
	var name_part := "[color=%s]%s[/color]" % [_hex(UIColors.LOG_IGNORED), attacker_name]
	var dmg_part: String
	if is_crit:
		dmg_part = "[b][color=%s]★ %d[/color][/b]" % [_hex(UIColors.FILTER_ON), dmg]
	else:
		dmg_part = "[color=%s]-%d[/color]" % [_hex(UIColors.LOG_DEFEAT), dmg]
	_add_log("%s inflige %s" % [name_part, dmg_part], tags)

func _set_filter(tab: String) -> void:
	_log_filter = tab
	for tab_name: String in _tab_buttons:
		_tab_buttons[tab_name].button_pressed = (tab_name == tab)
	for entry: Dictionary in _log_entries:
		entry["node"].visible = _matches_filter(entry["tags"])

func _matches_filter(tags: Array) -> bool:
	return _log_filter == "Tout" or _log_filter in tags

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
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone_label)

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
	var idx := clampi(int(zone), 0, 2)
	_zone_label.text = "◆ " + NOMS[idx]
	_zone_label.add_theme_color_override("font_color", UIColors.zone_color(idx))

func _show_unique_indicator() -> void:
	if _unique_panel != null:
		return
	var biome := GameData.get_entity(AdventureSystem.current_biome_id)
	if biome.get("creature_unique_vaincue", false):
		return
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return
	var nom := unique.get("nom_affichage_fr", "???") as String
	var color := UIColors.ZONE_ABYSSE

	_unique_panel = PanelContainer.new()
	_unique_panel.anchor_left = 0.5; _unique_panel.anchor_right = 0.5
	_unique_panel.anchor_top = 0.0;  _unique_panel.anchor_bottom = 0.0
	_unique_panel.offset_left = -150; _unique_panel.offset_right = 150
	_unique_panel.offset_top = 34;    _unique_panel.offset_bottom = 96
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.0, 0.0, 0.90)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_unique_panel.add_theme_stylebox_override("panel", style)
	add_child(_unique_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_unique_panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "☠  %s vous observe..." % nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	vb.add_child(lbl)
	var btn := Button.new()
	btn.text = "⚔  Affronter %s" % nom
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
	var ingr := GameData.get_entity(ingredient_id).get("nom_affichage_fr", ingredient_id) as String
	var passif := GameData.get_entity(passif_id).get("nom_affichage_fr", passif_id) as String
	_add_log("[color=%s]Créature Unique vaincue — %s, %s[/color]"
			% [_hex(Color(1.0, 0.8, 0.2)), ingr, passif], ["Héro"])

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

func _update_xp_label() -> void:
	if _xp_label:
		_xp_label.text = "XP ce cycle — %d" % int(_cycle_xp)

func _hero_tier_color() -> Color:
	var cid := GameData.player.get("active_creature_id", "") as String
	return UIColors.tier_color(int(GameData.get_entity(cid).get("maitrise_actuelle", 0)))

# Convertit une couleur en chaîne hex "#rrggbb" pour le BBCode.
func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

func _navigate_to_summary() -> void:
	if _navigating:
		return
	_navigating = true
	get_tree().change_scene_to_file("res://scenes/cycle/CycleSummaryScreen.tscn")
