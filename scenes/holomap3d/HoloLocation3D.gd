# ============================================================
# HoloLocation3D — Lieu d'expédition cliquable en 3D.
#
# Area3D placée à la position monde du lieu. Dessine, en COULEUR DE PALIER
# (UIColors.tier_color, trait plein + glow marqué → ressort du tissu urbain) :
#   • le bâtiment-lieu (boîte d'emprise N×M, étages, subdivision légère) ;
#   • un PIN diamant flottant relié par une tige ;
#   • un ANNEAU pulsant (ping radar) projeté au sol.
# Pin + anneau pulsent en continu ; le survol intensifie tout.
#
# Picking 3D via le viewport (Area3D + CollisionShape3D + input_ray_pickable) →
# survol/clic suivent la caméra. Clic gauche → émet `clique(id)`.
# ============================================================
class_name HoloLocation3D
extends Area3D

signal clique(id: String)
signal survol_change(loc: HoloLocation3D, actif: bool)

# ─── Données (définies AVANT add_child) ───────────────────────
var lieu_id: String = ""
var lieu_nom: String = ""
var tier: int = 0
var lore: String = ""
var col: Color = Color(0.7, 0.7, 0.7)   # couleur de palier (UIColors.tier_color)
var taille_x: float = 0.7                # emprise monde X
var taille_z: float = 0.7                # emprise monde Z
var hauteur: float = 1.0                 # hauteur monde du bâtiment
var etages: int = 4                      # subdivision (lignes d'étages)
var pin_float: float = 0.6               # distance du pin au-dessus du toit
var ring_radius: float = 0.8
var sans_batiment: bool = false          # true → pas de boîte/faces/tige (le décor EST le corps)
var line_shader: Shader
var face_material: Material               # faces sombres semi-opaques (occlusion)
var face_inset: float = 0.96

var _t := 0.0
var _hover := false
var _pin: MeshInstance3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _halo: MeshInstance3D
var _pin_y := 0.0
var _beam_a := 0.0          # opacité courante du faisceau (fondu au survol)
var _mat_bat: ShaderMaterial
var _mat_pin: ShaderMaterial
var _mat_ring: ShaderMaterial
var _mat_beam: ShaderMaterial
var _mat_halo: ShaderMaterial

const PIN_R := 0.26
const PIN_H := 0.34

func _ready() -> void:
	input_ray_pickable = true
	_mat_bat  = _mk_mat()
	_mat_pin  = _mk_mat()
	_mat_ring = _mk_mat()
	_mat_beam = _mk_mat()
	_mat_halo = _mk_mat()
	_pin_y = hauteur + pin_float
	_construire()

	# Collision : boîte englobant bâtiment + pin (clic sur tout le marqueur).
	var c := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var total_h := _pin_y + PIN_H
	shape.size = Vector3(maxf(taille_x, ring_radius * 2.0), total_h, maxf(taille_z, ring_radius * 2.0))
	c.shape = shape
	c.position = Vector3(0, total_h * 0.5, 0)
	add_child(c)

	mouse_entered.connect(func() -> void:
		_hover = true
		survol_change.emit(self, true))
	mouse_exited.connect(func() -> void:
		_hover = false
		survol_change.emit(self, false))
	input_event.connect(_on_input_event)
	set_process(true)

func ancre_globale() -> Vector3:
	return to_global(Vector3(0, _pin_y + PIN_H, 0))

# Reveal d'intro : rayon de matérialisation poussé sur tous les matériaux.
func set_reveal(r: float) -> void:
	for m in [_mat_bat, _mat_pin, _mat_ring, _mat_beam, _mat_halo]:
		if m != null:
			m.set_shader_parameter("reveal_r", r)

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
	# Lieu SANS bâtiment : on saute faces + boîte + tige ; le décor sous l'emprise
	# (ex. parc) tient lieu de corps. Seuls anneau + pin + collision subsistent.
	if not sans_batiment:
		# ── Faces sombres semi-opaques (occlusion douce), légèrement insérées ──
		if face_material != null:
			var sf := HoloMesh3D.st_tri()
			var nf := HoloMesh3D.box_faces(sf, Vector3.ZERO,
					taille_x * face_inset, hauteur * face_inset, taille_z * face_inset)
			var fmesh := HoloMesh3D.commit(sf, nf)
			if fmesh != null:
				var mif := MeshInstance3D.new()
				mif.mesh = fmesh
				mif.material_override = face_material
				add_child(mif)

		# ── Bâtiment-lieu : contour creux UNIQUEMENT (12 arêtes) ──
		var sb := HoloMesh3D.st()
		var n := HoloMesh3D.box(sb, Vector3.ZERO, taille_x, hauteur, taille_z, col)
		n += HoloMesh3D.line(sb, Vector3(0, hauteur, 0), Vector3(0, _pin_y - PIN_H, 0), col)  # tige
		var bat := MeshInstance3D.new()
		bat.mesh = HoloMesh3D.commit(sb, n)
		bat.material_override = _mat_bat
		add_child(bat)

	# ── Halo au sol (disque dégradé tier-coloré, ancre le lieu) ──
	var shd := SurfaceTool.new()
	shd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hrad := ring_radius * 1.5
	var hseg := 28
	for i in hseg:
		var a0 := TAU * float(i) / float(hseg)
		var a1 := TAU * float(i + 1) / float(hseg)
		shd.set_color(Color(col, 0.40)); shd.add_vertex(Vector3.ZERO)
		shd.set_color(Color(col, 0.0)); shd.add_vertex(Vector3(cos(a0) * hrad, 0, sin(a0) * hrad))
		shd.set_color(Color(col, 0.0)); shd.add_vertex(Vector3(cos(a1) * hrad, 0, sin(a1) * hrad))
	_halo = MeshInstance3D.new()
	_halo.mesh = shd.commit()
	_halo.material_override = _mat_halo
	_halo.position = Vector3(0, 0.012, 0)
	add_child(_halo)

	# ── Anneau pulsant au sol ──
	var sr := HoloMesh3D.st()
	var nr := HoloMesh3D.circle(sr, Vector3.ZERO, ring_radius, col, 36)
	_ring = MeshInstance3D.new()
	_ring.mesh = HoloMesh3D.commit(sr, nr)
	_ring.material_override = _mat_ring
	_ring.position = Vector3(0, 0.03, 0)
	add_child(_ring)

	# ── Pin diamant flottant ──
	var sp := HoloMesh3D.st()
	var np := HoloMesh3D.diamond(sp, Vector3.ZERO, PIN_R, PIN_H, col)
	_pin = MeshInstance3D.new()
	_pin.mesh = HoloMesh3D.commit(sp, np)
	_pin.material_override = _mat_pin
	_pin.position = Vector3(0, _pin_y, 0)
	add_child(_pin)

	# ── Faisceau vertical (visible au survol) : colonne de lumière vers le ciel ──
	var bh := maxf(hauteur * 2.4, 2.2)
	var rb := maxf(PIN_R * 0.6, taille_x * 0.12)
	var sm := HoloMesh3D.st()
	var nb := HoloMesh3D.line(sm, Vector3.ZERO, Vector3(0, bh, 0), col)
	for corner in [Vector2(rb, rb), Vector2(-rb, rb), Vector2(rb, -rb), Vector2(-rb, -rb)]:
		nb += HoloMesh3D.line(sm, Vector3(corner.x, 0, corner.y), Vector3(corner.x, bh, corner.y), col)
	nb += HoloMesh3D.circle(sm, Vector3(0, bh, 0), rb * 1.5, col, 16)
	_beam = MeshInstance3D.new()
	_beam.mesh = HoloMesh3D.commit(sm, nb)
	_beam.material_override = _mat_beam
	_beam.visible = false
	add_child(_beam)

func _process(dt: float) -> void:
	_t += dt
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	# Bâtiment-lieu : trait plein lumineux (glow marqué), boosté au survol.
	_mat_bat.set_shader_parameter("emission_strength",
			(3.6 + 0.5 * pulse) if _hover else 2.4)

	if is_instance_valid(_pin):
		_pin.position.y = _pin_y + sin(_t * 2.0) * 0.06
		_mat_pin.set_shader_parameter("emission_strength",
				(4.2 + 0.6 * pulse) if _hover else (2.8 + 0.5 * pulse))

	if is_instance_valid(_ring):
		var phase := fposmod(_t * 0.6, 1.0)
		var s := 0.5 + 0.9 * phase
		_ring.scale = Vector3(s, 1.0, s)
		_mat_ring.set_shader_parameter("alpha_mult",
				(1.0 - phase) * (1.5 if _hover else 1.0))
		_mat_ring.set_shader_parameter("emission_strength", 3.4 if _hover else 2.4)

	# Halo au sol : respiration douce, plus intense au survol.
	if is_instance_valid(_halo):
		_mat_halo.set_shader_parameter("alpha_mult", (0.55 + 0.3 * pulse) * (1.6 if _hover else 1.0))
		_mat_halo.set_shader_parameter("emission_strength", 1.9 if _hover else 1.2)

	# Faisceau : fondu d'apparition au survol (disparaît hors survol).
	if is_instance_valid(_beam):
		_beam_a = lerpf(_beam_a, 1.0 if _hover else 0.0, 1.0 - exp(-10.0 * dt))
		if _beam_a < 0.01:
			_beam.visible = false
		else:
			_beam.visible = true
			_mat_beam.set_shader_parameter("alpha_mult", _beam_a * (0.45 + 0.35 * pulse))
			_mat_beam.set_shader_parameter("emission_strength", 3.2)
