# ============================================================
# HoloLocation3D — Lieu d'expédition cliquable en 3D (PUR OVERLAY).
#
# Area3D placée sur la zone du lieu. N'ajoute JAMAIS de bâtiment : le décor sous la
# zone (usine, cimetière, pyramide, bâtiment générique, parc…) est DÉJÀ rendu par
# HoloMap3D. Pose seulement, en COULEUR DE PALIER (UIColors.tier_color) :
#   • un PIN diamant flottant au-dessus du toit réel (repère permanent) ;
#   • une BARRIÈRE D'ÉNERGIE verticale le long du périmètre de la zone — la
#     délimitation de la propriété exploitable : discrète au repos, vive au survol.
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
var taille_x: float = 0.7                # emprise monde X (zone) — pour la collision
var taille_z: float = 0.7                # emprise monde Z (zone) — pour la collision
var hauteur: float = 1.0                 # hauteur monde du DÉCOR sous la zone (pour flotter le pin)
var pin_float: float = 1.2               # distance du pin au-dessus du toit
var barriere_h: float = 0.6              # hauteur monde des piliers d'énergie
var pilier_hw: float = 0.06              # demi-largeur d'un pilier (indépendante de la hauteur)
var line_shader: Shader
# Périmètre de la zone : paires de points LOCAUX (segments d'arête au sol), fourni par
# HoloMap3D. Extrudé vers le haut → barrière verticale. Vide → pas de barrière (pin seul).
var perimetre: PackedVector3Array = PackedVector3Array()

var _t := 0.0
var _fade := 1.0                 # opacité du pin au dézoom (1 = plein, cf. HoloMap3D._appliquer_fade_pins)
var _hover := false
var _pin: MeshInstance3D
var _barriere: MeshInstance3D
var _pin_y := 0.0
var _barriere_a := 0.0       # intensité du survol (0 = repos discret, 1 = sélection vive)
var _mat_pin: ShaderMaterial
var _mat_barriere: ShaderMaterial

const PIN_R := 0.26
const PIN_H := 0.34
const BARRIERE_SHADER := preload("res://scenes/holomap3d/holo_barriere.gdshader")

func _ready() -> void:
	input_ray_pickable = true
	_mat_pin = _mk_mat()
	_mat_barriere = ShaderMaterial.new()
	_mat_barriere.shader = BARRIERE_SHADER
	_mat_barriere.set_shader_parameter("alpha_mult", 0.0)   # invisible au repos
	_pin_y = hauteur + pin_float
	_construire()

	# Collision en DEUX boîtes : le corps de la zone (au ras du décor) + le pin
	# seul. JAMAIS une colonne pleine sol→pin : l'air entre le toit et le pin
	# capterait le rayon et volerait le survol/clic des zones situées DERRIÈRE
	# dès que la caméra s'abaisse (régression vue en jeu quand pin_float et la
	# hauteur des piliers ont grandi — la colonne invisible a grandi avec eux).
	var c_zone := CollisionShape3D.new()
	var s_zone := BoxShape3D.new()
	var h_zone := hauteur + 0.3   # léger débord au-dessus du toit (barrière)
	s_zone.size = Vector3(maxf(taille_x, 0.2), h_zone, maxf(taille_z, 0.2))
	c_zone.shape = s_zone
	c_zone.position = Vector3(0, h_zone * 0.5, 0)
	add_child(c_zone)
	var c_pin := CollisionShape3D.new()
	var s_pin := BoxShape3D.new()
	# Marge autour du diamant (cible confortable) + amplitude du flottement.
	s_pin.size = Vector3(PIN_R * 3.2, PIN_H * 2.2, PIN_R * 3.2)
	c_pin.shape = s_pin
	c_pin.position = Vector3(0, _pin_y, 0)
	add_child(c_pin)

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

# Opacité du pin (0..1) pilotée par le dézoom (cf. HoloMap3D._appliquer_fade_pins) —
# jamais la barrière : elle reste invisible au repos de toute façon (n'apparaît
# qu'au survol), le fondu au dézoom n'a donc rien à y ajouter.
func set_fade(f: float) -> void:
	_fade = f

# Reveal d'intro : rayon de matérialisation poussé sur tous les matériaux.
func set_reveal(r: float) -> void:
	for m in [_mat_pin, _mat_barriere]:
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
	# ── Pin diamant flottant (repère permanent, au-dessus du toit réel) ──
	var sp := HoloMesh3D.st()
	var np := HoloMesh3D.diamond(sp, Vector3.ZERO, PIN_R, PIN_H, col)
	_pin = MeshInstance3D.new()
	_pin.mesh = HoloMesh3D.commit(sp, np)
	_pin.material_override = _mat_pin
	_pin.position = Vector3(0, _pin_y, 0)
	add_child(_pin)

	# ── Piliers d'énergie verticaux (champ de force VIVANT, cf. holo_barriere), plantés
	# à INTERVALLE RÉGULIER le long du périmètre (un au milieu de chaque arête de zone) →
	# des colonnes qui ceinturent la propriété. Invisibles au repos, apparaissent au survol. ──
	if perimetre.size() >= 2:
		var up := Vector3(0, barriere_h, 0)
		var hw := pilier_hw   # piliers fins, distincts (largeur indépendante de la hauteur)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var i := 0
		while i + 1 < perimetre.size():
			var mid: Vector3 = (perimetre[i] + perimetre[i + 1]) * 0.5
			_pilier(st, mid, hw, up)
			i += 2
		_barriere = MeshInstance3D.new()
		_barriere.mesh = st.commit()
		_barriere.material_override = _mat_barriere
		_barriere.visible = false   # apparaît au survol
		add_child(_barriere)

func _process(dt: float) -> void:
	_t += dt
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	if is_instance_valid(_pin):
		_pin.position.y = _pin_y + sin(_t * 2.0) * 0.06
		_mat_pin.set_shader_parameter("emission_strength",
				(10.5 + 1.2 * pulse) if _hover else (7.5 + 0.6 * pulse))
		_mat_pin.set_shader_parameter("alpha_mult", _fade)

	# Barrière : INVISIBLE au repos, fondu d'apparition au survol — l'animation VIVANTE
	# (bandes montantes, impulsion qui tourne, crépitement) est portée par le shader.
	if is_instance_valid(_barriere):
		_barriere_a = lerpf(_barriere_a, 1.0 if _hover else 0.0, 1.0 - exp(-10.0 * dt))
		if _barriere_a < 0.01:
			_barriere.visible = false
		else:
			_barriere.visible = true
			_mat_barriere.set_shader_parameter("alpha_mult", _barriere_a)

# Un pilier d'énergie = croix de 2 quads verticaux (axes X et Z) sur `base`, montant de
# `up` → une colonne lisible sous tout angle d'orbite.
func _pilier(st: SurfaceTool, base: Vector3, hw: float, up: Vector3) -> void:
	var dx := Vector3(hw, 0, 0)
	var dz := Vector3(0, 0, hw)
	_quad(st, base - dx, base + dx, base + dx + up, base - dx + up)
	_quad(st, base - dz, base + dz, base + dz + up, base - dz + up)

# Un panneau vertical (quad) du périmètre, en 2 triangles. UV.y = hauteur (0 base →
# 1 haut) pour le shader ; COLOR = teinte de palier. cull_disabled → visible des 2 faces.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, bt: Vector3, at: Vector3) -> void:
	var cc := Color(col, 1.0)
	st.set_color(cc); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_color(cc); st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_color(cc); st.set_uv(Vector2(1, 1)); st.add_vertex(bt)
	st.set_color(cc); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_color(cc); st.set_uv(Vector2(1, 1)); st.add_vertex(bt)
	st.set_color(cc); st.set_uv(Vector2(0, 1)); st.add_vertex(at)
