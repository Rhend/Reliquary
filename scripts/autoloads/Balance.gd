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
#   • Configs de passifs (poison on-hit)  → .tres des passifs
#   • Cadence/timings & animations        → AdventureSystem / CombatPlayer
# ============================================================
class_name Balance

# ═══════════════════════════════════════════════════════════
#  Stats du héros par palier de Maîtrise [T0..T5]
#  Source de vérité : le BESTIAIRE (100/18/10 à T0). T0→T4 = valeurs
#  Bestiaire ; T5 extrapolé à la même raison (×1.5 PV/ATK/DEF arrondi)
#  puisque le Bestiaire s'arrête à T4.
# ═══════════════════════════════════════════════════════════

const HERO_HP_PER_TIER:  Array[int] = [100, 150, 225, 338, 506, 759]
const HERO_ATK_PER_TIER: Array[int] = [18,  27,  40,  60,  90,  135]
const HERO_DEF_PER_TIER: Array[int] = [10,  15,  22,  33,  50,  75]
const HERO_VIT: int = 20  # constant à tous les paliers → 1.0 att/s

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
const CRIT_CHANCE:     float = 0.05   # probabilité de coup critique (fallback = base héros)
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

# ─── Poison de biome (Marécage Putride) — modèle à TICKS temps réel ─────────
# Le combat est ATB temps réel : plus de notion de « tour ». Le poison de biome
# tourne sur une HORLOGE GLOBALE par cible (le héros). À chaque tic, on inflige
# BIOME_POISON_DMG_PCT × ATK_source × (nombre de stacks VIVANTS à cet instant).
# Un stack rejoint l'horloge en cours mais garde sa durée de vie propre
# (BIOME_POISON_STACK_DURATION à partir de son application) → un stack isolé
# produit 2 ticks (t+2, t+4). Empilement additif et parallèle, plafonné.
# Source de vérité : « Référentiel des statistiques de combat ».
const BIOME_POISON_DMG_PCT:       float = 0.05  # % de l'ATK source infligé / tick / stack vivant
const BIOME_POISON_MAX_STACKS:    int   = 3     # stacks maximum
const BIOME_POISON_TICK_INTERVAL: float = 2.0   # secondes réelles entre deux tics de l'horloge
const BIOME_POISON_STACK_DURATION: float = 4.0  # secondes réelles : durée de vie d'un stack

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
# ⚠ Réglage : coef héros relevé à ×0.15 (Chantier 7 — montait trop lentement à
# ×0.05). Source de vérité alignée : Notion « Référentiel XP & Progression » + Fondations.
const DEFAULT_XP_COEF: float = 1.0
const ENTITY_XP_COEF: Dictionary = {
	Enums.EntityType.HERO: 0.15,
	# Équipement : plus lent que les créatures (×1.0), plus rapide que le biome
	# effectif → stoppe le fusage de palier. Constante de réglage (playtest).
	Enums.EntityType.EQUIPMENT: 0.4,
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
#  Village — montée AUTOMATIQUE du palier (critère de LARGEUR)
# ═══════════════════════════════════════════════════════════
# Le Village est la SEULE entité à évolution NON manuelle : ni XP, ni ressource
# dépensée, ni Fragment, ni buffer. Il monte de palier AUTOMATIQUEMENT dès qu'assez
# de bâtiments sont reconstruits (palier T0 ou plus), comptés transversalement à
# TOUS les quartiers. Strictement croissant, jamais de redescente. Les ROUTES ne
# sont pas des bâtiments : elles ne comptent jamais. Source : Système d'Expéditions
# §8 + Gestion du Village §9.
#
# Le CRITÈRE change selon le palier visé (contrainte : aucun drop avant la Forge,
# donc le 1er palier ne peut pas dépendre des bâtiments, qui exigent des drops) :
#   → T1 Peu Commun : compteur de KILLS ≥ 50 (ouvre la Forge + active les drops).
#   → T2 Rare       : bâtiments à T0+ ≥ 8  (ouvre le Sanctuaire).
# Valeurs de réglage (le débit ~12 combats/min est provisoire → le seuil kills suivra
# son recalibrage). Hors VS (réservé, non actif sous GLOBAL_MAX_TIER) : → T3 Épique
# basculera sur la PROFONDEUR (bâtiments à T2+ ≥ 6).
const VILLAGE_SEUIL_PEU_COMMUN_KILLS: int = 50  # kills pour → T1 (Peu Commun)
const VILLAGE_SEUIL_RARE_BATIMENTS:   int = 8   # bâtiments T0+ pour → T2 (Rare)

# Palier de Village atteignable selon l'état du monde (kills + bâtiments T0+), borné
# par le plafond DUR global. Strictement séquentiel : T2 exige d'abord T1.
static func village_target_tier(kills: int, building_count: int) -> int:
	var tier := 0
	if kills >= VILLAGE_SEUIL_PEU_COMMUN_KILLS:
		tier = 1
	if tier >= 1 and building_count >= VILLAGE_SEUIL_RARE_BATIMENTS:
		tier = 2
	return mini(tier, GLOBAL_MAX_TIER)

# Paliers de Maîtrise d'un biome qui libèrent un Fragment de Mémoire (un
# Fragment non collecté du biome par jalon atteint). Source unique de la
# règle, utilisée par GameData (libération) et l'UI (annonce des jalons).
const FRAGMENT_RELEASE_TIERS: Array[int] = [2, 4, 5]

# Palier de Maîtrise d'un biome qui révèle son biome secondaire.
const SECONDARY_BIOME_REVEAL_TIER: int = 4

# ═══════════════════════════════════════════════════════════
#  Village — Quartiers, routes & bâtiments (Chantier 4)
#  Source de vérité : « Gestion du Village — Quartiers & Coûts »
# ═══════════════════════════════════════════════════════════
# Courbe de coût UNIQUE, commune à TOUS les bâtiments (la différenciation par
# impact viendra plus tard). Paliers Délabré → T0 → T1 → T2 → T3 → T4 → T5.
#
# BUILDING_COST_BASE (20) et BUILDING_COST_GROWTH (1,6) sont les constantes
# nommées de l'INTENTION de courbe (la fréquente démarre à 20, ×1,6/palier).
# La table BUILDING_COST_STEPS ci-dessous est la DONNÉE adressable faisant foi :
# elle reprend cette intention pour les premiers paliers puis l'aplatit
# délibérément (la fréquente ne suit plus 1,6 dès T2 — réglage v1).
#
# Chaque palier (index = palier CIBLE, 0=Délabré→T0 … 5=T4→T5) résout en
# ressources concrètes contre l'assignation de biome du bâtiment :
#   • freq → quantité de la ressource FRÉQUENTE du biome principal (chaque palier)
#   • rare → quantité de la ressource RARE du biome principal (à partir de T2)
#   • add_count → nombre de biomes additionnels qui contribuent leur fréquente
#   • add_each  → quantité par biome additionnel
# Les biomes additionnels se résolvent contre BuildingData.biomes_additionnels
# (les `add_count` premiers). VS : T0→T2 mono-biome ; T3+ exige le multi-biomes.
const BUILDING_COST_BASE:   float = 20.0
const BUILDING_COST_GROWTH: float = 1.6

const BUILDING_COST_STEPS: Array = [
	{ "freq": 20, "rare": 0,  "add_count": 0, "add_each": 0  },  # Délabré → T0
	{ "freq": 32, "rare": 0,  "add_count": 0, "add_each": 0  },  # → T1
	{ "freq": 40, "rare": 3,  "add_count": 0, "add_each": 0  },  # → T2
	{ "freq": 52, "rare": 5,  "add_count": 1, "add_each": 10 },  # → T3
	{ "freq": 68, "rare": 7,  "add_count": 2, "add_each": 14 },  # → T4
	{ "freq": 90, "rare": 10, "add_count": 2, "add_each": 18 },  # → T5
]

# Palier Délabré (état initial d'un bâtiment, avant toute reconstruction) et
# palier maximum atteignable. Indépendants du plafond DUR global des entités
# (les bâtiments ne sont pas des entités à Maîtrise).
const BUILDING_TIER_DELABRE: int = -1
const BUILDING_MAX_TIER:     int = 5

# ─── Routes (gate mou d'onboarding) ─────────────────────────
# Segment unique reconstruit d'un coup (pas de paliers). Coût bas en ressource
# fréquente du biome dominant du quartier — sous le coût d'une reconstruction
# de bâtiment T0. quartier → { res_id, qty }.
const VILLAGE_ROUTE_COSTS: Dictionary = {
	"hero":      { "res_id": "res_fourrure", "qty": 12 },  # Forêt
	"adventure": { "res_id": "res_pierre",   "qty": 12 },  # Montagne
	"forge":     { "res_id": "res_pierre",   "qty": 15 },  # Montagne
}

# Palier de Maîtrise du VILLAGE requis pour débloquer le hub Forge (et donc la
# route Forge). Aligné sur MENU_ITEMS de Village.gd (Forge = tier_min 1).
const FORGE_HUB_UNLOCK_VILLAGE_TIER: int = 1

# ═══════════════════════════════════════════════════════════
#  Forge — Évolution & arbre d'équipement (Chantier 5)
#  Sources : « Forge » (structure) + « Équilibrage final Équipement »
# ═══════════════════════════════════════════════════════════
# L'équipement est une entité à Maîtrise (XP par l'usage, cf. Chantier 2). Son
# passage de palier N'EXIGE PAS d'ingrédient : il (1) ouvre une STRATE de l'arbre
# et (2) octroie un LOT de points de Forge. L'arbre s'achète aux points ; SEULS
# les keystones consomment en plus l'ingrédient rare du biome de l'équipement.
# VS : strates 1-2 uniquement (équipement plafonné à Rare/T2).

# Lot de points octroyé en ATTEIGNANT un palier (clé = palier atteint).
# Couvre à lui seul tout l'arbre non-keystone (marge ~16 %/strate).
const FORGE_PALIER_POINT_LOTS: Dictionary = {
	1: 120,   # T0 → T1 (ouvre strate 1)
	2: 290,   # T1 → T2 (ouvre strate 2)
	# post-VS : 3 → 570, 4 → 1250, 5 → 1610
}

# Conversion de l'XP EXCÉDENTAIRE (au-delà du seuil du palier) en points de Forge,
# RÉALISÉE au passage de palier : points += floor(overflow_xp / FORGE_XP_PER_POINT).
# Le buffer borné du Chantier 2 ne s'applique PAS à l'équipement (XP non cappée,
# tout l'excédent se convertit). Alimente les keystones / récompense le farm.
const FORGE_XP_PER_POINT: float = 25.0

# Coût en points par (strate, type de nœud). Strate absente / type absent → nœud
# indisponible. (post-VS : S3 50/120/150 · S4 90/210/260 · S5 160/380/450)
const FORGE_NODE_POINT_COST: Dictionary = {
	1: { "mineur": 15, "notable": 40 },
	2: { "mineur": 28, "notable": 70, "keystone": 90 },
}

# Bonus de stat en % par (strate, type). Le % DÉCROÎT par strate (la stat nue et
# le nombre de nœuds montent → apport absolu régulier). Keystone = 0 (nœud de
# RÈGLE, pas de % de stat). (post-VS : S3 0.07/0.16 · S4 0.05/0.12 · S5 0.04/0.09)
const FORGE_NODE_STAT_PCT: Dictionary = {
	1: { "mineur": 0.15, "notable": 0.33, "keystone": 0.0 },
	2: { "mineur": 0.10, "notable": 0.22, "keystone": 0.0 },
}

# Ingrédient rare du biome consommé par un KEYSTONE selon sa strate (en plus des
# points). SEUL usage de l'ingrédient dans la Forge — incitatif, jamais bloquant.
const FORGE_KEYSTONE_INGREDIENT_QTY: Dictionary = {
	2: 3,
	# post-VS : 3 → 6 · 4 → 10 · 5 → 15
}

# Coût en points d'un nœud (strate, type), 0 si indéfini.
static func forge_node_point_cost(strate: int, node_type: String) -> int:
	return int((FORGE_NODE_POINT_COST.get(strate, {}) as Dictionary).get(node_type, 0))

# Bonus de stat % d'un nœud (strate, type), 0.0 si indéfini.
static func forge_node_stat_pct(strate: int, node_type: String) -> float:
	return float((FORGE_NODE_STAT_PCT.get(strate, {}) as Dictionary).get(node_type, 0.0))

# Lot de points octroyé en atteignant `tier`, 0 si aucun.
static func forge_palier_lot(tier: int) -> int:
	return int(FORGE_PALIER_POINT_LOTS.get(tier, 0))

# Quantité d'ingrédient rare requise par un keystone de cette strate, 0 si aucune.
static func forge_keystone_ingredient_qty(strate: int) -> int:
	return int(FORGE_KEYSTONE_INGREDIENT_QTY.get(strate, 0))

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

const DEFAULT_REGEN_PCT: float = 0.0  # fallback du modificateur de cycle (hors base)
# Régénération de BASE entre rencontres, HORS bâtiment (Chantier 7 — C3). Garantit
# qu'un héros T0 sans village (pas de Maison → CH_REGEN_PCT = 0) tienne la durée
# d'une expédition. S'ADDITIONNE à la Maison / aux passifs / au Forge. Réglage.
const BASE_REGEN_PCT: float = 0.15  # 15 % des PV max régénérés après chaque rencontre

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
