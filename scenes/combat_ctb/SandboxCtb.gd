# ============================================================
# SandboxCtb — Scène ISOLÉE de test du moteur CTB (chantier 1).
#
# Lançable directement (F6 / godot res://scenes/combat_ctb/SandboxCtb.tscn) :
# combat Avatar vs 1-3 ennemis PARAMÉTRABLES — éditer `ennemis` dans
# l'inspecteur (dupliquer/modifier les .tres de data/combat_ctb/, stats
# éditables). Sans expédition, sans UI finale : le combat se déroule en
# automatique (Attaquer la première cible vivante) et le journal complet de
# la file CTB s'imprime en console + s'affiche à l'écran.
#
# `avatar_empoisonne_sur_coup` : pose un stack de Poison sur la cible à
# chaque coup de l'Avatar — bouton de DÉMO du hook DoT (timings/stacks
# visibles dans le journal), pas une mécanique de jeu.
# ============================================================
extends Control

@export var avatar: CombattantCtbData = preload("res://data/combat_ctb/avatar.tres")
@export var ennemis: Array[CombattantCtbData] = [
	preload("res://data/combat_ctb/ennemi_moyen.tres"),
]
@export var avatar_empoisonne_sur_coup := true
@export var poison: StatutCtbData = preload("res://data/combat_ctb/statut_poison.tres")
@export var graine_rng := 0   # 0 = aléatoire ; sinon combat reproductible

func _ready() -> void:
	var m := CtbMoteur.new()
	if graine_rng != 0:
		m.rng.seed = graine_rng
	m.ajouter(avatar, Enums.CampCtb.JOUEUR)
	for e in ennemis.slice(0, 3):   # camp adverse : 1 à 3
		m.ajouter(e, Enums.CampCtb.ADVERSE)
	m.demarrer()
	while not m.termine and m.nb_activations < CtbMoteur.MAX_ACTIVATIONS:
		var c := m.activer_suivant()
		if c == null:
			continue
		var action := m.action_auto(c)
		m.jouer(action)
		# Démo du hook DoT : chaque coup de l'Avatar empoisonne sa cible.
		if avatar_empoisonne_sur_coup and c == m.avatar() and not m.termine:
			var cible := action.get("cible") as CtbCombattant
			if cible != null and cible.est_vivant():
				m.appliquer_statut(cible, poison, c)
	var texte := "\n".join(m.journal)
	print("\n=== SANDBOX COMBAT CTB ===\n" + texte + "\n")
	_afficher(texte)

# Affichage minimal du journal à l'écran (fenêtré) — pas une UI de jeu.
func _afficher(texte: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var label := Label.new()
	label.text = texte
	label.add_theme_font_size_override("font_size", 13)
	scroll.add_child(label)
