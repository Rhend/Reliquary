# ============================================================
# CtbPont — Pont de données BESTIAIRE EXISTANT → moteur CTB
# (Rework Combat, chantier 3).
#
# Convertit une entité de GameData (créature dark fantasy au format de
# l'ancien moteur temps réel) en CombattantCtbData TRANSITOIRE (jamais
# sauvé en .tres) : mêmes stats, lues TELLES QUELLES via
# GameData.get_effective_stats (source unique : palier de Maîtrise courant,
# descente de palier, fallbacks crit de Balance) — aucun rééquilibrage.
#
# Mapping champ à champ (get_effective_stats → CombattantCtbData) :
#   hp              → pv_max
#   atk             → atk
#   def             → def
#   vit             → vit
#   crit_chance     → crit_chance      (fallback Balance.CRIT_CHANCE)
#   crit_multiplier → crit_multiplier  (fallback Balance.CRIT_MULTIPLIER)
#   id / nom_affichage_fr / nom_affichage_en → copiés de l'entité
#     (noms de BASE — le nom par palier via Translations est une affaire
#      d'UI, hors moteur ; nom_journal() n'est qu'un log de dev).
#
# Champs SANS équivalent CTB, ignorés par le pont :
#   xp_reward (stats_par_palier) — consommé en aval au chantier loot/XP ;
#   loot_table, ingredients_drop_ids — idem (drops hors moteur) ;
#   maitrise_actuelle, xp_maitrise_* — servent à CHOISIR la ligne de stats
#     (via get_effective_stats), pas transposés ;
#   noms_par_palier_*, lore_*, lore_par_palier_* — affichage/UI ;
#   est_unique, zone_associee, biome_id — sélection amont (pools/rencontres) ;
#   passif_debloque_id — progression de Maîtrise, hors combat CTB.
#
# ── Pont HÉROS (chantier 4) ─────────────────────────────────
# L'agrégation des stats effectives du héros que consommait l'ancien moteur
# vivait dans combat_player.start_combat() — SUPPRIMÉE avec lui (8d8f920).
# combattant_depuis_heros() la RECONSTRUIT À L'IDENTIQUE (formule vérifiée
# sur l'historique git) et devient la SOURCE UNIQUE de cette agrégation :
#   stat nue (GameData.get_effective_stats("hero"), tables Balance.HERO_*)
#   + bonus PLATS (PassiveSystem.get_combat_bonuses, GameData.get_equipment_bonuses)
#   puis × (1 + Σ bonus %) via StatStacker (VillageBuildings CH_*_PCT +
#   ForgeSystem *_pct, empilés ADDITIVEMENT — jamais de produit séquentiel).
#
# Mapping héros → CombattantCtbData (bonus de stats UNIQUEMENT) :
#   pv_max      = (hp nue + passifs.hp_bonus + équip.hp + niveau.hp)   × (1 + hp_pct)
#   atk         = (atk nue + passifs.atk_bonus + équip.atk + niveau.atk) × (1 + atk_pct)
#   def         = (def nue + passifs.def_bonus + équip.def + niveau.def) × (1 + def_pct)
#   vit         = (vit nue + niveau.vit) × (1 + équip.attack_speed_pct/100 + forge atb_pct)
#   crit_chance = crit nue + (village CH_CRIT_PCT + forge crit_pct)  [points]
#   crit_multiplier = crit_multiplier nue
# niveau.* = bonus PLATS du niveau de héros (chantier 6, ProgressionHeros.
# bonus_plats() — fractions cumulées (niveau−1) × gain, .tres), injectés à la
# même position que les autres plats, AVANT les % (additif universel inchangé).
# Le combattant étant construit AU LANCEMENT, un niveau gagné en cours de run
# compte au prochain combat — jamais à chaud (arbitrage 06/07/2026).
#
# LAISSÉ DERRIÈRE (volontairement — hors bonus de stats du héros seul) :
#   GameData.get_mastery_combat_bonus(enemy_id) — bonus d'ATK par familiarité
#     avec L'ENNEMI : dépend de chaque combat, impossible à figer au lancement
#     de l'expédition (à réintroduire côté moteur si le design le confirme) ;
#   atk_mult / def_mult — modificateurs de CYCLE de la boucle idle
#     (AdventureSystem), étrangers à l'expédition free-roam ;
#   ForgeSystem.combat_rules() — effets de RÈGLE (def_ignore, gauge_start,
#     crit_mult, cond_atk_hp_above, residual…), pas des stats ;
#   poison passif on-hit (PassiveSystem.get_passive_combat_effects) — effet
#     non-stat, hors scope.
# ============================================================
class_name CtbPont
extends RefCounted

# Dotation de compétences du héros (chantier 16) — data-driven, appliquée au
# combattant transitoire à chaque construction.
const DOTATION_COMPETENCES: DotationCompetencesData = \
		preload("res://data/progression/competences_heros.tres")

# Combattant CTB transitoire depuis une entité du bestiaire (id GameData).
# Retourne null (avec erreur console) si l'entité est inconnue ou sans stats.
static func combattant_depuis_entite(entity_id: String) -> CombattantCtbData:
	var entity: Dictionary = GameData.get_entity(entity_id)
	var stats: Dictionary = GameData.get_effective_stats(entity_id)
	if entity.is_empty() or stats.is_empty():
		push_error("CtbPont : entité inconnue ou sans stats — '%s'" % entity_id)
		return null
	var d := CombattantCtbData.new()
	d.id = entity_id
	d.nom_affichage_fr = str(entity.get("nom_affichage_fr", ""))
	d.nom_affichage_en = str(entity.get("nom_affichage_en", ""))
	d.pv_max = float(stats.get("hp", 0))
	d.atk = float(stats.get("atk", 0))
	d.def = float(stats.get("def", 0))
	d.vit = float(stats.get("vit", 20))
	d.crit_chance = float(stats.get("crit_chance", Balance.CRIT_CHANCE))
	d.crit_multiplier = float(stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER))
	return d

# Combattant CTB transitoire du VRAI héros (jamais sauvé) : stats effectives
# complètes, équipement compris (arbitrage 06/07/2026). Construit au LANCEMENT
# de l'expédition — un changement d'équipement compte au prochain lancement.
# Formule = reconstruction verbatim de l'ancien combat_player (cf. en-tête).
static func combattant_depuis_heros() -> CombattantCtbData:
	var entity: Dictionary = GameData.get_entity("hero")
	var stats: Dictionary = GameData.get_effective_stats("hero")
	if entity.is_empty() or stats.is_empty():
		push_error("CtbPont : héros introuvable ou sans stats")
		return null
	var passifs: Dictionary = PassiveSystem.get_combat_bonuses()
	var equip: Dictionary = GameData.get_equipment_bonuses()
	var niv: Dictionary = ProgressionHeros.bonus_plats()
	var atk_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_ATK_PCT) \
			+ ForgeSystem.get_stat_bonus("atk_pct")
	var def_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_DEF_PCT) \
			+ ForgeSystem.get_stat_bonus("def_pct")
	var hp_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_HP_MAX_PCT) \
			+ ForgeSystem.get_stat_bonus("hp_max_pct")
	var crit_pct: float = VillageBuildings.get_bonus(VillageBuildings.CH_CRIT_PCT) \
			+ ForgeSystem.get_stat_bonus("crit_pct")
	var d := CombattantCtbData.new()
	d.id = "hero"
	d.nom_affichage_fr = str(entity.get("nom_affichage_fr", "Héros"))
	d.nom_affichage_en = str(entity.get("nom_affichage_en", "Hero"))
	d.pv_max = StatStacker.final_stat(
			float(stats.get("hp", 100)) + float(passifs.get("hp_bonus", 0.0))
			+ float(equip.get("hp", 0.0)) + float(niv.get("hp", 0.0)), [hp_pct], "hp")
	d.atk = StatStacker.final_stat(
			float(stats.get("atk", 0)) + float(passifs.get("atk_bonus", 0.0))
			+ float(equip.get("atk", 0.0)) + float(niv.get("atk", 0.0)), [atk_pct], "atk")
	d.def = StatStacker.final_stat(
			float(stats.get("def", 0)) + float(passifs.get("def_bonus", 0.0))
			+ float(equip.get("def", 0.0)) + float(niv.get("def", 0.0)), [def_pct], "def")
	d.vit = StatStacker.final_stat(
			float(stats.get("vit", 20)) + float(niv.get("vit", 0.0)),
			[float(equip.get("attack_speed_pct", 0.0)) / 100.0,
			ForgeSystem.get_stat_bonus("atb_pct")], "vit")
	d.crit_chance = float(stats.get("crit_chance", Balance.CRIT_CHANCE)) + crit_pct
	d.crit_multiplier = float(stats.get("crit_multiplier", Balance.CRIT_MULTIPLIER))
	# Compétences (chantier 16) : dotation data-driven du héros, attachée au
	# combattant TRANSITOIRE (jamais persistée) — l'UI de combat les propose,
	# le moteur gère les cooldowns.
	d.competences = DOTATION_COMPETENCES.competences.duplicate()
	return d
