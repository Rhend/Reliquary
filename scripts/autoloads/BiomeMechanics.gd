# ============================================================
# BiomeMechanics.gd — Mécaniques fortes de biome (Feature 6).
#
# Chaque biome débloque une mécanique forte au palier Rare (tier 2).
# Ce singleton est initialisé au lancement de chaque cycle et
# consulté par AdventureSystem et CombatPlayer pour activer les effets.
#
# Mécaniques :
#   "ambush"      (Forêt Sombre)   — premier ennemi frappe avant le cycle VIT
#   "poison"      (Marécage Putride) — chaque frappe héros empoisonne l'ennemi
#   "bonne_etoile"                 — probabilités événements déplacées vers le positif (non assignée)
# ============================================================
extends Node

const UNLOCK_TIER:            int   = 2      # palier Rare requis pour débloquer
const BONNE_ETOILE_CREATURE:   float = -0.05  # -5 % de combats
const BONNE_ETOILE_BENEDICTION: float = 0.05  # +5 % d'événements positifs

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

# Retourne les probabilités d'événements modifiées pour la Bonne Étoile.
# Pour les autres mécaniques, retourne base_probs inchangé.
func modify_event_probabilities(base_probs: Dictionary) -> Dictionary:
	if active_mechanic != "bonne_etoile":
		return base_probs
	var modified := base_probs.duplicate()
	modified["creature"]    = maxf(float(base_probs.get("creature",    0.70)) + BONNE_ETOILE_CREATURE,    0.0)
	modified["benediction"] = minf(float(base_probs.get("benediction", 0.15)) + BONNE_ETOILE_BENEDICTION, 1.0)
	return modified
