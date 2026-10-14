# ============================================================
# VoiesConfigData — Contenu des VOIES du QG (chantier 17).
#
# L'ordre des voies est FIXE (ch.13 : 1 Sceau libre = 1 voie, compteur
# `player.voies_ouvertes`). Ce .tres dit ce que chaque voie OUVRE :
#   voie 1 — plus liée à l'Atelier (disponible d'emblée depuis le 14/10/2026) ;
#   voies 2-4 — un LIEU SECONDAIRE révélé sur la HoloMap (chantier 17 :
#     `lieux_par_voie`, appliqué par GameData.ouvrir_voie_suivante — le
#     flag est_decouvert est persisté, le Game Over le recule avec le
#     compteur de voies, cohérent) ;
#   voies 5-6 — placeholders (contenu à définir).
# La règle « le joueur voit ce qu'il débloque avant de valider » impose
# d'afficher la destination de la voie SUIVANTE dans VoiesPanel.
#
# ⚠ VIDE depuis le 07/09/2026 (pivot Cyberpunk, table rase du contenu Dark
# Fantasy) : Collines/Ville Fantôme/Cimetière ont été supprimés avec le
# reste de l'ancien bestiaire — seule l'Usine est un Lieu réel aujourd'hui,
# et il est déjà découvert d'emblée (`biome_usine.est_decouvert = true`),
# rien à révéler. Les voies 2-4 se comportent donc comme 5-6 (placeholder)
# jusqu'à ce qu'un nouveau Lieu secondaire soit designé.
# ============================================================
class_name VoiesConfigData
extends Resource

# numéro de voie (int) → id d'entité Lieu révélée à l'ouverture.
@export var lieux_par_voie: Dictionary = {}

func lieu_pour_voie(numero: int) -> String:
	return str(lieux_par_voie.get(numero, ""))
