# ============================================================
# ExpeCarteConfigData — Configuration de GÉNÉRATION de la carte d'expédition
# (Rework Combat, chantier 2). Toutes les valeurs sont PROVISOIRES, à calibrer.
#
# Choix de structure (documenté au recap) : UNE config GLOBALE unique
# (data/expedition/config_carte.tres) — pas de variante par étage ni par
# palier pour l'instant ; le palier de profondeur est un simple multiplicateur
# de difficulté porté par PalierProfondeurData, qui CIRCULE dans les signaux
# sans effet réel tant que les nœuds sont des stubs.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ExpeCarteConfigData" ...]
# ============================================================
class_name ExpeCarteConfigData
extends Resource

# Nombre de nœuds d'un étage : N ∈ [noeuds_min ; noeuds_max] (Entrée et Fin
# d'étage COMPRIS).
@export var noeuds_min := 8
@export var noeuds_max := 12

# Étages par expédition (Fin d'étage du dernier = fin d'expédition).
@export var nb_etages := 3

# Répartition des types des nœuds intérieurs (hors Entrée/Fin) — poids
# relatifs d'un tirage pondéré par nœud.
@export var poids_combat  := 0.5
@export var poids_mystere := 0.3
@export var poids_coffre  := 0.2

# Résolution du nœud « ? » à l'entrée du joueur — poids relatifs.
@export var mystere_poids_coffre           := 0.25
@export var mystere_poids_benediction      := 0.25
@export var mystere_poids_piege            := 0.25
@export var mystere_poids_attaque_surprise := 0.25

# ─── Disposition spatiale (génération 2D) ─────────────────────
# Distance minimale entre deux nœuds (unités abstraites de la carte 10×6).
@export var distance_min_noeuds := 1.5
# Probabilité d'essayer de retirer chaque arête de la triangulation (l'arête
# n'est retirée que si le graphe RESTE connexe) : 0 = graphe dense, 1 = épuré.
@export var elagage_aretes := 0.5
