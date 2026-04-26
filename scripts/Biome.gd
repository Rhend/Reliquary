# ============================================================
# Biome.gd — Scène d'aventure / combat.
#
# Mise en page :
#   [Titre du biome]
#   [Bandeau modificateur de cycle]   ← visible si modificateur actif
#   [Carte Héro]      [Carte Ennemi]
#   [Bandeau événement courant]
#   [Journal des 8 derniers événements]
#   [Bouton Quitter]
#
# Effets visuels (FX) :
#   • Dégâts flottants  : labels qui montent et s'estompent au-dessus des barres HP
#   • Flash HP          : la barre flashe blanc au moment d'un impact
#   • Tween HP smooth   : transition cubic ease-out sur 0.28 s
#   • Couleur HP        : verte/jaune/rouge pour le héro, inverse pour l'ennemi
#   • Pulse combo       : le label combo s'illumine dorée à chaque incrément
#   • Fondu de scène    : transition noir à chaque entrée / sortie
# ============================================================
extends Control

# ─── Héro (carte gauche) ────────────────────────────────────

var _c_hp_bar:    ProgressBar
var _c_hp_label:  Label
var _c_hp_style:  StyleBoxFlat   # Référence directe pour animer la couleur de remplissage
var _c_hp_tween:  Tween
var _c_atk_flash: Label          # Label "ATTAQUE !" qui pulse puis disparaît
var _combo_label: Label          # Compteur de combos propres consécutifs

# ─── Ennemi (carte droite) ──────────────────────────────────

var _e_name_label:  Label
var _e_stats_label: Label
var _e_hp_bar:      ProgressBar
var _e_hp_label:    Label
var _e_hp_style:    StyleBoxFlat
var _e_hp_tween:    Tween
var _e_atk_flash:   Label

# ─── Éléments partagés ──────────────────────────────────────

var _event_label:    Label       # Événement courant (remplacé à chaque événement)
var _modifier_label: Label       # Modificateur de cycle actif
var _log_vbox:       VBoxContainer  # Journal des derniers événements
var _fx_overlay:     Control     # Canvas transparent sur lequel on spawn les dégâts flottants
var _fade_rect:      ColorRect   # Overlay de transition de scène

# ─── État interne ────────────────────────────────────────────

var _enemy_max_hp:       float  = 0.0
var _current_enemy_name: String = "Ennemi"

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_build_ui()

	# Signaux de combat
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_turn.connect(_on_combat_turn)
	EventBus.combat_ended.connect(_on_combat_ended)

	# Signaux d'aventure
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)

	# Signaux FX / UI
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.modifier_activated.connect(_on_modifier_activated)
	EventBus.combo_changed.connect(_on_combo_changed)

	# Affiche le modificateur déjà actif si on arrive en cours d'aventure
	if not AdventureSystem.current_modifier.is_empty():
		_on_modifier_activated(AdventureSystem.current_modifier)

# ═══════════════════════════════════════════════════════════
#  Construction de l'interface
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	# Fond vert très sombre pour distinguer visuellement du village
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

	# Titre du biome
	var biome = GameData.get_entity(GameData.player.get("active_biome_id", ""))
	var title = Label.new()
	title.text = biome.get("name", "Biome").to_upper()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Bandeau modificateur (invisible jusqu'à l'émission du signal)
	_modifier_label = Label.new()
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.add_theme_font_size_override("font_size", 13)
	_modifier_label.add_theme_color_override("font_color", UIColors.MODIFIER_ACTIVE)
	_modifier_label.visible = false
	root.add_child(_modifier_label)

	# Ligne de combat : héro à gauche, ennemi à droite
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	_build_creature_card(row)
	_build_enemy_card(row)

	_build_event_banner(root)
	_build_event_log(root)

	# Bouton de sortie
	var exit_btn = Button.new()
	exit_btn.text = "Quitter le cycle"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	root.add_child(exit_btn)

	# ── FX overlay ─────────────────────────────────────────
	# Control transparent par-dessus tout — les dégâts flottants y sont spawned
	_fx_overlay = Control.new()
	_fx_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_overlay)

	# ── Overlay de fondu ────────────────────────────────────
	# Doit être le DERNIER enfant pour être rendu par-dessus tout le reste
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	# Fondu d'entrée : noir → transparent
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.40)

# ─── Carte héro ─────────────────────────────────────────────

func _build_creature_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	var creature_id    = GameData.player.get("active_creature_id", "")
	var creature       = GameData.get_entity(creature_id)
	var equip_bonuses  = GameData.get_equipment_bonuses()
	var eff_stats      = GameData.get_effective_stats(creature_id)
	var max_hp         = float(eff_stats.get("hp", 100)) + equip_bonuses.get("hp", 0.0)
	var initial_hp     = AdventureSystem.current_hp if AdventureSystem.is_running else max_hp

	_h1(vbox, creature.get("name", "Héro").to_upper())
	vbox.add_child(HSeparator.new())

	# Label HP avec valeurs courantes
	_c_hp_label      = Label.new()
	_c_hp_label.text = "PV : %.0f / %.0f" % [initial_hp, max_hp]
	vbox.add_child(_c_hp_label)

	# Barre de PV avec couleur dynamique
	_c_hp_style = _fill_style(UIColors.hero_hp(initial_hp / max_hp if max_hp > 0.0 else 1.0))
	_c_hp_bar   = _make_bar(_c_hp_style, max_hp, initial_hp)
	vbox.add_child(_c_hp_bar)

	# Stats effectives avec équipements
	var stats_lbl = Label.new()
	stats_lbl.text = "ATK %d   DEF %d   PV %d" % [
		int(eff_stats.get("atk", 0)) + int(equip_bonuses.get("atk", 0)),
		eff_stats.get("def", 0),
		int(max_hp)
	]
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	vbox.add_child(stats_lbl)

	# Noms des équipements portés
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

	# Compteur de combo — caché par défaut, affiché dès combo ≥ 2
	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 15)
	_combo_label.add_theme_color_override("font_color", UIColors.COMBO_COLOR)
	_combo_label.visible = false
	vbox.add_child(_combo_label)

	vbox.add_child(_spacer())

	# Flash FX "ATTAQUE !" (alpha=0 au repos, animé lors d'une attaque)
	_c_atk_flash = _flash_label("ATTAQUE !", Color(1.0, 0.92, 0.05))
	vbox.add_child(_c_atk_flash)

# ─── Carte ennemi ────────────────────────────────────────────

func _build_enemy_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m    = _pad(card, 16)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	# Nom de l'ennemi (remplacé dynamiquement au combat_started)
	_e_name_label      = Label.new()
	_e_name_label.text = "EN ATTENTE..."
	_e_name_label.add_theme_font_size_override("font_size", 18)
	_e_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_e_name_label)

	vbox.add_child(HSeparator.new())

	_e_hp_label      = Label.new()
	_e_hp_label.text = "PV : —"
	vbox.add_child(_e_hp_label)

	# Barre initialisée à 0 (mise à jour dans _on_combat_started)
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

# ─── Bandeau événement courant ───────────────────────────────

func _build_event_banner(parent: Node) -> void:
	var card = PanelContainer.new()
	parent.add_child(card)

	var m = _pad(card, 12)
	_event_label = Label.new()
	_event_label.text = "En attente du premier événement..."
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_child(_event_label)

# ─── Journal des événements (8 lignes max) ───────────────────

func _build_event_log(parent: Node) -> void:
	var panel = PanelContainer.new()
	parent.add_child(panel)

	var m = _pad(panel, 8)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	m.add_child(outer)

	var header = Label.new()
	header.text = "JOURNAL"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	outer.add_child(header)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size       = Vector2(0, 96)
	scroll.horizontal_scroll_mode    = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_log_vbox)

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
	_event_label.text = "Combat contre %s !" % _current_enemy_name
	_add_log_entry("Combat: %s  (PV %d)" % [_current_enemy_name, int(enemy_hp)],
		UIColors.LOG_COMBAT)

func _on_combat_turn(attacker: String, damage: float,
		creature_hp: float, enemy_hp: float) -> void:
	var c_name = GameData.get_entity(
		GameData.player.get("active_creature_id", "")).get("name", "Héro")

	if attacker == "creature":
		_set_enemy_hp(enemy_hp)
		_event_label.text = "%s inflige %.0f dégâts — PV ennemi : %.0f" % [
			c_name, damage, maxf(enemy_hp, 0.0)
		]
		_flash(_c_atk_flash)
		# Dégâts flottants dorés au-dessus de la barre HP de l'ennemi
		_spawn_damage_number(_e_hp_bar, "-%.0f" % damage, UIColors.DMG_BY_HERO)
	else:
		_set_creature_hp(creature_hp)
		_event_label.text = "%s riposte : %.0f dégâts — PV restants : %.0f" % [
			_current_enemy_name, damage, maxf(creature_hp, 0.0)
		]
		_flash(_e_atk_flash)
		# Dégâts flottants rouges au-dessus de la barre HP du héro
		_spawn_damage_number(_c_hp_bar, "-%.0f" % damage, UIColors.DMG_BY_ENEMY)

func _on_combat_ended(result: Dictionary) -> void:
	var enemy_name = result.get("enemy", {}).get("name", "l'ennemi")
	if result.get("victory", false):
		_event_label.text = "Victoire contre %s !" % enemy_name
		_add_log_entry("Victoire vs %s" % enemy_name, UIColors.LOG_VICTORY)
	else:
		_event_label.text = "Défaite contre %s..." % enemy_name
		_add_log_entry("Défaite vs %s" % enemy_name, UIColors.LOG_DEFEAT)
	_set_creature_hp(result.get("remaining_creature_hp", 0.0))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		"positive":
			var effect = event_data.get("effect", {})
			_event_label.text = effect.get("name", "Événement positif")
			_add_log_entry(effect.get("name", "Événement positif"), UIColors.LOG_EVENT)
			_clear_enemy_display()

		"trap":
			var trap    = event_data.get("trap", {})
			var ignored = event_data.get("ignored", false)
			if ignored:
				_event_label.text = "Piège ignoré : %s  (Fantôme)" % trap.get("name","?")
				_add_log_entry("Piège ignoré: %s" % trap.get("name","?"), UIColors.LOG_IGNORED)
			else:
				_event_label.text = "Piège : %s  (−%.0f PV)" % [
					trap.get("name","?"), trap.get("damage",0.0)
				]
				_add_log_entry("Piège: %s  −%.0f PV" % [
					trap.get("name","?"), trap.get("damage",0.0)
				], UIColors.LOG_TRAP)
			_clear_enemy_display()
			_set_creature_hp(AdventureSystem.current_hp)

func _on_cycle_ended(result: Dictionary) -> void:
	if not result.get("victory", true):
		_event_label.text = "Cycle terminé — retour au village dans 2 s..."
		_add_log_entry("Cycle terminé — défaite", UIColors.LOG_DEFEAT)
	await get_tree().create_timer(2.0).timeout
	_fade_to("res://scenes/Village.tscn")

func _on_loot_dropped(drops: Array, enemy_name: String) -> void:
	var parts: Array = []
	for d in drops:
		parts.append("%s ×%d" % [d.get("name", "?"), d.get("qty", 1)])
	var text = "Butin [%s] : %s" % [enemy_name, ", ".join(PackedStringArray(parts))]
	_add_log_entry(text, UIColors.LOG_LOOT)

func _on_modifier_activated(modifier: Dictionary) -> void:
	var m_name = modifier.get("name", "—")
	var m_desc = modifier.get("desc", "")
	if m_name == "—" or m_name == "":
		_modifier_label.visible = false
		return
	_modifier_label.text    = "%s  —  %s" % [m_name, m_desc]
	_modifier_label.visible = true
	# Fondu d'apparition du bandeau
	_modifier_label.modulate.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_OUT)
	tw.tween_property(_modifier_label, "modulate:a", 1.0, 0.50)

func _on_combo_changed(count: int) -> void:
	if count > 1:
		_combo_label.text    = "COMBO  x%d" % count
		_combo_label.visible = true
		# Pulse dorée : illumine le label puis revient à blanc
		_combo_label.modulate = UIColors.COMBO_COLOR * 1.6
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_combo_label, "modulate", Color.WHITE, 0.35)
	else:
		_combo_label.visible = false

func _on_exit_pressed() -> void:
	AdventureSystem.stop_adventure()
	_fade_to("res://scenes/Village.tscn")

# ═══════════════════════════════════════════════════════════
#  Gestion des barres HP (tween + couleur + flash d'impact)
# ═══════════════════════════════════════════════════════════

func _set_creature_hp(hp: float) -> void:
	var val       = maxf(hp, 0.0)
	var decreased = val < _c_hp_bar.value   # true si le héro vient de recevoir des dégâts

	_c_hp_label.text = "PV : %.0f / %.0f" % [val, _c_hp_bar.max_value]

	# Tween smooth de la barre
	if _c_hp_tween:
		_c_hp_tween.kill()
	_c_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_c_hp_tween.tween_property(_c_hp_bar, "value", val, 0.28)

	var pct       = val / _c_hp_bar.max_value if _c_hp_bar.max_value > 0.0 else 1.0
	var new_color = UIColors.hero_hp(pct)

	if decreased:
		# Flash blanc → couleur cible : retour visuel d'impact
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

# Remet à zéro l'affichage de l'ennemi entre deux combats.
func _clear_enemy_display() -> void:
	_e_name_label.text  = "—"
	_e_stats_label.text = ""
	_e_hp_label.text    = "PV : —"
	_e_hp_bar.value     = 0.0

# ═══════════════════════════════════════════════════════════
#  Effets visuels (FX)
# ═══════════════════════════════════════════════════════════

# Spawn un label de dégâts flottant au-dessus de anchor_bar,
# qui monte puis disparaît en 0.85 s.
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

	# Tween parallèle : montée + estompe simultanées
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", start.y - 65.0, 0.85) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85) \
		.set_ease(Tween.EASE_IN).set_delay(0.28)
	# Libère le label une fois l'animation terminée
	tw.chain().tween_callback(lbl.queue_free)

# Anime un label "ATTAQUE !" ou "RIPOSTE !" : apparaît puis s'estompe.
func _flash(lbl: Label) -> void:
	var tw = create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.04)
	tw.tween_interval(0.28)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45)

# ─── Journal ─────────────────────────────────────────────────

# Ajoute une ligne colorée au journal. Supprime la plus ancienne si > 8 lignes.
func _add_log_entry(text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_vbox.add_child(lbl)
	while _log_vbox.get_child_count() > 8:
		_log_vbox.get_child(0).queue_free()

# ─── Navigation ──────────────────────────────────────────────

# Fondu vers noir puis changement de scène.
func _fade_to(scene_path: String) -> void:
	_fade_rect.color.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.30)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ═══════════════════════════════════════════════════════════
#  Utilitaires constructeurs UI
# ═══════════════════════════════════════════════════════════

# StyleBoxFlat pour le remplissage d'une ProgressBar, avec coins arrondis.
func _fill_style(color: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color                   = color
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left  = 4
	return s

# ProgressBar avec fond sombre et remplissage coloré.
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

# MarginContainer avec padding uniforme, ajouté à parent.
func _pad(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

# Titre centré en gras.
func _h1(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

# Spacer vertical extensible.
func _spacer() -> Control:
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

# Label FX (alpha 0 au repos) pour les animations d'attaque.
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
