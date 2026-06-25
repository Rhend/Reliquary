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
@export var cellule: Vector2i = Vector2i.ZERO  # cellule de grille du lieu
@export var decouvert: bool = true             # false → totalement absent de la carte
