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

# Réglages 29/08/2026 (retour Rhend) : ×2 étincelles, traits et flash plus
# intenses. Chaque étincelle a maintenant sa PROPRE vie COURTE (VIE_ETINCELLE_*,
# indépendante de la durée totale du VFX) et les déclenchements s'étalent sur
# QUASIMENT TOUTE la durée du contact (`ETALEMENT_FRACTION`) plutôt que sur les
# 30% initiaux : à `_duree` = 2 s, une seule bouffée qui s'éteint lentement
# aurait fait des traînées interminables et clairsemées vers la fin — une
# pluie CONTINUE de courtes étincelles pendant toute la soudure lit mieux.
#
# ⚠ RE-CALIBRÉ le 30/08/2026 (retour Rhend : « on dirait une petite soudure de
# rien du tout ») — deux causes cumulées, pas juste un manque de punch :
#  1. Ce VFX est posé en ENFANT du sprite Main (voir `declencher`), donc TOUTES
#     ses tailles en pixels sont dans le repère LOCAL de ce sprite, hérité de
#     son `scale` (~0.27 à l'écran, cadre écran / canevas natif 4770 px). Un
#     rayon de flash "15" ne fait donc que ~4 px ÉCRAN, quasi invisible.
#  2. Le nouveau canevas plein cadre de la découpe (30/08, voir CombatDecorFactory)
#     a fait BAISSER ce ratio d'échelle par rapport à l'ancien Bras à part
#     (canevas 3256 px, scale ~0.40) : à réglages inchangés, le VFX avait donc
#     RÉTRÉCI tout seul en plus d'être déjà petit.
# Les constantes spatiales (épaisseur/longueur/rayon/vitesse/gravité) sont
# donc portées à un niveau qui rend un ARC DE SOUDURE INDUSTRIELLE bien vu à
# l'écran (usine qui monte une armée de robots, pas un fer à souder de
# bricoleur) — vitesse et gravité montées ENSEMBLE pour garder la même forme
# de gerbe (juste plus grande/plus loin), pas juste plus lente ou plus haute.
#
# ⚠ FLOU signalé (30/08/2026, retour Rhend, une fois vu EN JEU — invisible
# dans `SHOT_MODE=factory_bras`, qui capture un SubViewport offscreen à
# 1280×720 SANS passer par l'étirement de fenêtre, voir ScreenshotTool.gd) :
# le projet est en `window/stretch/mode="canvas_items"`, donc la fenêtre
# réelle (`window/size/mode=4` = plein écran EXCLUSIF, très probablement
# > 1280×720) réétire ce rendu au filtrage BILINÉAIRE. Un détail fin — un
# trait de quelques pixels avec en plus SA PROPRE antialiasing (`draw_line`
# posait `antialiased=true`) — passe très mal ce ré-étirement : le double
# adoucissement (AA du trait + filtrage bilinéaire de la fenêtre) le rend
# flou, là où l'aplat du décor (grandes zones de couleur plate, bords francs
# mais peu nombreux) ne montre presque rien du même effet. Remède : traits
# SANS antialiasing propre (`draw_line(..., false)`, bords francs laissés au
# filtrage de fenêtre plutôt qu'ajoutés en double) et encore plus ÉPAIS —
# plus une forme est grande à l'écran, moins le flou du filtrage bilinéaire
# se voit PROPORTIONNELLEMENT à sa taille.
const N_ETINCELLES := 46
const VITESSE_MIN := 220.0
const VITESSE_MAX := 820.0
const GRAVITE := 1250.0
const EPAISSEUR := 20.0
const LONGUEUR_TRAIT := 36.0
const FLASH_RAYON := 62.0
const FLASH_DUREE := 0.22
const VIE_ETINCELLE_MIN := 0.32
const VIE_ETINCELLE_MAX := 0.55
const ETALEMENT_FRACTION := 0.8

var _duree := 1.0
var _t := 0.0
var _etincelles: Array = []   # {dir, vitesse, decalage, vie_max}

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
			"decalage": rng.randf() * vfx._duree * ETALEMENT_FRACTION,
			"vie_max": rng.randf_range(VIE_ETINCELLE_MIN, VIE_ETINCELLE_MAX),
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
		# Halo double : lueur orange large (additif, donc elle se contente de
		# chauffer les alentours) + cœur quasi blanc étroit par-dessus — un
		# simple disque orange à ce diamètre lisait comme une tache plate,
		# pas un arc de soudure aveuglant.
		draw_circle(Vector2.ZERO, FLASH_RAYON * 1.7 * (0.3 + 0.7 * flash),
				Color(1.0, 0.55, 0.15, 0.5 * flash), true, -1.0, false)
		draw_circle(Vector2.ZERO, FLASH_RAYON * (0.4 + 0.6 * flash),
				Color(1.0, 0.98, 0.9, 0.95 * flash), true, -1.0, false)
	for e in _etincelles:
		var vie := _t - float(e["decalage"])
		var vie_max: float = e["vie_max"]
		if vie <= 0.0 or vie >= vie_max:
			continue
		var k := vie / vie_max
		var dir: Vector2 = e["dir"]
		var vitesse: float = e["vitesse"]
		# Trajectoire balistique : vitesse initiale + chute sous la gravité.
		var p := dir * vitesse * vie + Vector2.DOWN * GRAVITE * vie * vie * 0.5
		# Refroidissement : jaune-blanc vif au départ, rouge braise en fin de vie.
		var couleur := Color(1.0, 0.85, 0.3).lerp(Color(0.7, 0.15, 0.05), k)
		draw_line(p - dir * LONGUEUR_TRAIT, p,
				Color(couleur.r, couleur.g, couleur.b, 1.0 - k), EPAISSEUR, false)
