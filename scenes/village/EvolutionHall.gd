# ============================================================
# EvolutionHall — Hall des Évolutions, organisé par biome.
# Les biomes sont repliés par défaut (chevron ▶/▼).
# Les stats des entités se dévoilent progressivement par tier.
# ============================================================
extends Control

var _scroll_vbox: VBoxContainer

func _ready() -> void:
	_build_ui()
	EventBus.entity_evolved.connect(_on_entity_evolved)

# ── UI de base ───────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_header_bar())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	scroll.add_child(margin)

	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.add_theme_constant_override("separation", 12)
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll_vbox)

	_populate()

func _header_bar() -> Control:
	var bar = PanelContainer.new()
	var m   = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 14)
	bar.add_child(m)
	var hbox = HBoxContainer.new()
	m.add_child(hbox)

	var back = Button.new()
	back.text = "← Village"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/village/village.tscn"))
	hbox.add_child(back)

	var title = Label.new()
	title.text = "HALL DES ÉVOLUTIONS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIColors.FILTER_ON)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(spacer)
	return bar

# ── Population ───────────────────────────────────────────────

func _populate() -> void:
	for child in _scroll_vbox.get_children():
		_scroll_vbox.remove_child(child)
		child.queue_free()
	for biome in MasteryRegistry.get_entities_by_type("biome"):
		_add_biome_section(biome)

func _add_biome_section(biome: Dictionary) -> void:
	var biome_id   := biome.get("id",   "") as String
	var biome_name := biome.get("name", biome_id) as String
	var pools      := MasteryRegistry.get_biome_entity_pools(biome_id)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	_scroll_vbox.add_child(wrapper)

	# Contenu masqué par défaut
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = false

	# Header cliquable avec chevron
	var header := Button.new()
	header.text = "▶  " + biome_name.to_upper()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color",         UIColors.TYPE_BIOME)
	header.add_theme_color_override("font_hover_color",   UIColors.TYPE_BIOME)
	header.add_theme_color_override("font_pressed_color", UIColors.TYPE_BIOME)
	header.pressed.connect(func() -> void:
		content.visible = not content.visible
		header.text = ("▼  " if content.visible else "▶  ") + biome_name.to_upper()
	)
	wrapper.add_child(header)
	wrapper.add_child(HSeparator.new())
	wrapper.add_child(content)

	# Maîtrise du biome
	var bd := MasteryRegistry.get_mastery_display(biome_id)
	if not bd.is_empty():
		_add_entity_row(content, biome_id, bd, {})

	_add_pool_sub(content, "Créatures",   pools.get("creatures",  []), false)
	_add_pool_sub(content, "Événements",  pools.get("events",     []), false)
	_add_pool_sub(content, "Pièges",      pools.get("traps",      []), false)
	_add_pool_sub(content, "Équipements", pools.get("equipment",  []), true)
	_add_passives_sub(content, biome.get("passive_slots", []))

# ── Sous-sections ────────────────────────────────────────────

func _add_pool_sub(content: VBoxContainer, label: String, pool: Array, use_entities: bool) -> void:
	if pool.is_empty():
		return
	_sub_label(content, label)
	var disc := 0
	for entry: Dictionary in pool:
		var eid := entry.get("id", "") as String
		if MasteryRegistry.is_discovered(eid):
			disc += 1
			var display := MasteryRegistry.get_mastery_display(eid) if use_entities \
				else _bestiary_display(eid, entry.get("name", eid))
			if not display.is_empty():
				var raw := GameData.get_entity(eid) if use_entities else entry
				_add_entity_row(content, eid, display, raw)
		else:
			_add_unknown_slot(content)
	_count_label(content, disc, pool.size())

func _add_passives_sub(content: VBoxContainer, passive_slots: Array) -> void:
	if passive_slots.is_empty():
		return
	_sub_label(content, "Passifs")
	for slot: Dictionary in passive_slots:
		var pid         := slot.get("passive_id",   "") as String
		var unlock_tier := slot.get("unlock_tier",   0) as int
		var display     := MasteryRegistry.get_mastery_display(pid)
		if display.is_empty():
			_add_unknown_slot(content)
		else:
			_add_entity_row(content, pid, display, {"_unlock_tier": unlock_tier})

# ── Lignes d'entités ─────────────────────────────────────────

func _add_entity_row(parent: Node, entity_id: String, display: Dictionary, raw: Dictionary) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 6)
	card.add_child(m)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	m.add_child(hbox)

	# Gauche : nom + tier + stats progressives
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)

	var name_lbl := Label.new()
	name_lbl.text = display["name"]
	name_lbl.add_theme_font_size_override("font_size", 12)
	left.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = display["tier_name"]
	tier_lbl.add_theme_font_size_override("font_size", 10)
	tier_lbl.add_theme_color_override("font_color", UIColors.tier_color(display["tier"]))
	left.add_child(tier_lbl)

	var stats := _stats_text(raw, display["tier"])
	if not stats.is_empty():
		var stats_lbl := Label.new()
		stats_lbl.text = stats
		stats_lbl.add_theme_font_size_override("font_size", 10)
		stats_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		left.add_child(stats_lbl)

	# Droite : barre XP + bouton
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(170, 0)
	hbox.add_child(right)

	if not display["at_max"]:
		var bar := ProgressBar.new()
		bar.min_value       = 0.0
		bar.max_value       = display["xp_max"]
		bar.value           = display["xp"]
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(0, 14)

		var fs := StyleBoxFlat.new()
		fs.bg_color = UIColors.FILTER_ON if display["can_evolve"] else UIColors.STAT_HP
		fs.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fs)
		var bs := StyleBoxFlat.new()
		bs.bg_color = UIColors.BG_BAR
		bs.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bs)
		bar.add_theme_color_override("font_color", Color.WHITE)
		bar.add_theme_font_size_override("font_size", 9)
		right.add_child(bar)

		if display["can_evolve"]:
			var btn := Button.new()
			btn.text = "ÉVOLUER ▲"
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_color_override("font_color", UIColors.FILTER_ON)
			btn.add_theme_font_size_override("font_size", 11)
			btn.pressed.connect(func() -> void: _on_evolve_pressed(entity_id))
			right.add_child(btn)
	else:
		var max_lbl := Label.new()
		max_lbl.text = "Maîtrise max"
		max_lbl.add_theme_font_size_override("font_size", 10)
		max_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		right.add_child(max_lbl)

func _add_unknown_slot(parent: Node) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 6)
	card.add_child(m)
	var lbl := Label.new()
	lbl.text = "??? — Non découvert"
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 11)
	m.add_child(lbl)

# ── Stats progressives ───────────────────────────────────────

func _stats_text(raw: Dictionary, mastery_tier: int) -> String:
	if raw.is_empty() or mastery_tier == 0:
		return ""
	var parts: Array[String] = []
	if raw.has("atk"):
		# Créature : PV (t1) → ATK (t2) → DEF (t3) → XP reward (t4)
		if mastery_tier >= 1: parts.append("PV %d"  % raw.get("hp",         0))
		if mastery_tier >= 2: parts.append("ATK %d" % raw.get("atk",        0))
		if mastery_tier >= 3: parts.append("DEF %d" % raw.get("def",        0))
		if mastery_tier >= 4: parts.append("XP ×%d" % raw.get("xp_reward",  0))
	elif raw.has("damage"):
		# Piège
		parts.append("Dégâts %d" % raw.get("damage", 0))
	elif raw.has("effect"):
		# Événement positif
		var effect := raw.get("effect", "") as String
		var value  := raw.get("value",  0)  as int
		if   effect == "heal": parts.append("Soin +%d PV"   % value)
		elif effect == "luck": parts.append("Chance +%d"    % value)
		else:                   parts.append("%s +%d" % [effect, value])
	elif raw.has("base_stats"):
		# Équipement : bonus progressifs
		var bonuses: Dictionary = raw.get("base_stats", {}).get("bonuses", {})
		if mastery_tier >= 1 and bonuses.has("hp"):               parts.append("+%d PV"  % int(bonuses["hp"]))
		if mastery_tier >= 2 and bonuses.has("atk"):              parts.append("+%d ATK" % int(bonuses["atk"]))
		if mastery_tier >= 3 and bonuses.has("def"):              parts.append("+%d DEF" % int(bonuses["def"]))
		if mastery_tier >= 4 and bonuses.has("attack_speed_pct"): parts.append("Vitesse +%.0f%%" % float(bonuses["attack_speed_pct"]))
	elif raw.has("_unlock_tier"):
		# Passif
		parts.append("Débloqué au tier %d" % raw.get("_unlock_tier", 0))
	return "  ·  ".join(parts)

# ── Helpers UI ───────────────────────────────────────────────

func _sub_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	parent.add_child(lbl)

func _count_label(parent: Node, disc: int, total: int) -> void:
	var lbl := Label.new()
	lbl.text = "%d / %d découvert(s)" % [disc, total]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	parent.add_child(lbl)

# ── Données ──────────────────────────────────────────────────

func _bestiary_display(entity_id: String, fallback_name: String) -> Dictionary:
	var entry := GameData.player.get("bestiary", {}).get(entity_id, {}) as Dictionary
	if entry.is_empty():
		return {}
	var tier   := entry.get("tier", 0)   as int
	var xp     := entry.get("xp",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max := float(GameData.xp_thresholds[ni])
	return {
		"name":       entry.get("name", fallback_name),
		"tier":       tier,
		"tier_name":  GameData.get_tier_name(tier),
		"xp":         xp,
		"xp_max":     xp_max,
		"can_evolve": tier < GameData.MAX_TIER and xp >= xp_max,
		"at_max":     tier >= GameData.MAX_TIER,
	}

# ── Callbacks ────────────────────────────────────────────────

func _on_evolve_pressed(entity_id: String) -> void:
	if MasterySystem.evolve_entity(entity_id):
		_populate()

func _on_entity_evolved(_id: String, _tier: int) -> void:
	_populate()
