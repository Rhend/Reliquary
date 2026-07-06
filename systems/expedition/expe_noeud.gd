# ============================================================
# ExpeNoeud — Un nœud de la carte d'expédition (état runtime pur).
#
# Brouillard de guerre (pilier « non découvert = absent ») :
#   decouvert = false → le nœud n'existe PAS à l'affichage (ni grisé, ni
#   silhouetté). Exceptions à l'init : l'Entrée (position du joueur) et la
#   Fin d'étage (visible d'emblée, position ET type).
# Un nœud résolu devient INERTE : traversable, ne se re-déclenche jamais.
# ============================================================
class_name ExpeNoeud
extends RefCounted

var id := 0
var type: Enums.TypeNoeud = Enums.TypeNoeud.COMBAT
var pos := Vector2.ZERO               # position 2D abstraite (layout de l'étage)
var voisins: Array[int] = []          # ids des nœuds adjacents (arêtes)

var decouvert := false                # révélé par adjacence (ou d'emblée : Entrée/Fin)
var resolu := false                   # entré une fois → inerte
# Contenu réel d'un nœud « ? » : -1 tant que le joueur n'y est pas ENTRÉ
# (le tirage n'a pas encore eu lieu — rien à révéler, même en debug).
var contenu_mystere := -1             # Enums.ContenuMystere une fois tiré
