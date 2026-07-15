# ============================================================
# CtbCombattant — État RUNTIME d'un combattant dans la file CTB.
#
# Référence sa ressource de stats nues (CombattantCtbData) sans dupliquer
# ses champs : seul l'état de combat vit ici (PV courants, horloge, bonus %,
# stacks de statuts). Les stats finales se calculent à la demande via
# StatStacker : stat_finale = stat_nue × (1 + Σ bonus%), cumul additif,
# toutes sources — un buff VIT posé en cours de combat agit donc dès le
# réarmement d'horloge suivant.
# ============================================================
class_name CtbCombattant
extends RefCounted

var data: CombattantCtbData          # stats nues (.tres) — JAMAIS dupliquées ici
var camp: Enums.CampCtb = Enums.CampCtb.ADVERSE
var ordre := 0                       # rang d'insertion DANS son camp (départage d'égalité)

var pv := 0.0                        # PV courants (initialisés à pv_max finale au démarrage)
var horloge := 0.0                   # prochaine_action (compteur logique CTB)

# Bonus % par stat : nom de stat → Array de fractions (0.16 = +16 %).
# Ex. bonus_pct["vit"] = [0.5] → VIT finale ×1.5 dès le prochain réarmement.
var bonus_pct: Dictionary = {}

# Stacks de statuts actifs : { "statut": StatutCtbData, "degats_par_tick": float
# (figés à la pose : % ATK finale du poseur), "restant": int (activations) }.
# Ordre de la liste = ordre de pose (le plus ancien en tête).
var statuts: Array = []

# Garde (action DEFENDRE, chantier 5) : dégâts d'ATTAQUE subis réduits
# (ConfigCtbData.defendre_reduction_degats) jusqu'à la PROCHAINE activation de
# ce combattant — le moteur baisse la garde à l'ouverture de l'activation.
# État LISIBLE par l'UI (marqueur sur la carte du combattant).
var en_defense := false

func _init(d: CombattantCtbData, c: Enums.CampCtb, o: int) -> void:
	data = d
	camp = c
	ordre = o
	pv = stat_finale("pv_max")

# Stat finale d'une stat nue de la ressource, après empilement additif des
# bonus % (StatStacker). Noms valides : pv_max, atk, def, vit, crit_chance,
# crit_multiplier (les champs exportés de CombattantCtbData).
func stat_finale(nom: String) -> float:
	return StatStacker.final_stat(float(data.get(nom)), bonus_pct.get(nom, []), nom)

# Ajoute un bonus % (fraction) sur une stat — cumul additif avec l'existant.
func ajouter_bonus_pct(nom: String, fraction: float) -> void:
	if not bonus_pct.has(nom):
		bonus_pct[nom] = []
	bonus_pct[nom].append(fraction)

func est_vivant() -> bool:
	return pv > 0.0

func est_joueur() -> bool:
	return camp == Enums.CampCtb.JOUEUR

func nom_journal() -> String:
	return data.nom_journal()
