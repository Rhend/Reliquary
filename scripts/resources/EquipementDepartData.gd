# ============================================================
# EquipementDepartData — Dotation d'ÉQUIPEMENT DE DÉPART d'une partie neuve
# (Rework Combat, chantier 13 — acté 06/07/2026 : l'équipement complet de
# rareté Commun est présent dès le début, la progression passe par son
# amélioration à la Forge/Atelier, débloquée au premier Sceau).
#
# Liste data-driven des ids d'équipement à débloquer ET équiper à la
# création d'une partie (chaque .tres visé doit être un EquipmentData
# existant, Commun = maitrise 0, nom non vide — jamais inventer un
# équipement ici, compléter data/equipements/ d'abord).
# VS : 3 slots couverts (Arme/Anneau/Armure) — Ceinture/Bouclier/Talisman
# sont des placeholders sans contenu (biomes post-VS), donc HORS dotation.
#
# Header .tres requis (Godot 4.6) :
#   [gd_resource type="Resource" script_class="EquipementDepartData" ...]
# ============================================================
class_name EquipementDepartData
extends Resource

@export var equipement_ids: Array[String] = [
	"equipment_arme", "equipment_anneau", "equipment_armure",
]
