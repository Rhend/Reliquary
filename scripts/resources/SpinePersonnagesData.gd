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
#   • `variantes`   — liste explicite {skin, nom}, non utilisée à ce jour ;
#   • `niveaux`     — n paliers d'ÉQUIPEMENT portés par des SLOTS suffixés
#                     « _Nv<n> » (livraison Relic du 24/08/2026 : 6 niveaux,
#                     cf. SpriteSpinePersonnage.niveaux_du_slot) ;
#   • `prefixe_skin`— les 5 paliers de rareté en skins (ennemis) ;
#   • rien de tout ça → une apparence unique, sans skin à poser.
# ORTHOGONAL à ces trois formes : `genres`, un jeu ALTERNATIF complet de
# `skins_base`/`cosmetiques`/`coiffures` (livraison « Relic Femme » du
# 23/09/2026 — voir `avec_genre` plus bas). `variantes` avait été envisagé
# pour porter les versions masculine/féminine du héros, mais il REMPLACE
# entièrement les `niveaux` dans `apparences()` : incompatible avec Relic, qui
# a besoin des deux axes (genre ET niveau d'équipement) en même temps.
#
# COMPOSITION DE SKINS (`skins_base` + `cosmetiques` + `coiffures`) : Relic
# n'a pas une skin par apparence mais un corps (« Men_Global »), un jeu de
# pièces d'équipement (« Men_Level », « Men_Level_Hit ») et deux axes
# « Random » mutuellement exclusifs CHACUN dans son axe (visage / coiffure).
# Ces skins se CUMULENT — SpriteSpinePersonnage en fabrique une skin composée.
# `skins_base` est toujours posé ; `cosmetiques` (visage) et `coiffures`
# (17/09/2026, retour Rhend : « un raccourci pour changer de coupe de cheveux,
# comme pour le visage ») sont chacun une liste de jeux alternatifs (un seul
# posé par axe à la fois), que la ShowRoom fait défiler indépendamment — DEUX
# axes nommés plutôt qu'un système générique à N axes : c'est tout ce que
# Christophe a livré à ce jour (visage, cheveux), pas de raison d'anticiper
# plus (le vêtement reste dans `skins_base`, une seule famille livrée).
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
#     "cosmetiques":  [],                        # [{nom, skins}] alternatifs (visage)
#     "coiffures":    [],                        # [{nom, skins}] alternatifs (cheveux)
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

# Entrée du registre pour un id de COMBAT (`CombattantCtbData.id`, = l'id
# d'entité GameData, ex. "creature_flamebot") — le registre garde ses propres
# ids COURTS ("flamebot", voir l'en-tête) : ce pont accepte les deux formes
# plutôt que de faire porter le préfixe "creature_" au registre visuel, qui
# n'a aucune raison de connaître le bestiaire. {} si l'entrée n'existe pas
# encore (livraison non faite) — l'appelant retombe alors sur son placeholder.
static func par_id(id: String) -> Dictionary:
	var registre := charger()
	if registre == null:
		return {}
	var court := id.trim_prefix("creature_")
	for p in registre.personnages:
		var pid := str(p.get("id", ""))
		if pid == id or pid == court:
			return p
	return {}

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

# ─── GENRE (livraison « Relic Femme », 23/09/2026) ────────────
#
# Deuxième version complète du héros : Christophe livre un jeu de skins
# SYMÉTRIQUE au premier, préfixé « Woman_ » au lieu de « Men_ » (mêmes
# familles : Global, Level, Level_Hit, Random_Level_Clothing_1,
# Random_(Level_)Face_Accessory_1-3, Random_Level_Hair_1-2 — vérifié via
# tools/inspect_spine_ennemis.gd). Les 6 niveaux d'équipement restent portés
# par les MÊMES slots « _Nv<n> » pour les deux genres (aucune donnée
# dupliquée à ce niveau, cf. SpriteSpinePersonnage.niveaux_du_slot) : seul le
# socle skins_base/cosmetiques/coiffures change avec le genre.
#
# Plutôt qu'un axe `variantes` (qui remplacerait ENTIÈREMENT les 6 niveaux
# d'équipement dans `apparences()`, incompatible avec le fait que Relic a
# BESOIN des deux axes en même temps), `genres` porte un jeu ALTERNATIF
# complet de ces trois champs. `avec_genre` le substitue à l'entrée AVANT
# tout le reste du pipeline (apparences/cosmetiques/coiffures/skins_composees) :
# aucun de ces appels n'a besoin de connaître le genre, ils reçoivent déjà une
# entrée résolue. Genre 0 = comportement PAR DÉFAUT de l'entrée elle-même —
# un personnage sans second genre n'a donc RIEN à changer.
static func genres(entree: Dictionary) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for g in entree.get("genres", []):
		sortie.append(g as Dictionary)
	return sortie

# Nombre de genres jouables d'une entrée : 1 (son genre par défaut) si elle
# ne déclare aucune alternative dans `genres`.
static func nb_genres(entree: Dictionary) -> int:
	return genres(entree).size() + 1

# Entrée du registre avec le socle skins_base/cosmetiques/coiffures du genre
# demandé substitué au sien. `genre` 0 = l'entrée telle quelle (rien à
# résoudre) ; 1, 2… pique dans `genres` (1-based — l'entrée décrit déjà son
# propre genre 0), clampé sur le dernier genre déclaré. Vide/hors bornes en
# amont → l'entrée d'origine, comme un personnage sans second genre.
static func avec_genre(entree: Dictionary, genre: int) -> Dictionary:
	if genre <= 0:
		return entree
	var jeux := genres(entree)
	if jeux.is_empty():
		return entree
	var choisi: Dictionary = jeux[clampi(genre - 1, 0, jeux.size() - 1)]
	var sortie := entree.duplicate()
	sortie["skins_base"] = choisi.get("skins_base", [])
	sortie["cosmetiques"] = choisi.get("cosmetiques", [])
	sortie["coiffures"] = choisi.get("coiffures", [])
	return sortie

# Nom d'affichage d'un genre (0 = l'entrée elle-même, via `nom_genre_defaut`
# — "Masculin" si absent ; 1, 2… via `genres[n-1].nom`).
static func nom_genre(entree: Dictionary, genre: int) -> String:
	if genre <= 0:
		return str(entree.get("nom_genre_defaut", "Masculin"))
	var jeux := genres(entree)
	if jeux.is_empty():
		return str(entree.get("nom_genre_defaut", "Masculin"))
	return str(jeux[clampi(genre - 1, 0, jeux.size() - 1)].get("nom", "?"))

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
# accessoires de VISAGE « Random » de Christophe. Vide = le personnage n'en a
# pas. Voir `coiffures` pour l'axe équivalent côté cheveux.
static func cosmetiques(entree: Dictionary) -> Array[Dictionary]:
	return _jeux_alternatifs(entree, "cosmetiques")

# Coiffures ALTERNATIVES d'une entrée (un seul jeu posé à la fois) : les
# chevelures « Random » de Christophe (livraison du 25/08/2026 — Hair_1/
# Hair_2). Axe indépendant de `cosmetiques` (visage) — les DEUX se cumulent
# sur `skins_base`, voir `skins_composees`. Vide = le personnage n'en a pas.
static func coiffures(entree: Dictionary) -> Array[Dictionary]:
	return _jeux_alternatifs(entree, "coiffures")

static func _jeux_alternatifs(entree: Dictionary, champ: String) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for c in entree.get(champ, []):
		var jeu := c as Dictionary
		sortie.append({"nom": str(jeu.get("nom", "?")), "skins": _liste(jeu.get("skins", []))})
	return sortie

# Apparences d'une entrée, dans l'ordre d'affichage — voir l'en-tête pour la
# règle de priorité. `cosmetique`/`coiffure` choisissent chacun leur jeu
# cumulé (index dans `cosmetiques`/`coiffures` respectivement, bornés : 0
# quand le personnage n'a pas cet axe).
# Chaque élément : {"skin": String, "skins": PackedStringArray, "niveau": int,
# "nom": String, "palier": int} — `palier` vaut -1 hors échelle de rareté
# (l'appelant colore alors en neutre), `niveau` vaut 0 quand les slots
# d'équipement ne sont pas filtrés.
static func apparences(entree: Dictionary, cosmetique: int = 0, coiffure: int = 0) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	var base := skins_composees(entree, cosmetique, coiffure)

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

# Skins CUMULÉES d'une entrée : le socle `skins_base` plus le jeu de visage
# ET le jeu de coiffure choisis (deux axes INDÉPENDANTS qui se cumulent tous
# les deux — pas un choix entre les deux). Vide pour un personnage qui n'en
# déclare aucun (ennemis).
static func skins_composees(entree: Dictionary, cosmetique: int = 0, coiffure: int = 0) -> PackedStringArray:
	var sortie := _liste(entree.get("skins_base", []))
	sortie.append_array(_skins_du_jeu(cosmetiques(entree), cosmetique))
	sortie.append_array(_skins_du_jeu(coiffures(entree), coiffure))
	return sortie

static func _skins_du_jeu(jeux: Array[Dictionary], idx: int) -> PackedStringArray:
	if jeux.is_empty():
		return PackedStringArray()
	var jeu: Dictionary = jeux[clampi(idx, 0, jeux.size() - 1)]
	return jeu["skins"] as PackedStringArray

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
