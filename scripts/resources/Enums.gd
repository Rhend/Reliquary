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
	const FORGE_TREE    := "forge_tree"
	# Pseudo-type : le Village n'est pas dans GameData.entities, mais son
	# évolution transite par le rituel d'ascension avec ce type.
	const VILLAGE       := "village"

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

# ─── Combat tour par tour CTB (Rework Combat — chantier 1) ────

# Camp d'un combattant dans la file d'initiative. À égalité d'horloge,
# le camp JOUEUR a l'avantage (Avatar d'abord, puis pets, puis ennemis).
enum CampCtb {
	JOUEUR  = 0,
	ADVERSE = 1,
}

# Types d'action d'une activation. Seul ATTAQUER est fonctionnel (chantier 1) ;
# COMPETENCE et OBJET sont prévus par l'architecture mais sans contenu —
# aucun bouton ne doit apparaître tant que le contenu n'existe pas.
enum ActionCtb {
	ATTAQUER,
	COMPETENCE,
	OBJET,
}

# Timing du tick d'un statut DoT, relatif à l'ACTIVATION de la cible :
# Saignement tique au DÉBUT ; Poison et Brûlure tiquent à la FIN.
enum TimingStatut {
	DEBUT_ACTIVATION = 0,
	FIN_ACTIVATION   = 1,
}

# ─── Carte d'expédition (Rework Combat — chantier 2) ──────────

# Types de nœuds d'un étage. MYSTERE = le nœud « ? » : son contenu réel
# (ContenuMystere) n'est déterminé et révélé qu'à l'ENTRÉE du joueur.
enum TypeNoeud {
	ENTREE    = 0,
	COMBAT    = 1,
	MYSTERE   = 2,
	COFFRE    = 3,
	FIN_ETAGE = 4,
}

# Contenu réel d'un nœud « ? », tiré à l'entrée (probas data-driven).
enum ContenuMystere {
	COFFRE           = 0,
	BENEDICTION      = 1,
	PIEGE            = 2,
	ATTAQUE_SURPRISE = 3,
}
