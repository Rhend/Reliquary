# EvolutionHall.gd — Écran complet du Hall des Évolutions.
# Instancié dynamiquement par Village.gd via _open_hall().
extends Control

var _entries_vbox: VBoxContainer
var _collapsed:    Dictionary = {}   # biome_id → bool (true = replié)

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	EventBus.entity_evolved.connect(func(_id, _t): _refresh())
	EventBus.xp_gained.connect(func(_id, _a):     _refresh())

# ═══════════════════════════════════════════════════════════
#  Construction UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# En-tête
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var accent = ColorRect.new()
	accent.color = UIColors.TYPE_CREATURE
	accent.custom_minimum_size = Vector2(4, 26)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(accent)

	var title_lbl = Label.new()
	title_lbl.text = "HALL DES ÉVOLUTIONS"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "✕ FERMER"
	close_btn.pressed.connect(queue_free)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_entries_vbox = VBoxContainer.new()
	_entries_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_entries_vbox)

	_refresh()

# ═══════════════════════════════════════════════════════════
#  Rafraîchissement
# ═══════════════════════════════════════════════════════════

func _refresh() -> void:
	if _entries_vbox == null:
		return
	for child in _entries_vbox.get_children():
		child.queue_free()

	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") == "biome":
			_add_biome_section(entity_id, e)

# ═══════════════════════════════════════════════════════════
#  Section biome (repliable)
# ═══════════════════════════════════════════════════════════

func _add_biome_section(biome_id: String, biome: Dictionary) -> void:
	if not _collapsed.has(biome_id):
		_collapsed[biome_id] = true   # replié par défaut

	var counts   = _count_encounters(biome_id, biome)
	var found    = counts[0]
	var total    = counts[1]
	var is_open  = not _collapsed[biome_id]
	var tier     = biome.get("current_tier", 0)

	# ── En-tête cliquable ─────────────────────────────────────
	var section_vbox = VBoxContainer.new()
	section_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_vbox.add_child(section_vbox)

	var header_btn = Button.new()
	header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.add_theme_font_size_override("font_size", 14)
	_style_biome_header(header_btn, biome, found, total, is_open, tier)
	section_vbox.add_child(header_btn)

	# ── Contenu (caché si replié) ──────────────────────────────
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 5)
	content_vbox.visible = is_open
	section_vbox.add_child(content_vbox)

	if is_open:
		_fill_biome_content(content_vbox, biome_id, biome)

	header_btn.pressed.connect(func():
		_collapsed[biome_id] = not _collapsed[biome_id]
		_refresh()
	)

func _style_biome_header(btn: Button, biome: Dictionary,
		found: int, total: int, is_open: bool, tier: int) -> void:
	var arrow      = "▼" if is_open else "▶"
	var tier_name  = GameData.get_tier_name(tier)
	var tier_col   = UIColors.tier_color(tier)
	var count_col  = UIColors.TEXT_BONUS if found == total else UIColors.TEXT_MUTED

	btn.text = "%s  %s" % [arrow, biome.get("name", "?").to_upper()]
	btn.add_theme_color_override("font_color", tier_col)

	# Annotation X/Y en suffixe via un Label séparé dans la même ligne
	# On insère l'info directement dans le texte du bouton pour simplifier
	btn.text = "%s  %s     %d / %d" % [arrow, biome.get("name", "?").to_upper(), found, total]
	# Couleur du compteur : on ne peut pas styler partiellement un Button,
	# alors on ajoute un label flottant à droite via le parent plus bas.

	var s = StyleBoxFlat.new()
	s.bg_color = UIColors.BG_CARD
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_right = 0 if is_open else 4
	s.corner_radius_bottom_left  = 0 if is_open else 4
	s.content_margin_left   = 12
	s.content_margin_right  = 12
	s.content_margin_top    = 8
	s.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_color_override("font_color", tier_col)

func _fill_biome_content(parent: Node, biome_id: String, biome: Dictionary) -> void:
	var wrapper = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrapper)

	var s = StyleBoxFlat.new()
	s.bg_color = UIColors.BG_CARD
	s.corner_radius_top_left     = 0
	s.corner_radius_top_right    = 0
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left  = 4
	wrapper.add_theme_stylebox_override("panel", s)

	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 10)
	wrapper.add_child(m)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	m.add_child(inner)

	# Progression du biome
	_add_biome_progress(inner, biome_id, biome)
	inner.add_child(HSeparator.new())

	# Rencontres
	var hall = GameData.player.get("bestiary", {})
	var base = biome.get("base_stats", {})
	var groups = [
		[base.get("enemies",         []), "Créature"],
		[base.get("positive_events", []), "Événement"],
		[base.get("traps",           []), "Piège"],
	]
	for group in groups:
		for enc in group[0]:
			var enc_id: String = enc.get("id", "")
			if hall.has(enc_id):
				_add_encounter_card(inner, hall[enc_id])
			else:
				_add_hidden_card(inner, group[1])

# ═══════════════════════════════════════════════════════════
#  Progression biome (barre XP + évoluer)
# ═══════════════════════════════════════════════════════════

func _add_biome_progress(parent: Node, biome_id: String, biome: Dictionary) -> void:
	var tier      = biome.get("current_tier", 0)
	var xp        = biome.get("current_xp",  0.0)
	var is_max    = tier >= GameData.MAX_TIER
	var next_i    = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max    = float(GameData.xp_thresholds[next_i]) if not is_max else 1.0
	var can_evolve = not is_max and xp >= xp_max
	var tier_col   = UIColors.tier_color(tier)
	var active_col = UIColors.FILTER_ON if can_evolve else tier_col

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var tier_lbl = Label.new()
	tier_lbl.text = GameData.get_tier_name(tier).to_upper()
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", tier_col)
	tier_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(tier_lbl)

	if is_max:
		var max_lbl = Label.new()
		max_lbl.text = "Maîtrise maximale"
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(max_lbl)
	else:
		var xp_col = VBoxContainer.new()
		xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(xp_col)

		var bar = _xp_bar(active_col, 10)
		bar.min_value = 0.0
		bar.max_value = xp_max
		bar.value     = minf(xp, xp_max)
		xp_col.add_child(bar)

		var xp_lbl = Label.new()
		xp_lbl.text = "%.0f / %.0f XP" % [xp, xp_max]
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color",
			UIColors.FILTER_ON if can_evolve else UIColors.TEXT_MUTED)
		xp_col.add_child(xp_lbl)

		if can_evolve:
			var btn = Button.new()
			btn.text = "ÉVOLUER ▲"
			btn.add_theme_color_override("font_color", UIColors.FILTER_ON)
			btn.pressed.connect(func():
				if MasterySystem.evolve_entity(biome_id):
					_refresh()
			)
			row.add_child(btn)

	# Passifs débloqués / prochain passif
	var unlocked = biome.get("unlocked_passives", [])
	if not unlocked.is_empty():
		var names: Array = []
		for pid in unlocked:
			names.append(GameData.get_entity(pid).get("name", pid))
		var plab = Label.new()
		plab.text = "Passifs : " + ", ".join(PackedStringArray(names))
		plab.add_theme_font_size_override("font_size", 10)
		plab.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
		parent.add_child(plab)

	if not is_max:
		for slot in biome.get("passive_slots", []):
			if slot.get("unlock_tier", 99) == tier + 1:
				var np = GameData.get_entity(slot.get("passive_id", ""))
				if not np.is_empty():
					var hint = Label.new()
					hint.text = "Prochain passif : %s" % np.get("name", "")
					hint.add_theme_font_size_override("font_size", 10)
					hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
					parent.add_child(hint)
				break

# ═══════════════════════════════════════════════════════════
#  Cartes de rencontres
# ═══════════════════════════════════════════════════════════

func _add_encounter_card(parent: Node, entry: Dictionary) -> void:
	var tier      = entry.get("tier",  0)
	var xp        = entry.get("xp",    0.0)
	var count     = entry.get("count", 0)
	var enc_type  = entry.get("type",  "Créature")
	var tier_col  = UIColors.tier_color(tier)
	var type_col  = UIColors.encounter(enc_type)
	var is_max    = tier >= GameData.MAX_TIER
	var next_i    = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max    = float(GameData.xp_thresholds[next_i])

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)

	# Ligne : nom | tier badge | type | compteur
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var name_lbl = Label.new()
	name_lbl.text = entry.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", tier_col)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var tier_badge = Label.new()
	tier_badge.text = GameData.get_tier_name(tier).to_upper()
	tier_badge.add_theme_font_size_override("font_size", 10)
	tier_badge.add_theme_color_override("font_color", tier_col)
	row.add_child(tier_badge)

	var type_lbl = Label.new()
	type_lbl.text = enc_type
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", type_col)
	row.add_child(type_lbl)

	var count_lbl = Label.new()
	count_lbl.text = "%d×" % count
	count_lbl.add_theme_font_size_override("font_size", 10)
	count_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	row.add_child(count_lbl)

	# Barre XP
	if is_max:
		var max_lbl = Label.new()
		max_lbl.text = "Maîtrise maximale"
		max_lbl.add_theme_font_size_override("font_size", 10)
		max_lbl.add_theme_color_override("font_color", tier_col)
		vbox.add_child(max_lbl)
	else:
		var bar = _xp_bar(tier_col, 8)
		bar.min_value = 0.0
		bar.max_value = xp_max
		bar.value     = minf(xp, xp_max)
		vbox.add_child(bar)

		var xp_lbl = Label.new()
		xp_lbl.text = "%.0f / %.0f XP" % [xp, xp_max]
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		vbox.add_child(xp_lbl)

func _add_hidden_card(parent: Node, enc_type: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_lbl = Label.new()
	name_lbl.text = "???"
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var type_lbl = Label.new()
	type_lbl.text = enc_type
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	row.add_child(type_lbl)

	var hint = Label.new()
	hint.text = "Non rencontré"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	row.add_child(hint)

# ═══════════════════════════════════════════════════════════
#  Utilitaires
# ═══════════════════════════════════════════════════════════

func _count_encounters(biome_id: String, biome: Dictionary) -> Array:
	var hall  = GameData.player.get("bestiary", {})
	var base  = biome.get("base_stats", {})
	var total = 0
	var found = 0
	for group in [base.get("enemies",[]), base.get("positive_events",[]), base.get("traps",[])]:
		for enc in group:
			total += 1
			if hall.has(enc.get("id", "")):
				found += 1
	return [found, total]

func _xp_bar(color: Color, min_h: int) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size   = Vector2(0, maxi(min_h, 16))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage       = true
	bar.add_theme_color_override("font_color", Color.WHITE)
	bar.add_theme_font_size_override("font_size", 10)

	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	for c in ["corner_radius_top_left","corner_radius_top_right",
			"corner_radius_bottom_right","corner_radius_bottom_left"]:
		fill.set(c, 3)
	bar.add_theme_stylebox_override("fill", fill)

	var bg = StyleBoxFlat.new()
	bg.bg_color = UIColors.BG_BAR
	for c in ["corner_radius_top_left","corner_radius_top_right",
			"corner_radius_bottom_right","corner_radius_bottom_left"]:
		bg.set(c, 3)
	bar.add_theme_stylebox_override("background", bg)

	return bar
