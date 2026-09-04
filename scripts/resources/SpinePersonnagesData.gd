# ============================================================
# SpinePersonnagesData — Registre des personnages Spine livrés par Christophe.
#
# Source UNIQUE du « qui a des assets Spine, et où » : la ShowRoom s'en sert
# pour peupler sa vitrine, et le combat réel s'y branchera pour donner un
# sprite aux ennemis (aujourd'hui encore des placeholders EnergyBoule).
# Ajouter un monstre livré = une entrée ici, rien d'autre à toucher.
#
# Contrat d'export (vérifié par tools/inspect_spine_ennemis.gd) :
#   • animations « Idle », « Attack_CaC », « Hit », « Death » — plus
#     « Attack_Shoot » pour Relic, qui a une attaque à distance ;
#   • les ENNEMIS portent leurs PALIERS par des SKINS Spine nommées
#     <prefixe_skin><n>, n = 1..5, dans l'ordre Commun(0) → Légendaire(4).
#
# ANNONCÉ PAR CHRISTOPHE (25/08/2026), pas encore livré — deux formes à
# prévoir, toutes deux documentées dans ChristopheAnimationWIP/SPECS_SPINE.md :
#   • ENNEMI DÉCOUPÉ : ses 5 paliers sur des SLOTS « …_Nv1 » … « _Nv5 »
#     (« WorkBot_Bras_D_Nv1 ») au lieu de 5 skins. La route existe déjà —
#     `niveaux: 5` au lieu de `prefixe_skin` — mais ⚠ la PURGE des autres
#     paliers ne tourne QUE dans `SpriteSpinePersonnage._composer_skin`, donc
#     seulement si l'entrée déclare des `skins` (`skins_base`). Un export dont
#     toutes les pièces vivent dans la skin « default » sortirait avec les 5
#     paliers EMPILÉS : c'est le point à traiter à la première livraison.
#   • BOSS À VFX PERMANENT (aura posée dans la pose de repos) : la mesure
#     automatique compterait l'aura comme du corps et le rendrait trop petit.
#     `SpriteSpinePersonnage.creer()` prend déjà `hauteur_cible_px` ; il
#     faudra la porter dans l'entrée du registre pour ces personnages-là.
#
# TROIS façons pour un personnage de porter plusieurs apparences, de la plus
# spécifique à la plus générale — l'appelant n'a jamais à savoir laquelle :
#   • `variantes`   — liste explicite {skin, nom} (forme prévue pour les
#                     versions masculine / féminine du héros, non livrées) ;
#   • `niveaux`     — n paliers d'ÉQUIPEMENT portés par des SLOTS suffixés
#                     « _Nv<n> » (livraison Relic du 24/08/2026 : 6 niveaux,
#                     cf. SpriteSpinePersonnage.niveaux_du_slot) ;
#   • `prefixe_skin`— les 5 paliers de rareté en skins (ennemis) ;
#   • rien de tout ça → une apparence unique, sans skin à poser.
#
# COMPOSITION DE SKINS (`skins_base` + `cosmetiques`) : Relic n'a pas une skin
# par apparence mais un corps (« Men_Global »), un jeu de pièces d'équipement
# (« Men_Level », « Men_Level_Hit ») et des accessoires « Random » mutuellement
# exclusifs. Ces skins se CUMULENT — SpriteSpinePersonnage en fabrique une skin
# composée. `skins_base` est toujours posé ; `cosmetiques` est une liste de jeux
# alternatifs (un seul à la fois), que la ShowRoom fait défiler.
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
#     "prefixe_skin": "FlameBot_Nv",             # "" si pas de skin de palier
#     "skins_base":   [],                        # skins cumulées (Relic)
#     "cosmetiques":  [],                        # [{nom, skins}] alternatifs
#     "niveaux":      0,                         # paliers portés par les slots
#     "ennemi":       true,
#     "regarde_a_droite": true,                  # SENS D'EXPORT (voir plus bas)
#     "taille_relative_pct": 20.0,                # écart chara design vs l'étalon (voir plus bas)
#   }
@export var personnages: Array[Dictionary] = []

# Chemin du registre — SOURCE UNIQUE : tout appelant passe par `charger()`
# plutôt que de recopier le chemin (la ShowRoom comme l'écran de combat).
const CHEMIN := "res://data/personnages/spine_personnages.tres"

static func charger() -> SpinePersonnagesData:
	return load(CHEMIN) as SpinePersonnagesData

# Entrées ennemies, dans l'ordre du registre.
func ennemis() -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for p in personnages:
		if bool(p.get("ennemi", false)):
			sortie.append(p)
	return sortie

# ─── SENS D'EXPORT ──────────────────────────────────────────
#
# Le registre décrit L'ASSET tel qu'il a été livré ; c'est l'appelant qui décide
# de la MISE EN SCÈNE. Cette séparation compte : « vers où regarde le sprite de
# Christophe » est un fait constaté à l'intégration, « vers où il doit regarder
# à l'écran » dépend du camp où on le pose, et les deux n'ont aucune raison de
# vivre au même endroit.
#
# Constaté le 27/08/2026 sur la livraison courante : Christophe dessine CHAQUE
# CAMP PRÊT À L'EMPLOI — Relic tourné vers la DROITE, FlameBot et WorkBot vers
# la GAUCHE. Posés à leurs ancrages (joueur à gauche, adverse à droite), ils se
# font donc face SANS AUCUN MIROIR : `echelle_x` rend +1 partout aujourd'hui.
#
# ⚠ Ne JAMAIS lire le sens sur l'ARME. Le FlameBot porte son canon en travers
# du corps, pointé vers l'arrière-droite, alors que sa TÊTE (masque en V,
# optiques) regarde à gauche. C'est cette confusion qui a fait poser un miroir
# systématique sur les ennemis, lequel les retournait DOS à Relic — le bug que
# Christophe a signalé. Le REGARD donne le sens, pas ce que le personnage tient.
#
# Le champ existe pour le jour où une livraison arrivera dans l'autre sens : une
# ligne à changer sur SON entrée, aucun code à toucher, les autres ne bougent pas.
static func regarde_a_droite(entree: Dictionary) -> bool:
	return bool(entree.get("regarde_a_droite", true))

# Signe à donner à `scale.x` pour qu'un personnage regarde du côté voulu.
# Rend -1 quand le sens d'export et le sens voulu s'opposent, +1 sinon.
static func echelle_x(entree: Dictionary, doit_regarder_a_droite: bool) -> float:
	return 1.0 if regarde_a_droite(entree) == doit_regarder_a_droite else -1.0

# ─── TAILLE RELATIVE (chara design, acté 09/2026) ────────────
#
# Les entités n'ont plus toutes la même hauteur à l'écran : leur gabarit sert
# à ENVOYER UN MESSAGE au joueur (WorkBot lit petit et utilitaire, FlameBot
# lit imposant et dangereux). On est PARTI d'un ratio d'unités Spine brutes
# entre squelettes pour dériver ça automatiquement — abandonné : les unités
# natives d'un export ne reflètent AUCUNE intention de gabarit (un simple
# sous-produit de l'échelle de travail propre à chaque fichier Spine), au
# point d'inverser l'ordre voulu (Relic mesurait moins d'unités que WorkBot,
# alors qu'il doit rendre plus grand). La taille relative est donc une
# DÉCISION DE DESIGN explicite, un chiffre par entrée, jamais déduite.
#
# `taille_relative_pct` = écart en % par rapport à l'ÉTALON
# (`SpriteSpinePersonnage.HAUTEUR_ETALON_PX` — WorkBot aujourd'hui, à 0 %).
# +20.0 = 20 % plus grand que l'étalon ; -10.0 = 10 % plus petit. Absent =
# 0 % (même taille que l'étalon). Christophe n'a RIEN à faire porter ça dans
# son export (voir ChristopheAnimationWIP/SPECS_SPINE.md §5) : ce chiffre vit
# uniquement ici.
static func taille_relative_pct(entree: Dictionary) -> float:
	return float(entree.get("taille_relative_pct", 0.0))

# Hauteur RENDUE (px) visée pour cette entrée : l'étalon modulé par son écart
# de chara design. Remplace l'ancienne cible UNIQUE partagée par tout le
# monde — voir SpriteSpinePersonnage.HAUTEUR_ETALON_PX pour le mécanisme de
# mise à l'échelle qui consomme cette valeur.
static func hauteur_cible_px(entree: Dictionary) -> float:
	return SpriteSpinePersonnage.HAUTEUR_ETALON_PX * (1.0 + taille_relative_pct(entree) / 100.0)

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

# Jeux cosmétiques ALTERNATIFS d'une entrée (un seul posé à la fois) : les
# accessoires « Random » de Christophe. Vide = le personnage n'en a pas.
static func cosmetiques(entree: Dictionary) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for c in entree.get("cosmetiques", []):
		var jeu := c as Dictionary
		sortie.append({"nom": str(jeu.get("nom", "?")), "skins": _liste(jeu.get("skins", []))})
	return sortie

# Apparences d'une entrée, dans l'ordre d'affichage — voir l'en-tête pour la
# règle de priorité. `cosmetique` choisit le jeu d'accessoires cumulé (index
# dans `cosmetiques`, borné : 0 quand le personnage n'en a pas).
# Chaque élément : {"skin": String, "skins": PackedStringArray, "niveau": int,
# "nom": String, "palier": int} — `palier` vaut -1 hors échelle de rareté
# (l'appelant colore alors en neutre), `niveau` vaut 0 quand les slots
# d'équipement ne sont pas filtrés.
static func apparences(entree: Dictionary, cosmetique: int = 0) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	var base := skins_composees(entree, cosmetique)

	var nommees: Array = entree.get("variantes", [])
	if not nommees.is_empty():
		for v in nommees:
			sortie.append(_apparence(str((v as Dictionary).get("skin", "")), base, 0,
					str((v as Dictionary).get("nom", "?")), -1))
		return _avec_decalage(sortie, entree)

	var nb_niveaux := int(entree.get("niveaux", 0))
	if nb_niveaux > 0:
		for n in range(1, nb_niveaux + 1):
			# Nv1 = Commun, comme les skins de palier des ennemis. Au-delà de
			# l'échelle de rareté (6 paliers), le niveau se nomme lui-même.
			var palier: int = n - 1 if n <= NB_PALIERS_RARETE else -1
			var nom: String = GameData.get_tier_name(palier) if palier >= 0 else "Nv %d" % n
			sortie.append(_apparence("", base, n, nom, palier))
		return _avec_decalage(sortie, entree)

	if str(entree.get("prefixe_skin", "")) != "":
		for t in NB_PALIERS:
			sortie.append(_apparence(skin_pour_palier(entree, t), base, 0,
					GameData.get_tier_name(t), t))
		return _avec_decalage(sortie, entree)

	sortie.append(_apparence("", base, 0, str(entree.get("nom", "?")), -1))
	return _avec_decalage(sortie, entree)

# Skins CUMULÉES d'une entrée : le socle `skins_base` plus le jeu cosmétique
# choisi. Vide pour un personnage qui n'en déclare pas (ennemis).
static func skins_composees(entree: Dictionary, cosmetique: int = 0) -> PackedStringArray:
	var sortie := _liste(entree.get("skins_base", []))
	var jeux := cosmetiques(entree)
	if not jeux.is_empty():
		var jeu: Dictionary = jeux[clampi(cosmetique, 0, jeux.size() - 1)]
		sortie.append_array(jeu["skins"] as PackedStringArray)
	return sortie

# Reporte le recentrage visuel de l'entrée sur toutes ses apparences. Il ne
# dépend ni du palier ni du costume : c'est la POSE qui penche, et elle est la
# même partout. Les 6 niveaux de Relic partagent donc une seule valeur.
static func _avec_decalage(apparences_: Array[Dictionary],
		entree: Dictionary) -> Array[Dictionary]:
	var dx := float(entree.get("decalage_x_px", 0.0))
	if dx == 0.0:
		return apparences_
	for a in apparences_:
		a["decalage_x_px"] = dx
	return apparences_

static func _apparence(skin: String, skins: PackedStringArray, niveau: int,
		nom: String, palier: int) -> Dictionary:
	return {"skin": skin, "skins": skins, "niveau": niveau, "nom": nom, "palier": palier}

static func _liste(brut: Variant) -> PackedStringArray:
	var sortie := PackedStringArray()
	for v in (brut as Array):
		sortie.append(str(v))
	return sortie

# Paliers de rareté portés par les exports d'ennemis : Commun(0) → Légendaire(4).
# Unique(5) est hors échelle créature (Balance.ENTITY_MAX_TIER).
const NB_PALIERS := 5
# Échelle de rareté complète (Commun → Unique) : les niveaux d'ÉQUIPEMENT de
# Relic vont jusqu'à 6, ils empruntent donc les noms de palier jusqu'à Unique.
const NB_PALIERS_RARETE := 6
