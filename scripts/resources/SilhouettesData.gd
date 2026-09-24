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

# Clé = chemin du .skel, éventuellement suffixé « #g<n> » pour un GENRE (voir
# `cle`) — un squelette partagé par plusieurs corps visuellement différents
# (« Relic Femme », 23/09/2026 : skin Woman_* sur le même Relic.skel que
# Men_*) a besoin d'UNE mesure par corps, pas une seule pour tous. Les 6
# NIVEAUX d'équipement d'un même genre, eux, continuent de partager une seule
# mesure (même silhouette globale) — c'est déjà la règle que TestShowRoom
# vérifie.
#   "res://…/Relic.skel":     {"hauteur": 1962.4, "bornes": 2916.0}   # genre 0 (défaut)
#   "res://…/Relic.skel#g1":  {"hauteur": …,      "bornes": …}        # genre 1 (Féminin)
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

# Clé de `mesures` pour un squelette + un genre — SOURCE UNIQUE du format,
# utilisée aussi bien par le bake (tools/mesurer_silhouettes.gd) que par la
# lecture runtime (`hauteur`), pour qu'ils ne puissent jamais diverger.
# genre 0 (défaut) garde la clé nue : un personnage sans second genre n'a donc
# rien de changé dans son fichier baké.
static func cle(chemin_skel: String, genre: int = 0) -> String:
	return chemin_skel if genre <= 0 else "%s#g%d" % [chemin_skel, genre]

# Hauteur de corps bakée pour ce squelette + ce genre, ou 0.0 s'il n'y en a
# pas / si elle est périmée. `bornes_courantes` <= 0 saute le contrôle
# d'obsolescence (appelant qui n'a pas la mesure sous la main). Un genre sans
# mesure bakée (bake pas encore relancé après une livraison) rend 0.0 — même
# repli propre qu'un squelette jamais baké, pas d'erreur.
func hauteur(chemin_skel: String, bornes_courantes: float = 0.0, genre: int = 0) -> float:
	var m := mesures.get(cle(chemin_skel, genre), {}) as Dictionary
	var haut := float(m.get("hauteur", 0.0))
	if haut <= 0.0:
		return 0.0
	var ref := float(m.get("bornes", 0.0))
	if bornes_courantes > 0.0 and ref > 0.0 \
			and absf(bornes_courantes - ref) > ref * ECART_BORNES_MAX:
		push_warning(("SilhouettesData : mesure PÉRIMÉE pour %s (bornes %.0f, "
				+ "bakées à %.0f) — re-baker avec tools/mesurer_silhouettes.tscn")
				% [cle(chemin_skel, genre), bornes_courantes, ref])
		return 0.0
	return haut
