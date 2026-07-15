# ============================================================
# ConsommableData — Consommable DE RUN d'expédition (Rework Combat,
# chantier 7). Définition actée 06/07/2026 : Coffre = consommables
# utilisables durant la run — acquis en run, PERDUS en fin de run
# (extraction comprise : « de run », pas de stock permanent).
#
# Usage : EN COMBAT uniquement (ce chantier) — l'action OBJET du moteur CTB
# (consomme l'activation). Effets typés :
#   DEGATS_CIBLE     — dégâts à un ennemi ciblé :
#                      valeur × (1 + Σ bonus % ATK du porteur), IGNORE la DEF
#   SOIN_PCT_PV_MAX  — rend (valeur × pv_max finale) PV au porteur, clampé
# TOUTES les valeurs sont PROVISOIRES, à calibrer ; noms libres (DA).
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="ConsommableData" ...]
# ============================================================
class_name ConsommableData
extends Resource

@export var id: String = ""
@export var nom_affichage_fr: String = ""
@export var nom_affichage_en: String = ""

@export var effet: Enums.EffetConsommable = Enums.EffetConsommable.DEGATS_CIBLE

# DEGATS_CIBLE : dégâts de base (50 = 50 dégâts avant scaling ATK %).
# SOIN_PCT_PV_MAX : fraction des PV max rendus (0.30 = 30 %).
@export var valeur := 0.0

# L'effet demande-t-il une CIBLE ennemie ? (choix de cible dans l'UI)
func cible_requise() -> bool:
	return effet == Enums.EffetConsommable.DEGATS_CIBLE

func nom_journal() -> String:
	return nom_affichage_fr if nom_affichage_fr != "" else id
