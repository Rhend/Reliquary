# ============================================================
# SilhouettesData — hauteurs de CORPS mesurées au pixel, par squelette Spine.
#
# POURQUOI. L'échelle d'un personnage se déduit de sa hauteur native. La seule
# mesure disponible au runtime, `get_bounds`, donne l'ENCOMBREMENT de la pose :
# elle compte l'épée que Relic tient au-dessus de la tête, et — mesuré le
# 26/08/2026 — surestime le corps du FlameBot d'environ 37 % (276 unités pour
# ~201 réellement visibles). Deux personnages calés sur leurs bornes ne sont
# donc PAS à la même taille à l'écran, ce qui est tout ce qu'on cherche.
#
# La seule mesure fidèle est le nombre de pixels effectivement dessinés. Elle
# exige un rendu, donc une fenêtre — impossible sous `--headless`, où tournent
# les tests et la CI. On la BAKE : `tools/mesurer_silhouettes.gd` rend chaque
# personnage une fois et écrit le résultat ici ; le runtime ne fait plus que
# lire un nombre. Même patron que l'instantané de la holomap
# (`data/holomap/carte_holomap.snapshot`) : un outil d'autoring, une donnée
# versionnée, zéro coût au démarrage.
#
# ⚠ APRÈS CHAQUE LIVRAISON D'ASSET, RE-BAKER :
#     godot --path . res://tools/mesurer_silhouettes.tscn
# (sans --headless : l'outil a besoin de rendre). TestShowRoom échoue si une
# mesure ne correspond plus à son squelette.
#
# ANTI-PÉRIMÉ. Chaque mesure retient aussi les BORNES du squelette au moment
# où elle a été prise. Au chargement, SpriteSpinePersonnage compare les bornes
# courantes : si elles ont bougé, l'asset a changé sans re-bake — la mesure est
# ignorée (retour aux bornes) et un warning le dit. Un `.tres` périmé ne peut
# donc pas rapetisser un personnage en silence, ce qui est exactement le mode
# de panne qui a coûté la livraison « cheveux » du 25/08/2026.
#
# Header .tres requis :
#   [gd_resource type="Resource" script_class="SilhouettesData" ...]
# ============================================================
class_name SilhouettesData
extends Resource

# Clé = chemin du .skel (identifie le squelette, pas le personnage : les 6
# costumes de Relic partagent un squelette, donc une échelle — c'est déjà la
# règle que TestShowRoom vérifie).
#   "res://…/Relic.skel": {"hauteur": 1962.4, "bornes": 2916.0}
#     • hauteur — corps SEUL, arme et VFX retirés, en unités Spine ;
#     • bornes  — get_bounds().size.y au moment de la mesure (anti-périmé).
@export var mesures: Dictionary = {}

const CHEMIN := "res://data/personnages/silhouettes.tres"

# Tolérance sur les bornes avant de déclarer la mesure périmée. Les bornes
# dépendent de la pose, qui respire avec l'Idle : on ne compare pas au pixel.
const ECART_BORNES_MAX := 0.02   # 2 %

static func charger() -> SilhouettesData:
	if not ResourceLoader.exists(CHEMIN):
		return null
	return load(CHEMIN) as SilhouettesData

# Hauteur de corps bakée pour ce squelette, ou 0.0 s'il n'y en a pas / si elle
# est périmée. `bornes_courantes` <= 0 saute le contrôle d'obsolescence (appelant
# qui n'a pas la mesure sous la main).
func hauteur(chemin_skel: String, bornes_courantes: float = 0.0) -> float:
	var m := mesures.get(chemin_skel, {}) as Dictionary
	var haut := float(m.get("hauteur", 0.0))
	if haut <= 0.0:
		return 0.0
	var ref := float(m.get("bornes", 0.0))
	if bornes_courantes > 0.0 and ref > 0.0 \
			and absf(bornes_courantes - ref) > ref * ECART_BORNES_MAX:
		push_warning(("SilhouettesData : mesure PÉRIMÉE pour %s (bornes %.0f, "
				+ "bakées à %.0f) — re-baker avec tools/mesurer_silhouettes.tscn")
				% [chemin_skel, bornes_courantes, ref])
		return 0.0
	return haut
