# ============================================================
# Hero.gd — Fiche détaillée du héro (stats, XP, évolution).
#
# Scène modale ouverte depuis le bouton HÉRO du Village.
# Affiche le nom, le tier, les stats effectives et la barre XP.
# Si le tier max est atteint (≥ xp_max) le bouton ÉVOLUER apparaît.
# ============================================================
extends Control

# ═══════════════════════════════════════════════════════════
# Initialise la scène fullscreen, la barre de navigation et
# le contenu défilable du panneau héro.
func _ready() -> void:
	var root := UIHelpers.fullscreen_root(self)
	root.add_child(UIHelpers.scene_header_bar("HÉRO", UIColors.STAT_HP, func() -> void:
		get_tree().change_scene_to_file("res://scenes/village/village.tscn")
	))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical           = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode        = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var m := UIHelpers.margin_of(20)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	_fill_content(vb)

# ═══════════════════════════════════════════════════════════
# Peuple le VBox central avec les infos du héro actif :
# nom + tier, stats (ATK/DEF/PV), barre XP et bouton évolution.
func _fill_content(vb: VBoxContainer) -> void:
	var cid    := GameData.player.get("active_creature_id", "") as String
	var c      := GameData.get_entity(cid)
	var tier   := c.get("current_tier", 0) as int
	var xp     := c.get("current_xp",   0.0) as float
	var ni     := mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max := float(GameData.xp_thresholds[ni])
	var can_ev := tier < GameData.MAX_TIER and xp >= xp_max
	var tcolor := UIColors.tier_color(tier)

	# ── Nom et tier ─────────────────────────────────────────
	var lbl_name := Label.new()
	lbl_name.text                 = "%s  —  %s" % [c.get("name", "Héro"), GameData.get_tier_name(tier)]
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.add_theme_font_size_override("font_size", 18)
	lbl_name.add_theme_color_override("font_color", tcolor)
	vb.add_child(lbl_name)
	vb.add_child(HSeparator.new())

	# ── Stats effectives (base + équipement + passifs) ──────
	var eq  := GameData.get_equipment_bonuses()
	var eff := GameData.get_effective_stats(cid)
	var pas := PassiveSystem.get_combat_bonuses()

	for row: Array in [
		["ATK", int(eff.get("atk", 0)) + int(eq.get("atk", 0)) + int(pas.get("atk_bonus", 0)), UIColors.STAT_ATK],
		["DEF", int(eff.get("def", 0)) + int(pas.get("def_bonus", 0)),                           UIColors.STAT_DEF],
		["PV",  int(eff.get("hp",  0)) + int(eq.get("hp",  0)) + int(pas.get("hp_bonus",  0)),  UIColors.STAT_HP ],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		vb.add_child(hb)

		var kl := Label.new()
		kl.text = str(row[0]) + " :"
		kl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hb.add_child(kl)

		var vl := Label.new()
		vl.text = str(row[1])
		vl.add_theme_font_size_override("font_size", 14)
		vl.add_theme_color_override("font_color", row[2])
		hb.add_child(vl)

	vb.add_child(HSeparator.new())

	# ── Barre XP + bouton évolution ─────────────────────────
	if tier < GameData.MAX_TIER:
		var xp_color := UIColors.FILTER_ON if can_ev else UIColors.STAT_HP
		vb.add_child(UIHelpers.xp_bar(xp, xp_max, xp_color))

		var xl := Label.new()
		xl.text                 = "XP  %.0f / %.0f" % [xp, xp_max]
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.add_theme_font_size_override("font_size", 10)
		xl.add_theme_color_override("font_color", UIColors.FILTER_ON if can_ev else UIColors.TEXT_MUTED)
		vb.add_child(xl)

		if can_ev:
			var eb := Button.new()
			eb.text                  = "ÉVOLUER ▲"
			eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			eb.add_theme_color_override("font_color", UIColors.FILTER_ON)
			eb.pressed.connect(func() -> void:
				if MasterySystem.evolve_entity(cid):
					get_tree().reload_current_scene()
			)
			vb.add_child(eb)
	else:
		var ml := Label.new()
		ml.text                 = "▲ NIVEAU MAXIMUM"
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 11)
		ml.add_theme_color_override("font_color", UIColors.FILTER_ON)
		vb.add_child(ml)
