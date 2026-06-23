# ============================================================
# CombatLootBanner.gd — Bandeau de butin du cycle (extrait de CombatScene).
#
# Concern autonome : le bandeau bas-gauche qui « encaisse » les ingrédients
# droppés. À chaque drop, une pastille jaillit de la créature, vole en arc
# vers le bandeau et s'y empile (×2, ×3…).
#
# Le host (CombatScene) reste le PARENT des pastilles volantes (l'animation
# traverse l'arène) et fournit la position source (boule de la créature) via
# `host.loot_source_pos()`. Les connexions EventBus restent côté host (Node →
# auto-déconnexion) ; ce composant n'écoute aucun signal pour éviter qu'une
# connexion ne le maintienne en vie après la libération de la scène.
# ============================================================
class_name CombatLootBanner
extends RefCounted

var _host: Control                # CombatScene : parent des pastilles + géométrie
var _banner:  PanelContainer      # cible « qui encaisse »
var _row:     HBoxContainer       # rangée de pastilles empilées
var _hint:    Label               # libellé affiché quand le bandeau est vide
var _pellets: Dictionary = {}     # item_id → {box: Control, count: Label, qty: int}

func _init(host: Control) -> void:
	_host = host

# Construit le bandeau (titre + rangée). À ajouter à l'arbre par l'appelant.
func build() -> Control:
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("margin_left",   5)
	wrap.add_theme_constant_override("margin_bottom", 4)

	_banner = PanelContainer.new()
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner.custom_minimum_size = Vector2(0, 42)
	_banner.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.LOG_LOOT, 0.06, 0.45, 1, 6))
	wrap.add_child(_banner)

	# Marge serrée (6 px) pour laisser un maximum de hauteur aux pastilles.
	var m := UIHelpers.margin_of(6)
	_banner.add_child(m)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(inner)

	var title := UIHelpers.label(Translations.T("combat.loot.title"), 12, UIColors.LOG_LOOT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(title)

	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override("separation", 6)
	inner.add_child(_row)

	_hint = UIHelpers.label(Translations.T("combat.loot.empty"), 12, UIColors.TEXT_MUTED)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(_hint)
	return wrap

# Vide le bandeau (nouveau cycle) : pastilles retirées, indice « vide » rétabli.
func reset() -> void:
	if not _row:
		return
	for child in _row.get_children():
		if child != _hint:
			child.queue_free()
	_pellets.clear()
	if _hint:
		_hint.visible = true

# drops : Array de { item_id, name, qty }. Inerte si le bandeau n'existe pas
# (Forge non débloquée → bandeau masqué).
func on_loot_dropped(drops: Array) -> void:
	if not _row:
		return
	for d in drops:
		var item_id := String(d.get("item_id", ""))
		if item_id == "":
			continue
		var ingr := GameData.get_entity(item_id)
		var nom  := Translations.entity_name(ingr, String(d.get("name", item_id)))
		_spawn_pellet(item_id, nom, int(d.get("qty", 1)))

# Badge rond placeholder (en attendant les icônes) : pastille colorée + initiale.
func _make_badge(color: Color, initial: String, diameter: int) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(diameter, diameter)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color     = Color(color.r, color.g, color.b, 0.92)
	st.border_color = color.lightened(0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(int(diameter / 2))
	st.shadow_color = Color(0, 0, 0, 0.40)
	st.shadow_size  = 4
	badge.add_theme_stylebox_override("panel", st)
	var lbl := UIHelpers.label(initial, int(diameter * 0.5), Color(0.06, 0.06, 0.09))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge

# Une pastille jaillit de la créature, fait un pop, puis vole en arc vers le
# bandeau et s'y empile. La pastille volante est parentée au host (elle traverse
# l'arène) ; le tween appartient aussi au host (auto-tué à la libération).
func _spawn_pellet(item_id: String, item_name: String, qty: int) -> void:
	var color   := UIColors.loot_color(item_id)
	var initial := item_name.substr(0, 1).to_upper() if item_name != "" else "?"
	const D := 33   # +25 % vs taille du bandeau, pour bien la voir jaillir
	var half := Vector2(D, D) * 0.5

	# Origine : centre de la boule d'énergie de la créature (fournie par le host).
	var start_c: Vector2 = _host.loot_source_pos()
	# Cible : tiers gauche du bandeau (fallback : coin bas-gauche).
	var end_c := _host.size * Vector2(0.10, 0.95)
	if _banner and is_instance_valid(_banner):
		end_c = _banner.global_position + _banner.size * Vector2(0.15, 0.5)

	var pellet := _make_badge(color, initial, D)
	pellet.z_index = 120
	_host.add_child(pellet)
	pellet.pivot_offset    = half
	pellet.global_position = start_c - half
	pellet.scale           = Vector2(0.3, 0.3)

	var arc_h := 60.0 + absf(end_c.x - start_c.x) * 0.10

	var tw := _host.create_tween()
	# Jaillissement : pop élastique sur place.
	tw.tween_property(pellet, "scale", Vector2(1.05, 1.05), 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Vol en arc vers le bandeau (apex via sinus). Lambda mono-ligne : un corps
	# multi-ligne en argument non-final casse l'indentation côté GDScript.
	tw.tween_method(func(t: float) -> void: pellet.set("global_position",
			start_c.lerp(end_c, t) - Vector2(0.0, arc_h * sin(PI * t)) - half),
			0.0, 1.0, 0.46).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Léger rétrécissement en approche (s'écrase dans le bandeau).
	tw.parallel().tween_property(pellet, "scale", Vector2(0.7, 0.7), 0.46) \
			.set_ease(Tween.EASE_IN)
	# Atterrissage : empilement + impact du bandeau.
	tw.tween_callback(func() -> void:
		pellet.queue_free()
		_land(item_id, item_name, qty, color, initial)
	)

# La pastille atterrit : crée son entrée dans le bandeau, ou incrémente le
# compteur de l'entrée existante (×2, ×3…) avec un punch. Le bandeau encaisse.
func _land(item_id: String, item_name: String, qty: int, color: Color, initial: String) -> void:
	if _hint:
		_hint.visible = false
	_punch(_banner, 1.03)

	if _pellets.has(item_id):
		var entry: Dictionary = _pellets[item_id]
		entry["qty"] = int(entry["qty"]) + qty
		var cl: Label = entry["count"]
		cl.text    = "×%d" % int(entry["qty"])
		cl.visible = int(entry["qty"]) > 1
		_punch(entry["box"], 1.25)
		return

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	# Badge dimensionné au max de la hauteur utile du bandeau (≈ 42 − 2×6).
	box.add_child(_make_badge(color, initial, 30))
	var nm := UIHelpers.label(item_name, 14, Color.WHITE)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var cnt := UIHelpers.label("×%d" % qty, 14, UIColors.LOG_LOOT)
	cnt.visible = qty > 1
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(cnt)
	_row.add_child(box)
	_pellets[item_id] = {"box": box, "count": cnt, "qty": qty}

	# Pop d'apparition (pivot connu une fois la taille calculée).
	box.scale = Vector2(0.6, 0.6)
	box.resized.connect(func() -> void:
		box.pivot_offset = box.size * 0.5
	, CONNECT_ONE_SHOT)
	_host.create_tween().tween_property(box, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Petit « punch » de mise à l'échelle (impact d'encaissement).
func _punch(node: Control, amount: float) -> void:
	if not node or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var tw := _host.create_tween()
	tw.tween_property(node, "scale", Vector2(amount, amount), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
