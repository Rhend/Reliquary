class_name Enums

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
