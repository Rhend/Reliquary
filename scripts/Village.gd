# ============================================================
# Village.gd — Scène principale du Village.
#
# Sections affichées :
#   • Partir en aventure  — sélection du biome + lancement
#   • Héro                — stats ATK / DEF / PV (sans XP ni évolution)
#   • Équipement          — 4 slots (arme / bouclier / bottes / armure)
#   • Hall des Évolutions — toutes les rencontres, filtré par type
#   • Inventaire          — ressources possédées avec quantités
#   • Forge               — recettes disponibles avec boutons de craft
#
# Les sections Inventaire et Forge se rafraîchissent dynamiquement
# via les signaux EventBus.resources_changed et EventBus.loot_dropped.
# ============================================================
extends Control

# ─── Références UI dynamiques ───────────────────────────────

var _bestiary_vbox:   VBoxContainer
var _resources_vbox:  VBoxContainer
var _forge_vbox:      VBoxContainer
var _passives_vbox:   VBoxContainer
var _fade_rect:       ColorRect      # Overlay de transition de scène

# ─── État du filtre Hall des Évolutions ─────────────────────

var _hall_filter:    String     = "Tout"
var _filter_buttons: Dictionary = {}   # label → Button

# Correspondance label de filtre → valeur du champ "type" dans le bestiaire
const FILTER_TO_TYPE: Dictionary = {
	"Créatures":  "Créature",
	"Pièges":     "Piège",
	"Événements": "Événement"
}

# ─── Libellés et icônes des slots d'équipement ──────────────

const SLOT_ICONS: Dictionary = {
	"weapon": "Arme",
	"shield": "Bouclier",
	"boots":  "Bottes",
	"armor":  "Armure"
}

# ═══════════════════════════════════════════════════════════
#  Initialisation
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	SaveManager.load_save()

	# Sélectionne la première créature disponible si la sauvegarde n'en avait pas
	if GameData.player.get("active_creature_id", "") == "":
		for entity_id in GameData.entities:
			if GameData.entities[entity_id].get("entity_type") == "creature":
				GameData.player["active_creature_id"] = entity_id
				break

	_build_ui()

	# Rafraîchissements dynamiques via EventBus
	EventBus.loot_dropped.connect(func(_d, _n): _refresh_resources())
	EventBus.resources_changed.connect(_refresh_resources)
	EventBus.bestiary_updated.connect(func(_id): _refresh_bestiary())
	EventBus.entity_evolved.connect(_on_entity_evolved)
	EventBus.passive_unlocked.connect(func(_eid, _pid): _refresh_passives())

# ═══════════════════════════════════════════════════════════
#  Construction de l'interface (appelée une seule fois)
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	# Fond sombre de la scène
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	# ScrollContainer global pour les petits écrans
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	scroll.add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 24)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	# Titre
	var title = Label.new()
	title.text = "VILLAGE"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# Ligne principale de cartes (aventure / héro / équipement)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(row)

	_build_adventure_card(row)
	_build_hero_card(row)
	_build_equipment_card(row)

	# Sections inférieures
	_build_hall_section(root_vbox)
	_build_passives_section(root_vbox)
	_build_resources_section(root_vbox)
	_build_forge_section(root_vbox)

	# Overlay de fondu — doit être le DERNIER enfant pour se rendre par-dessus tout
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	# Fondu d'entrée : noir → transparent
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.40)

# ─── Carte "Partir en aventure" ─────────────────────────────

func _build_adventure_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 220)
	parent.add_child(card)

	var m    = _margin(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	m.add_child(vbox)

	_title_label(vbox, "PARTIR EN AVENTURE")
	vbox.add_child(HSeparator.new())

	var biome_lbl = Label.new()
	biome_lbl.text = "Choisir un biome :"
	vbox.add_child(biome_lbl)

	# Peuple la liste avec tous les biomes disponibles
	var biome_selector = OptionButton.new()
	biome_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") == "biome":
			biome_selector.add_item(e.get("name", entity_id))
			biome_selector.set_item_metadata(biome_selector.item_count - 1, entity_id)
	vbox.add_child(biome_selector)

	vbox.add_child(_spacer())

	var start_btn = Button.new()
	start_btn.text = "Lancer l'aventure"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(func(): _start_adventure(biome_selector))
	vbox.add_child(start_btn)

# ─── Carte Héro (stats uniquement — pas d'XP ni d'évolution) ─

func _build_hero_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	parent.add_child(card)

	var m    = _margin(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	var creature_id = GameData.player.get("active_creature_id", "")
	var creature    = GameData.get_entity(creature_id)

	_title_label(vbox, creature.get("name", "Héro").to_upper())
	vbox.add_child(HSeparator.new())

	var equip = GameData.get_equipment_bonuses()
	var eff   = GameData.get_effective_stats(creature_id)

	# Affiche ATK, DEF et PV avec leurs couleurs respectives
	var stat_rows = [
		["ATK", int(eff.get("atk", 0)) + int(equip.get("atk", 0)), UIColors.STAT_ATK],
		["DEF", eff.get("def", 0),                                   UIColors.STAT_DEF],
		["PV",  int(eff.get("hp",  0)) + int(equip.get("hp",  0)),  UIColors.STAT_HP ]
	]
	for row_data in stat_rows:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(hbox)

		var key_lbl = Label.new()
		key_lbl.text = str(row_data[0]) + " :"
		key_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		hbox.add_child(key_lbl)

		var val_lbl = Label.new()
		val_lbl.text = str(row_data[1])
		val_lbl.add_theme_color_override("font_color", row_data[2])
		val_lbl.add_theme_font_size_override("font_size", 14)
		hbox.add_child(val_lbl)

	vbox.add_child(_spacer())

# ─── Carte Équipement (4 slots) ──────────────────────────────

func _build_equipment_card(parent: Node) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 220)
	parent.add_child(card)

	var m    = _margin(card, 18)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	m.add_child(vbox)

	_title_label(vbox, "ÉQUIPEMENT")
	vbox.add_child(HSeparator.new())

	for slot in ["weapon", "shield", "boots", "armor"]:
		var item_id = GameData.player.get("equipped", {}).get(slot, "")
		var item    = GameData.get_entity(item_id)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		# Slot label (type d'équipement)
		var slot_lbl = Label.new()
		slot_lbl.text = SLOT_ICONS.get(slot, "?")
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		slot_lbl.custom_minimum_size = Vector2(58, 0)
		row.add_child(slot_lbl)

		# Nom de l'objet équipé
		var name_lbl = Label.new()
		name_lbl.text = item.get("name", "(vide)") if not item.is_empty() else "(vide)"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if item.is_empty():
			name_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		row.add_child(name_lbl)

		# Résumé des bonus de l'objet
		if not item.is_empty():
			var bonuses = item.get("base_stats", {}).get("bonuses", {})
			var parts: Array = []
			for key in bonuses:
				match key:
					"atk":              parts.append("+%d ATK" % int(bonuses[key]))
					"hp":               parts.append("+%d PV"  % int(bonuses[key]))
					"attack_speed_pct": parts.append("+%d%% vit." % int(bonuses[key]))
			if not parts.is_empty():
				var bonus_lbl = Label.new()
				bonus_lbl.text = "  ".join(PackedStringArray(parts))
				bonus_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
				bonus_lbl.add_theme_font_size_override("font_size", 11)
				row.add_child(bonus_lbl)

	vbox.add_child(_spacer())

# ═══════════════════════════════════════════════════════════
#  Hall des Évolutions
# ═══════════════════════════════════════════════════════════

func _build_hall_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "HALL DES ÉVOLUTIONS")
	section.add_child(HSeparator.new())
	_build_filter_buttons(section)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size         = Vector2(0, 300)
	scroll.size_flags_horizontal       = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode      = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)

	_bestiary_vbox = VBoxContainer.new()
	_bestiary_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(_bestiary_vbox)

	_refresh_bestiary()

func _build_filter_buttons(parent: Node) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	for f in ["Tout", "Créatures", "Pièges", "Événements", "Biomes"]:
		var btn = Button.new()
		btn.text = f
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.flat = true
		_filter_buttons[f] = btn
		btn.pressed.connect(func(): _on_filter_pressed(f))
		row.add_child(btn)

	_update_filter_highlight()

func _on_filter_pressed(filter: String) -> void:
	_hall_filter = filter
	_update_filter_highlight()
	_refresh_bestiary()

# Met en évidence le bouton de filtre actif en jaune.
func _update_filter_highlight() -> void:
	for f in _filter_buttons:
		var btn: Button = _filter_buttons[f]
		if f == _hall_filter:
			btn.add_theme_color_override("font_color",       UIColors.FILTER_ON)
			btn.add_theme_color_override("font_hover_color", UIColors.FILTER_ON)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")

func _refresh_bestiary() -> void:
	if _bestiary_vbox == null:
		return
	for child in _bestiary_vbox.get_children():
		child.queue_free()

	# Vue spéciale "Biomes"
	if _hall_filter == "Biomes":
		_populate_biomes()
		return

	# Regroupe les entrées par biome, filtrées par type si nécessaire
	var hall: Dictionary   = GameData.player.get("bestiary", {})
	var by_biome: Dictionary = {}

	for enc_id in hall:
		var entry    = hall[enc_id]
		var enc_type = entry.get("type", "Créature")
		if _hall_filter != "Tout":
			var required = FILTER_TO_TYPE.get(_hall_filter, "")
			if enc_type != required:
				continue
		var biome_name = entry.get("biome_name", "Inconnu")
		if not by_biome.has(biome_name):
			by_biome[biome_name] = []
		by_biome[biome_name].append(entry)

	if by_biome.is_empty():
		var lbl = Label.new()
		lbl.text = ("Aucune rencontre de ce type enregistrée." if not hall.is_empty()
				else "Aucune rencontre enregistrée pour le moment...")
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_bestiary_vbox.add_child(lbl)
		return

	for biome_name in by_biome:
		_add_group_header(biome_name)
		for entry in by_biome[biome_name]:
			_add_entry_row(entry)
		_bestiary_vbox.add_child(HSeparator.new())

# Affiche les biomes avec leur XP/tier et un bouton Évoluer si disponible.
func _populate_biomes() -> void:
	_add_group_header("BIOMES EXPLORÉS")
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		if e.get("entity_type") != "biome":
			continue
		_add_evolvable_row(entity_id, e, UIColors.TYPE_BIOME)

# Ligne d'entité évolutive (biome ou passif) avec barre XP et bouton Évoluer.
func _add_evolvable_row(entity_id: String, entity: Dictionary, bar_color: Color) -> void:
	var tier:     int   = entity.get("current_tier", 0)
	var xp:       float = entity.get("current_xp",   0.0)
	var next_idx: int   = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max:   float = float(GameData.xp_thresholds[next_idx]) if tier < GameData.MAX_TIER else 1.0
	var can_evolve: bool = tier < GameData.MAX_TIER and xp >= xp_max

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_vbox.add_child(row)

	# Colonne gauche : nom + tier
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(160, 0)
	row.add_child(left)

	var name_lbl = Label.new()
	name_lbl.text = entity.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 13)
	left.add_child(name_lbl)

	var tier_lbl = Label.new()
	tier_lbl.text = GameData.get_tier_name(tier)
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color",
		UIColors.FILTER_ON if tier > 0 else UIColors.TEXT_MUTED)
	left.add_child(tier_lbl)

	# Passifs déjà débloqués sur cette entité
	var unlocked = entity.get("unlocked_passives", [])
	if not unlocked.is_empty():
		var pnames: Array = []
		for pid in unlocked:
			pnames.append(GameData.get_entity(pid).get("name", pid))
		var plab = Label.new()
		plab.text = "Passifs : " + ", ".join(PackedStringArray(pnames))
		plab.add_theme_font_size_override("font_size", 10)
		plab.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
		left.add_child(plab)

	# Prochain passif à débloquer
	var next_passive_name = ""
	for slot in entity.get("passive_slots", []):
		if slot.get("unlock_tier", 99) == tier + 1:
			var np = GameData.get_entity(slot.get("passive_id", ""))
			if not np.is_empty():
				next_passive_name = np.get("name", "")
			break

	# Colonne droite : barre XP + bouton
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	if tier < GameData.MAX_TIER:
		var bar = _colored_bar(bar_color if not can_evolve else UIColors.FILTER_ON, 12)
		bar.min_value = 0.0
		bar.max_value = xp_max
		bar.value     = minf(xp, xp_max)
		right.add_child(bar)

		var hint = ""
		if next_passive_name != "":
			hint = "  → %s" % next_passive_name
		var xp_lbl = Label.new()
		xp_lbl.text = "XP %.0f / %.0f%s" % [xp, xp_max, hint]
		xp_lbl.add_theme_font_size_override("font_size", 10)
		xp_lbl.add_theme_color_override("font_color",
			UIColors.FILTER_ON if can_evolve else UIColors.TEXT_MUTED)
		right.add_child(xp_lbl)

		if can_evolve:
			var btn = Button.new()
			btn.text = "ÉVOLUER ▲"
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_color_override("font_color", UIColors.FILTER_ON)
			btn.pressed.connect(func(): _on_evolve_pressed(entity_id))
			right.add_child(btn)
	else:
		var max_lbl = Label.new()
		max_lbl.text = "Maîtrise maximale atteinte"
		max_lbl.add_theme_font_size_override("font_size", 11)
		max_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
		right.add_child(max_lbl)

func _on_entity_evolved(_entity_id: String, _new_tier: int) -> void:
	_refresh_bestiary()
	_refresh_passives()

func _on_evolve_pressed(entity_id: String) -> void:
	if MasterySystem.evolve_entity(entity_id):
		_refresh_bestiary()
		_refresh_passives()

func _add_group_header(biome_name: String) -> void:
	var lbl = Label.new()
	lbl.text = "  " + biome_name.to_upper()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	_bestiary_vbox.add_child(lbl)

	# En-tête de colonnes
	var header = _hall_row()
	_bestiary_vbox.add_child(header)
	for col in ["Nom", "Type", "Maîtrise", "XP"]:
		var h = Label.new()
		h.text = col
		h.add_theme_font_size_override("font_size", 11)
		h.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(h)

func _add_entry_row(entry: Dictionary) -> void:
	var tier:     int   = entry.get("tier",  0)
	var xp:       float = entry.get("xp",    0.0)
	var count:    int   = entry.get("count", 0)
	var enc_type        = entry.get("type",  "Créature")
	var next_i:   int   = mini(tier + 1, GameData.xp_thresholds.size() - 1)
	var xp_max:   float = float(GameData.xp_thresholds[next_i])
	var bar_color       = UIColors.encounter(enc_type)

	var row = _hall_row()
	_bestiary_vbox.add_child(row)

	var name_lbl = Label.new()
	name_lbl.text = entry.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)

	var type_lbl = Label.new()
	type_lbl.text = enc_type
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.add_theme_color_override("font_color", bar_color)
	row.add_child(type_lbl)

	var tier_lbl = Label.new()
	tier_lbl.text = GameData.get_tier_name(tier)
	tier_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(tier_lbl)

	# Colonne XP : barre colorée + texte
	var xp_col = VBoxContainer.new()
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar = _colored_bar(bar_color, 14)
	bar.min_value = 0.0
	bar.max_value = xp_max
	bar.value     = xp
	xp_col.add_child(bar)

	var count_text = "  (%d×)" % count if count > 0 else ""
	var xp_lbl = Label.new()
	xp_lbl.text = "%.0f / %.0f%s" % [xp, xp_max, count_text]
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	xp_col.add_child(xp_lbl)

	row.add_child(xp_col)

# ═══════════════════════════════════════════════════════════
#  Inventaire
# ═══════════════════════════════════════════════════════════

func _build_resources_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "INVENTAIRE")
	section.add_child(HSeparator.new())

	_resources_vbox = VBoxContainer.new()
	_resources_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resources_vbox.add_theme_constant_override("separation", 4)
	section.add_child(_resources_vbox)

	_refresh_resources()

func _refresh_resources() -> void:
	if _resources_vbox == null:
		return
	for child in _resources_vbox.get_children():
		child.queue_free()

	var resources: Dictionary = GameData.player.get("resources", {})

	# Filtre les ressources à quantité nulle ou négative
	var has_any = false
	for item_id in resources:
		if int(resources[item_id]) > 0:
			has_any = true
			break

	if not has_any:
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune ressource pour le moment..."
		empty_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_resources_vbox.add_child(empty_lbl)
		return

	# HFlowContainer pour un affichage en grille fluide
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 6)
	_resources_vbox.add_child(flow)

	for item_id in resources:
		var qty = int(resources[item_id])
		if qty <= 0:
			continue
		var res      = GameData.get_entity(item_id)
		var res_name = res.get("name", item_id)

		# Chip : nom + quantité sur fond de carte
		var chip = PanelContainer.new()
		flow.add_child(chip)

		var m = MarginContainer.new()
		for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
			m.add_theme_constant_override(side, 6)
		chip.add_child(m)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		m.add_child(hbox)

		var name_lbl = Label.new()
		name_lbl.text = res_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(name_lbl)

		var qty_lbl = Label.new()
		qty_lbl.text = "×%d" % qty
		qty_lbl.add_theme_font_size_override("font_size", 12)
		qty_lbl.add_theme_color_override("font_color", UIColors.RESOURCE_QTY)
		hbox.add_child(qty_lbl)

# ═══════════════════════════════════════════════════════════
#  Forge
# ═══════════════════════════════════════════════════════════

func _build_forge_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "FORGE")
	section.add_child(HSeparator.new())

	_forge_vbox = VBoxContainer.new()
	_forge_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_vbox.add_theme_constant_override("separation", 10)
	section.add_child(_forge_vbox)

	_refresh_forge()

func _refresh_forge() -> void:
	if _forge_vbox == null:
		return
	for child in _forge_vbox.get_children():
		child.queue_free()

	var recipes = GameData.get_forge_recipes()
	if recipes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune recette disponible."
		empty_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		_forge_vbox.add_child(empty_lbl)
		return

	for recipe in recipes:
		_add_recipe_card(recipe)

func _add_recipe_card(recipe: Dictionary) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_vbox.add_child(card)

	var m    = _margin(card, 12)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	m.add_child(vbox)

	# En-tête : nom de la recette + slot cible
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_lbl = Label.new()
	name_lbl.text = recipe.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var slot_lbl = Label.new()
	slot_lbl.text = "[%s]" % SLOT_ICONS.get(recipe.get("result_slot", ""), recipe.get("result_slot", "?"))
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.add_theme_color_override("font_color", UIColors.RESULT_SLOT)
	header.add_child(slot_lbl)

	# Liste des ingrédients avec indicateur vert/rouge selon le stock
	var ing_row = HBoxContainer.new()
	ing_row.add_theme_constant_override("separation", 14)
	vbox.add_child(ing_row)

	var resources: Dictionary = GameData.player.get("resources", {})
	for ing in recipe.get("ingredients", []):
		var item_id   = ing.get("item_id", "")
		var needed    = int(ing.get("qty", 0))
		var have      = int(resources.get(item_id, 0))
		var res_name  = GameData.get_entity(item_id).get("name", item_id)

		var ing_lbl = Label.new()
		ing_lbl.add_theme_font_size_override("font_size", 11)
		ing_lbl.text = "%s  %d/%d" % [res_name, have, needed]
		ing_lbl.add_theme_color_override("font_color",
			UIColors.INGREDIENT_OK if have >= needed else UIColors.INGREDIENT_MISSING)
		ing_row.add_child(ing_lbl)

	# Bouton Forger (grisé si stock insuffisant)
	var can_craft = GameData.can_craft(recipe)
	var forge_btn = Button.new()
	forge_btn.text     = "Forger"
	forge_btn.disabled = not can_craft
	forge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_btn.pressed.connect(func(): _on_forge_pressed(recipe))
	vbox.add_child(forge_btn)

func _on_forge_pressed(recipe: Dictionary) -> void:
	if GameData.craft(recipe):
		# La ressource a changé — rafraîchit les deux sections concernées
		_refresh_resources()
		_refresh_forge()

# ═══════════════════════════════════════════════════════════
#  Passifs actifs
# ═══════════════════════════════════════════════════════════

func _build_passives_section(parent: Node) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	_title_label(section, "PASSIFS ACTIFS")
	section.add_child(HSeparator.new())

	_passives_vbox = VBoxContainer.new()
	_passives_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_passives_vbox.add_theme_constant_override("separation", 6)
	section.add_child(_passives_vbox)

	_refresh_passives()

func _refresh_passives() -> void:
	if _passives_vbox == null:
		return
	for child in _passives_vbox.get_children():
		child.queue_free()

	# Collecte tous les passifs actifs (débloqués sur des entités)
	var active: Array = []
	for entity_id in GameData.entities:
		var e = GameData.entities[entity_id]
		for passive_id in e.get("unlocked_passives", []):
			if passive_id not in active:
				active.append(passive_id)
	for passive_id in GameData.player.get("active_passives", []):
		if passive_id not in active:
			active.append(passive_id)

	if active.is_empty():
		var lbl = Label.new()
		lbl.text = "Aucun passif actif — faites évoluer vos biomes !"
		lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 12)
		_passives_vbox.add_child(lbl)
		return

	var bonuses = PassiveSystem.get_combat_bonuses()

	for passive_id in active:
		var p = GameData.get_entity(passive_id)
		if p.is_empty():
			continue

		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_passives_vbox.add_child(card)

		var m    = _margin(card, 10)
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		m.add_child(hbox)

		# Nom + effets
		var left = VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(left)

		var name_lbl = Label.new()
		name_lbl.text = p.get("name", passive_id)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
		left.add_child(name_lbl)

		for effect in p.get("base_stats", {}).get("effects", []):
			var eff_lbl = Label.new()
			eff_lbl.text = effect.get("description", "")
			eff_lbl.add_theme_font_size_override("font_size", 11)
			eff_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
			left.add_child(eff_lbl)

	# Résumé des bonus totaux
	var parts: Array = []
	if bonuses.get("atk_bonus", 0.0) > 0.0:
		parts.append("+%.0f ATK" % bonuses["atk_bonus"])
	if bonuses.get("def_bonus", 0.0) > 0.0:
		parts.append("+%.0f DEF" % bonuses["def_bonus"])
	if bonuses.get("hp_bonus", 0.0) > 0.0:
		parts.append("+%.0f PV" % bonuses["hp_bonus"])

	if not parts.is_empty():
		var total_lbl = Label.new()
		total_lbl.text = "Bonus total : " + "   ".join(PackedStringArray(parts))
		total_lbl.add_theme_font_size_override("font_size", 12)
		total_lbl.add_theme_color_override("font_color", UIColors.STAT_ATK)
		total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_passives_vbox.add_child(total_lbl)

# ═══════════════════════════════════════════════════════════
#  Logique aventure
# ═══════════════════════════════════════════════════════════

func _start_adventure(biome_selector: OptionButton) -> void:
	if biome_selector.item_count == 0:
		return
	var biome_id    = biome_selector.get_item_metadata(biome_selector.selected)
	var creature_id = GameData.player.get("active_creature_id", "")
	if creature_id == "":
		return
	AdventureSystem.start_adventure(biome_id)
	_fade_to("res://scenes/Biome.tscn")

# Fondu vers noir puis changement de scène.
func _fade_to(scene_path: String) -> void:
	_fade_rect.color.a = 0.0
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.30)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ═══════════════════════════════════════════════════════════
#  Utilitaires constructeurs UI
# ═══════════════════════════════════════════════════════════

# Crée un MarginContainer avec marges uniformes et l'ajoute à parent.
func _margin(parent: Node, px: int) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, px)
	parent.add_child(m)
	return m

# Titre de section centré.
func _title_label(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

# Spacer vertical pour pousser le contenu vers le haut.
func _spacer() -> Control:
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

# HBoxContainer avec séparation uniforme, pleine largeur.
func _hall_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

# ProgressBar colorée avec fond sombre pour le Hall des Évolutions.
func _colored_bar(color: Color, min_h: int) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, min_h)
	bar.show_percentage = false

	var fill = StyleBoxFlat.new()
	fill.bg_color                   = color
	fill.corner_radius_top_left     = 3
	fill.corner_radius_top_right    = 3
	fill.corner_radius_bottom_right = 3
	fill.corner_radius_bottom_left  = 3
	bar.add_theme_stylebox_override("fill", fill)

	var bg = StyleBoxFlat.new()
	bg.bg_color                   = UIColors.BG_BAR
	bg.corner_radius_top_left     = 3
	bg.corner_radius_top_right    = 3
	bg.corner_radius_bottom_right = 3
	bg.corner_radius_bottom_left  = 3
	bar.add_theme_stylebox_override("background", bg)

	return bar
