# ============================================================
# SpinePersonnagesData — Registre des personnages Spine livrés par Christophe.
#
# Source UNIQUE du « qui a des assets Spine, et où » : la ShowRoom s'en sert
# pour peupler sa vitrine, et le combat réel s'y branchera pour donner un
# sprite aux ennemis (aujourd'hui encore des placeholders EnergyBoule).
# Ajouter un monstre livré = une entrée ici, rien d'autre à toucher.
#
# Contrat d'export (vérifié par tools/inspect_spine_ennemis.gd) :
#   • animations « Idle », « Attack_CaC », « Hit », « Death » ;
#   • PALIERS portés par des SKINS Spine nommées <prefixe_skin><n>, n = 1..5,
#     dans l'ordre Commun(0) → Peu Commun(1) → Rare(2) → Épique(3) →
#     Légendaire(4). Un personnage SANS variante (le héros) laisse
#     `prefixe_skin` vide : il n'a qu'une apparence.
#
# Header .tres requis :
#   [gd_resource type="Resource" script_class="SpinePersonnagesData" ...]
# ============================================================
class_name SpinePersonnagesData
extends Resource

# Une entrée par personnage. Dictionnaires plutôt qu'une sous-Resource : la
# donnée est plate et purement descriptive (aucun comportement).
#   {
#     "id":           "flamebot",                # identifiant stable
#     "nom":          "FlameBot",                # libellé de vitrine (dev)
#     "skel":         "res://…/FlameBot.skel",
#     "atlas":        "res://…/FlameBot.atlas",
#     "prefixe_skin": "FlameBot_Nv",             # "" si pas de variante
#     "ennemi":       true,
#   }
@export var personnages: Array[Dictionary] = []

# Entrées ennemies, dans l'ordre du registre.
func ennemis() -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for p in personnages:
		if bool(p.get("ennemi", false)):
			sortie.append(p)
	return sortie

# Première entrée non ennemie = le héros (Relic) — le vis-à-vis du mode Combat.
func heros() -> Dictionary:
	for p in personnages:
		if not bool(p.get("ennemi", false)):
			return p
	return {}

# Nom de skin d'une entrée pour un palier (0 = Commun … 4 = Légendaire).
# Rend "" si le personnage n'a pas de variantes → l'appelant ne pose pas de skin.
static func skin_pour_palier(entree: Dictionary, palier: int) -> String:
	var prefixe := str(entree.get("prefixe_skin", ""))
	if prefixe == "":
		return ""
	return "%s%d" % [prefixe, palier + 1]   # Nv1 = Commun
