# ============================================================
# CombatFondScinde — décor de fond de la scène de combat CTB, PLEIN ÉCRAN
# pour les DEUX camps.
#
# Jusqu'au 02/10/2026, ce fichier composait DEUX décors séparés par une
# diagonale (ville réelle de Christophe côté héros, Usine côté adverse —
# écrêtage shader par calque + couture holographique `CombatCoupureHolo`).
# SUPPRIMÉ à la demande de Rhend (« gros changement » : un seul fond plein
# écran, « il n'y a plus de séparation au sol ») — un seul Lieu existe à ce
# jour (voir CLAUDE.md, table rase du 07/09/2026), donc un seul décor a un
# sens : l'Usine réelle de Christophe (`CombatDecorFactory`), CENTRÉE et sans
# masque, qui couvre tout le cadre pour les deux camps. La ville
# (`CombatDecorCity`) reste dans le dépôt (code + assets + tests, RIEN
# supprimé côté art) mais n'est plus appelée par aucun écran de jeu —
# orpheline, prête à resservir si un futur Lieu veut un fond "ville".
#
# Bénéfice en prime : ~moitié moins de calques alpha-blendés plein écran
# empilés (plus de ville en dessous) → le plafond ~20 FPS du 24/09/2026 qui
# avait motivé un downscale `SubViewport` (et sa contrepartie floue, réglée
# au ×1,35 le 02/10/2026) n'a plus lieu d'être : SUPPRIMÉ avec le reste, voir
# l'historique git si besoin de ressortir cette mécanique.
#
# class_name statique (pattern Balance/ExpeStyle, PAS un autoload) : PARTAGÉ
# entre l'écran de combat réel (CombatCtbUi) et la vitrine (ShowRoom) pour
# que les deux restent identiques à l'octet près — une seule source, jamais
# deux copies qui pourraient diverger. Reste le point d'entrée naturel pour
# un futur sélecteur de décor PAR LIEU (un seul Lieu livré à ce jour, voir
# CombatDecorFactory) : ce fichier ne fait aujourd'hui que déléguer, mais
# c'est lui qui gagnerait un `match` sur le Lieu le jour venu.
# ============================================================
class_name CombatFondScinde

# `vue` = résolution de référence du projet (1280×720, fixe) : la math de
# calage du sol est volontairement en unités ABSOLUES, pas la taille réelle
# du nœud (souvent pas encore connue à la construction, avant le premier layout).
static func construire(parent: Control, sol_y_frac: float, vue: Vector2 = Vector2(1280, 720)) -> void:
	# Centré (0.5) : plus de camp à privilégier, un seul décor pour tout l'écran.
	CombatDecorFactory.construire(parent, sol_y_frac, 0.5, vue)
