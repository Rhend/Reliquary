# ============================================================
# NeonsCiteData — TRACÉS des enseignes néon du décor de ville, bakés au pixel.
#
# POURQUOI. Christophe livre chaque plan d'immeubles en DEUX images de même
# cadrage : la façade nue (`…_Immeuble_01.png`) et la même façade AVEC ses
# enseignes (`…_Immeuble_01_Neon.png`). Vérifié le 27/08/2026 : les deux sont
# alignées au pixel près et ne diffèrent que sur ~1,3 % du cadre. La
# DIFFÉRENCE isole donc les enseignes seules, sans rien demander à l'artiste.
#
# Chaque enseigne isolée est une composante connexe, et — c'est le coup de
# chance qui rend l'effet abordable — son CONTOUR EXTÉRIEUR est déjà le tracé
# recherché : les enseignes creuses (le grand cadre rouge, le globe filaire, le
# triangle suspendu) sont des bandes fines dont le pourtour SUIT le néon, et les
# panneaux pleins donnent le tour de leur cadre, soit exactement le chenillard
# d'une vraie enseigne. Aucune squelettisation nécessaire.
#
# Le calcul exige de lire deux images de 12,6 M pixels : hors de question au
# démarrage d'un combat. On le BAKE — même patron que SilhouettesData et que
# l'instantané de la holomap : un outil d'autoring, une donnée versionnée, zéro
# coût au runtime, qui ne fait plus que lire des polylignes.
#
# ⚠ APRÈS CHAQUE LIVRAISON D'UN PLAN DE VILLE, RE-BAKER :
#     godot --headless --path . --script res://tools/bake_neons_cite.gd
# TestNeonsCite échoue si un bake ne correspond plus à son image.
#
# ANTI-PÉRIMÉ, à deux niveaux, parce que les deux contextes n'ont pas les mêmes
# moyens :
#   • RUNTIME — on compare la TAILLE de la texture (gratuite, et disponible en
#     export où les .png sources n'existent plus). Une relivraison à un autre
#     cadrage décale tous les tracés : c'est le mode de panne qui compte, et il
#     est attrapé. Tracés ignorés + warning, le décor reste correct sans points.
#   • BAKE / TESTS — on compare l'EMPREINTE du fichier source (hash des octets
#     du .png). Exact, détecte toute retouche même à cadrage constant, et ne
#     coûte que la lecture de ~400 Ko. Réservé au dev : en export, pas de .png.
#
# Header .tres requis :
#   [gd_resource type="Resource" script_class="NeonsCiteData" ...]
# ============================================================
class_name NeonsCiteData
extends Resource

const CHEMIN := "res://data/decor/neons_cite.tres"

# Clé = chemin du calque NÉON (celui qui porte les enseignes, donc celui sur
# lequel les points seront posés au runtime).
#   "res://…/…_Neon.png": {
#       "source":    Vector2(4770, 2655),   # cadrage au moment du bake
#       "empreinte": "d41d8c…",             # MD5 du .png source (dev)
#       "traces":    [ {…}, {…} ],
#   }
# Un tracé :
#   "points":   PackedVector2Array — contour FERMÉ (le premier point est
#               répété en fin de tableau), en pixels de l'IMAGE SOURCE ;
#   "couleur":  Color — teinte vive de l'enseigne, pondérée par la luminance ;
#   "longueur": float — périmètre en pixels source, pré-calculé.
@export var enseignes: Dictionary = {}

# Écart de cadrage toléré avant de déclarer le bake périmé. Strict : un plan
# relivré garde en principe le canevas commun 4770×2655, et quelques pixels de
# dérive suffiraient déjà à décoller les points de leurs enseignes.
const ECART_SOURCE_MAX := 2.0

static func charger() -> NeonsCiteData:
	if not ResourceLoader.exists(CHEMIN):
		return null
	return load(CHEMIN) as NeonsCiteData

# Tracés bakés pour ce calque, ou [] s'il n'y en a pas / si le bake est périmé.
# `taille_courante` à ZERO saute le contrôle d'obsolescence (appelant qui n'a
# pas la texture sous la main — les tests, qui vérifient l'empreinte à la place).
func traces(chemin_calque: String, taille_courante: Vector2 = Vector2.ZERO) -> Array:
	var e := enseignes.get(chemin_calque, {}) as Dictionary
	var liste := e.get("traces", []) as Array
	if liste.is_empty():
		return []
	var ref := e.get("source", Vector2.ZERO) as Vector2
	if taille_courante != Vector2.ZERO and ref != Vector2.ZERO \
			and (taille_courante - ref).length() > ECART_SOURCE_MAX:
		push_warning(("NeonsCiteData : bake PÉRIMÉ pour %s (image %s, bakée en %s) "
				+ "— re-baker avec tools/bake_neons_cite.gd")
				% [chemin_calque.get_file(), taille_courante, ref])
		return []
	return liste

# Empreinte du .png tel qu'il est sur le disque, ou "" s'il est illisible. Sert
# au bake (écriture) et aux tests (comparaison). Inutilisable en export : les
# sources n'y sont pas embarquées, seules les textures importées le sont.
# MD5 plutôt qu'un hash de Variant : c'est calculé nativement sur le fichier,
# sans charger les octets côté script, et ça ne dépend d'aucun détail interne.
static func empreinte_fichier(chemin: String) -> String:
	if not FileAccess.file_exists(chemin):
		return ""
	return FileAccess.get_md5(chemin)

# Position et TANGENTE à `distance` le long d'un tracé fermé, la distance étant
# repliée sur le périmètre : un point qui avance indéfiniment tourne en rond.
# Rend [position, tangente normalisée] en pixels source.
static func echantillon(points: PackedVector2Array, longueur: float, distance: float) -> Array:
	if points.size() < 2 or longueur <= 0.0:
		return [Vector2.ZERO, Vector2.RIGHT]
	var reste := fposmod(distance, longueur)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		if reste <= seg:
			var dir := (b - a) / seg
			return [a + dir * reste, dir]
		reste -= seg
	# Arrondis en fin de parcours : on rend le dernier sommet plutôt que rien.
	var fin := points[points.size() - 1]
	var avant := points[points.size() - 2]
	return [fin, (fin - avant).normalized()]
