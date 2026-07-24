# ============================================================
# VoiesConfigData — Contenu des VOIES du QG (chantier 17).
#
# L'ordre des voies est FIXE (ch.13 : 1 Sceau libre = 1 voie, compteur
# `player.voies_ouvertes`). Ce .tres dit ce que chaque voie OUVRE :
#   voie 1 — l'Atelier/Forge (câblé en dur ch.13 : GameData.atelier_ouvert) ;
#   voies 2-4 — un LIEU SECONDAIRE révélé sur la HoloMap (chantier 17 :
#     `lieux_par_voie`, appliqué par GameData.ouvrir_voie_suivante — le
#     flag est_decouvert est persisté, le Game Over le recule avec le
#     compteur de voies, cohérent) ;
#   voies 5-6 — placeholders (contenu à définir).
# La règle « le joueur voit ce qu'il débloque avant de valider » impose
# d'afficher la destination de la voie SUIVANTE dans VoiesPanel.
# ============================================================
class_name VoiesConfigData
extends Resource

# numéro de voie (int) → id d'entité Lieu révélée à l'ouverture.
@export var lieux_par_voie: Dictionary = {
	2: "biome_colline",
	3: "biome_ville_fantome",
	4: "biome_cimetiere",
}

func lieu_pour_voie(numero: int) -> String:
	return str(lieux_par_voie.get(numero, ""))
