# ============================================================
# HoloLocation3D — Lieu d'expédition cliquable en 3D.
#
# Area3D placée à la position monde du lieu. Dessine :
#   • une base wireframe (contour magenta + petit cercle au sol) ;
#   • un PIN diamant flottant (octaèdre wireframe) relié par une tige ;
#   • un ANNEAU pulsant (ping radar) projeté au sol.
# Pin + anneau pulsent en continu ; le survol (raycast caméra) intensifie tout.
#
# Détection clic/survol en 3D via le picking physique du viewport (Area3D +
# CollisionShape3D + input_ray_pickable). Suit la caméra → fonctionne pendant
# et après rotation. Clic gauche → émet `clique(id)`.
# ============================================================
class_name HoloLocation3D
extends Area3D

signal clique(id: String)
# Survol entrée/sortie (raycast caméra) — HoloMap3D s'y abonne pour le tooltip.
signal survol_change(loc: HoloLocation3D, actif: bool)

# ─── Données (définies AVANT add_child) ───────────────────────
var lieu_id: String = ""
var lieu_nom: String = ""
var tier: int = 0                  # palier du lieu (couleur + nom de palier au tooltip)
var lore: String = ""              # texte d'ambiance (tooltip)
var accent_color: Color = Color(1.00, 0.25, 0.78)  # magenta (marqueur)
var base_color: Color = Color(0.30, 0.85, 1.00)    # cyan (touche)
var footprint: float = 0.8        # côté de la base (unités monde)
var base_y: float = 0.0           # hauteur du sol (relief) sous le lieu
var base_height: float = 1.4      # hauteur de la base-contour
var pin_float: float = 1.1        # distance du pin au-dessus de la base
var ring_radius: float = 0.9
var line_shader: Shader

var _t := 0.0
var _hover := false
var _pin: MeshInstance3D
var _ring: MeshInstance3D
var _pin_y := 0.0
var _mat_base: ShaderMaterial
var _mat_pin: ShaderMaterial
var _mat_ring: ShaderMaterial

const PIN_R := 0.32
const PIN_H := 0.42

func _ready() -> void:
	input_ray_pickable = true
	_mat_base = _mk_mat()
	_mat_pin  = _mk_mat()
	_mat_ring = _mk_mat()
	_construire()

	var box_top := base_y + base_height
	_pin_y = box_top + pin_float

	# Collision : boîte englobant base + pin (clic sur tout le marqueur).
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var total_h := (_pin_y + PIN_H) - base_y
	shape.size = Vector3(footprint * 1.4, total_h, footprint * 1.4)
	col.shape = shape
	col.position = Vector3(0, base_y + total_h * 0.5, 0)
	add_child(col)

	mouse_entered.connect(func() -> void:
		_hover = true
		survol_change.emit(self, true))
	mouse_exited.connect(func() -> void:
		_hover = false
		survol_change.emit(self, false))
	input_event.connect(_on_input_event)
	set_process(true)

# Position monde du pin (sommet du diamant) — ancre 3D du tooltip.
func ancre_globale() -> Vector3:
	return to_global(Vector3(0, _pin_y + PIN_H, 0))

func _mk_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = line_shader
	return m

func _on_input_event(_cam: Node, ev: InputEvent, _pos: Vector3, _nrm: Vector3, _shape: int) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clique.emit(lieu_id)

func _construire() -> void:
	var box_top := base_y + base_height
	var pin_y := box_top + pin_float

	# ── Base : contour + cercle au sol + tige vers le pin ──
	var sb := HoloMesh3D.st()
	var n := 0
	HoloMesh3D.box(sb, Vector3(0, base_y, 0), footprint, base_height, footprint, accent_color); n += 12
	HoloMesh3D.circle(sb, Vector3(0, base_y + 0.02, 0), ring_radius * 0.45,
			Color(base_color, 0.9), 24); n += 24
	HoloMesh3D.line(sb, Vector3(0, box_top, 0), Vector3(0, pin_y - PIN_H, 0),
			Color(accent_color, 0.6)); n += 1
	var base := MeshInstance3D.new()
	base.mesh = HoloMesh3D.commit(sb, n)
	base.material_override = _mat_base
	add_child(base)

	# ── Anneau pulsant au sol ──
	var sr := HoloMesh3D.st()
	HoloMesh3D.circle(sr, Vector3.ZERO, ring_radius, accent_color, 36)
	_ring = MeshInstance3D.new()
	_ring.mesh = HoloMesh3D.commit(sr, 36)
	_ring.material_override = _mat_ring
	_ring.position = Vector3(0, base_y + 0.03, 0)
	add_child(_ring)

	# ── Pin diamant flottant ──
	var sp := HoloMesh3D.st()
	HoloMesh3D.diamond(sp, Vector3.ZERO, PIN_R, PIN_H, accent_color); var np := 12
	_pin = MeshInstance3D.new()
	_pin.mesh = HoloMesh3D.commit(sp, np)
	_pin.material_override = _mat_pin
	_pin.position = Vector3(0, pin_y, 0)
	add_child(_pin)

func _process(dt: float) -> void:
	_t += dt
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	# Base (contour) : émission constante, boostée au survol.
	_mat_base.set_shader_parameter("emission_strength",
			(2.8 + 0.4 * pulse) if _hover else 1.7)

	# Pin : bob vertical + pulse d'émission.
	if is_instance_valid(_pin):
		_pin.position.y = _pin_y + sin(_t * 2.0) * 0.08
		_mat_pin.set_shader_parameter("emission_strength",
				(3.6 + 0.6 * pulse) if _hover else (2.2 + 0.5 * pulse))

	# Anneau : ping radar (expansion + fondu).
	if is_instance_valid(_ring):
		var phase := fposmod(_t * 0.6, 1.0)
		var s := 0.5 + 0.9 * phase
		_ring.scale = Vector3(s, 1.0, s)
		_mat_ring.set_shader_parameter("alpha_mult",
				(1.0 - phase) * (1.5 if _hover else 1.0))
		_mat_ring.set_shader_parameter("emission_strength", 3.0 if _hover else 2.0)
