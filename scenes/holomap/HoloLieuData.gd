# ============================================================
# HoloLieuData — Données placeholder d'un lieu d'expédition sur la carte holo.
#
# Un lieu = un point marqué « lieu » de la ville. Ressource éditable en .tres
# (en-tête : type="Resource" script_class="HoloLieuData").
#
# Règle stricte du projet : seuls les lieux `decouvert == true` sont instanciés
# et visibles. Un lieu non découvert est ABSENT — aucun marqueur grisé.
#
# `tier` alimente UIColors.tier_color + le nom de palier (jamais de numéro de
# tier affiché). Le nom s'affiche TOUJOURS via `nom_affichage_fr` (jamais un
# champ `name` résiduel). `lore_fr` = texte d'ambiance du tooltip.
# ============================================================
class_name HoloLieuData
extends Resource

@export var id: String = ""                    # identifiant unique (porté par le signal)
@export var nom_affichage_fr: String = ""      # libellé affiché (jamais un champ `name`)
@export var tier: int = 0                      # palier (0=Commun … 5=Unique) → couleur + nom de palier
@export var lore_fr: String = ""               # texte d'ambiance (tooltip)
@export var cellule: Vector2i = Vector2i.ZERO  # cellule d'origine (coin) du bâtiment-lieu
@export var emprise: Vector2i = Vector2i(2, 2) # emprise au sol N×M (cellules)
# Cellules exactes de la zone (délimitée par la bordure de tier sur la grille).
# Posées au runtime depuis la feuille Lieux ; servent à tracer le CONTOUR de
# périmètre réel du lieu (≠ simple boîte d'emprise). Vide → contour = bbox d'emprise.
var cells: Array[Vector2i] = []
@export var etages: int = 5                    # hauteur en unités-maison
# true → lieu SANS bâtiment : pas de boîte (ni faces), juste pin + anneau +
# zone cliquable. Le décor sous l'emprise (ex. parc) EST le corps du lieu.
@export var sans_batiment: bool = false
@export var decouvert: bool = true             # false → totalement absent de la carte
