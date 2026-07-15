# ============================================================
# ProgressionHerosData — Courbe de NIVEAU du héros + gains par niveau
# (Rework Combat, chantier 6 : économie de récompense).
# TOUTES les valeurs sont PROVISOIRES, à calibrer.
#
# Courbe (arbitrage 06/07/2026, système RPG classique) :
#   XP TOTALE CUMULÉE requise pour atteindre le niveau n =
#     arrondi(xp_niveau_base × n ^ xp_niveau_exposant)
#   Niveau plancher : 1 (un héros à 0 XP est niveau 1). L'XP ne se dépense
#   pas et ne se perd jamais (règle projet : cumul au-delà des seuils).
#
# Gains par niveau : bonus PLATS aux stats nues, cumulés en fractions
# ((niveau − 1) × gain), injectés dans l'agrégation du pont héros
# (CtbPont.combattant_depuis_heros) à la même position que les autres bonus
# plats — AVANT les % (empilement additif universel inchangé).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ProgressionHerosData" ...]
# ============================================================
class_name ProgressionHerosData
extends Resource

@export var xp_niveau_base := 100.0      # provisoire, à calibrer
@export var xp_niveau_exposant := 1.5    # provisoire, à calibrer

# Bonus plats par niveau AU-DELÀ du 1er (provisoire, à calibrer).
@export var gain_pv_max_par_niveau := 2.0
@export var gain_atk_par_niveau := 1.0
@export var gain_def_par_niveau := 0.5
@export var gain_vit_par_niveau := 0.5

# XP totale cumulée requise pour ATTEINDRE le niveau n (n ≥ 2 ; 1 = plancher).
func seuil_xp(niveau: int) -> float:
	return roundf(xp_niveau_base * pow(float(niveau), xp_niveau_exposant))

# Niveau atteint pour une XP totale cumulée (plancher 1, jamais décroissant).
func niveau_pour_xp(xp_totale: float) -> int:
	var n := 1
	while seuil_xp(n + 1) <= xp_totale:
		n += 1
	return n

# Bonus plats cumulés au niveau donné : {hp, atk, def, vit} (fractions
# conservées — l'arrondi éventuel appartient à l'agrégation/affichage).
func bonus_plats(niveau: int) -> Dictionary:
	var paliers := float(maxi(niveau, 1) - 1)
	return {
		"hp":  paliers * gain_pv_max_par_niveau,
		"atk": paliers * gain_atk_par_niveau,
		"def": paliers * gain_def_par_niveau,
		"vit": paliers * gain_vit_par_niveau,
	}
