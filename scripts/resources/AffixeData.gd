# ============================================================
# AffixeData — Affixe DE RUN d'expédition (Rework Combat, chantier 7).
# Définitions actées 06/07/2026 : Bénédiction = affixe POSITIF pour la durée
# de la run ; Piège = affixe NÉGATIF pour la durée de la run. Purge
# systématique en fin d'expédition (toutes sorties) — rien ne persiste.
#
# Un affixe = un ensemble de bonus % de stats (fractions, négatives pour un
# malus). Il s'ajoute au Σ bonus % du combattant JOUEUR à chaque création de
# combat (empilement additif universel — StatStacker) ; plusieurs affixes
# coexistent, y compris le même tiré deux fois (les % s'additionnent).
#
# Clés de `bonus` = noms de stats de CombattantCtbData :
#   pv_max, atk, def, vit (crit_* possibles, pool provisoire sans).
# TOUTES les valeurs sont PROVISOIRES, à calibrer ; noms libres à la
# relecture DA.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="AffixeData" ...]
# ============================================================
class_name AffixeData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""

# true = Bénédiction (pool positif) ; false = Piège (pool négatif).
@export var est_positif := true

# stat ("pv_max"/"atk"/"def"/"vit"…) → fraction (+0.15 = +15 %, −0.10 = −10 %).
@export var bonus: Dictionary = {}

const _NOMS_STATS := {"pv_max": "PV max", "atk": "ATK", "def": "DEF", "vit": "VIT",
		"crit_chance": "crit", "crit_multiplier": "crit ×"}

# Résumé lisible des bonus (« +15 % ATK », « −10 % DEF ») — journal/popup.
func resume() -> String:
	var parts: PackedStringArray = []
	for stat: String in bonus:
		var pct := float(bonus[stat]) * 100.0
		parts.append("%s%.0f %% %s" % ["+" if pct >= 0.0 else "−", absf(pct),
				_NOMS_STATS.get(stat, stat)])
	return ", ".join(parts)

func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
