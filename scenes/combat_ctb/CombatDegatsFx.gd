# ============================================================
# CombatDegatsFx — couche de « feel » des dégâts en combat (demande Rhend
# 11/11/2026 : « la gestion des dégâts n'est pas assez impactante »).
#
# C'est LA couche FX plein écran de `CombatCtbUi` (son `_fx`), posée au-dessus
# de tout le contenu de jeu. Elle porte quatre effets, tous PUREMENT visuels
# (le hit-stop, lui, est LOCAL aux personnages : `CombatCtbUi._geler_contact`)
# (le moteur n'en sait rien, aucun n'attend ni ne bloque la boucle de combat) :
#
#   • `chiffre()`  — le chiffre flottant, ACCROCHÉ à une ancre (la tête du
#     combattant) recalculée à chaque frame : il suit sa cible pendant le
#     zoom-duel, la convergence au centre et la secousse, au lieu de rester
#     planté là où elle se trouvait à l'impact. Quatre styles : COUP (pop
#     élastique), CRIT (gros, écrasé depuis ×2,6 comme un tampon, chauffé à
#     blanc, étiquette « CRITIQUE ! »), SOIN, INFO (statuts, garde…). Plusieurs
#     chiffres sur la même cible s'EMPILENT vers le haut, jamais superposés.
#   • `eclat()`    — gerbe d'impact additive sur le torse : lueur + étincelles
#     orientées dans le SENS du coup, anneau en plus sur un critique.
#   • `secouer()`  — secousse caméra amortie, premier à-coup dans le sens du
#     coup. ⚠ Le décor couvre EXACTEMENT l'écran, sans marge : une secousse en
#     simple translation découvrirait la couleur de fond aux bords. Elle
#     s'accompagne donc d'un micro punch-in (≈ 3 % au plus fort) calculé pour
#     couvrir pile son propre débattement. Elle agit sur un nœud ENVELOPPE dédié
#     (`CombatCtbUi._couche_secousse`), jamais sur `_couche_scene` : le `scale`
#     de celle-ci appartient au zoom-duel ET est lu par la parallaxe du décor.
#   • `flash()`    — voile plein écran très bref (critique).
#
# Pas de `class_name` : préchargé par CombatCtbUi (`DEGATS_FX`).
# ============================================================
extends Control

enum Style { COUP, CRIT, SOIN, INFO }

const PAS_EMPILEMENT := 30.0   # écart vertical entre deux chiffres d'une même cible
# Gabarits de rastérisation des textes (voir `_label`) : taille de police et
# contour FIXES, l'échelle du nœud fait la taille affichée.
const RASTER_GROS := 56
const CONTOUR_GROS := 12
const RASTER_PETIT := 24
const CONTOUR_PETIT := 7
const GLYPHES_GROS := "0123456789+-−"
const GLYPHES_PETIT := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzéèêàç0123456789 +-−!✦"

# Secousse : pulsations (rad/s) volontairement non multiples l'une de l'autre.
const SECOUSSE_PULS_X := 64.0
const SECOUSSE_PULS_Y := 47.0
const SECOUSSE_PART_Y := 0.55     # l'axe du coup domine
const SECOUSSE_COUVERTURE := 1.2  # marge du punch-in sur le débattement

static var _police: SystemFont = null
static var _lueur: GradientTexture2D = null

var _empilement: Dictionary = {}   # clé (combattant) → nb de chiffres vivants

var _sec_noeud: Control = null
var _sec_amp := 0.0
var _sec_duree := 0.0
var _sec_t := 0.0
var _sec_sens := 1.0
var _sec_phase := 0.0

# ─── Chiffre accroché à son ancre ────────────────────────────
class Chiffre extends Control:
	var ancre: Callable            # → Vector2, dans l'espace de la couche FX
	var decalage := Vector2.ZERO   # animé par les tweens (montée, dérive)
	var tremble := 0.0             # amplitude (px) du tremblement d'un critique
	# Marges d'écran jamais franchies (cible en bord de cadre, ou tête sortie
	# du champ par le zoom-duel).
	const MARGE_X := 70.0
	const MARGE_HAUT := 26.0

	func _process(_delta: float) -> void:
		if not ancre.is_valid():
			return
		var p: Vector2 = ancre.call()
		p += decalage
		if tremble > 0.0:
			p += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * tremble
		var cadre := get_parent_area_size()
		p.x = clampf(p.x, MARGE_X, maxf(MARGE_X, cadre.x - MARGE_X))
		p.y = maxf(p.y, MARGE_HAUT)
		position = p

# ─── Gerbe d'impact ──────────────────────────────────────────
class Eclat extends Control:
	var couleur := Color.WHITE
	var fort := false
	var rayons: Array[Vector3] = []   # (angle, longueur, rayon de départ)
	var lueur: Texture2D = null
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		var e := 1.0 - pow(1.0 - t, 3.0)   # jaillit vite, finit doucement
		var reste := 1.0 - t
		var r_lueur := lerpf(34.0, 96.0, e) * (1.6 if fort else 1.0)
		if lueur != null:
			draw_texture_rect(lueur, Rect2(-r_lueur, -r_lueur, r_lueur * 2.0, r_lueur * 2.0),
					false, Color(couleur.r, couleur.g, couleur.b, reste * reste * 0.9))
			var r_coeur := r_lueur * 0.45
			draw_texture_rect(lueur, Rect2(-r_coeur, -r_coeur, r_coeur * 2.0, r_coeur * 2.0),
					false, Color(1.0, 1.0, 1.0, pow(reste, 3.0)))
		for r in rayons:
			var dir := Vector2.from_angle(r.x)
			var debut := r.z + r.y * e
			var fin := debut + r.y * 0.5 * reste
			draw_line(dir * debut, dir * fin, couleur.lerp(Color.WHITE, reste * 0.8) * Color(1, 1, 1, reste),
					maxf(1.0, (4.0 if fort else 3.0) * reste), true)
		if fort:
			draw_arc(Vector2.ZERO, lerpf(20.0, 150.0, e), 0.0, TAU, 56,
					Color(couleur.r, couleur.g, couleur.b, reste), 1.0 + 5.0 * reste, true)

# ─── Montage ─────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prechauffer_glyphes()

func _exit_tree() -> void:
	_fin_secousse()

func _process(delta: float) -> void:
	if _sec_noeud == null:
		return
	_sec_t += delta
	if not is_instance_valid(_sec_noeud) or _sec_t >= _sec_duree:
		_fin_secousse()
		return
	var k := 1.0 - _sec_t / _sec_duree
	var amp := _sec_amp * k * k
	_sec_noeud.pivot_offset = _sec_noeud.size * 0.5
	_sec_noeud.position = Vector2(
			cos(_sec_t * SECOUSSE_PULS_X) * _sec_sens,
			sin(_sec_t * SECOUSSE_PULS_Y + _sec_phase) * SECOUSSE_PART_Y) * amp
	_sec_noeud.scale = Vector2.ONE * _echelle_couvrante(_sec_noeud, amp)

# Punch-in minimal pour que `amp` px de débattement ne découvrent aucun bord
# (pivot au centre : la marge gagnée vaut demi-côté × (échelle − 1)).
static func _echelle_couvrante(noeud: Control, amp: float) -> float:
	var demi := minf(noeud.size.x, noeud.size.y) * 0.5
	if demi <= 0.0:
		return 1.0
	return 1.0 + amp * SECOUSSE_COUVERTURE / demi

# ─── Chiffre flottant ────────────────────────────────────────
# `ancre` : Callable → Vector2 (espace de cette couche), rappelé à chaque
# frame. `cle` : ce qui partage une même pile (le combattant). `etiquette` :
# petit texte au-dessus du chiffre (« CRITIQUE ! »), vide = aucun.
func chiffre(ancre: Callable, cle: Variant, texte: String, style: int,
		couleur: Color, taille: int, etiquette := "") -> void:
	if not is_inside_tree():
		return
	var c := Chiffre.new()
	c.ancre = ancre
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rang := int(_empilement.get(cle, 0))
	_empilement[cle] = rang + 1
	c.tree_exiting.connect(_depiler.bind(cle))
	c.decalage = Vector2(0.0, -PAS_EMPILEMENT * rang)
	add_child(c)

	var lbl := _label(texte, taille, couleur, style != Style.INFO)
	c.add_child(lbl)
	var t_lbl := lbl.get_minimum_size() * lbl.scale
	lbl.position = -t_lbl * 0.5
	if etiquette != "":
		var tag := _label(etiquette, maxi(12, int(taille * 0.36)), Color.WHITE, false)
		c.add_child(tag)
		var t_tag := tag.get_minimum_size() * tag.scale
		tag.position = Vector2(-t_tag.x * 0.5, -t_lbl.y * 0.5 - t_tag.y + 6.0)
	c._process(0.0)   # posé dès cette frame, pas en (0, 0) le temps d'un tick

	match style:
		Style.CRIT:
			_animer_crit(c, lbl)
		Style.COUP:
			_animer_pop(c, 0.40, 1.22, randf_range(-18.0, 18.0), 38.0, 0.95)
		Style.SOIN:
			_animer_pop(c, 0.50, 1.15, 0.0, 44.0, 1.10)
		_:
			_animer_pop(c, 0.70, 1.06, 0.0, 26.0, 1.05)

func _depiler(cle: Variant) -> void:
	var n := int(_empilement.get(cle, 0)) - 1
	if n <= 0:
		_empilement.erase(cle)
	else:
		_empilement[cle] = n

# Apparition élastique → courte tenue → montée + fondu + léger rétrécissement.
func _animer_pop(c: Chiffre, depart: float, depassement: float, derive_x: float,
		montee: float, vie: float) -> void:
	c.scale = Vector2.ONE * depart
	c.modulate.a = 0.0
	var tw_e := c.create_tween()
	tw_e.tween_property(c, "scale", Vector2.ONE * depassement, 0.09) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_e.tween_property(c, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.06)
	c.create_tween().tween_property(c, "decalage", c.decalage + Vector2(derive_x, -montee), vie) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_animer_sortie(c, vie, 0.30)

# Critique : écrasé depuis très grand (tampon), rebond, chauffé à blanc, tremblé,
# TENU en place plus longtemps qu'un coup normal, puis s'envole.
func _animer_crit(c: Chiffre, lbl: Label) -> void:
	const VIE := 1.45
	c.scale = Vector2.ONE * 2.6
	c.modulate.a = 0.0
	c.rotation = randf_range(0.07, 0.14) * (1.0 if randf() < 0.5 else -1.0)
	var tw_e := c.create_tween()
	tw_e.tween_property(c, "scale", Vector2.ONE * 0.90, 0.11) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_e.tween_property(c, "scale", Vector2.ONE * 1.10, 0.07) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_e.tween_property(c, "scale", Vector2.ONE, 0.09) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.05)
	c.create_tween().tween_property(c, "rotation", 0.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Chauffé à blanc à l'impact du tampon, puis retour à sa couleur.
	lbl.modulate = Color(2.6, 2.6, 2.6)
	c.create_tween().tween_property(lbl, "modulate", Color.WHITE, 0.26).set_delay(0.09)
	var tw_t := c.create_tween()
	tw_t.tween_interval(0.11)
	tw_t.tween_property(c, "tremble", 6.0, 0.0)
	tw_t.tween_property(c, "tremble", 0.0, 0.24)
	var tw_m := c.create_tween()
	tw_m.tween_interval(0.70)
	tw_m.tween_property(c, "decalage", c.decalage + Vector2(0.0, -52.0), VIE - 0.70) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_animer_sortie(c, VIE, 0.36)

func _animer_sortie(c: Chiffre, vie: float, fondu: float) -> void:
	var tw := c.create_tween()
	tw.tween_interval(vie - fondu)
	tw.tween_property(c, "modulate:a", 0.0, fondu).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(c, "scale", Vector2.ONE * 0.80, fondu) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.queue_free)

# ⚠ Un texte n'est JAMAIS rastérisé à sa taille d'affichage : chaque couple
# (taille de police, épaisseur de contour) inédit oblige le moteur à dessiner
# un nouveau jeu de glyphes, et la taille d'un chiffre varie avec les dégâts —
# soit un à-coup à presque chaque coup. Deux gabarits FIXES seulement (gros
# chiffres / petits textes), préchauffés au montage (`_prechauffer_glyphes`),
# puis mis à l'échelle par le nœud.
func _label(texte: String, taille: int, couleur: Color, gros: bool) -> Label:
	var raster := RASTER_GROS if gros else RASTER_PETIT
	var contour := CONTOUR_GROS if gros else CONTOUR_PETIT
	var l := Label.new()
	l.text = texte
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.scale = Vector2.ONE * (float(taille) / float(raster))
	l.add_theme_font_override("font", _police_grasse())
	l.add_theme_font_size_override("font_size", raster)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_constant_override("outline_size", contour)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 0.92))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 5 if gros else 3)
	l.add_theme_constant_override("shadow_outline_size", contour)
	return l

# Même famille technique que le reste du combat (`ExpeStyle.police_mono`), en
# GRAS : un chiffre de dégâts doit se lire d'un coup d'œil par-dessus le décor.
static func _police_grasse() -> SystemFont:
	if _police == null:
		_police = SystemFont.new()
		_police.font_names = (ExpeStyle.police_mono() as SystemFont).font_names
		_police.font_weight = 800
	return _police

# ─── Gerbe d'impact ──────────────────────────────────────────
# `pos` : espace de cette couche. `sens` : +1 = coup porté vers la droite.
func eclat(pos: Vector2, couleur: Color, sens: float, fort: bool) -> void:
	if not is_inside_tree():
		return
	var e := Eclat.new()
	e.couleur = couleur
	e.fort = fort
	e.lueur = _texture_lueur()
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.position = pos
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	e.material = mat
	# Étincelles en éventail dans le sens du coup, quelques-unes à rebours.
	var axe := 0.0 if sens >= 0.0 else PI
	var nb := 13 if fort else 7
	for i in nb:
		var angle := axe + randf_range(-1.15, 1.15)
		if i % 4 == 3:
			angle += PI
		var longueur := randf_range(36.0, 78.0) * (1.6 if fort else 1.0)
		e.rayons.append(Vector3(angle, longueur, randf_range(8.0, 20.0)))
	add_child(e)
	move_child(e, 0)   # sous les chiffres
	var tw := e.create_tween()
	tw.tween_property(e, "t", 1.0, 0.34 if fort else 0.24)
	tw.tween_callback(e.queue_free)

static func _texture_lueur() -> GradientTexture2D:
	if _lueur == null:
		_lueur = UIHelpers.radial_glow_tex(128, [0.0, 0.35, 1.0], [1.0, 0.40, 0.0])
	return _lueur

# ─── Voile plein écran ───────────────────────────────────────
func flash(couleur: Color, alpha: float, duree := 0.18) -> void:
	if not is_inside_tree():
		return
	var r := ColorRect.new()
	r.color = Color(couleur.r, couleur.g, couleur.b, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	move_child(r, 0)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, duree).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)

# ─── Secousse caméra ─────────────────────────────────────────
# `noeud` : l'enveloppe à secouer (plein cadre). `amplitude` en px au plus
# fort, amortie au carré sur `duree`. Une secousse plus faible n'écrase jamais
# une plus forte encore en cours.
func secouer(noeud: Control, amplitude: float, duree: float, sens := 1.0) -> void:
	if noeud == null or amplitude <= 0.0 or duree <= 0.0:
		return
	if _sec_noeud != null and _sec_t < _sec_duree:
		var k := 1.0 - _sec_t / _sec_duree
		if _sec_amp * k * k > amplitude:
			return
	_sec_noeud = noeud
	_sec_amp = amplitude
	_sec_duree = duree
	_sec_t = 0.0
	_sec_sens = 1.0 if sens >= 0.0 else -1.0
	_sec_phase = randf_range(0.0, TAU)

func _fin_secousse() -> void:
	if is_instance_valid(_sec_noeud):
		_sec_noeud.position = Vector2.ZERO
		_sec_noeud.scale = Vector2.ONE
	_sec_noeud = null

# ─── Préchauffe des glyphes ──────────────────────────────────
# Les glyphes (et leur contour) ne sont dessinés qu'à leur PREMIER affichage :
# sans ceci, c'est le premier coup du combat qui payait. Deux étiquettes
# quasi invisibles (alpha sous le perceptible, mais au-dessus du seuil où le
# moteur saute le dessin) vivent quelques images à l'ouverture, puis s'en vont.
func _prechauffer_glyphes() -> void:
	var temoins: Array[Label] = [
		_label(GLYPHES_GROS, RASTER_GROS, Color.WHITE, true),
		_label(GLYPHES_PETIT, RASTER_PETIT, Color.WHITE, false),
	]
	for l in temoins:
		l.modulate.a = 0.01
		add_child(l)
	for i in 3:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	for l in temoins:
		l.queue_free()
