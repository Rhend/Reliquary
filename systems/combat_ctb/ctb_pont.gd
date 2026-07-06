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
# ============================================================
class_name CtbPont
extends RefCounted

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
