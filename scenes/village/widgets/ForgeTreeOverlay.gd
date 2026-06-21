# ============================================================
# ForgeTreeOverlay — Arbre d'amélioration spatial d'un équipement (Chantier 5).
#
# Overlay plein écran (ajouté par ForgePanel à Village). Affiche l'arbre du
# `equipment_id` : nœuds positionnés (ForgeTreeData.pos), liens dessinés entre
# voisins, achat au clic. Couleurs d'état : acquis (vert) · achetable (couleur du
# palier) · verrouillé strate/connexité (gris). Glisser pour déplacer la vue.
#
# Se reconstruit sur forge_tree_changed / resources_changed (achat, évolution).
# ============================================================
class_name ForgeTreeOverlay
extends Control

var equipment_id: String = ""

const BOARD_SIZE := Vector2(660.0, 660.0)
const NODE_SIZE  := Vector2(58.0, 58.0)

var _layer: Control = null   # conteneur pannable (canvas de liens + boutons de nœuds)
var _pan_offset := Vector2.ZERO
var _dragging := false

const GLYPH := { "mineur": "●", "notable": "◆", "keystone": "✦" }

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	EventBus.forge_tree_changed.connect(_on_changed)
	EventBus.resources_changed.connect(_on_changed_void)
	_build()

func _on_changed(_eq: String = "") -> void:
	_build()

func _on_changed_void() -> void:
	_build()

func _close() -> void:
	queue_free()

# ─── Construction ────────────────────────────────────────────

func _build() -> void:
	for c in get_children():
		c.queue_free()

	var tree := ForgeSystem.tree_for(equipment_id)
	var equip := GameData.get_entity(equipment_id)
	var tier := int(equip.get("maitrise_actuelle", 0))
	var ec := UIColors.tier_color(tier)

	# Voile sombre — un clic hors du plateau ferme.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(dim)

	# Plateau centré.
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UIHelpers.card_style(ec, 0.10, 0.70, 2, 10))
	board.custom_minimum_size = BOARD_SIZE
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.size = BOARD_SIZE
	board.position = (get_viewport_rect().size - BOARD_SIZE) * 0.5
	add_child(board)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	var mc := UIHelpers.margin_of(10)
	mc.add_child(root)
	board.add_child(mc)

	# En-tête : nom + palier + points + fermer.
	root.add_child(_header(equip, tier, ec))

	# Zone d'arbre (clipée) : conteneur pannable avec liens + nœuds.
	var area := Control.new()
	area.clip_contents = true
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size = Vector2(BOARD_SIZE.x - 24, BOARD_SIZE.y - 80)
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	area.gui_input.connect(_on_area_input)
	root.add_child(area)

	_layer = _Canvas.new()
	(_layer as _Canvas).tree_nodes = tree.get("nodes", [])
	(_layer as _Canvas).owned = _owned_set()
	(_layer as _Canvas).link_color = ec
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.position = _pan_offset
	_layer.size = BOARD_SIZE
	area.add_child(_layer)

	for node in tree.get("nodes", []):
		_layer.add_child(_node_button(node, tier))

func _header(equip: Dictionary, tier: int, ec: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = Translations.entity_name(equip, equipment_id)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", ec.lerp(Color.WHITE, 0.3))
	row.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = GameData.get_tier_name(tier)
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", ec.lerp(Color.WHITE, 0.25))
	row.add_child(tier_lbl)

	var pts_lbl := Label.new()
	pts_lbl.text = Translations.T("forge.points") % ForgeSystem.points(equipment_id)
	pts_lbl.add_theme_font_size_override("font_size", 12)
	pts_lbl.add_theme_color_override("font_color", UIColors.FILTER_ON)
	row.add_child(pts_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", ec)
	close_btn.pressed.connect(_close)
	row.add_child(close_btn)
	return row

# ─── Bouton de nœud ──────────────────────────────────────────

func _node_button(node: Dictionary, tier: int) -> Button:
	var node_id := str(node.get("id", ""))
	var ntype := str(node.get("type", "mineur"))
	var state := ForgeSystem.node_state(equipment_id, node_id)
	var buyable := ForgeSystem.can_buy_node(equipment_id, node_id)

	var col := UIColors.TEXT_MUTED
	match state:
		"owned":     col = UIColors.LOG_VICTORY
		"available": col = UIColors.tier_color(tier) if buyable else UIColors.tier_color(tier).darkened(0.35)

	var btn := Button.new()
	btn.text = GLYPH.get(ntype, "●")
	btn.size = NODE_SIZE
	btn.position = (node.get("pos", Vector2.ZERO) as Vector2) - NODE_SIZE * 0.5
	btn.add_theme_font_size_override("font_size", 22 if ntype == "keystone" else 18)
	btn.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.4))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var fill := 0.30 if state == "owned" else (0.16 if state == "available" else 0.06)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(col, fill, 0.9, 2, 28))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(col, fill + 0.12, 1.0, 2, 28))
	btn.add_theme_stylebox_override("pressed", UIHelpers.card_style(col, fill + 0.12, 1.0, 2, 28))

	UIHelpers.register_tooltip(btn, _node_title(node), _node_tooltip(node, state), col)

	if buyable:
		btn.pressed.connect(func() -> void: ForgeSystem.buy_node(equipment_id, node_id))
	else:
		btn.disabled = (state != "available")  # garde le survol pour le tooltip si achetable plus tard
	return btn

func _node_title(node: Dictionary) -> String:
	var loc := GameSettings.language
	var key := "nom_en" if loc == "en" else "nom_fr"
	return str(node.get(key, node.get("nom_fr", node.get("id", ""))))

func _node_tooltip(node: Dictionary, state: String) -> String:
	var lines: Array[String] = []
	var strate := int(node.get("strate", 1))
	var ntype := str(node.get("type", "mineur"))
	lines.append(Translations.T("forge.node.type." + ntype) + " · " + (Translations.T("forge.node.strate") % strate))

	# Effet de stat de base (mineur/notable).
	var stat := str(node.get("stat", ""))
	if stat != "":
		var pct := int(round(Balance.forge_node_stat_pct(strate, ntype) * 100.0))
		if pct != 0:
			lines.append("+%d%% %s" % [pct, Translations.T("forge.stat." + stat)])
	# Effet nommé.
	var eff := node.get("effect", {}) as Dictionary
	if not eff.is_empty():
		lines.append(Translations.T("forge.effect." + str(eff.get("kind", ""))))

	# Coût.
	if state != "owned":
		var cost := ForgeSystem.node_point_cost(equipment_id, node)
		lines.append(Translations.T("forge.node.cost") % cost)
		var ing := ForgeSystem.node_ingredient_cost(equipment_id, node)
		if not ing.is_empty():
			var res := GameData.get_entity(ing["res_id"])
			lines.append("%s ×%d" % [Translations.entity_name(res, ing["res_id"]), int(ing["qty"])])
		if state == "locked_strate":
			lines.append(Translations.T("forge.node.locked_strate") % strate)
		elif state == "locked_connexite":
			lines.append(Translations.T("forge.node.locked_connexite"))
	else:
		lines.append(Translations.T("forge.node.owned"))
	return "\n".join(lines)

func _owned_set() -> Dictionary:
	var out: Dictionary = {}
	for n in ForgeSystem.forge_state(equipment_id).get("nodes", []):
		out[str(n)] = true
	return out

# ─── Pan (glisser la vue) ────────────────────────────────────

func _on_area_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (ev as InputEventMouseButton).pressed
	elif ev is InputEventMouseMotion and _dragging and _layer:
		_pan_offset += (ev as InputEventMouseMotion).relative
		_layer.position = _pan_offset

# ─── Canvas interne : dessine les liens entre voisins ────────

class _Canvas extends Control:
	var tree_nodes: Array = []
	var owned: Dictionary = {}
	var link_color: Color = Color.WHITE

	func _draw() -> void:
		var pos: Dictionary = {}
		for n in tree_nodes:
			pos[str(n.get("id", ""))] = n.get("pos", Vector2.ZERO)
		var seen: Dictionary = {}
		for n in tree_nodes:
			var aid := str(n.get("id", ""))
			for bid_v in n.get("adj", []):
				var bid := str(bid_v)
				var key := aid + "|" + bid if aid < bid else bid + "|" + aid
				if seen.has(key) or not pos.has(bid):
					continue
				seen[key] = true
				var both_owned: bool = owned.has(aid) and owned.has(bid)
				var c := link_color if both_owned else Color(link_color, 0.28)
				draw_line(pos[aid], pos[bid], c, 3.0 if both_owned else 2.0, true)
