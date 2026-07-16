# ============================================================
# AlarmeConfigData — Effets du système d'ALARME (Rework Combat, chantier 11).
#
# Table data-driven par nombre de slots remplis (0-6, un slot par Lieutenant
# vaincu — premier kill seulement) : bonus % de stats appliqués à TOUS les
# combattants ennemis à leur création (toutes expéditions, assauts compris)
# + affixes « permanents » (réutilisation d'AffixeData — permanents = tant
# que le palier d'Alarme est atteint, pas liés à une run).
#
# Application : ExpeRun à la création des combattants ennemis (même endroit
# que le pont bestiaire) — jamais dans le moteur CTB. Logique : Alarme.gd.
# TOUTES les valeurs sont PROVISOIRES, à calibrer.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="AlarmeConfigData" ...]
# ============================================================
class_name AlarmeConfigData
extends Resource

# stat ("pv_max"/"atk"/…) → fraction PAR SLOT rempli (cumul additif :
# 3 slots × 0.05 = +15 %, empilé avec le reste via StatStacker).
@export var pct_par_slot: Dictionary = {}

# niveau d'Alarme (int) → AffixeData ajouté à TOUS les ennemis à partir de ce
# niveau. CUMULATIF : au niveau 5, les affixes des paliers 4 ET 5 s'appliquent.
@export var affixes_par_palier: Dictionary = {}
