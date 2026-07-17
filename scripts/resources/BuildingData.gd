# ============================================================
# BuildingData — Un bâtiment de quartier du Village (Chantier 4).
#
# Donnée pure (un .tres dans data/batiments/). Tient :
#   • les bonus passifs débloqués palier par palier (bonus_par_palier) ;
#   • l'assignation de biome (principal + additionnels) — INERTE depuis le
#     chantier 12 : les coûts sont en Euren + Modules (couts_batiments.tres),
#     plus jamais en ressources de biome. Champs conservés en donnée (une
#     future thématisation pourra s'en resservir), plus lus par les coûts.
#
# Paliers : Délabré(-1) → T0 → T1 → T2 → T3 → T4 → T5. L'état (palier courant
# par bâtiment) vit dans GameData.village, PAS ici.
#
# bonus_par_palier : Dictionary  tier(int) → Array de { "channel": String,
# "value": float }. Encodage INCRÉMENTAL : un bâtiment au palier T confère la
# somme (ou le max / OU logique selon le canal, cf. VillageBuildings) des effets
# des paliers 0..T. Tous les bonus % passent par l'agrégateur additif
# (StatStacker) — cf. VillageBuildings.refresh_bonuses.
# ============================================================
class_name BuildingData
extends Resource

@export var id:                String       = ""
@export var quartier:          String       = ""   # "hero" | "adventure" | "forge"
@export var nom_affichage_fr:  String       = ""
@export var nom_affichage_en:  String       = ""
@export var lore_fr:           String       = ""
@export var lore_en:           String       = ""
# Assignation de biome — INERTE depuis le chantier 12 (cf. en-tête).
@export var biome_principal_id: String      = ""
@export var biomes_additionnels: Array[String] = []
# tier(int) → Array de { channel, value }. Incrémental (cf. en-tête).
@export var bonus_par_palier:  Dictionary   = {}
# Gelé en VS (Couturier) : non reconstructible, aucun bonus actif.
@export var gele:              bool         = false
