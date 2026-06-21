# ============================================================
# ForgeTreeData — Arbre d'amélioration d'UN équipement (Chantier 5).
#
# Donnée pure (un .tres dans data/forge_trees/). L'état joueur (points de Forge,
# nœuds acquis) vit dans GameData.player.forge, PAS ici.
#
# `nodes` : Array de Dictionary. Schéma d'un nœud :
#   id      : String  — unique dans l'arbre
#   type    : "mineur" | "notable" | "keystone"
#   strate  : int     — 1..5 (VS : 1-2). Gate : strate accessible si l'équipement
#                       a atteint le palier correspondant (strate = palier).
#   stat    : String  — canal de stat du % de base ("atk","def","crit","atb",
#                       "hp","regen","drop"). "" = pas de % de base (ex. keystone,
#                       ou nœud purement conditionnel comme Élan).
#   adj     : Array[String] — voisins (connexité non orientée). Un nœud n'est
#                       achetable que si un voisin est déjà acquis (racine ouverte).
#   root    : bool    — (optionnel) nœud ouvert dès l'activation de l'arbre (S1).
#   pos     : Vector2 — position pour le rendu spatial de l'arbre.
#   nom_fr/nom_en : String — nom affiché.
#   effect  : Dictionary — (optionnel, notables/keystones) effet nommé. `kind` :
#     "stat_pct"   {stat, value}          — ajoute value au canal `stat` (bonus annexe)
#     "per_tier"   {stat, value}          — ajoute value × palier de l'équipement à `stat`
#     "crit_mult"  {value}                — + au multiplicateur de critique
#     "gauge_start"{value}                — jauge ATB de départ (toute expédition)
#     "def_ignore" {value}                — le héros ignore value × DEF ennemie
#     "cond_atk_hp_above" {hp_frac}       — +% ATK (barème notable) si PV héros > hp_frac
#     "residual"   {damage_pct,duration,chance} — dégâts résiduels sur l'ennemi (rail poison passif)
#     "endurcissement_counter" {value}    — dégâts héros ×(1+value) sous Endurcissement
#     "ambush_negate"                     — annule l'embuscade subie (Forêt)
#     "poison_stack_reduction" {value}    — −N stacks de venin de biome subis
# Le % de BASE d'un nœud (mineur/notable) vient de Balance.forge_node_stat_pct
# (par strate/type) — JAMAIS codé en dur par nœud (cf. Forge §10.2).
# ============================================================
class_name ForgeTreeData
extends Resource

@export var id:           String = ""
@export var equipment_id: String = ""
@export var nodes:        Array  = []
