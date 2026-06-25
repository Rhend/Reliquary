# ============================================================
# HoloGabarit — Gabarit de bâtiment de remplissage (tissu urbain).
#
# Ressource éditable en .tres (en-tête : type="Resource"
# script_class="HoloGabarit"). Décrit une emprise au sol (cellules), une
# hauteur (en unités-maison / étages) et le mode de rendu : « creux » = contour
# extérieur seul (12 arêtes, ex. décharge 5×5 vide), sinon subdivision légère
# par étages. `poids` pondère le tirage aléatoire.
# ============================================================
class_name HoloGabarit
extends Resource

@export var nom: String = ""
@export var emprise: Vector2i = Vector2i(1, 1)   # N×M cellules
@export var etages: int = 1                       # hauteur en unités-maison
@export var creux: bool = false                   # true = contour seul (pas de subdivision)
@export var poids: float = 1.0                    # pondération de tirage
