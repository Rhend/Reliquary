# ============================================================
# TestXPMotifs — Banc d'essai visuel des motifs de barres d'XP.
#
# Affiche, pour chaque grande catégorie d'entité, une barre d'XP en T0 et en
# T1 avec un remplissage aléatoire dans [30 % ; 60 %]. Permet de vérifier d'un
# coup d'œil que chaque motif s'applique à la bonne catégorie :
#   Passifs → bulles · Pièges → éclairs · Biomes → losanges
#   Bénédictions → croix + · Créatures → empreintes · Héros → étoiles
#
# Passe par le VRAI chemin de code (UIHelpers.entity_xp_card → XPCard.motif_for_type),
# donc ce que tu vois ici est exactement ce qui s'affiche en jeu.
#
# Lancer : ouvrir tests/TestXPMotifs.tscn et la jouer (F6) depuis l'éditeur.
# Relancer la scène pour retirer un nouveau set de remplissages aléatoires.
# ============================================================
extends Control

# [entity_type, libellé lisible (catégorie — motif)]
const CATEGORIES: Array = [
	["hero",        "HÉROS — étoiles"],
	["creature",    "CRÉATURES — empreintes"],
	["trap",        "PIÈGES — éclairs"],
	["benediction", "BÉNÉDICTIONS — croix +"],
	["biome",       "BIOMES — losanges"],
	["passive",     "PASSIFS — bulles"],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := UIHelpers.margin_of(20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = "BANC D'ESSAI — MOTIFS DE BARRES D'XP"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIColors.TEXT_HEADER)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Chaque catégorie de T0 (Commun) à T5 (Unique), remplissage aléatoire 30–60 %. Relance la scène pour de nouveaux tirages."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	root.add_child(hint)

	for cat: Array in CATEGORIES:
		var etype := cat[0] as String
		var label := cat[1] as String
		root.add_child(UIHelpers.section_header("◆  " + label, UIColors.TEXT_HEADER))
		for tier in range(GameData.MAX_TIER + 1):   # T0 → T5 (Unique)
			root.add_child(_demo_card(etype, tier))

# Construit une barre d'XP de démonstration pour un type d'entité à un palier
# donné, remplie d'un pourcentage aléatoire dans [30 % ; 60 %].
# Au palier Unique (T5) la courbe n'a pas de seuil suivant : on réutilise le
# dernier seuil pour garder la barre remplie et le motif visible.
func _demo_card(entity_type: String, tier: int) -> Control:
	var next_idx := tier + 1
	var threshold := float(GameData.xp_thresholds[next_idx]) if next_idx < GameData.xp_thresholds.size() \
			else float(GameData.xp_thresholds.back())
	var frac := randf_range(0.30, 0.60)
	var xp := frac * threshold

	var built := UIHelpers.entity_xp_card(
			"Palier %s" % GameData.get_tier_name(tier),
			tier, xp, threshold, "", entity_type)
	var card := built["card"] as XPCard
	card.custom_minimum_size = Vector2(0.0, 42.0)

	# Pourcentage attendu, greffé à droite de l'en-tête (vérification visuelle).
	var pct := Label.new()
	pct.text = "  %d%%" % int(round(frac * 100.0))
	pct.add_theme_font_size_override("font_size", 10)
	pct.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	(built["header"] as HBoxContainer).add_child(pct)

	return card
