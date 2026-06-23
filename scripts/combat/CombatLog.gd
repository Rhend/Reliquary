# ============================================================
# CombatLog.gd — Journal de combat à onglets (extrait de CombatScene).
#
# Concern autonome : construit le panneau à onglets, stocke les entrées
# (RichTextLabel BBCode déjà formaté par l'appelant) et applique le filtre
# par catégorie. CombatScene ne garde qu'un `_log` + des wrappers fins.
#
# DORMANT par défaut (CombatScene.LOG_ENABLED = false) : `build()` n'est
# appelé que si le journal est activé ; `add()` est sinerte tant que le
# panneau n'est pas construit.
# ============================================================
class_name CombatLog
extends RefCounted

const TAB_KEYS: Array[String] = ["all", "hero", "monster", "attack", "defense", "heal", "status"]

var _vbox:    VBoxContainer
var _entries: Array = []          # [{node: RichTextLabel, tags: Array}]
var _filter:  String = "all"
var _tab_buttons: Dictionary = {}     # nom → Button

# Construit et retourne le panneau (onglets + zone scrollable). À ajouter
# à l'arbre par l'appelant.
func build() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.custom_minimum_size = Vector2(0, 180)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	outer.add_child(tabs)
	var tab_labels := Translations.log_tabs()
	for i in TAB_KEYS.size():
		var key := TAB_KEYS[i]
		var b := Button.new()
		b.text = tab_labels[i]
		b.toggle_mode = true
		b.button_pressed = (key == _filter)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var is_active := (key == _filter)
		var tc := UIColors.FILTER_ON if is_active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color",         tc)
		b.add_theme_color_override("font_pressed_color", UIColors.FILTER_ON)
		b.add_theme_color_override("font_hover_color",   Color(1, 1, 1, 0.75))
		b.add_theme_stylebox_override("normal",   UIHelpers.card_style(tc, 0.0 if not is_active else 0.12, 0.0 if not is_active else 0.50, 1 if is_active else 0, 4))
		b.add_theme_stylebox_override("pressed",  UIHelpers.card_style(UIColors.FILTER_ON, 0.12, 0.50, 1, 4))
		b.add_theme_stylebox_override("hover",    UIHelpers.card_style(UIColors.TEXT_MUTED, 0.08, 0.30, 0, 4))
		b.pressed.connect(set_filter.bind(key))
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

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_vbox)
	return outer

# Ajoute une entrée (la plus récente en haut), taguée pour le filtre. Inerte
# tant que le panneau n'a pas été construit (journal désactivé).
func add(bbcode: String, tags: Array) -> void:
	if _vbox == null:
		return
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content    = true
	rt.scroll_active  = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 12)
	rt.text = bbcode
	_vbox.add_child(rt)
	_vbox.move_child(rt, 0)
	_entries.push_front({"node": rt, "tags": tags})
	rt.visible = _matches_filter(tags)

func set_filter(tab: String) -> void:
	_filter = tab
	for tab_name: String in _tab_buttons:
		var b: Button = _tab_buttons[tab_name]
		var active := (tab_name == tab)
		b.button_pressed = active
		var tc := UIColors.FILTER_ON if active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color", tc)
		b.add_theme_stylebox_override("normal", UIHelpers.card_style(tc, 0.12 if active else 0.0, 0.50 if active else 0.0, 1 if active else 0, 4))
	for entry: Dictionary in _entries:
		entry["node"].visible = _matches_filter(entry["tags"])

func _matches_filter(tags: Array) -> bool:
	return _filter == "all" or _filter in tags
