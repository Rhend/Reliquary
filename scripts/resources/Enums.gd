class_name Enums

# ─── Types d'entités (champ entity_type dans GameData.entities) ──
# Toujours utiliser ces constantes plutôt que des littéraux : une faute
# de frappe dans un littéral est silencieuse (les .get(...) retournent
# leur valeur par défaut au lieu de planter).
class EntityType:
	const HERO          := "hero"
	const CREATURE      := "creature"
	const BIOME         := "biome"
	const PASSIVE       := "passive"
	const PASSIF_UNIQUE := "passif_unique"
	const EQUIPMENT     := "equipment"
	const TRAP          := "trap"
	const BENEDICTION   := "benediction"
	const INGREDIENT    := "ingredient"
	const FRAGMENT      := "fragment"
	const RESOURCE      := "resource"
	const RECIPE        := "recipe"
	const BUILDING      := "building"
	# Pseudo-type : le Village n'est pas dans GameData.entities, mais son
	# évolution transite par le rituel d'ascension avec ce type.
	const VILLAGE       := "village"

# ─── Acteurs d'un step de combat (champ attacker de CombatStep) ──
# Distinct d'EntityType : désigne qui frappe pendant la résolution VIT-based,
# pas le type d'une entité du catalogue.
class Actor:
	const HERO  := "hero"
	const ENEMY := "enemy"

# ─── Effets de bénédiction (champ effet des BenedictionData) ──
# Seuls effets supportés par AdventureSystem._apply_benediction_effect.
class BlessEffect:
	const HEAL     := "heal"
	const XP_BONUS := "xp_bonus"
	const HASTE    := "haste"   # +X % de vitesse d'attaque du héros pendant N s réelles (rail de vitesse)

enum Maitrise {
	COMMUN     = 0,
	PEU_COMMUN = 1,
	RARE       = 2,
	EPIQUE     = 3,
	LEGENDAIRE = 4,
	UNIQUE     = 5,
}

enum SlotEquipement {
	ARME,
	ANNEAU,
	ARMURE,
	CEINTURE,
	BOUCLIER,
	TALISMAN,
}

# Zones d'enfoncement d'un biome. Sert à la fois pour la zone d'exploration
# courante (AdventureSystem) et pour la zone d'appartenance d'une créature
# (CreatureData.zone_associee) — c'est le même référentiel ordonné.
enum Zone {
	SURFACE    = 0,
	PROFONDEUR = 1,
	ABYSSE     = 2,
}
