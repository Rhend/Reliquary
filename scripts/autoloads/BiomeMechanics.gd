# ============================================================
# BiomeMechanics.gd — Mécaniques fortes de biome (Feature 6).
#
# Chaque biome débloque une mécanique forte au palier Rare (tier 2).
# Ce singleton est initialisé au lancement de chaque cycle et
# consulté par AdventureSystem et CombatPlayer pour activer les effets.
#
# Mécaniques :
#   "ambush"      (Forêt Sombre)   — premier ennemi frappe avant le cycle VIT
#   "poison"      (Marécage Putride) — chaque frappe héro empoisonne l'ennemi
#   "pirate_luck" (Plage Sauvage)  — probabilités événements déplacées vers le positif
# ============================================================
extends Node

const UNLOCK_TIER:            int   = 2      # palier Rare requis pour débloquer
const PIRATE_LUCK_CREATURE:   float = -0.05  # -5 % de combats
const PIRATE_LUCK_BENEDICTION: float = 0.05  # +5 % d'événements positifs

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

	var mechanic := biome.get("strong_mechanic", "") as String
	if mechanic == "":
		return

	var required_tier: int = int(biome.get("unlock_tier", UNLOCK_TIER))
	var current_tier:  int = int(biome.get("current_tier", 0))

	if current_tier >= required_tier:
		active_mechanic = mechanic
		EventBus.biome_mechanic_activated.emit(mechanic)

# Retourne vrai si l'embuscade est active ce cycle.
func is_ambush_active() -> bool:
	return active_mechanic == "ambush"

# Retourne vrai si la mécanique donnée est active ce cycle.
func is_mechanic_active(mechanic: String) -> bool:
	return active_mechanic == mechanic

# Retourne les probabilités d'événements modifiées pour la Chance Corsaire.
# Pour les autres mécaniques, retourne base_probs inchangé.
func modify_event_probabilities(base_probs: Dictionary) -> Dictionary:
	if active_mechanic != "pirate_luck":
		return base_probs
	var modified := base_probs.duplicate()
	modified["creature"]    = maxf(float(base_probs.get("creature",    0.70)) + PIRATE_LUCK_CREATURE,    0.0)
	modified["benediction"] = minf(float(base_probs.get("benediction", 0.15)) + PIRATE_LUCK_BENEDICTION, 1.0)
	return modified
