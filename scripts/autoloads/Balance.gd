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
# Usage : Balance.CRIT_CHANCE, Balance.evolve_cost(...), etc.
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
const BLESS_XP_BONUS_PCT: float = 0.50  # bonus d'XP de base sur le prochain événement (LEGACY xp_bonus)
# Bénédiction de Hâte : +X % de vitesse d'attaque du héros pendant N secondes
# réelles, appliquée au prochain combat (rail de vitesse, modificateur
# multiplicatif temporaire). Placeholder — équilibrage ultérieur. Le % réel
# vient du champ `valeur` du .tres (fallback sur ce défaut).
const BLESS_HASTE_PCT_DEFAULT: float = 30.0  # +30 % par défaut (si valeur du .tres absente)
const BLESS_HASTE_DURATION:    float = 10.0  # fenêtre active en secondes réelles de combat

# ═══════════════════════════════════════════════════════════
#  Combat — résolution (CombatResolver)
# ═══════════════════════════════════════════════════════════

# ─── Référentiel de vitesse : VIT = cadence d'attaques par seconde ──────────
# Depuis la refonte ATB temps réel, la jauge d'action s'horodate en SECONDES
# réelles : un combattant frappe toutes les (1 / aps) secondes, où aps est sa
# cadence en attaques/seconde. Repères : 0,7 lent · 1,0 normal · 1,3 rapide.
#
# Les stats `vit` brutes des .tres (échelle ~20, héros = HERO_VIT = 20) ne sont
# PAS retouchées : on les transpose vers le référentiel att/s par division.
#   aps = vit / VIT_PER_APS   →   vit 20 = 1,0 att/s (normal),
#                                 vit 14 ≈ 0,7 (lent), vit 26 ≈ 1,3 (rapide).
# VIT_PER_APS = HERO_VIT préserve au mieux le comportement relatif actuel
# (toutes les créatures sont aujourd'hui à vit = 20, donc 1,0 att/s comme le héros).
const VIT_PER_APS: float = 20.0   # 1 attaque/s = VIT_PER_APS points de vit bruts
const APS_SLOW:    float = 0.7    # repère documentaire — cadence « lente »
const APS_NORMAL:  float = 1.0    # repère documentaire — cadence « normale »
const APS_FAST:    float = 1.3    # repère documentaire — cadence « rapide »
const APS_MIN:     float = 0.05   # garde-fou : cadence plancher (évite 1/0)

# Seuil de la jauge d'action exprimé en ATTAQUES : la jauge accumule `aps` par
# seconde, le combattant frappe à 1 attaque accumulée puis retire ce seuil
# (le surplus est conservé → aucune fraction de cadence perdue).
const ATTACK_GAUGE: float = 1.0
# Tolérance de simultanéité : si héros et ennemi atteignent leur seuil à moins
# de ce delta (en secondes), le HÉROS frappe en premier.
const SIMULTANEITY_EPS: float = 0.01  # 1 centième de seconde

const GAUGE_THRESHOLD: float = 100.0  # LEGACY (ancien référentiel par ticks) — plus utilisé par le resolver
const CRIT_CHANCE:     float = 0.20   # probabilité de coup critique
const CRIT_MULTIPLIER: float = 1.8    # multiplicateur de dégâts en cas de critique
const MIN_DAMAGE:      float = 1.0    # plancher de dégâts : un coup inflige toujours ≥ 1

# ─── Atténuation des dégâts par la DEF (réduction) ───────────
# Formule verrouillée (cf. « Référentiel des statistiques de combat ») :
#   réduction = DEF_REDUCTION_CAP × DEF / (DEF + DEF_REDUCTION_HALF)
#   dégâts    = max(1, ATK × (1 − réduction))
# Courbe à rendements décroissants : la réduction MONTE TOUJOURS avec la DEF
# (elle ne recule JAMAIS — plus de DEF ⇒ jamais moins de réduction) et SATURE
# vers un plafond doux (DEF_REDUCTION_CAP, asymptote atteinte à DEF → ∞).
# Empiler de la DEF reste utile mais de moins en moins, ce qui décourage le
# stacking dégénéré sans cap arbitraire ET sans qu'une stat ne régresse jamais.
# DEF_REDUCTION_HALF est le bouton de réglage : c'est la DEF de demi-saturation
# (réduction = CAP/2) ; la réduire fait saturer plus tôt, l'augmenter plus tard.
# ATK/DEF reçus sont les stats FINALES (après empilement additif, cf. StatStacker).
const DEF_REDUCTION_CAP:  float = 0.50  # plafond (asymptote) de la réduction
const DEF_REDUCTION_HALF: float = 40.0  # DEF de demi-saturation (réduction = CAP/2)

# Réduction de dégâts apportée par une DEF donnée, bornée [0, DEF_REDUCTION_CAP[.
# Monotone croissante. Pure et statique → réutilisable par l'UI (tooltips) et les tests.
static func def_reduction(def_val: float) -> float:
	if def_val <= 0.0:
		return 0.0
	return DEF_REDUCTION_CAP * def_val / (def_val + DEF_REDUCTION_HALF)

# Dégâts d'un coup APRÈS atténuation par la DEF, planchés à MIN_DAMAGE.
# Crit / endurcissement sont des multiplicateurs appliqués EN AVAL par le resolver.
static func mitigated_damage(atk: float, def_val: float) -> float:
	return maxf(atk * (1.0 - def_reduction(def_val)), MIN_DAMAGE)

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

# ═══════════════════════════════════════════════════════════
#  Économie XP — Chantier 2 (source de vérité : « Référentiel XP & Progression »)
# ═══════════════════════════════════════════════════════════
# Trois leviers INDÉPENDANTS pilotent toute la progression :
#   A. XP PRODUITE par un événement résolu, selon le palier de la CIBLE :
#        XP_produite = XP_PRODUCED_BASE × XP_PRODUCED_GROWTH ^ palier_cible
#      (T0→10, T1→16, T2→26, T3→41, T4→66). PAS de modificateur d'écart de
#      palier (abandonné : trop opaque). Stockée en float exact, arrondie
#      seulement à l'affichage (sinon l'erreur se cumule sur des milliers d'évts).
#   B. COÛT d'évolution vers un palier visé (× selon le type) :
#        coût = EVOLVE_COST_BASE × EVOLVE_COST_GROWTH ^ (palier_visé − 1) × mult_type
#      (créature →T1 100, →T2 180, →T3 324, →T4 583 ; biome = ×3).
#   C. COEFFICIENT d'XP reçue par type de RÉCEPTEUR (cf. ENTITY_XP_COEF).
# L'XP est distribuée SIMULTANÉMENT à toutes les entités actives, chacune
# recevant XP_produite × son coef (pas de partage, pas de division).
const XP_PRODUCED_BASE:   float = 10.0  # XP produite par un événement T0 (réglage)
const XP_PRODUCED_GROWTH: float = 1.6   # raison géométrique par palier de la cible

# XP produite par un événement résolu de palier `target_tier` (float exact).
static func xp_produced(target_tier: int) -> float:
	return XP_PRODUCED_BASE * pow(XP_PRODUCED_GROWTH, float(target_tier))

const EVOLVE_COST_BASE:   float = 100.0  # coût créature → T1 (réglage)
const EVOLVE_COST_GROWTH: float = 1.8    # raison géométrique par palier
# Multiplicateur de coût ISOLÉ par type (point unique, modifiable en 1 ligne).
# ⚠ PROVISOIRE : le ×3 biome n'est pas réconcilié avec le débit de farm —
# premier chiffre à rouvrir en passe finale (cf. audit du Référentiel XP).
const EVOLVE_COST_TYPE_MULT: Dictionary = {
	Enums.EntityType.BIOME: 3.0,
}

# Coût d'XP pour franchir vers `target_tier` (≥1), selon le type. Float exact.
static func evolve_cost(entity_type: String, target_tier: int) -> float:
	if target_tier < 1:
		return 0.0
	var mult := float(EVOLVE_COST_TYPE_MULT.get(entity_type, 1.0))
	return EVOLVE_COST_BASE * pow(EVOLVE_COST_GROWTH, float(target_tier - 1)) * mult

# Buffer d'évolution (universel, décorrélé du biome) : une entité PRÊTE mais
# non évoluée bufferise l'XP excédentaire jusqu'à cette fraction du coût du
# palier visé, puis la perd. Au déclenchement de l'évolution, le buffer est
# reversé dans la progression suivante. Cap < 100% ⇒ JAMAIS de cascade.
# Constante de réglage, à évaluer en playtest.
const EVOLVE_BUFFER_CAP: float = 0.20

# XP créditée au Hall des Évolutions (bestiaire) pour un événement non-combat
# résolu (piège, bénédiction). Les combats créditent l'XP produite de la créature.
const HALL_XP_EVENT: float = 5.0

# ─── Coefficient d'XP reçue par type de RÉCEPTEUR ───────────
# XP reçue = XP produite × coef. Tout type absent → DEFAULT_XP_COEF (×1.0 :
# créatures, pièges, bénédictions, biomes, passifs). Le héros est isolé et
# réglable individuellement.
# ⚠ PROVISOIRE : coef héros ×0.05 peut-être trop bas — marge 0.08–0.10 sans
# toucher au reste.
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

# Plafond DUR global, toutes entités confondues : aucune entité ne peut franchir
# ce palier (Rare). Une fois atteint → « Palier Max atteint » et plus aucune XP de
# Maîtrise n'est accumulée. Garde-fou appliqué par GameData.get_max_tier_for_type
# (donc effective_max_tier / can_evolve / coût de palier / UI) et par
# MasterySystem.add_xp_to_entity (arrêt de l'XP). Mettre à DEFAULT_MAX_TIER pour
# rendre la progression complète.
const GLOBAL_MAX_TIER: int = 2

# ═══════════════════════════════════════════════════════════
#  Plafond de Maîtrise des créatures selon le palier du biome
# ═══════════════════════════════════════════════════════════
# Palier max franchissable par une créature selon le palier du biome et sa zone.
# Au plafond, la créature est « prête mais non évoluée » : l'XP entre dans le
# buffer d'évolution (borné EVOLVE_BUFFER_CAP), l'excédent est PERDU — la valeur
# du farm plafonné passe par l'ingrédient, pas l'XP. Le plafond se lève quand le
# biome monte (réévaluation à l'évolution du biome, qui resignale les créatures).
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

# Paliers de Maîtrise d'un biome qui libèrent un Fragment de Mémoire (un
# Fragment non collecté du biome par jalon atteint). Source unique de la
# règle, utilisée par GameData (libération) et l'UI (annonce des jalons).
const FRAGMENT_RELEASE_TIERS: Array[int] = [2, 4, 5]

# Palier de Maîtrise d'un biome qui révèle son biome secondaire.
const SECONDARY_BIOME_REVEAL_TIER: int = 4

# ─── Éclosion : naissance du Village (phase préliminaire, pré-T0) ───
# Progression requise pour faire éclore le Village en T0 et débloquer
# les expéditions (remplace l'ancien clicker d'XP menant à T1).
const ECLOSION_CLICS: int = 100
# Progression ajoutée par clic. Valeur normale : 1 (≈ 100 clics).
# (Peut être réglée temporairement à 25 pour accélérer les tests.)
const ECLOSION_CLIC_VALUE: int = 1

# ═══════════════════════════════════════════════════════════
#  Régénération
# ═══════════════════════════════════════════════════════════

const DEFAULT_REGEN_PCT: float = 0.0  # régen par défaut entre rencontres (hors modificateur)

# ═══════════════════════════════════════════════════════════
#  Bonus de maîtrise au combat (familiarité du bestiaire)
# ═══════════════════════════════════════════════════════════

const MASTERY_COMBAT_ATK_PER_TIER: float = 2.0  # ATK bonus par tier de bestiaire face à l'ennemi

# ═══════════════════════════════════════════════════════════
#  Drops de ressources par biome — Chantier 3
#  (source de vérité : « Référentiel Ressources & Drops »)
# ═══════════════════════════════════════════════════════════
# À chaque créature NON-BOSS vaincue, deux tirages INDÉPENDANTS sur les deux
# ressources propres du biome courant (cf. BiomeData.ressource_frequente_id /
# ressource_rare_id) : une fréquente (taux fixe) et une rare (taux selon le
# palier de la créature). Quantité 1 chacune. Les boss (créatures Uniques) ne
# droppent aucune ressource de farm.
const DROP_FREQUENT_RATE: float = 0.90  # taux de la ressource fréquente (tout palier)

# Taux de la ressource rare selon le PALIER de la créature tuée (index = palier).
# Courbe NON linéaire → table adressable, pas une formule. T0..T4.
const DROP_RARE_RATE_BY_TIER: Array[float] = [0.02, 0.05, 0.10, 0.18, 0.30]

# Taux de drop de la ressource rare pour un palier de créature (clampé à la table).
static func rare_drop_rate(creature_tier: int) -> float:
	return DROP_RARE_RATE_BY_TIER[clampi(creature_tier, 0, DROP_RARE_RATE_BY_TIER.size() - 1)]

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
# Combats : depuis la refonte ATB temps réel, la durée est ÉMERGENTE — chaque
#           CombatStep est joué à son horodatage réel (time_sec), sans borne min
#           ni max. GameSettings.combat_speed est le seul multiplicateur global
#           de vitesse de lecture.

const TRANSITION:          float = 1.0  # pause post-événement avant la rencontre suivante
const AFFICHAGE_EVENEMENT: float = 1.5  # durée d'affichage fixe d'un piège ou d'une bénédiction
# LEGACY — ne bornent plus la durée d'un combat (référentiel ATB temps réel).
# Conservés au cas où un futur réglage de cadence les réutilise ; aucun appelant
# actuel hors documentation.
const COMBAT_MIN:          float = 2.0  # LEGACY (ancien plancher de durée de combat)
const COMBAT_MAX:          float = 5.0  # LEGACY (ancien plafond de durée de combat)
const TEMPS_TOUR_IDEAL:    float = 1.2  # LEGACY (ancienne durée cible par tour)

# ═══════════════════════════════════════════════════════════
#  Pondération du pool de créatures par zone
# ═══════════════════════════════════════════════════════════

const POOL_WEIGHT_SURFACE_ONLY: float = 100.0  # zone Surface : créature Surface uniquement
const POOL_WEIGHT_BASE:         float = 50.0   # Profondeur/Abysse : poids égal pour les deux créatures (50/50 fixe)

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
