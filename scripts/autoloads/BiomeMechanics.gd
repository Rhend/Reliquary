# ============================================================
# BiomeMechanics.gd — Mécaniques fortes de biome (Feature 6).
#
# Chaque biome débloque une mécanique forte au palier Rare (tier 2).
# Ce singleton est initialisé au lancement de chaque cycle et
# consulté par AdventureSystem et CombatPlayer pour activer les effets.
#
# Mécaniques :
#   "ambush"        (Forêt Sombre)    — premier ennemi frappe avant le cycle VIT
#   "poison"        (Marécage Putride)— chaque frappe héros empoisonne l'ennemi
#   "endurcissement"(Montagne)        — dégâts héros réduits de Balance.MONTAGNE_ENDURCISSEMENT_REDUCTION
# ============================================================
extends Node

const UNLOCK_TIER: int = 2  # palier Rare requis pour débloquer

# Mécanique active pour le cycle courant ("" si aucune).
var active_mechanic: String = ""

# ═══════════════════════════════════════════════════════════
#  Interface publique
# ═══════════════════════════════════════════════════════════

# Appelée au début de chaque cycle. Vérifie le tier du biome et
# active la mécanique correspondante si le seuil est atteint.
func initialize_for_biome(biome_id: String) -> void:
	active_mechanic = ""

	var biome := GameData.get_entity(biome_id)
	if biome.is_empty():
		return

	var mechanic := biome.get("mecanique_forte_id", "") as String
	if mechanic == "":
		return

	var required_tier: int = UNLOCK_TIER
	var biome_tier:  int = int(biome.get("maitrise_actuelle", 0))

	if biome_tier >= required_tier:
		active_mechanic = mechanic

# Retourne vrai si l'embuscade est active ce cycle.
func is_ambush_active() -> bool:
	return active_mechanic == "ambush"

# Retourne vrai si la mécanique donnée est active ce cycle.
func is_mechanic_active(mechanic: String) -> bool:
	return active_mechanic == mechanic
