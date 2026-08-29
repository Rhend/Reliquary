# ============================================================
# FactorySoudureVfx — gerbe d'étincelles de soudure du décor Usine (29/08/2026).
#
# Purement procédural (`_draw()`, même parti pris que NeonRunners : pas de
# sprite-sheet à faire livrer et corriger à chaque itération) : un flash bref
# au contact, puis une poignée de traits qui giclent dans un éventail vers le
# haut et retombent sous la gravité, comme de vraies étincelles de soudure à
# l'arc — pas une pluie omnidirectionnelle de feu d'artifice.
#
# Se pose en ENFANT du sprite du bras (voir CombatDecorFactory._declencher_
# etincelles) : la position locale demandée est donc en PIXELS DE L'IMAGE du
# bras, et le nœud hérite gratuitement de la descente du bras, du zoom-duel et
# de la brume — même raisonnement de parentage que NeonRunners.
# ============================================================
class_name FactorySoudureVfx
extends Node2D

const MASK_SHADER := "res://scenes/combat_ctb/raster_split_mask_additif.gdshader"

const N_ETINCELLES := 14
const VITESSE_MIN := 60.0
const VITESSE_MAX := 220.0
const GRAVITE := 340.0
const EPAISSEUR := 2.0
const LONGUEUR_TRAIT := 6.0
const FLASH_RAYON := 10.0
const FLASH_DUREE := 0.15

var _duree := 1.0
var _t := 0.0
var _etincelles: Array = []   # {dir, vitesse, decalage}

# `split_tilt` : même bande VS que le reste du décor Usine, pour rester du
# bon côté de l'écran si jamais un contact tombait près de la diagonale.
static func declencher(parent: Node2D, position_locale: Vector2, duree: float,
		split_tilt: float) -> FactorySoudureVfx:
	var vfx := FactorySoudureVfx.new()
	vfx.position = position_locale
	vfx._duree = maxf(duree, 0.05)
	var mat := ShaderMaterial.new()
	mat.shader = load(MASK_SHADER)
	mat.set_shader_parameter("split_tilt", split_tilt)
	vfx.material = mat
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in N_ETINCELLES:
		# Éventail vers le HAUT (angles autour de -90°) : une soudure gicle,
		# elle ne pleut pas dans toutes les directions.
		var angle := rng.randf_range(-PI * 0.85, -PI * 0.15)
		vfx._etincelles.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"vitesse": rng.randf_range(VITESSE_MIN, VITESSE_MAX),
			# Étalement du déclenchement : toutes les étincelles ne jaillissent
			# pas à la même milliseconde, sinon la gerbe fait un pouls unique.
			"decalage": rng.randf() * vfx._duree * 0.3,
		})
	parent.add_child(vfx)
	return vfx

func _process(delta: float) -> void:
	_t += delta
	if _t >= _duree:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var flash := clampf(1.0 - _t / FLASH_DUREE, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, FLASH_RAYON * (0.4 + 0.6 * flash),
				Color(1.0, 0.95, 0.7, 0.8 * flash))
	for e in _etincelles:
		var vie := _t - float(e["decalage"])
		var duree_vie := _duree - float(e["decalage"])
		if vie <= 0.0 or duree_vie <= 0.0:
			continue
		var k := clampf(vie / duree_vie, 0.0, 1.0)
		var dir: Vector2 = e["dir"]
		var vitesse: float = e["vitesse"]
		# Trajectoire balistique : vitesse initiale + chute sous la gravité.
		var p := dir * vitesse * vie + Vector2.DOWN * GRAVITE * vie * vie * 0.5
		# Refroidissement : jaune-blanc vif au départ, rouge braise en fin de vie.
		var couleur := Color(1.0, 0.85, 0.3).lerp(Color(0.7, 0.15, 0.05), k)
		draw_line(p - dir * LONGUEUR_TRAIT, p,
				Color(couleur.r, couleur.g, couleur.b, 1.0 - k), EPAISSEUR, true)
