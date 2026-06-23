# ============================================================
# District — Quartier explorable : un MINI-HUB à la même DA que le Village.
#
# Révélé depuis un élément de la place centrale (« owner ») au bout de son
# EnergyLink. Présente un CircleRing, un libellé central, une zone-fermeture
# cliquable au cœur, et des « pièces » (HexItem) réparties sur l'anneau.
#
# 100 % data-driven : les pièces (ids/icônes/libellés) sont PROPRES à chaque
# quartier et passées par `rooms`. Ce widget ne suppose AUCUN nom de pièce.
# L'orchestration (lien, boule, caméra, ouverture des panneaux) reste côté
# Village ; ce widget ne fait que se construire et émettre des signaux.
# ============================================================
class_name District extends Control

# Émis au clic d'une pièce (le panel_id de la pièce, ex. "district_house").
signal room_clicked(panel_id: String)
# Émis au clic de la zone centrale (demande de fermeture du quartier).
signal close_requested

const RING_PAD      := 80.0                  # diamètre de l'anneau = radius*2 + PAD
const ROOM_SIZE     := Vector2(152.0, 152.0)
const CLOSER_RADIUS := 78.0

# ─── Paramètres (à définir AVANT build()) ─────────────────────
var center          : Vector2 = Vector2.ZERO  # centre du quartier (coords du parent)
var radius          : float   = 165.0
var ring_color      : Color   = Color.WHITE
var tier            : int     = 0
var title_text      : String  = ""
# Pièces du quartier : [ [room_panel_id, icon], … ]. Distinctes d'un quartier
# à l'autre — c'est l'appelant qui fournit les libellés (via panel.<room_pid>).
var rooms           : Array   = []
var active_panel_id : String  = ""            # pièce dont le panneau est ouvert

var _rooms_by_id    : Dictionary = {}          # room_panel_id → HexItem

# Construit les nœuds du quartier. `center` etc. doivent être définis avant.
func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_by_id.clear()
	_build_ring()
	_build_title()
	_build_closer()
	_build_rooms()
	# Pivot au centre du quartier → le jiggle d'apparition s'anime « en place ».
	pivot_offset = center

# Anneau (visuel) — non bloquant pour laisser passer le pan sur l'espace.
func _build_ring() -> void:
	var qdiam := radius * 2.0 + RING_PAD
	var ring := CircleRing.new()
	ring.ring_color    = ring_color
	ring.ring_radius   = radius
	ring.tier          = tier
	ring.fill_fraction = 0.0
	ring.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	ring.size          = Vector2(qdiam, qdiam)
	ring.position      = center - Vector2(qdiam, qdiam) * 0.5
	add_child(ring)

# Libellé central du quartier.
func _build_title() -> void:
	var label_box := Control.new()
	label_box.size = Vector2(260.0, 64.0)
	label_box.position = center - Vector2(130.0, 32.0)
	label_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label_box)
	var title := UIHelpers.label(title_text, 20, ring_color.lerp(Color.WHITE, 0.30))
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override("shadow_offset_y", 2)
	label_box.add_child(title)

# Zone centrale CLIQUABLE : un clic au centre referme le quartier.
func _build_closer() -> void:
	var closer := Control.new()
	closer.size = Vector2(CLOSER_RADIUS * 2.0, CLOSER_RADIUS * 2.0)
	closer.position = center - Vector2(CLOSER_RADIUS, CLOSER_RADIUS)
	closer.mouse_filter = Control.MOUSE_FILTER_STOP
	closer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	closer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (ev as InputEventMouseButton).pressed:
			close_requested.emit()
	)
	add_child(closer)

# Pièces : bulles cliquables SUR l'anneau (comme les hexagones du Village),
# chacune ouvre le panneau de son room_panel_id.
func _build_rooms() -> void:
	var count := rooms.size()
	if count <= 0:
		return
	for i in count:
		var ang := -PI * 0.5 + float(i) * TAU / float(count)
		var dir := Vector2(cos(ang), sin(ang))
		var rpos := center + dir * radius
		var pid: String = rooms[i][0]
		var room := HexItem.new()
		room.label_text   = Translations.T("panel." + pid)
		room.tier_color   = ring_color
		room.tier         = maxi(tier, 1)            # 1-2 → bulle ronde
		room.outward_dir  = dir
		room.callback      = _emit_room.bind(pid)
		room.size         = ROOM_SIZE
		room.position     = rpos - ROOM_SIZE * 0.5
		room.pivot_offset = ROOM_SIZE * 0.5
		room.is_selected  = (active_panel_id == pid)
		add_child(room)
		_rooms_by_id[pid] = room

func _emit_room(panel_id: String) -> void:
	room_clicked.emit(panel_id)

# Met à jour l'état sélectionné des pièces selon le panneau ouvert.
func set_room_selected(active_id: String) -> void:
	active_panel_id = active_id
	for pid in _rooms_by_id:
		var node: Variant = _rooms_by_id[pid]
		if is_instance_valid(node):
			var room := node as HexItem
			room.is_selected = (pid == active_id)
			room.queue_redraw()
