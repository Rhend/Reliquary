# ============================================================
# Balance.gd — Source de vérité UNIQUE de l'équilibrage du jeu.
#
# Toutes les constantes d'équilibrage globales (combat, XP,
# maîtrise, drops, zones, modificateurs de cycle…) sont
# regroupées ici pour pouvoir retoucher les chiffres et les
# règles à un seul endroit lors des refontes mathématiques.
#
# Classe utilitaire (class_name), PAS un autoload : les
# constantes se résolvent directement sur le type — y compris
# depuis les fonctions statiques (ex. CombatResolver). Même
# convention que UIHelpers.gd.
#
# Usage : Balance.CRIT_CHANCE, Balance.XP_THRESHOLDS, etc.
#
# Ce qui N'EST PAS ici (volontairement) :
#   • Tables d'événements par biome       → .tres des biomes
#   • Configs de passifs (bouclier/poison)→ .tres des passifs
#   • Cadence/timings & animations        → AdventureSystem / CombatPlayer
# ============================================================
class_name Balance

# ═══════════════════════════════════════════════════════════
#  Stats du héros par palier de Maîtrise [T0..T5]
#  Source de vérité (spec "Fondations du jeu").
#  T3-T5 extrapolés à ~×1.7/tier HP/ATK, ×2.0 DEF.
# ═══════════════════════════════════════════════════════════

const HERO_HP_PER_TIER:  Array[int] = [150, 230, 390, 650, 1085, 1815]
const HERO_ATK_PER_TIER: Array[int] = [20,  32,  55,  90,  150,  245]
const HERO_DEF_PER_TIER: Array[int] = [3,   5,   9,   16,  30,   55]
const HERO_VIT: int = 20  # constant à tous les paliers

# Palier de Maîtrise qu'un biome doit atteindre pour livrer son équipement
# (obtenu au palier Commun/T0). Progression : T0 découverte → T1 équipement
# → T2 mécanique forte du biome.
const EQUIPMENT_UNLOCK_BIOME_TIER: int = 1

# ═══════════════════════════════════════════════════════════
#  Stats génériques des créatures par palier [T0..T5]
#  Surface et Profondeur — valeurs de référence spec.
#  DEF = 0 (première passe). VIT stocké par créature dans .tres.
#  T3-T5 extrapolés à ~×1.63/tier HP, ~×1.6/tier ATK.
# ═══════════════════════════════════════════════════════════

const CREATURE_SURFACE_HP:  Array[int] = [40,  64,  105, 175, 285, 470]
const CREATURE_SURFACE_ATK: Array[int] = [10,  15,  24,  38,  60,  96]

const CREATURE_PROFONDEUR_HP:  Array[int] = [60,  95,  155, 255, 415, 675]
const CREATURE_PROFONDEUR_ATK: Array[int] = [14,  21,  33,  53,  85,  135]

# ═══════════════════════════════════════════════════════════
#  Pièges — dégâts en % des PV max du héros (palier Commun)
#  Modulés par zone. Première passe ; la modulation par
#  Maîtrise du piège sera calibrée dans une passe dédiée.
# ═══════════════════════════════════════════════════════════

const TRAP_DMG_PCT_SURFACE:    float = 0.08
const TRAP_DMG_PCT_PROFONDEUR: float = 0.15
const TRAP_DMG_PCT_ABYSSE:     float = 0.30

# ─── Saignement (infligé par certains pièges) ─────────────
const BLEED_DMG_PCT:  float = 0.02  # % PV max par événement
const BLEED_DURATION: int   = 3     # nombre d'événements

# ═══════════════════════════════════════════════════════════
#  Bénédictions — effets de base (palier Commun)
#  La modulation par Maîtrise de la bénédiction sera calibrée
#  dans une passe dédiée.
# ═══════════════════════════════════════════════════════════

const BLESS_HEAL_PCT:     float = 0.15  # % PV max restaurés (indépendant de la zone)
const BLESS_XP_BONUS_PCT: float = 0.50  # bonus d'XP de base sur le prochain événement

# ═══════════════════════════════════════════════════════════
#  Combat — résolution (CombatResolver)
# ═══════════════════════════════════════════════════════════

const GAUGE_THRESHOLD: float = 100.0  # jauge d'action requise pour agir (+VIT/tick)
const CRIT_CHANCE:     float = 0.20   # probabilité de coup critique
const CRIT_MULTIPLIER: float = 1.8    # multiplicateur de dégâts en cas de critique
const MIN_DAMAGE:      float = 1.0    # plancher de dégâts après défense (ATK − DEF)

# ─── Endurcissement de biome (Montagne) ─────────────────────
const MONTAGNE_ENDURCISSEMENT_REDUCTION: float = 0.20  # réduction des dégâts héros (−20 %)

# ─── Poison de biome (Marécage Putride) ──────────────────────
const BIOME_POISON_DMG_PCT:   float = 0.05  # % de l'ATK héros infligé par stack
const BIOME_POISON_MAX_STACKS: int  = 3     # stacks maximum
const BIOME_POISON_DURATION:   int  = 3     # tours avant expiration des stacks

# ─── Bouclier d'urgence (défauts si la config du passif est incomplète) ──
const SHIELD_THRESHOLD_DEFAULT: float = 0.30  # % PV max déclenchant le bouclier
const SHIELD_VALUE_PCT_DEFAULT: float = 0.15  # % PV max absorbé par le bouclier

# ═══════════════════════════════════════════════════════════
#  Progression — Maîtrise (ex-mastery_config.json)
# ═══════════════════════════════════════════════════════════

# XP requis pour franchir du palier n au palier n+1 (index = palier source).
# Courbe : seuil(n) = 360 × 2.2^n. L'index 0 est inutilisé (pas de palier −1→0).
# Légendaire→Unique (index 5) ne concerne que biomes / pièges / bénédictions
# (les créatures s'arrêtent à Légendaire — voir ENTITY_MAX_TIER).
# Calibré pour 25-30 min de session beta : cumul jusqu'à Rare = 1152 XP / biome.
const XP_THRESHOLDS: Array = [0, 360, 792, 1742, 3833, 8432]

# Modificateur d'XP selon l'écart de Maîtrise = (palier de l'entité − palier de l'événement),
# clampé à ±4. Entité plus FAIBLE que l'événement (écart négatif) → plus d'XP (catch-up).
# Table de correspondance FIXE (pas une formule : les deux branches n'ont pas la même progression).
const XP_GAP_MODIFIERS: Dictionary = {
	-4: 5.00, -3: 3.34, -2: 2.24, -1: 1.49,
	 0: 1.00,  1: 0.47,  2: 0.22,  3: 0.11, 4: 0.05,
}
const XP_GAP_CLAMP: int = 4  # écart clampé à ±4

# ═══════════════════════════════════════════════════════════
#  XP de base par type d'événement résolu
# ═══════════════════════════════════════════════════════════

const XP_BASE_COMBAT:      float = 10.0  # créature résolue
const XP_BASE_TRAP:        float = 6.0   # piège déclenché
const XP_BASE_BENEDICTION: float = 6.0   # bénédiction rencontrée

# XP créditée au Hall des Évolutions (bestiaire) pour un événement non-combat
# résolu (piège, bénédiction). Les combats créditent XP_BASE_COMBAT à la victoire.
const HALL_XP_EVENT: float = 5.0

# ═══════════════════════════════════════════════════════════
#  Coefficient de progression par type d'entité réceptrice
# ═══════════════════════════════════════════════════════════
# À chaque événement, XP reçue = XP de base × modificateur d'écart × coefficient.
# Tout type absent → DEFAULT_XP_COEF (créatures, pièges, bénédictions, passifs, biomes : ×1.0).

const DEFAULT_XP_COEF: float = 1.0
const ENTITY_XP_COEF: Dictionary = {
	Enums.EntityType.HERO: 0.05,
}

# ═══════════════════════════════════════════════════════════
#  Palier maximum par type d'entité
# ═══════════════════════════════════════════════════════════
# Créatures (Surface/Profondeur) : s'arrêtent à Légendaire (4).
# Tout le reste (pièges, bénédictions, biomes, village, héros, équipements) : Unique (5).

const DEFAULT_MAX_TIER: int = 5
const ENTITY_MAX_TIER: Dictionary = {
	Enums.EntityType.CREATURE:  4,
	Enums.EntityType.EQUIPMENT: 2,
}

# ═══════════════════════════════════════════════════════════
#  Plafond de Maîtrise des créatures selon le palier du biome
# ═══════════════════════════════════════════════════════════
# Palier max franchissable par une créature selon le palier du biome et sa zone.
# L'XP au-delà du plafond n'est pas perdue : elle reste stockée et débloque des
# paliers quand le biome monte (réévaluation à l'évolution du biome).
# Profondeur : zone non débloquée tant que le biome < Rare (2) → absente de la table.
# Clé = palier du biome (0..5), valeur = palier max de la créature.

const CREATURE_CAP_SURFACE: Dictionary = {
	0: 1, 1: 2, 2: 3, 3: 4, 4: 4, 5: 4,
}
const CREATURE_CAP_PROFONDEUR: Dictionary = {
	2: 1, 3: 2, 4: 3, 5: 4,
}

# ═══════════════════════════════════════════════════════════
#  Village — coût en Fragments pour chaque palier de Maîtrise
# ═══════════════════════════════════════════════════════════
# Fragments requis pour passer du palier n au palier n+1 (index = palier source).
# Palier 0→1 : 1 fragment, 1→2 : 2, …, 4→5 : 5.

const VILLAGE_FRAGMENT_COSTS: Array[int] = [1, 2, 3, 4, 5]

# ─── Éclosion : naissance du Village (phase préliminaire, pré-T0) ───
# Progression requise pour faire éclore le Village en T0 et débloquer
# les expéditions (remplace l'ancien clicker d'XP menant à T1).
const ECLOSION_CLICS: int = 100
# Progression ajoutée par clic. Valeur normale : 1 (≈ 100 clics).
# Réglée à 25 pour accélérer les tests (4 clics → paliers d'éveil 25/50/75/100).
const ECLOSION_CLIC_VALUE: int = 25

# ═══════════════════════════════════════════════════════════
#  Régénération
# ═══════════════════════════════════════════════════════════

const DEFAULT_REGEN_PCT: float = 0.0  # régen par défaut entre rencontres (hors modificateur)

# ═══════════════════════════════════════════════════════════
#  Bonus de maîtrise au combat (familiarité du bestiaire)
# ═══════════════════════════════════════════════════════════

const MASTERY_COMBAT_ATK_PER_TIER: float = 2.0  # ATK bonus par tier de bestiaire face à l'ennemi

# ═══════════════════════════════════════════════════════════
#  Drops
# ═══════════════════════════════════════════════════════════

const CREATURE_INGREDIENT_DROP_CHANCE: float = 0.5  # chance de drop d'ingrédient par créature non-unique

# ═══════════════════════════════════════════════════════════
#  Zones
# ═══════════════════════════════════════════════════════════

# Tier de Maîtrise du biome requis pour débloquer chaque zone.
const ZONE_UNLOCK_TIER_PROFONDEUR: int = 2
const ZONE_UNLOCK_TIER_ABYSSE:     int = 4

# Zone d'enfoncement la plus profonde débloquée selon le palier de Maîtrise du biome.
# Renvoie l'index de zone (0 = Surface, toujours ; 1 = Profondeur, ≥ Rare ;
# 2 = Abysse, ≥ Légendaire) — compatible avec Enums.Zone. Source unique de cette
# règle, utilisée par AdventureSystem (transitions) et l'UI (filtrage par zone).
static func max_unlocked_zone(biome_tier: int) -> int:
	if biome_tier >= ZONE_UNLOCK_TIER_ABYSSE:
		return 2
	if biome_tier >= ZONE_UNLOCK_TIER_PROFONDEUR:
		return 1
	return 0

# ═══════════════════════════════════════════════════════════
#  Cadence d'affichage des événements
# ═══════════════════════════════════════════════════════════
# Durées nominales en secondes (à combat_speed = 1.0).
# Pièges/bénédictions : AFFICHAGE_EVENEMENT puis TRANSITION puis suivant.
# Combats : durée calculée par CombatPlayer (nb_tours × IDEAL → clamp MIN..MAX)
#           puis TRANSITION puis suivant.
# Valeurs à affiner au playtest via COMBAT_MIN / COMBAT_MAX / TEMPS_TOUR_IDEAL ;
# ne pas toucher les seuils XP pour corriger le ressenti de rythme.

const TRANSITION:          float = 1.0  # pause post-événement avant la rencontre suivante
const AFFICHAGE_EVENEMENT: float = 1.5  # durée d'affichage fixe d'un piège ou d'une bénédiction
const COMBAT_MIN:          float = 2.0  # durée minimale d'affichage d'un combat (plancher)
const COMBAT_MAX:          float = 5.0  # durée maximale d'affichage d'un combat (plafond rafale)
const TEMPS_TOUR_IDEAL:    float = 1.2  # durée cible par tour (référence de calcul)

# ═══════════════════════════════════════════════════════════
#  Pondération du pool de créatures par zone
# ═══════════════════════════════════════════════════════════

const POOL_WEIGHT_SURFACE_ONLY: float = 100.0  # zone Surface : créature Surface uniquement
const POOL_WEIGHT_BASE:         float = 50.0   # poids de base quand les deux créatures sont au même palier
const POOL_WEIGHT_DIFF_BONUS:   float = 10.0   # bonus par palier d'écart, vers la créature la moins avancée

# ═══════════════════════════════════════════════════════════
#  Modificateurs de cycle (tirage pondéré au lancement d'aventure)
# ═══════════════════════════════════════════════════════════

const CYCLE_MODIFIERS: Array = [
	{
		"id": "none", "name": "—", "desc": "", "xp_mult": 1.0, "weight": 66
	},
	{
		"id": "bonus_xp", "name": "Cycle Chanceux",
		"desc": "XP ×1.5 ce cycle", "xp_mult": 1.5, "weight": 15
	},
	{
		"id": "resilient", "name": "Endurance",
		"desc": "Régénère 30 % entre combats", "xp_mult": 0.8, "regen_pct": 0.30, "weight": 10
	},
	{
		"id": "ghost", "name": "Fantôme",
		"desc": "Pièges ignorés, XP ×0.7", "xp_mult": 0.7, "ignore_traps": true, "weight": 5
	},
	{
		"id": "berserker_mod", "name": "Frénésie",
		"desc": "ATK ×1.3, DEF ×0.6", "xp_mult": 1.1, "atk_mult": 1.3, "def_mult": 0.6, "weight": 4
	},
]
