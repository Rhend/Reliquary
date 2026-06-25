# ============================================================
# HoloLieuData — Données placeholder d'un lieu d'expédition sur la carte holo.
#
# Un lieu = un bâtiment marqué « lieu » de la ville. Ressource éditable en
# .tres (en-tête : type="Resource" script_class="HoloLieuData").
#
# Règle stricte du projet : seuls les lieux `decouvert == true` sont
# instanciés et visibles sur la carte. Un lieu non découvert est ABSENT —
# aucun marqueur grisé, aucun placeholder.
# ============================================================
class_name HoloLieuData
extends Resource

@export var id: String = ""               # identifiant unique (porté par le signal)
@export var nom: String = ""              # libellé affiché
@export var cellule: Vector2i = Vector2i.ZERO  # cellule de grille du bâtiment-lieu
@export var hauteur: float = 0.0          # hauteur d'extrusion en px ; 0 = aléatoire au build
@export var decouvert: bool = true        # false → totalement absent de la carte
