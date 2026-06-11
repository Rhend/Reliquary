# ============================================================
# SettingsOverlay — Panneau Paramètres modal plein écran.
#
# Sections : Audio (musique / SFX) · Affichage (plein écran) ·
#            Sauvegarde (export / import) · Langue (FR / EN).
#
# Usage (Village) :
#   add_child(SettingsOverlay.new())
#
# Cycle de vie autonome :
#   • clic hors de la carte ou ✕ → l'overlay se libère lui-même ;
#   • Échap → géré par Village (_unhandled_key_input), qui ouvre/ferme ;
#   • changement de langue → l'overlay se reconstruit lui-même.
# ============================================================
class_name SettingsOverlay
extends ColorRect

func _ready() -> void:
	color        = Color(0.0, 0.0, 0.0, 0.45)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			queue_free()
	)
	GameSettings.language_changed.connect(_on_language_changed)
	_build()

func _on_language_changed(_lang: String) -> void:
	UIHelpers.clear_children(self)
	_build()

# ─── Construction ─────────────────────────────────────────────

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	# La carte intercepte les clics : cliquer dedans ne ferme pas l'overlay.
	# Fond OPAQUE : le panneau ne doit pas laisser transparaître le hub.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color     = UIColors.BG_CARD
	style.border_color = Color(UIColors.TEXT_HEADER, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var mg := UIHelpers.margin_of(16)
	card.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mg.add_child(vb)

	# ── En-tête ───────────────────────────────────────────────
	var hdr := HBoxContainer.new()
	vb.add_child(hdr)
	var title_lbl := Label.new()
	title_lbl.text = Translations.T("settings.title")
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	hdr.add_child(title_lbl)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	close_btn.pressed.connect(queue_free)
	hdr.add_child(close_btn)

	vb.add_child(_sep())

	# ── AUDIO ────────────────────────────────────────────────
	vb.add_child(_section(Translations.T("settings.audio")))
	vb.add_child(_slider(Translations.T("settings.music"), GameSettings.volume_music,
			func(v: float) -> void: GameSettings.set_volume_music(v)))
	vb.add_child(_slider(Translations.T("settings.sfx"),  GameSettings.volume_sfx,
			func(v: float) -> void: GameSettings.set_volume_sfx(v)))

	vb.add_child(_sep())

	# ── AFFICHAGE ────────────────────────────────────────────
	vb.add_child(_section(Translations.T("settings.display")))
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 10)
	vb.add_child(fs_row)
	var fs_lbl := Label.new()
	fs_lbl.text = Translations.T("settings.fullscreen")
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_lbl.add_theme_font_size_override("font_size", 13)
	fs_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	fs_row.add_child(fs_lbl)
	var fs_hint := Label.new()
	fs_hint.text = "F11"
	fs_hint.add_theme_font_size_override("font_size", 11)
	fs_hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	fs_row.add_child(fs_hint)
	var fs_check := CheckButton.new()
	fs_check.button_pressed = GameSettings.fullscreen
	fs_check.toggled.connect(func(v: bool) -> void: GameSettings.set_fullscreen(v))
	fs_row.add_child(fs_check)

	vb.add_child(_sep())

	# ── SAUVEGARDE ───────────────────────────────────────────
	vb.add_child(_section(Translations.T("settings.save")))
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	vb.add_child(save_row)
	var exp_btn := Button.new()
	exp_btn.text = Translations.T("settings.export")
	exp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_btn.pressed.connect(_export_save)
	save_row.add_child(exp_btn)
	var imp_btn := Button.new()
	imp_btn.text = Translations.T("settings.import")
	imp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	imp_btn.pressed.connect(_import_save)
	save_row.add_child(imp_btn)

	vb.add_child(_sep())

	# ── LANGUE ───────────────────────────────────────────────
	vb.add_child(_section(Translations.T("settings.language")))
	var lang_codes: Array[String] = ["fr", "en"]
	var lang_opt := OptionButton.new()
	lang_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_opt.focus_mode = Control.FOCUS_NONE
	for i in lang_codes.size():
		lang_opt.add_item(Translations.T("settings.lang." + lang_codes[i]), i)
	lang_opt.select(lang_codes.find(GameSettings.language))
	lang_opt.item_selected.connect(func(idx: int) -> void:
		GameSettings.set_language(lang_codes[idx]))
	vb.add_child(lang_opt)

# ─── Fabriques de lignes ──────────────────────────────────────

func _sep() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.color                 = Color(1.0, 1.0, 1.0, 0.15)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sep

func _section(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	return lbl

# Ligne "label + slider 0..1 + pourcentage" ; on_change reçoit la valeur.
func _slider(label: String, initial: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text                = label
	lbl.custom_minimum_size = Vector2(72, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value             = 0.0
	slider.max_value             = 1.0
	slider.step                  = 0.01
	slider.value                 = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var pct := Label.new()
	pct.text                 = "%d %%" % int(initial * 100)
	pct.custom_minimum_size  = Vector2(42, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_size_override("font_size", 12)
	pct.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	row.add_child(pct)
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d %%" % int(v * 100)
		on_change.call(v)
	)
	return row

# ─── Export / Import de sauvegarde ────────────────────────────
# La logique fichier (copie, validation, écriture atomique) vit dans
# SaveManager ; ici on ne gère que les dialogues de sélection.

func _export_save() -> void:
	if not FileAccess.file_exists(SaveManager.SAVE_PATH):
		return
	var fd := FileDialog.new()
	fd.file_mode    = FileDialog.FILE_MODE_SAVE_FILE
	fd.access       = FileDialog.ACCESS_FILESYSTEM
	fd.filters      = PackedStringArray(["*.json ; Sauvegarde JSON"])
	fd.current_file = "IdleEvolutionSave.json"
	add_child(fd)
	fd.popup_centered(Vector2(700, 480))
	fd.file_selected.connect(func(dest: String) -> void:
		SaveManager.export_to(dest)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)

func _import_save() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access    = FileDialog.ACCESS_FILESYSTEM
	fd.filters   = PackedStringArray(["*.json ; Sauvegarde JSON"])
	add_child(fd)
	fd.popup_centered(Vector2(700, 480))
	fd.file_selected.connect(func(src_path: String) -> void:
		# SaveManager valide (JSON + version) : une sauvegarde invalide
		# n'écrase jamais la sauvegarde courante.
		var imported := SaveManager.import_from(src_path)
		fd.queue_free()
		if imported:
			get_tree().reload_current_scene()
	)
	fd.canceled.connect(fd.queue_free)
