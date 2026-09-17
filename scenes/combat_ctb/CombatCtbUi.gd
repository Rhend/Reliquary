# ============================================================
# CombatCtbUi — Écran de combat CTB JOUABLE (Rework Combat, chantier 5).
#
# Écran scindé (référence Advanced Wars) : camp joueur à gauche, camp adverse
# à droite (jusqu'à 3 combattants par camp — architecture N-vs-N actée), fond
# scindé en diagonale purement COSMÉTIQUE (`CombatFondScinde` — décor RÉEL de
# Christophe côté joueur, biome placeholder `BiomeBackground` côté adverse,
# le Lieu n'ayant pas encore son propre art — CONSERVÉ à la demande de Rhend,
# la peau cyberpunk du chantier 10 habille le chrome par-dessus : panneaux
# opaques, tokens UIColors.CYBER_*, ExpeStyle). Scène de
# bataille : SOL + emplacements des sprites — le personnage principal est le
# sprite Spine RÉEL de Christophe (SpriteSpinePersonnage : Idle en boucle,
# Attack_CaC ou Attack_Shoot selon le GESTE de l'action ; retombe sur le
# placeholder si le runtime spine-godot manque) ; les adversaires restent des
# boules de lumière (EnergyBoule) en attendant leurs assets. L'attaque du
# JOUEUR déclenche un ZOOM-DUEL façon Darkest Dungeon : les deux personnages
# glissent au centre de l'écran face à face, punch-in fort (crit = plus
# marqué), puis retour — activations ennemies SANS effet de caméra ; seule la
# scène zoome, le chrome UI reste fixe. Un TIR (compétence à distance) garde
# le punch-in mais ne fait converger personne : il cadre le tireur et sa cible.
# DA finale hors scope (Christophe).
#
# Pilote un CtbMoteur DÉJÀ démarré, en pull-based :
#   • activation du camp joueur → attend l'input : Attaquer / Défendre /
#     COMPÉTENCES (chantier 16 — un bouton par compétence du combattant,
#     grisé « (n) » en recharge, absent s'il n'en a pas) / Objet (chantier 7 —
#     n'existe que si l'inventaire de run est non vide) ; Attaquer, une
#     compétence ciblée ou un objet ciblé → choix de cible parmi les ennemis
#     vivants (boutons ou clic sur la carte ennemie) ;
#   • activations ennemies : auto-résolues (IA du moteur), séquencées par de
#     courtes pauses pour rester lisibles.
#
# Lisibilité : file d'initiative des N_FILE prochaines activations (ordre
# seul, recalculée après chaque action via moteur.prevoir_ordre), PV +
# statuts par carte (CarteCombattantCtb), dégâts flottants distincts
# (normal / CRITIQUE / tick de DoT) via le signal structuré
# `moteur.evenement`, annonce d'embuscade à l'ouverture.
#
# Transitions placeholder : fondu noir en entrée (carte → combat) ; l'issue
# (VICTOIRE / DÉFAITE) s'affiche en fin de bataille, clic pour revenir à la
# carte → signal `fermee(recap)` (l'appelant libère l'écran ; la suite —
# reprise de run, Game Over — reste chez lui).
#
# `facteur_delais` : multiplicateur des pauses (1.0 jeu ; 0.0 = aucun délai
# ni clic de sortie — tests headless).
# ============================================================
class_name CombatCtbUi
extends Control

signal fermee(recap: Dictionary)

const N_FILE := 6              # activations prédites affichées (proposition actée)
const BANDE_VS_PX := 80.0      # largeur de la découpe diagonale des deux fonds
# Splash d'ouverture (« ENNEMY DETECTED », voir _intro) : tenue fixe puis fondu
# vers le combat (retour Rhend 07/09/2026 — 1 seconde, peu importe embuscade
# ou mécanique de Lieu à annoncer).
const DUREE_SPLASH_S := 1.0
const DUREE_FONDU_SPLASH_S := 0.45

# Boutons d'action en DEUX COLONNES encadrant le héros, reliées à son buste
# par un trait (chantier UI_Concept2, 07/09/2026 — le mockup fait foi :
# remplace l'ancien arc au-dessus de la tête). Indices pairs → colonne
# GAUCHE, impairs → DROITE (5 boutons ⇒ 3 gauche/2 droite, comme le mockup),
# chacune étalée verticalement entre l'épaule et la hanche du héros.
const ACTIONS_MARGE_PX := 64.0        # écart horizontal buste ↔ colonne de boutons
const ACTIONS_HAUT_FRAC := 0.88       # bord haut de l'étalement (fraction de la hauteur rendue)
const ACTIONS_BAS_FRAC := 0.30        # bord bas de l'étalement
# Trait de liaison bouton → buste (asset Cyber_Line livré mais figé : la
# géométrie ci-dessous est PROCÉDURALE, seule la couleur vient de l'asset —
# voir CombatUiSkin.couleur_lien) : coude horizontal → diagonal → petit
# cercle creux sur le POINT B. Depuis la livraison « Bone UI » (Christophe,
# 17/09/2026), le point B est l'un des deux os d'ancrage RÉELS du squelette
# (SpriteSpinePersonnage.position_os/OS_ANCRE_* — épée pour Attaquer,
# ceinture pour Objet), donc plus forcément à la même hauteur que le bouton
# (la diagonale devient un vrai segment, pas un artifice). LIEN_ANCRE_FRAC
# ci-dessous reste le REPLI (os absent : export sans la livraison, runtime
# spine-godot manquant, placeholder EnergyBoule).
#
# ⚠ RÉDUCTION TEMPORAIRE (retour Rhend 17/09/2026) : seuls DEUX os d'ancrage
# existent à ce jour (épée, ceinture) — Défendre et les Compétences n'en ont
# aucun à viser proprement. En attendant, `ACTIONS_LIMITEES_AUX_OS` MASQUE
# ces actions (le bouton Défendre reste dans l'arbre, juste invisible ; les
# boutons de Compétences ne sont simplement pas créés) — rien n'est
# supprimé côté moteur/logique, seul l'affichage est réduit à Attaquer/Objet.
# Repasser à false dès que d'autres os d'ancrage sont livrés.
const ACTIONS_LIMITEES_AUX_OS := true
const LIEN_EPAISSEUR_PX := 2.0
const LIEN_COUDE_PX := 26.0
const LIEN_RAYON_NOEUD_PX := 4.0
# Ancre de REPLI sur le buste : fraction de la largeur rendue du héros,
# depuis son centre — À L'INTÉRIEUR de la silhouette (pas à son bord), à LA
# MÊME HAUTEUR que le bouton. `largeur_rendue_px()` EXCLUT l'arme/VFX
# (hors_mesure, voir SpriteSpinePersonnage) : ACTIONS_MARGE_PX compense ce
# budget manquant pour que le bouton ne chevauche pas l'épée tenue au-dessus
# du corps mesuré.
const LIEN_ANCRE_FRAC := 0.34
# Puce carrée de la file d'initiative compacte (portraits, chantier UI_Concept2).
const TAILLE_PUCE_TOUR := 30.0

# Zoom-DUEL sur l'attaque du JOUEUR uniquement (recette Darkest Dungeon 1,
# resserrée — retour Rhend) : l'attaquant et sa cible GLISSENT au centre de
# l'écran face à face, comme pour un coup final, pendant que la scène
# punch-in fort ; tenue le temps du coup, puis chacun regagne son
# emplacement. Les activations ennemies n'ont AUCUN effet de caméra. Seule
# la scène (_couche_scene) bouge — le chrome UI reste fixe. Recette et
# constantes dans `DuelZoomFx` (26/08/2026, SOURCE PARTAGÉE avec la vitrine
# ShowRoom — jamais une copie).

var moteur: CtbMoteur
var embuscade := false
# Mécanique forte du Lieu à ANNONCER à l'intro ("" = rien — chantier 15).
# L'écran reste générique : c'est un id de clé Translations (« meca.<id> »),
# fourni par l'appelant ; l'effet lui-même vit dans le moteur (hooks).
var annonce_mecanique := ""
var facteur_delais := 1.0
# Récompenses du combat pour l'écran d'issue (chantier 6) : Callable SANS
# argument retournant {xp, euren} (ou {}) — fournie par l'appelant (le
# sandbox la branche sur ExpeRun.dernier_combat_recompenses). L'écran reste
# générique : il ne connaît ni l'expédition ni l'économie.
var recompenses_fournisseur := Callable()
# Consommables de run (chantier 7) — même pattern : l'inventaire vit chez
# l'appelant (ExpeRun). `inventaire_fournisseur` retourne
# Array[ConsommableData] ; `sur_objet_utilise` est notifiée au moment où
# l'action OBJET est validée (décrément — ExpeRun.consommer). Le bouton
# Objet n'EXISTE que si l'inventaire est non vide (pilier « contenu absent,
# pas grisé ») : recréé/retiré à chaque tour joueur.
var inventaire_fournisseur := Callable()
var sur_objet_utilise := Callable()

# Surcharges de PRÉVISUALISATION dev (ShowRoom UNIQUEMENT, 09/2026 — la
# vitrine est désormais CET écran, pas une copie, voir CLAUDE.md « la
# ShowRoom est un banc d'essai ») : posées par l'appelant avant `add_child`,
# comme `embuscade`/`facteur_delais` ci-dessus. -1 (ou 0 pour le cosmétique/
# la coiffure) = comportement du jeu réel — niveau d'équipement/Maîtrise
# RÉELS. N'affectent QUE le sprite choisi à la construction, jamais les
# stats ni le déroulé.
var previsu_niveau_heros := -1
var previsu_cosmetique_heros := 0
var previsu_coiffure_heros := 0
var previsu_palier_ennemi := -1

const SOL_Y_FRAC := 0.806          # ligne des pieds : MILIEU de la bande de sol du décor
const SOL_X_JOUEUR := 0.25         # ancrage des emplacements du camp joueur : CENTRE de sa moitié
const SOL_X_ADVERSE := 0.75        # ancrage du camp adverse — miroir exact du joueur
# Pas diagonal entre emplacements. Y RÉDUIT (46 -> 22) le 26/08/2026 : les pieds
# étant descendus au milieu du sol, un pas de 46 poussait le 3e ennemi (2 x 46)
# sous la barre d'action, qui est du chrome dessiné PAR-DESSUS la scène.
const SOL_PAS := Vector2(64, 22)
const ORBE_TAILLE := Vector2(64, 64)
# Barre de PV (CarteCombattantCtb) décalée plus BAS que son ancrage naturel
# aux pieds (retour Rhend 17/09/2026) — fraction de la hauteur de la scène,
# même dénominateur que SOL_Y_FRAC/ACTIONS_*_FRAC ci-dessus pour rester
# cohérent quelle que soit la résolution.
const CARTE_DECALAGE_BAS_FRAC := 0.05

# Voile de lumière AMBIANT par défaut (17/09/2026, voir _voile_previsu) —
# teinte froide quasi blanche, additive et douce : elle NE remplace aucune
# couleur du décor, elle en soulève juste l'exposition, comme une lumière de
# studio au-dessus de la scène. SOURCE UNIQUE : ShowRoom.NIVEAUX_LUMIERE
# (niveau « Studio ») pointe sur CES MÊMES constantes plutôt que de garder sa
# propre valeur — un seul réglage « lumière normale », qu'on le voie depuis le
# jeu réel ou depuis la vitrine dev. Un peu plus haut que l'ancien défaut
# ShowRoom (0.10 → 0.14) : suffisant pour sortir un palier Commun (gris
# terne) du quasi-noir sans blanchir les néons/le rouge du camp adverse.
const VOILE_TEINTE_DEFAUT := Color(0.78, 0.82, 0.90)
const VOILE_ALPHA_DEFAUT := 0.14

var _cartes: Dictionary = {}   # CtbCombattant → CarteCombattantCtb
# Vignette « tête/cou/cheveux » du héros GÉNÉRÉE à la volée pour la file
# d'initiative (voir _demarrer_generation_portrait_heros) — null tant que le
# rendu SubViewport (différé d'au moins une frame) n'est pas prêt, ou si
# aucun runtime spine-godot. Repli SOUS le fichier livré (`CombatUiSkin.
# portrait_heros`, prioritaire s'il existe un jour), lui-même au-dessus de
# l'initiale du nom (voir _portrait_pour).
var _portrait_heros_genere: Texture2D = null
var _couche_scene: Control = null   # couches zoomables (fonds + sol + sprites)
var _duel_tween: Tween = null
var _duel_restaure: Array = []      # paires [CanvasItem, position d'origine]
var _duel_acteurs: Array = []       # [attaquant, cible] du duel en cours
var _duel_ordre_restaure: Array = []   # [CanvasItem attaquant, index d'origine dans _sol]
# Ciblage À LA SOURIS dans la scène (retour Rhend 07/2026) : une zone de
# clic invisible par ennemi, ACTIVE seulement en mode ciblage — l'ennemi se
# choisit en le cliquant (scène ou carte), plus de rangée de boutons nominatifs.
var _zones_cible: Dictionary = {}   # CtbCombattant → Control (zone de clic)
var _cible_survolee: CtbCombattant = null
var _ciblage_actif := false
var _sol: Control = null       # scène : sol + emplacements des futurs sprites
# Voile de LUMIÈRE au-dessus du décor, EN DESSOUS des personnages (jamais sur
# eux — on éclaire le décor, jamais les personnages, dont le rendu Spine a
# déjà sa propre exposition). Posé à un niveau AMBIANT PAR DÉFAUT (voir
# VOILE_TEINTE_DEFAUT/VOILE_ALPHA_DEFAUT) — ⚠ RETOUR au 17/09/2026 (Rhend :
# « tout est assez sombre, travail propre d'highlight/ombre-lumière sur toute
# l'UI de combat ») : avant cette date, le voile démarrait TRANSPARENT (zéro
# lumière) et seule la ShowRoom le réglait (`previsu_definir_voile`,
# jamais appelé par le jeu réel) — la vitrine tournait donc TOUJOURS mieux
# éclairée que le vrai combat, qui rendait sa version la plus sombre possible
# par pur défaut de câblage, pas par choix de DA (CLAUDE.md notait déjà :
# « un fond quasi noir noie les paliers Commun » — un constat qui s'appliquait
# au jeu réel sans que personne ne l'y corrige). `previsu_definir_voile`
# (ShowRoom) reste un OVERRIDE possible par-dessus ce défaut, posé après coup.
var _voile_previsu: ColorRect = null
var _orbes: Dictionary = {}    # CtbCombattant → EnergyBoule (placeholder sprite)
var _sprites: Dictionary = {}  # CtbCombattant → SpriteSpinePersonnage (sprite RÉEL)
var _ombres: Dictionary = {}   # CtbCombattant → CombatOmbrePortee (ombre au sol, sous le sprite/orbe)
var _pieds: Dictionary = {}    # CtbCombattant → point d'appui au sol (dessin)
var _panneau_file: VBoxContainer
var _file_box: HBoxContainer
var _soulignement_file: Control
var _lbl_tour: Label
var _panneau_stats: CombatPanneauStats
# « Entité alliée en sélection » du panneau de stats — un seul allié possible
# aujourd'hui (l'avatar), câblé ici pour qu'un futur multi-héros n'ait qu'à
# réassigner CETTE variable (voir CombatPanneauStats).
var _entite_alliee_selectionnee: CtbCombattant = null
# Traits bouton → buste calculés par `_disposer_actions_deux_colonnes`,
# peints par `_dessiner_liens_actions` (voir CombatUiSkin.couleur_lien).
var _liens_actions: Array[Dictionary] = []
var _bandeaux: VBoxContainer
var _btn_attaquer: Button
var _btn_defendre: Button
var _btn_objet: Button = null          # créé au tour du joueur, grisé si inventaire vide
# Compétences (chantier 16) : boutons recréés à chaque tour joueur — absents
# si le combattant n'en a pas ; GRISÉS avec compteur pendant la recharge
# (état temporaire d'un contenu possédé — ≠ contenu absent).
var _btns_competences: Array[Button] = []
# Boutons d'action : Control de positionnement LIBRE (retour Rhend
# 07/09/2026, 2 colonnes encadrant le héros — voir
# _disposer_actions_deux_colonnes), plus une HBoxContainer classique.
var _rangee_boutons: Control
var _rangee_cibles: HBoxContainer
var _objet_en_attente: ConsommableData = null   # objet ciblé en attente de cible
var _competence_en_attente: CompetenceCtbData = null   # idem pour une compétence
var _fx: Control               # couche des textes flottants (plein écran)
var _voile: ColorRect          # fondu de transition + écran d'issue
var _voile_contenu: VBoxContainer
var _recap: Dictionary = {}
var _action_en_attente: Dictionary = {}
signal _action_choisie

func _init(m: CtbMoteur, avec_embuscade: bool = false) -> void:
	moteur = m
	embuscade = avec_embuscade

# Fabrique l'écran CÂBLÉ au combat en cours d'une run d'expédition —
# récompenses, inventaire, consommation, libération à la fermeture (câblage
# identique jeu réel / sandbox : UN point de vérité). L'écran lui-même reste
# générique : le contrat n'est fait QUE des Callables déjà publics.
# `data` = payload de combat_demarre (embuscade, mécanique de Lieu…) ;
# `sur_fermee` est appelée après libération (rafraîchissement chez l'appelant).
static func pour_run(run: ExpeRun, data: Dictionary, sur_fermee: Callable) -> CombatCtbUi:
	var ui := CombatCtbUi.new(run.combat_en_cours, bool(data.get("embuscade", false)))
	ui.annonce_mecanique = str(data.get("mecanique", ""))
	ui.recompenses_fournisseur = func() -> Dictionary:
		return run.dernier_combat_recompenses
	ui.inventaire_fournisseur = func() -> Array:
		return run.inventaire
	ui.sur_objet_utilise = func(objet: ConsommableData) -> void:
		run.consommer(objet)
	ui.fermee.connect(func(_r: Dictionary) -> void:
		ui.queue_free()
		sur_fermee.call())
	return ui

# Surcharge le voile de lumière au-delà de son niveau ambiant par défaut
# (VOILE_TEINTE_DEFAUT/VOILE_ALPHA_DEFAUT, posé par `_construire()`) — la
# ShowRoom s'en sert pour comparer les 4 niveaux d'éclairage (B). Sans effet
# si appelé avant `_construire()` (le voile n'existe pas encore) ; la
# ShowRoom l'appelle donc après `add_child`, comme le reste de son overlay dev.
func previsu_definir_voile(couleur: Color) -> void:
	if _voile_previsu != null:
		_voile_previsu.color = couleur

func _ready() -> void:
	# and_offsets : set_anchors_preset seul CONSERVE les offsets courants —
	# ajouté à un SubViewport (ScreenshotTool), l'écran restait en 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloque la carte en dessous
	_construire()
	CombatUiSkin.installer_curseur()
	tree_exiting.connect(CombatUiSkin.retirer_curseur)
	moteur.evenement.connect(_sur_evenement)
	moteur.victoire.connect(func(r: Dictionary) -> void: _recap = r)
	moteur.defaite.connect(func(r: Dictionary) -> void: _recap = r)
	_boucle()

# ─── Construction (100 % code — règle projet) ────────────────

# Sprite/ombre RÉELS d'UN combattant, ou repli EnergyBoule — factorisé hors
# de `_construire()` pour que `previsu_rafraichir_visuel` (hot-reload du
# palier/niveau/costume prévisualisés, ShowRoom) reconstruise EXACTEMENT le
# même visuel, sans dupliquer cette logique en deux endroits qui pourraient
# diverger. N'ajoute PAS la carte HUD (celle-ci ne dépend jamais de
# l'apparence, jamais reconstruite — voir `previsu_rafraichir_visuel`).
func _construire_visuel(cb: CtbCombattant) -> void:
	# Construit AVANT l'ombre (mais pas encore ajouté à l'arbre) pour pouvoir
	# mesurer sa largeur RENDUE réelle (`largeur_rendue_px`) — l'ombre doit
	# englober l'encombrement du personnage qu'elle porte, pas une taille
	# fixe pour tout le monde (retours Rhend 29/08/2026 : « aucune
	# corrélation entre la taille du sprite et l'ombre », puis « elle doit
	# englober la taille de l'entité »).
	var sprite: SpriteSpinePersonnage = null
	if cb == moteur.avatar():
		# creer_heros() et pas creer() : l'apparence vient du registre —
		# sans skin posée, l'export « costumes » de Relic est invisible.
		# `previsu_niveau_heros`/`previsu_cosmetique_heros`/`previsu_coiffure_
		# heros` : surcharge dev ShowRoom, -1 = comportement réel (Nv1, la
		# dotation de départ).
		var niveau_heros := previsu_niveau_heros if previsu_niveau_heros > 0 else 1
		sprite = SpriteSpinePersonnage.creer_heros(
				niveau_heros, previsu_cosmetique_heros, previsu_coiffure_heros)
		# Vignette de file d'initiative GÉNÉRÉE à la volée (retour Rhend
		# 17/09/2026) : portrait_heros() n'a aucun fichier livré pour le héros
		# à ce jour (contrairement aux ennemis) — tant que ça reste vrai,
		# `_portrait_pour` retombe sur l'initiale. Fire-and-forget, EXACTEMENT
		# la même apparence que le sprite ci-dessus.
		_demarrer_generation_portrait_heros(niveau_heros, previsu_cosmetique_heros,
				previsu_coiffure_heros)
	else:
		# Ennemi : même registre / même apparence que la ShowRoom, qui EST
		# cet écran depuis 09/2026 (voir CLAUDE.md « la ShowRoom est un
		# banc d'essai ») — {} tant que sa livraison Spine n'existe pas
		# encore, repli sur EnergyBoule ci-dessous.
		sprite = _creer_sprite_ennemi(cb)
	var largeur_ref := ORBE_TAILLE.x
	if sprite != null:
		var l := sprite.largeur_rendue_px()
		if l > 0.0:
			largeur_ref = l
	# Ombre portée AVANT le sprite/orbe : l'ordre d'ajout EST l'ordre de
	# dessin dans Godot, donc l'ombre reste sous le personnage sans jouer
	# avec le z-index (voir CombatOmbrePortee).
	var ombre := CombatOmbrePortee.creer(cb.est_joueur(), largeur_ref)
	if ombre != null:
		_ombres[cb] = ombre
		_sol.add_child(ombre)
	if sprite != null:
		_sprites[cb] = sprite
		_sol.add_child(sprite)
	else:
		var orbe := EnergyBoule.new()
		orbe.accent = ExpeStyle.accent_camp(cb.est_joueur())
		orbe.size = ORBE_TAILLE
		_orbes[cb] = orbe
		_sol.add_child(orbe)
		# Placeholder de sprite, pas un élément interactif (EnergyBoule
		# est cliquable par défaut au Village) : souris ignorée.
		orbe.mouse_filter = Control.MOUSE_FILTER_IGNORE

# Hot-reload du VISUEL prévisualisé (ShowRoom UNIQUEMENT, retour Rhend :
# « t'es obligé de reload le combat ? ») : ↑/↓/H/V ne changent QUE le skin
# affiché, JAMAIS les stats (le palier ennemi prévisualisé ne touche pas
# `CtbPont.combattant_depuis_entite`, qui reste sur la Maîtrise réelle) — le
# moteur, les PV en cours, l'ordre d'initiative n'ont donc aucune raison de
# bouger. `pour_ennemi` borne le rafraîchissement à un camp : changer le
# costume du héros ne doit jamais retoucher l'ennemi, et réciproquement.
# Change de CRÉATURE (←/→) reste une reconstruction complète côté ShowRoom
# (`_lancer_duel`) : ça change les stats réelles, donc le combattant du
# moteur lui-même — pas un simple habillage.
func previsu_rafraichir_visuel(pour_ennemi: bool) -> void:
	if _sol == null:
		return
	for cb in moteur.combattants:
		if cb.est_joueur() == pour_ennemi:
			continue
		var carte: CarteCombattantCtb = _cartes.get(cb)
		for dico: Dictionary in [_ombres, _sprites, _orbes]:
			if dico.has(cb):
				var ancien: Node = dico[cb]
				_sol.remove_child(ancien)
				ancien.queue_free()
				dico.erase(cb)
		_construire_visuel(cb)
		# Réinsère juste AVANT la carte de CE combattant — ombre < sprite <
		# carte, comme à la construction initiale. Le reste de l'arbre (les
		# autres combattants) n'a pas bougé.
		if carte != null:
			if _ombres.has(cb):
				_sol.move_child(_ombres[cb], carte.get_index())
			var noeud := _noeud_bataille(cb)
			if noeud != null:
				_sol.move_child(noeud, carte.get_index())
	_placer_orbes()
	# La puce de file d'initiative de ce combattant porte le même portrait
	# que son sprite (`_portrait_pour`) : sans ce rafraîchissement, elle
	# resterait sur l'ancien palier/niveau après un hot-reload.
	_rafraichir_file()

func _construire() -> void:
	# Fond scindé : décor RÉEL de Christophe côté joueur, biome placeholder
	# côté adverse (`CombatFondScinde`, PARTAGÉ avec la vitrine ShowRoom —
	# une seule source, jamais deux copies qui divergent). RESTAURÉ à la
	# demande de Rhend après la passe cyberpunk : le fond reste visible, la
	# peau habille le chrome PAR-DESSUS (panneaux opaques).
	# Conteneur ZOOMABLE de la scène de bataille (fonds + diagonale + sol +
	# sprites) : le zoom d'attaque façon Darkest Dungeon ne scale que lui —
	# le chrome UI (file, cartes, actions, FX) reste fixe par-dessus.
	_couche_scene = Control.new()
	_couche_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_couche_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_couche_scene)
	CombatFondScinde.construire(_couche_scene, SOL_Y_FRAC, SOL_X_JOUEUR, BANDE_VS_PX)

	# Voile de lumière — posé APRÈS le décor, AVANT `_sol` (donc sous les
	# personnages) : ordre d'ajout = ordre de dessin. Part du niveau AMBIANT
	# PAR DÉFAUT (voir VOILE_TEINTE_DEFAUT/VOILE_ALPHA_DEFAUT ci-dessus) — le
	# jeu réel n'a plus besoin d'appeler quoi que ce soit pour être éclairé ;
	# `previsu_definir_voile` (ShowRoom) reste libre de le régler PAR-DESSUS.
	_voile_previsu = ColorRect.new()
	_voile_previsu.color = Color(VOILE_TEINTE_DEFAUT, VOILE_ALPHA_DEFAUT)
	_voile_previsu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_voile_previsu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_couche_scene.add_child(_voile_previsu)

	# Scène de bataille : SOL + emplacements des futurs sprites de personnages
	# (placeholder : boules de lumière — retour Rhend, chantier 10).
	_sol = Control.new()
	_sol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sol.draw.connect(_dessiner_sol)
	_sol.resized.connect(_placer_orbes)
	_couche_scene.add_child(_sol)
	for cb in moteur.combattants:
		_construire_visuel(cb)
		# HUD compact (PV + statuts) SOUS LES PIEDS de CE combattant — chantier
		# UI_Concept2 (07/09/2026, le mockup fait foi) : plus de carte en
		# colonne latérale. Ajoutée APRÈS le sprite/orbe pour rester visible
		# par-dessus lui ; positionnée par `_placer_orbes()`.
		var carte := CarteCombattantCtb.new(cb)
		_cartes[cb] = carte
		_sol.add_child(carte)
	# Zones de CLIC des ennemis (ciblage à la souris) : invisibles, posées
	# sur l'emplacement du personnage, dormantes hors mode ciblage.
	for cb in moteur.combattants:
		if cb.est_joueur():
			continue
		var zone := Control.new()
		zone.size = Vector2(96, 116)
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		zone.gui_input.connect(_sur_zone_input.bind(cb))
		zone.mouse_entered.connect(_sur_zone_survol.bind(cb, true))
		zone.mouse_exited.connect(_sur_zone_survol.bind(cb, false))
		_sol.add_child(zone)
		_zones_cible[cb] = zone
	_placer_orbes()

	# Panneau de stats détaillé, bas-gauche (chantier UI_Concept2) : lié à
	# l'« entité alliée en sélection » — un seul allié possible aujourd'hui,
	# voir `_entite_alliee_selectionnee` et `CombatPanneauStats`.
	_entite_alliee_selectionnee = moteur.avatar()
	_panneau_stats = CombatPanneauStats.creer(true)
	add_child(_panneau_stats)
	_panneau_stats.definir_combattant(_entite_alliee_selectionnee)
	_repositionner_panel_stats()

	# File d'initiative compacte, HAUT-DROITE (chantier UI_Concept2 : rangée
	# HORIZONTALE de puces carrées façon portraits, plus de colonne de noms en
	# toutes lettres ni de gros panneau bordé — le mockup n'en a pas).
	# Repositionné À LA MAIN (`_repositionner_panneau_file`, pas un ancrage
	# posé une fois) : son contenu n'existe pas encore ici, il arrive via
	# `_rafraichir_file()` — un ancrage figé se serait retrouvé à agrandir la
	# boîte HORS ÉCRAN vers la droite au premier remplissage.
	_panneau_file = VBoxContainer.new()
	_panneau_file.add_theme_constant_override("separation", 4)
	_panneau_file.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panneau_file)
	_file_box = HBoxContainer.new()
	_file_box.add_theme_constant_override("separation", 4)
	_file_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panneau_file.add_child(_file_box)
	# Soulignement décoratif (retour Rhend : « il manque le sprite qui
	# souligne la zone d'initiative ») — même langage que les traits
	# bouton → buste (coude + cercle creux, couleur de Cyber_Line), pour lier
	# visuellement la rangée de puces au compteur de tour en dessous.
	_soulignement_file = Control.new()
	_soulignement_file.custom_minimum_size = Vector2(TAILLE_PUCE_TOUR + LIEN_COUDE_PX, 12.0)
	_soulignement_file.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_soulignement_file.draw.connect(_dessiner_soulignement_file)
	_panneau_file.add_child(_soulignement_file)
	var tour_box := HBoxContainer.new()
	tour_box.add_theme_constant_override("separation", 4)
	tour_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panneau_file.add_child(tour_box)
	var chevron := TextureRect.new()
	chevron.texture = CombatUiSkin.CHEVRON
	chevron.custom_minimum_size = Vector2(14, 14)
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tour_box.add_child(chevron)
	_lbl_tour = ExpeStyle.label_mono("", 13, UIColors.CYBER_ACCENT)
	tour_box.add_child(_lbl_tour)
	_repositionner_panneau_file()

	# Boutons d'action : Control à positionnement LIBRE, en 2 colonnes
	# encadrant le héros (voir _disposer_actions_deux_colonnes) — la barre
	# dédiée du bas n'a plus lieu d'être, Christophe fait apparaître les
	# actions à même la scène. `_rangee_cibles` (invite + Annuler du ciblage,
	# choix d'objet) reste un simple bandeau flottant, sans le gros panneau
	# qui le portait avant — plus d'annonce « Au tour de … » (retour Rhend :
	# sans intérêt, redondant avec les boutons qui apparaissent).
	_rangee_boutons = Control.new()
	_rangee_boutons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rangee_boutons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rangee_boutons.draw.connect(_dessiner_liens_actions)
	add_child(_rangee_boutons)
	_btn_attaquer = CombatUiSkin.bouton(Translations.T("ctb.attaquer"))
	_btn_attaquer.pressed.connect(_sur_attaquer)
	_rangee_boutons.add_child(_btn_attaquer)
	_btn_defendre = CombatUiSkin.bouton(Translations.T("ctb.defendre"))
	_btn_defendre.pressed.connect(func() -> void:
		_valider_action({"type": Enums.ActionCtb.DEFENDRE}))
	_rangee_boutons.add_child(_btn_defendre)
	# PAS de bouton Objet ici : il n'existe que si l'inventaire de run est
	# non vide, recréé à chaque tour joueur (_montrer_actions).

	_bandeaux = VBoxContainer.new()
	_bandeaux.add_theme_constant_override("separation", 4)
	add_child(_bandeaux)
	_rangee_cibles = HBoxContainer.new()
	_rangee_cibles.alignment = BoxContainer.ALIGNMENT_CENTER
	_rangee_cibles.add_theme_constant_override("separation", 8)
	_bandeaux.add_child(_rangee_cibles)
	_repositionner_bandeaux()
	_montrer_actions(false)

	# Couche FX (dégâts flottants) au-dessus de tout le contenu de jeu.
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	# PAS de scanlines ici (retiré 17/09/2026, retour Rhend : « enlève le
	# [filtre scanlines] concernant les combats ») — le reste de la peau
	# cyberpunk (expédition, panneau de lancement, écrans de message) les
	# garde, voir ExpeStyle.scanlines.

	# Voile de transition (début / fin de bataille) — au-dessus de tout.
	_voile = ColorRect.new()
	_voile.color = Color(0, 0, 0, 1)
	_voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_voile)
	_voile_contenu = VBoxContainer.new()
	_voile_contenu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_voile_contenu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_voile_contenu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_voile_contenu.alignment = BoxContainer.ALIGNMENT_CENTER
	_voile.add_child(_voile_contenu)

# Sprite Spine RÉEL d'un ennemi si son entrée existe au registre — MÊME
# apparence/orientation que la ShowRoom (banc d'essai partagé, voir CLAUDE.md
# « la ShowRoom est un banc d'essai, pas une fin ») : sens d'export lu du
# registre (`echelle_x(entree, false)` — camp adverse regarde vers la
# GAUCHE), hauteur cible = son chara design (`hauteur_cible_px`). Le palier
# affiché suit la Maîtrise RÉELLE de la créature (`maitrise_actuelle`,
# 0=Commun..4=Légendaire — mêmes indices que les 5 skins de palier) : deux
# WorkBot au même combat peuvent donc ne pas avoir la même apparence si leur
# progression diverge. `previsu_palier_ennemi` (ShowRoom) force un palier au
# lieu de la Maîtrise réelle — -1 = comportement réel. null tant que la
# livraison Spine de cette créature n'existe pas (registre vide pour son id)
# — l'appelant retombe sur EnergyBoule, exactement comme avant ce branchement.
func _creer_sprite_ennemi(cb: CtbCombattant) -> SpriteSpinePersonnage:
	var entree := SpinePersonnagesData.par_id(cb.data.id)
	if entree.is_empty():
		return null
	var apparences := SpinePersonnagesData.apparences(entree)
	if apparences.is_empty():
		return null
	var sprite := SpriteSpinePersonnage.creer(str(entree.get("skel", "")),
			str(entree.get("atlas", "")),
			apparences[clampi(_palier_ennemi(cb), 0, apparences.size() - 1)],
			SpinePersonnagesData.hauteur_cible_px(entree))
	if sprite != null:
		sprite.orienter(SpinePersonnagesData.echelle_x(entree, false))
	return sprite

# Palier AFFICHÉ d'un ennemi (skin Spine ET portrait de file) : la Maîtrise
# réelle de la créature, sauf surcharge dev `previsu_palier_ennemi`
# (ShowRoom, jamais posée par le jeu réel). Centralisé pour que le sprite et
# le portrait ne puissent jamais afficher deux paliers différents.
func _palier_ennemi(cb: CtbCombattant) -> int:
	return previsu_palier_ennemi if previsu_palier_ennemi >= 0 \
			else int(GameData.get_entity(cb.data.id).get("maitrise_actuelle", 0))

# Portrait d'UN combattant pour sa puce de file d'initiative — même source
# que son sprite : le héros suit son niveau d'équipement prévisualisé/réel,
# l'ennemi son palier réel/prévisualisé (`_palier_ennemi`, PARTAGÉ avec
# `_creer_sprite_ennemi`). Héros : fichier livré prioritaire (`CombatUiSkin.
# portrait_heros`, toujours null à ce jour — aucune livraison), sinon la
# vignette GÉNÉRÉE (`_portrait_heros_genere`, voir _demarrer_generation_
# portrait_heros). `null` si ni l'un ni l'autre n'est disponible — l'appelant
# (`_rafraichir_file`) retombe sur l'initiale du nom.
func _portrait_pour(cb: CtbCombattant) -> Texture2D:
	if cb == moteur.avatar():
		var niveau := previsu_niveau_heros if previsu_niveau_heros > 0 else 1
		var livre := CombatUiSkin.portrait_heros(niveau)
		return livre if livre != null else _portrait_heros_genere
	var entree := SpinePersonnagesData.par_id(cb.data.id)
	if entree.is_empty():
		return null
	return CombatUiSkin.portrait_ennemi(str(entree.get("nom", "")), _palier_ennemi(cb))

# Lance en tâche de fond la génération de la vignette « tête/cou/cheveux » du
# héros (retour Rhend 17/09/2026 — voir _portrait_heros_genere). Fire-and-
# forget : le rendu SubViewport est DIFFÉRÉ d'au moins une frame
# (CombatUiSkin.generer_portrait_heros), `_portrait_pour` retombe sur
# l'initiale en attendant ; une fois prête, on rafraîchit juste la file pour
# la faire apparaître, sans reconstruire l'écran. Mise en cache côté
# CombatUiSkin (niveau/cosmétique/coiffure) : gratuit dès la 2e fois pour la
# même apparence, y compris d'un combat à l'autre.
func _demarrer_generation_portrait_heros(niveau: int, cosmetique: int, coiffure: int) -> void:
	var tex := await CombatUiSkin.generer_portrait_heros(niveau, cosmetique, coiffure, self)
	if tex == null or not is_inside_tree():
		return
	_portrait_heros_genere = tex
	_rafraichir_file()

# Panneau de stats : PLAQUÉ contre le bord bas-gauche de l'écran, sa largeur
# forcée jusqu'au trait de séparation (retour Rhend : « doit prendre tout le
# bas de la partie de gauche et doit être coupé par le trait ») — même
# formule que la coupure holographique (`CombatFondScinde.x_frontiere`),
# évaluée à `size.y` (le bas de l'écran, où la diagonale est la PLUS À
# GAUCHE) pour qu'AUCUNE portion du panneau ne déborde dans le camp adverse
# sur toute sa hauteur. `reset_size()` d'abord pour la hauteur NATURELLE
# (varie avec le nombre de statuts actifs de l'entité suivie), puis la
# largeur est ÉCRASÉE — `clip_contents` (CombatPanneauStats) protège si le
# contenu ne tenait quand même pas.
func _repositionner_panel_stats() -> void:
	if _panneau_stats == null:
		return
	_panneau_stats.reset_size()
	var largeur := CombatFondScinde.x_frontiere(size.y, size.y, size.x, BANDE_VS_PX)
	_panneau_stats.size = Vector2(largeur, _panneau_stats.size.y)
	_panneau_stats.position = Vector2(0.0, size.y - _panneau_stats.size.y)

# Recale la file d'initiative en HAUT-DROITE sur SA taille minimale COURANTE
# (`reset_size()`) — appelé à chaque changement de contenu (`_rafraichir_
# file`), jamais un ancrage posé une fois : un Control hors d'un Container
# grandit toujours vers le bas-droite quand son contenu grossit, jamais vers
# une ancre, un panneau ancré à droite avant l'arrivée des chips finirait
# hors écran au premier remplissage.
func _repositionner_panneau_file() -> void:
	if _panneau_file == null:
		return
	_panneau_file.reset_size()
	_panneau_file.position = Vector2(size.x - _panneau_file.size.x - 10.0, 10.0)

# Même correctif pour le bandeau de tour + la rangée de ciblage : centré en
# bas, recalé à chaque changement (texte du tour, invite/Annuler, liste
# d'objets). Tenu AU-DESSUS du panneau de stats (bas-gauche, largeur variable
# selon les statuts actifs) — centré sur tout l'écran, il chevaucherait sinon
# son coin droit.
func _repositionner_bandeaux() -> void:
	if _bandeaux == null:
		return
	_bandeaux.reset_size()
	var marge_bas := 12.0
	if _panneau_stats != null:
		marge_bas = _panneau_stats.size.y + 20.0
	_bandeaux.position = Vector2((size.x - _bandeaux.size.x) * 0.5, size.y - _bandeaux.size.y - marge_bas)

# ─── Scène de bataille : sol + emplacements (placeholder sprites) ──

# Emplacements des FUTURS sprites de personnages, posés sur le sol —
# placeholder : boules de lumière (EnergyBoule) aux accents de camp.
func _placer_orbes() -> void:
	# `resized` peut tirer PENDANT add_child(_sol), avant la création des orbes.
	if _sol == null or _sol.size.x <= 0.0 or (_orbes.is_empty() and _sprites.is_empty()):
		return
	# Resize pendant un duel : les positions d'origine capturées par le tween
	# seraient obsolètes — on coupe net, chacun sera replacé juste dessous.
	_duel_interrompre()
	_pieds.clear()
	for camp_joueur in [true, false]:
		var membres: Array[CtbCombattant] = []
		for cb in moteur.combattants:
			if cb.est_joueur() == camp_joueur:
				membres.append(cb)
		var base_x: float = _sol.size.x * (SOL_X_JOUEUR if camp_joueur else SOL_X_ADVERSE)
		var dir := -1.0 if camp_joueur else 1.0
		for i in membres.size():
			var t := float(i) - float(membres.size() - 1) * 0.5
			var pied := Vector2(base_x + dir * t * SOL_PAS.x,
					_sol.size.y * SOL_Y_FRAC + t * SOL_PAS.y)
			_pieds[membres[i]] = pied
			var noeud := _noeud_bataille(membres[i])
			if noeud != null:
				noeud.position = _pos_depuis_pied(membres[i], pied)
			var ombre: CombatOmbrePortee = _ombres.get(membres[i])
			if ombre != null:
				ombre.position = pied
			var zone: Control = _zones_cible.get(membres[i])
			if zone != null:
				zone.position = pied - Vector2(zone.size.x * 0.5, zone.size.y - 12.0)
			var carte: CarteCombattantCtb = _cartes.get(membres[i])
			if carte != null:
				carte.definir_position(pied, _sol.size.y * CARTE_DECALAGE_BAS_FRAC)
	_sol.queue_redraw()

# Sol de la scène : la ligne d'horizon + bande dégradée qui vivait ici avant
# (chrome peint par-dessus le décor, pensé pour un sol sans art réel) est
# SUPPRIMÉE : posée sur le vrai décor de ville, elle se lisait comme un trait
# diffus non voulu en travers de tout le côté joueur, pile sous les pieds de
# Relic (signalé par Rhend). Le décor réel (`CombatDecorCity`) porte déjà son
# propre trottoir. Même correctif déjà appliqué à la ShowRoom (26 et
# 27/08/2026). L'ellipse-repère qui vivait ensuite ici sous chaque placeholder
# EnergyBoule est ELLE AUSSI retirée (29/08/2026) : remplacée par la vraie
# ombre portée de Christophe (`CombatOmbrePortee`, sprite au sol sous CHAQUE
# combattant, sprite Spine compris — plus une exception pour le placeholder).
func _dessiner_sol() -> void:
	if _sol.size.x <= 0.0:
		return
	# Mode ciblage (retour Rhend 07/2026) : l'ennemi se choisit à la souris
	# dans la scène — anneau OR discret sur chaque cible possible, réticule
	# marqué + chevron sur la cible survolée (même or que les cartes :
	# un seul langage « ciblable » dans tout l'écran).
	if _ciblage_actif:
		for cb: CtbCombattant in _zones_cible:
			if not cb.est_vivant() or not _pieds.has(cb):
				continue
			var pied: Vector2 = _pieds[cb]
			var fort := cb == _cible_survolee
			_sol.draw_set_transform(pied, 0.0, Vector2(1.0, 0.38))
			_sol.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 40,
					Color(UIColors.SELECTION_GOLD, 0.90 if fort else 0.35),
					2.5 if fort else 1.0)
			if fort:
				_sol.draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 40,
						Color(UIColors.SELECTION_GOLD, 0.35), 1.0)
			_sol.draw_set_transform(Vector2.ZERO)
			if fort:
				# Réticule RÉEL (Icone_Arrow_2, Christophe) — remplace le "▼"
				# ASCII ; couleur native de l'icône, l'anneau or ci-dessus
				# reste le signal « ciblable » du langage projet.
				_sol.draw_texture_rect(CombatUiSkin.RETICULE,
						Rect2(pied + Vector2(-12.0, -92.0), Vector2(24.0, 24.0)), false)

# Un personnage mort disparaît de la scène (l'ellipse d'emplacement reste) ;
# un sprite Spine joue son animation Death et TIENT la pose (pas de fondu) —
# idempotent, couvre tous les chemins de mort (attaque, DoT).
# Pendant un duel, les DEUX acteurs gardent leur alpha : le coup fatal doit se
# JOUER à l'écran (glissement + tenue) — le fondu du vaincu est réappliqué à
# la fin du duel (tween.finished → _rafraichir_orbes).
func _rafraichir_orbes() -> void:
	for cb: CtbCombattant in _orbes:
		if _duel_tween != null and cb in _duel_acteurs:
			continue
		(_orbes[cb] as EnergyBoule).modulate.a = 1.0 if cb.est_vivant() else 0.10
	for cb: CtbCombattant in _sprites:
		if not cb.est_vivant():
			(_sprites[cb] as SpriteSpinePersonnage).jouer_mort()

# ─── Boucle de combat (pull-based, asynchrone) ───────────────

func _boucle() -> void:
	await _intro()
	while not moteur.termine and is_inside_tree():
		_rafraichir_tout()
		var c := moteur.activer_suivant()
		_rafraichir_tout()   # les ticks DÉBUT (Saignement) sont déjà passés
		if moteur.termine:
			break
		if c == null:
			await _pause(0.5)   # activation consommée (mort au tick DÉBUT)
			continue
		_marquer_actif(c)
		if c.est_joueur():
			_montrer_actions(true, c)
			await _action_choisie
			if not is_inside_tree():
				return
			_montrer_actions(false)
			moteur.jouer(_action_en_attente)
		else:
			await _pause(0.55)   # séquencement lisible des activations ennemies
			if not is_inside_tree():
				return
			moteur.jouer(moteur.action_auto(c))
		_marquer_actif(null)
		_rafraichir_tout()
		await _pause(0.35)
	if is_inside_tree():
		await _outro()

# ─── Actions du joueur ───────────────────────────────────────

func _montrer_actions(on: bool, acteur: CtbCombattant = null) -> void:
	_btn_attaquer.visible = on
	# Défendre MASQUÉ tant qu'ACTIONS_LIMITEES_AUX_OS tient (voir la constante) :
	# pas d'os d'ancrage à lui viser proprement pour l'instant.
	_btn_defendre.visible = on and not ACTIONS_LIMITEES_AUX_OS
	_objet_en_attente = null
	_competence_en_attente = null
	# Compétences (chantier 16) : un bouton par compétence du combattant
	# actif — recréés à chaque tour (le cooldown a pu bouger), grisés « (n) »
	# en recharge, ABSENTS si le combattant n'en a pas. Toujours CRÉÉS (la
	# logique/les tests qui les actionnent restent valables) mais MASQUÉS
	# tant qu'ACTIONS_LIMITEES_AUX_OS tient — pas d'os d'ancrage pour eux —
	# et exclus des colonnes/traits (voir plus bas), même traitement que
	# Défendre.
	for b in _btns_competences:
		_rangee_boutons.remove_child(b)
		b.queue_free()
	_btns_competences.clear()
	if on and acteur != null:
		for comp: CompetenceCtbData in acteur.data.competences:
			var nom := Translations.resource_name(comp, comp.id)
			var prete := acteur.competence_prete(comp)
			var b := CombatUiSkin.bouton(
					nom if prete else "%s (%d)" % [nom, acteur.cooldown_restant(comp)])
			b.disabled = not prete
			b.visible = not ACTIONS_LIMITEES_AUX_OS
			b.pressed.connect(_sur_competence.bind(comp))
			_rangee_boutons.add_child(b)
			_btns_competences.append(b)
	# Bouton Objet : TOUJOURS présent au tour du joueur (retour Rhend
	# 17/09/2026 — supersède l'ancienne règle « contenu absent, pas grisé » :
	# l'action a désormais un os d'ancrage réel à viser (la ceinture), un
	# trait qui apparaît/disparaît avec le bouton n'a plus de sens). GRISÉ
	# si l'inventaire de run est vide OU absent (ShowRoom/sandbox sans run
	# réelle : `inventaire_fournisseur` invalide) — même langage que les
	# compétences en recharge, recréé à chaque tour (le contenu a pu changer).
	if _btn_objet != null:
		_rangee_boutons.remove_child(_btn_objet)
		_btn_objet.queue_free()
		_btn_objet = null
	if on:
		var inv: Array = inventaire_fournisseur.call() if inventaire_fournisseur.is_valid() else []
		_btn_objet = CombatUiSkin.bouton(Translations.T("ctb.objet"))
		_btn_objet.disabled = inv.is_empty()
		_btn_objet.pressed.connect(_sur_objet)
		_rangee_boutons.add_child(_btn_objet)
	UIHelpers.clear_children_now(_rangee_cibles)
	if on:
		var visibles: Array = [_btn_attaquer]
		if not ACTIONS_LIMITEES_AUX_OS:
			visibles.append(_btn_defendre)
			visibles.append_array(_btns_competences)
		if _btn_objet != null:
			visibles.append(_btn_objet)
		_disposer_actions_deux_colonnes(visibles)
	if not on:
		_mettre_cibles_en_avant(false)
		_liens_actions.clear()
		if _rangee_boutons != null:
			_rangee_boutons.queue_redraw()
	_repositionner_bandeaux()

# Boutons d'action en 2 COLONNES encadrant le buste du héros (retour Rhend,
# chantier UI_Concept2 — le mockup fait foi, remplace l'ancien arc au-dessus
# de la tête). Indices pairs → colonne GAUCHE, impairs → DROITE (5 boutons ⇒
# 3 gauche/2 droite, comme le mockup Attack/Block/Move | Object/Capacity),
# chacune étalée verticalement entre l'épaule et la hanche. Calcule ET
# stocke un segment de trait par bouton (`_liens_actions`), peint ensuite par
# `_dessiner_liens_actions` — `reset_size()` d'abord, la largeur des boutons
# varie avec leur texte (compétences grisées « (n) », objets « ×N »).
#
# Point B RÉEL depuis la livraison « Bone UI » (Christophe, 17/09/2026) :
# le trait de chaque bouton vise l'un des deux os d'ancrage du squelette
# (SpriteSpinePersonnage.OS_ANCRE_* — épée pour Attaquer, ceinture pour
# Objet — SEULES actions affichées tant qu'ACTIONS_LIMITEES_AUX_OS tient,
# voir plus haut), chacun un point FIXE (là où le personnage porte
# réellement son arme/sa ceinture), ce qui rend la seconde moitié du trait
# (coude → point B) diagonale pour de vrai. Repli sur l'ancienne ancre
# procédurale (fraction de largeur, à la hauteur du bouton) si l'os est
# absent (export sans la livraison, runtime spine-godot manquant,
# placeholder EnergyBoule).
func _disposer_actions_deux_colonnes(boutons: Array) -> void:
	_liens_actions.clear()
	if boutons.is_empty() or _sol == null or _sol.size.x <= 0.0:
		if _rangee_boutons != null:
			_rangee_boutons.queue_redraw()
		return
	var avatar := moteur.avatar()
	var pied: Vector2 = _pieds.get(avatar,
			Vector2(_sol.size.x * SOL_X_JOUEUR, _sol.size.y * SOL_Y_FRAC))
	var hauteur := ORBE_TAILLE.y
	var largeur := ORBE_TAILLE.x
	var sprite: SpriteSpinePersonnage = _sprites.get(avatar)
	var ancre_attaque := Vector2.ZERO
	var ancre_objet := Vector2.ZERO
	if sprite != null:
		var h := sprite.hauteur_rendue_px()
		if h > 0.0:
			hauteur = h
		var l := sprite.largeur_rendue_px()
		if l > 0.0:
			largeur = l
		ancre_attaque = sprite.position_os(SpriteSpinePersonnage.OS_ANCRE_ATTAQUE)
		ancre_objet = sprite.position_os(SpriteSpinePersonnage.OS_ANCRE_OBJET)
	var haut := pied.y - hauteur * ACTIONS_HAUT_FRAC
	var bas := pied.y - hauteur * ACTIONS_BAS_FRAC
	var n := boutons.size()
	# Hauteur tirée de l'index GLOBAL (pas d'un compteur par colonne) : les
	# deux colonnes échantillonnent des crans ALTERNÉS sur le même étalement
	# vertical, donc se décalent naturellement l'une par rapport à l'autre —
	# la symétrie miroir (mêmes hauteurs des deux côtés) ne suit PAS le
	# mockup, où les colonnes sont visiblement décalées (retour Rhend).
	for i in n:
		var a_droite := i % 2 == 1
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var y := lerpf(haut, bas, t)
		var x := pied.x + (1.0 if a_droite else -1.0) * (largeur * 0.5 + ACTIONS_MARGE_PX)
		var b: Control = boutons[i]
		b.reset_size()
		var centre := Vector2(x, y)
		b.position = centre - b.size * 0.5
		var bord_x := centre.x - b.size.x * 0.5 if a_droite else centre.x + b.size.x * 0.5
		var ancre := ancre_objet if b == _btn_objet else ancre_attaque
		var arrivee := ancre
		if ancre == Vector2.ZERO:
			var ancre_x := pied.x + (1.0 if a_droite else -1.0) * largeur * LIEN_ANCRE_FRAC
			arrivee = Vector2(ancre_x, y)
		_liens_actions.append({
			"depart": Vector2(bord_x, y), "arrivee": arrivee, "a_droite": a_droite,
		})
	if _rangee_boutons != null:
		_rangee_boutons.queue_redraw()

# Coude horizontal → diagonal → petit cercle creux (langage visuel de
# UI_Combat_Cyber_Line.png, dont la COULEUR vient de CombatUiSkin.
# couleur_lien — mais dont la GÉOMÉTRIE est procédurale : un angle figé ne se
# stretch pas vers une cible arbitraire). Le pas horizontal du coude est
# borné à la moitié du trajet : jamais de dépassement de l'ancre, même sur un
# personnage/bouton très rapprochés.
func _dessiner_liens_actions() -> void:
	if _rangee_boutons == null or _liens_actions.is_empty():
		return
	var couleur := CombatUiSkin.couleur_lien()
	for lien: Dictionary in _liens_actions:
		var depart: Vector2 = lien["depart"]
		var arrivee: Vector2 = lien["arrivee"]
		var dx := arrivee.x - depart.x
		var pas := clampf(absf(dx) * 0.5, 0.0, LIEN_COUDE_PX)
		var coude := Vector2(depart.x + signf(dx) * pas, depart.y)
		_rangee_boutons.draw_line(depart, coude, couleur, LIEN_EPAISSEUR_PX, true)
		_rangee_boutons.draw_line(coude, arrivee, couleur, LIEN_EPAISSEUR_PX, true)
		_rangee_boutons.draw_arc(arrivee, LIEN_RAYON_NOEUD_PX, 0.0, TAU, 16, couleur,
				LIEN_EPAISSEUR_PX, true)

# Même langage visuel (coude + cercle creux) que les traits d'action, réduit
# pour lier la rangée de puces de la file d'initiative à « Tour : N » en
# dessous (retour Rhend — décoration statique, pas besoin de recalcul).
func _dessiner_soulignement_file() -> void:
	if _soulignement_file == null:
		return
	var couleur := CombatUiSkin.couleur_lien()
	var h := _soulignement_file.size.y
	var depart := Vector2(0.0, 2.0)
	var coude := Vector2(TAILLE_PUCE_TOUR * 0.5, 2.0)
	var arrivee := Vector2(coude.x + LIEN_COUDE_PX, h - 2.0)
	_soulignement_file.draw_line(depart, coude, couleur, LIEN_EPAISSEUR_PX, true)
	_soulignement_file.draw_line(coude, arrivee, couleur, LIEN_EPAISSEUR_PX, true)
	_soulignement_file.draw_arc(arrivee, LIEN_RAYON_NOEUD_PX, 0.0, TAU, 16, couleur,
			LIEN_EPAISSEUR_PX, true)

func _sur_attaquer() -> void:
	if not _btn_attaquer.visible:
		return   # pas d'activation joueur ouverte (press programmatique hors tour)
	_objet_en_attente = null
	_competence_en_attente = null
	var vivants: Array[CtbCombattant] = _ennemis_vivants()
	if vivants.size() <= 1:
		_valider_action({"type": Enums.ActionCtb.ATTAQUER,
				"cible": vivants[0] if vivants.size() == 1 else null})
		return
	_montrer_choix_cibles(vivants)

# Compétence (chantier 16) : sans cible requise → validée direct (soin) ;
# sinon même rangée de choix de cible que l'attaque et l'objet.
func _sur_competence(comp: CompetenceCtbData) -> void:
	if not _btn_attaquer.visible:
		return
	_objet_en_attente = null
	_competence_en_attente = null
	if not comp.cible_requise():
		_valider_action({"type": Enums.ActionCtb.COMPETENCE, "competence": comp})
		return
	var vivants: Array[CtbCombattant] = _ennemis_vivants()
	if vivants.size() <= 1:
		_valider_action({"type": Enums.ActionCtb.COMPETENCE, "competence": comp,
				"cible": vivants[0] if vivants.size() == 1 else null})
		return
	_competence_en_attente = comp
	_montrer_choix_cibles(vivants)

# Mode ciblage (attaque, compétence ou objet ciblé) : l'ennemi se choisit
# À LA SOURIS — clic sur son personnage DANS LA SCÈNE (zone + réticule or)
# ou sur sa carte. Plus de boutons nominatifs (retour Rhend 07/2026) :
# seule l'invite et Annuler restent dans la rangée du bas.
func _montrer_choix_cibles(_vivants: Array[CtbCombattant]) -> void:
	UIHelpers.clear_children_now(_rangee_cibles)
	var invite := ExpeStyle.label_mono(
			Translations.T("ctb.choisir_cible"), 12, UIColors.SELECTION_GOLD)
	invite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rangee_cibles.add_child(invite)
	var annuler := CombatUiSkin.bouton(Translations.T("ctb.annuler"), 13, Vector2(0, 34))
	annuler.pressed.connect(func() -> void:
		_objet_en_attente = null
		_competence_en_attente = null
		UIHelpers.clear_children_now(_rangee_cibles)
		_mettre_cibles_en_avant(false)
		_repositionner_bandeaux())
	_rangee_cibles.add_child(annuler)
	_mettre_cibles_en_avant(true)
	AudioManager.play_sfx("ui_select", -10.0)
	_repositionner_bandeaux()

# Choix d'un objet (chantier 7) : liste de l'inventaire (doublons regroupés
# « ×n »), puis cible si l'effet en demande une.
func _sur_objet() -> void:
	if _btn_objet == null or not _btn_objet.visible or _btn_objet.disabled:
		return
	_objet_en_attente = null
	UIHelpers.clear_children_now(_rangee_cibles)
	_rangee_cibles.add_child(ExpeStyle.label_mono(
			Translations.T("ctb.choisir_objet"), 12, UIColors.CYBER_TEXTE_MUTED))
	var inv: Array = inventaire_fournisseur.call()
	var groupes: Dictionary = {}   # id → {"objet": ConsommableData, "n": int}
	for o: ConsommableData in inv:
		if not groupes.has(o.id):
			groupes[o.id] = {"objet": o, "n": 0}
		groupes[o.id]["n"] += 1
	for id: String in groupes:
		var grp: Dictionary = groupes[id]
		var objet := grp["objet"] as ConsommableData
		var nom := Translations.resource_name(objet, objet.id)
		var b := CombatUiSkin.bouton(
				nom if int(grp["n"]) == 1 else "%s ×%d" % [nom, int(grp["n"])],
				13, Vector2(0, 34))
		b.pressed.connect(_sur_objet_choisi.bind(objet))
		_rangee_cibles.add_child(b)
	var annuler := CombatUiSkin.bouton(Translations.T("ctb.annuler"), 13, Vector2(0, 34))
	annuler.pressed.connect(func() -> void:
		UIHelpers.clear_children_now(_rangee_cibles)
		_repositionner_bandeaux())
	_rangee_cibles.add_child(annuler)
	AudioManager.play_sfx("ui_select", -10.0)
	_repositionner_bandeaux()

func _sur_objet_choisi(objet: ConsommableData) -> void:
	if not _btn_attaquer.visible:
		return
	if not objet.cible_requise():
		_valider_action({"type": Enums.ActionCtb.OBJET, "objet": objet})
		return
	var vivants: Array[CtbCombattant] = _ennemis_vivants()
	if vivants.size() <= 1:
		_valider_action({"type": Enums.ActionCtb.OBJET, "objet": objet,
				"cible": vivants[0] if vivants.size() == 1 else null})
		return
	_objet_en_attente = objet
	_montrer_choix_cibles(vivants)

func _sur_cible_cliquee(cible: CtbCombattant) -> void:
	if not _btn_attaquer.visible or not cible.est_vivant():
		return
	if _competence_en_attente != null:
		_valider_action({"type": Enums.ActionCtb.COMPETENCE,
				"competence": _competence_en_attente, "cible": cible})
		return
	if _objet_en_attente != null:
		_valider_action({"type": Enums.ActionCtb.OBJET, "objet": _objet_en_attente,
				"cible": cible})
		return
	_valider_action({"type": Enums.ActionCtb.ATTAQUER, "cible": cible})

func _valider_action(action: Dictionary) -> void:
	AudioManager.play_sfx("ui_select", -8.0)
	# Objet : l'inventaire (chez l'appelant) est décrémenté AU MOMENT où
	# l'action est validée — le moteur reste agnostique.
	if int(action.get("type", -1)) == Enums.ActionCtb.OBJET \
			and sur_objet_utilise.is_valid():
		sur_objet_utilise.call(action["objet"])
	_objet_en_attente = null
	_competence_en_attente = null
	_action_en_attente = action
	_action_choisie.emit()

func _mettre_cibles_en_avant(on: bool) -> void:
	_ciblage_actif = on
	# L'anneau or « ciblable » vit dans la scène (_dessiner_sol) — plus de
	# liseré dupliqué sur une carte depuis que le HUD par combattant a quitté
	# la colonne latérale (chantier UI_Concept2).
	# Zones de clic de la scène : ACTIVES seulement en mode ciblage (le reste
	# du temps la scène est purement décorative — souris ignorée).
	for cb: CtbCombattant in _zones_cible:
		(_zones_cible[cb] as Control).mouse_filter = Control.MOUSE_FILTER_STOP \
				if on and cb.est_vivant() else Control.MOUSE_FILTER_IGNORE
	if not on:
		_cible_survolee = null
	if _sol != null:
		_sol.queue_redraw()

# Zone de clic d'un ennemi : clic gauche = choisir cette cible
# (_sur_cible_cliquee ignore hors mode ciblage — seule garde nécessaire).
func _sur_zone_input(ev: InputEvent, cb: CtbCombattant) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_sur_cible_cliquee(cb)

func _sur_zone_survol(cb: CtbCombattant, actif: bool) -> void:
	if actif:
		_cible_survolee = cb
	elif _cible_survolee == cb:
		_cible_survolee = null
	if _sol != null:
		_sol.queue_redraw()

func _ennemis_vivants() -> Array[CtbCombattant]:
	var out: Array[CtbCombattant] = []
	for cb in moteur.combattants:
		if not cb.est_joueur() and cb.est_vivant():
			out.append(cb)
	return out

# ─── Affichage ───────────────────────────────────────────────

func _rafraichir_tout() -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).rafraichir()
	if _panneau_stats != null:
		_panneau_stats.rafraichir()
		_repositionner_panel_stats()
	_rafraichir_file()
	_rafraichir_orbes()

# File d'initiative compacte : rangée HORIZONTALE de puces carrées façon
# portraits (chantier UI_Concept2 — remplace la colonne de noms en toutes
# lettres). Portrait RÉEL si `_portrait_pour(cb)` en trouve un (livraison
# « Turn_Icone_Ennemis », 16/09/2026 — FlameBot/WorkBot, 5 paliers chacun ;
# le héros n'a pas encore le sien), sinon repli sur l'initiale du nom. Ordre
# des N_FILE prochaines activations, recalculé après chaque action.
func _rafraichir_file() -> void:
	UIHelpers.clear_children_now(_file_box)
	var predits := moteur.prevoir_ordre(N_FILE)
	for i in predits.size():
		var cb: CtbCombattant = predits[i]
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(TAILLE_PUCE_TOUR, TAILLE_PUCE_TOUR)
		# Cadre RÉEL de Christophe (Turn_back/Border) : halo (Aura) sur la
		# PROCHAINE activation (i == 0) pour la faire ressortir de la file.
		chip.add_theme_stylebox_override("panel",
				CombatUiSkin.style_chip_tour(cb.est_joueur(), i == 0))
		var portrait := _portrait_pour(cb)
		if portrait != null:
			var tr := TextureRect.new()
			tr.texture = portrait
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			chip.add_child(tr)
		else:
			var initiale := CarteCombattantCtb.nom_ui(cb.data).left(1).to_upper()
			var lbl := ExpeStyle.label_mono(initiale, 13,
					ExpeStyle.accent_camp(cb.est_joueur()).lightened(0.35))
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			chip.add_child(lbl)
		_file_box.add_child(chip)
	if _lbl_tour != null:
		_lbl_tour.text = Translations.T("ctb.tour_compteur") % moteur.nb_activations
	_repositionner_panneau_file()

func _marquer_actif(c: CtbCombattant) -> void:
	# Le halo « c'est ton tour » vit sur l'ombre portée (CombatOmbrePortee) —
	# plus de doublon sur une carte depuis le chantier UI_Concept2.
	for cb: CtbCombattant in _ombres:
		(_ombres[cb] as CombatOmbrePortee).definir_actif(cb == c)

# ─── Retours visuels (signal structuré du moteur) ────────────

# Nœud de scène d'un combattant : sprite Spine s'il existe, sinon son orbe.
func _noeud_bataille(cb: CtbCombattant) -> CanvasItem:
	if _sprites.has(cb):
		return _sprites[cb]
	return _orbes.get(cb)

# Position du nœud pour poser ses PIEDS sur `pied` (le sprite Spine a son
# origine aux pieds ; l'orbe est un Control ancré en haut-gauche).
func _pos_depuis_pied(cb: CtbCombattant, pied: Vector2) -> Vector2:
	if _sprites.has(cb):
		return pied
	return pied - Vector2(ORBE_TAILLE.x * 0.5, ORBE_TAILLE.y - 10.0)

# Coupe net un duel en cours : chacun regagne instantanément son
# emplacement, la scène redevient nette — un nouveau duel repart de zéro.
func _duel_interrompre() -> void:
	if _duel_tween != null and _duel_tween.is_valid():
		_duel_tween.kill()
	_duel_tween = null
	for paire: Array in _duel_restaure:
		(paire[0] as CanvasItem).position = paire[1]
	_duel_restaure.clear()
	_duel_restaurer_ordre()
	if _couche_scene != null:
		_couche_scene.scale = Vector2.ONE
	if not _duel_acteurs.is_empty():
		_duel_acteurs = []
		_rafraichir_orbes()   # réapplique le fondu différé d'un vaincu du duel

# Zoom-DUEL (attaque du joueur seulement — recette dans `DuelZoomFx`) :
# glissement simultané des deux personnages vers le centre + punch-in de la
# scène, tenue le temps du coup, puis retour aux emplacements. Crit = zoom
# plus marqué.
# `converger` = false (TIR) : personne ne bouge — charger l'adversaire
# contredirait le geste — mais le punch-in reste, recentré sur la CIBLE :
# c'est là que le coup arrive, et c'est ce qu'il faut regarder.
func _duel_attaque(att: CtbCombattant, cible: CtbCombattant, crit: bool,
		converger: bool = true) -> void:
	if facteur_delais <= 0.0 or _couche_scene == null or _sol == null:
		return   # tests headless : aucun délai, aucun tween
	if not _pieds.has(att) or not _pieds.has(cible):
		return
	_duel_interrompre()
	var noeud_att := _noeud_bataille(att)
	var noeud_cib := _noeud_bataille(cible)
	if noeud_att == null or noeud_cib == null:
		return
	var centre := Vector2(_sol.size.x * 0.5, _sol.size.y * SOL_Y_FRAC)
	# Point regardé : le centre de l'écran en mêlée (les deux corps y viennent),
	# le MILIEU du couple tireur/cible en tir — personne ne bouge, et pivoter
	# sur la seule cible pousserait le tireur hors cadre quand elle est loin.
	var foyer: Vector2 = centre if converger \
			else ((_pieds[att] as Vector2) + (_pieds[cible] as Vector2)) * 0.5
	# Le joueur vient de gauche, sa cible lui fait face à droite.
	var pos_att := _pos_depuis_pied(att, centre + Vector2(-DuelZoomFx.ECART_PX * 0.5, 0.0))
	var pos_cib := _pos_depuis_pied(cible, centre + Vector2(DuelZoomFx.ECART_PX * 0.5, 0.0))
	# Rien à restaurer sans convergence : les positions ne sont pas touchées.
	_duel_restaure = [[noeud_att, noeud_att.position], [noeud_cib, noeud_cib.position]] \
			if converger else []
	# L'ATTAQUANT doit se dessiner PAR-DESSUS sa cible : son arme déborde de
	# son propre corps pendant le geste, et l'ordre d'ajout à `_sol` (joueur
	# ajouté avant les ennemis, cf. `_construire`) le mettait sinon TOUJOURS
	# derrière l'adversaire dès que la convergence les rapproche au centre —
	# le coup d'épée du héros disparaissait derrière l'ennemi (retour Rhend).
	if converger:
		_duel_ordre_restaure = [noeud_att, noeud_att.get_index()]
		_sol.move_child(noeud_att, _sol.get_child_count() - 1)
	_duel_acteurs = [att, cible]
	_duel_tween = DuelZoomFx.jouer(_couche_scene, foyer, noeud_att, pos_att, noeud_cib, pos_cib,
			crit, converger, facteur_delais, func() -> void:
				_duel_restaure.clear()
				_duel_restaurer_ordre()
				_duel_tween = null
				_duel_acteurs = []
				_rafraichir_orbes())   # fondu différé du vaincu, une fois le duel joué

# Replace l'attaquant à son rang d'origine dans `_sol` une fois le duel fini
# (ou interrompu) — le z-order ne doit servir que le temps du geste, jamais
# devenir l'ordre permanent de la scène.
func _duel_restaurer_ordre() -> void:
	if _duel_ordre_restaure.is_empty():
		return
	var noeud := _duel_ordre_restaure[0] as CanvasItem
	var index: int = _duel_ordre_restaure[1]
	_duel_ordre_restaure = []
	if is_instance_valid(noeud) and _sol != null:
		_sol.move_child(noeud, index)

func _sur_evenement(e: Dictionary) -> void:
	if not is_inside_tree():
		return
	match str(e.get("type", "")):
		"attaque":
			# Sprites Spine : l'attaquant joue son GESTE (Attack_CaC, ou
			# Attack_Shoot quand la compétence est un tir), la cible joue Hit
			# (ou Death si le coup tue — jouer_mort est prioritaire et
			# verrouille les animations suivantes).
			var a_distance: bool = int(e.get("animation",
					Enums.AnimationAttaque.MELEE)) == Enums.AnimationAttaque.DISTANCE
			var sprite_att: SpriteSpinePersonnage = _sprites.get(e["attaquant"])
			if sprite_att != null:
				sprite_att.jouer_attaque(a_distance)
			var cible := e["cible"] as CtbCombattant
			var sprite_cible: SpriteSpinePersonnage = _sprites.get(cible)
			if sprite_cible != null:
				if bool(e["mort"]):
					sprite_cible.jouer_mort()
				else:
					sprite_cible.jouer_hit()
			var degats := int(e["degats"])
			var crit := bool(e["crit"])
			# Mise en scène de duel UNIQUEMENT sur l'attaque du joueur —
			# les activations ennemies restent sobres (retour Rhend). Un TIR
			# ne fait converger personne : le zoom se recentre sur la cible.
			var attaquant := e["attaquant"] as CtbCombattant
			if attaquant.est_joueur():
				_duel_attaque(attaquant, cible, crit, not a_distance)
			var couleur: Color
			if cible.est_joueur():
				couleur = UIColors.DMG_HEAVY_ENEMY if crit else UIColors.DMG_BY_ENEMY
			else:
				couleur = UIColors.DMG_HEAVY_HERO if crit else UIColors.DMG_BY_HERO
			var texte := (Translations.T("ctb.crit_float") % degats) if crit else str(degats)
			AudioManager.play_sfx("attack", -6.0)
			_flotter(cible, texte, 22 if crit else 17, couleur, crit)
		"tick_statut":
			# Tick de DoT : distinct des coups (violet, préfixe du statut).
			_flotter(e["cible"] as CtbCombattant, "−%d %s" % [int(e["degats"]),
					str(e["nom"])], 14, UIColors.POISON, false)
		"statut_pose":
			var sd := e["statut"] as StatutCtbData
			# StatutCtbData partage les champs nom_affichage_* : même chemin
			# Translations que les combattants (pas de FR en dur).
			var nom := Translations.resource_name(sd, sd.id)
			_flotter(e["cible"] as CtbCombattant, "+ %s" % nom, 13, UIColors.POISON, false)
		"defense":
			_flotter(e["combattant"] as CtbCombattant,
					Translations.T("ctb.garde_pill"), 15, UIColors.SHIELD, false)
		"competence":
			# Annonce du lancement (chantier 16) — les dégâts éventuels
			# arrivent par l'événement « attaque » standard juste après.
			var comp := e["competence"] as CompetenceCtbData
			_flotter(e["utilisateur"] as CtbCombattant,
					"✦ %s" % Translations.resource_name(comp, comp.id), 14,
					UIColors.CYBER_ACCENT_2, false)
		"soin":
			_flotter(e["cible"] as CtbCombattant,
					"+%d" % int(roundf(float(e["soin"]))), 18,
					UIColors.HEAL_COLOR, true)
		"objet":
			# Consommable (chantier 7) : dégâts (Bombe) ou soin (Nano).
			if e.has("degats"):
				AudioManager.play_sfx("attack", -4.0)
				_flotter(e["cible"] as CtbCombattant, str(int(e["degats"])), 20,
						UIColors.DMG_HEAVY_HERO, true)
			elif e.has("soin"):
				_flotter(e["cible"] as CtbCombattant,
						"+%d" % int(roundf(float(e["soin"]))), 18,
						UIColors.HEAL_COLOR, true)

func _flotter(cb: CtbCombattant, texte: String, taille: int, couleur: Color,
		punch: bool) -> void:
	var carte := _cartes.get(cb) as CarteCombattantCtb
	if carte == null or _fx == null:
		return
	var pos := carte.centre_fx() - _fx.global_position
	UIHelpers.float_text(_fx, texte, taille, couleur, pos, 46.0, punch)

# ─── Transitions de bataille (placeholder assumé) ────────────

# Fondu d'ouverture (carte → combat) + annonce d'embuscade le cas échéant.
# Splash RÉEL de Christophe (« ENNEMY DETECTED », UI_Concept1.png) : fond +
# circuit rouge + glyphe Artefact + lances, posés SOUS le texte (_voile_contenu
# reste au sommet de `_voile`) et retirés avec elle en fin d'intro — l'outro
# (victoire/défaite) réutilise `_voile` SANS ce décor. Tenue à DUREE_SPLASH_S
# fixe (retour Rhend 07/09/2026 : depuis AssetCache/BootWarmupScreen, la
# construction qui précède est quasi instantanée — CombatLoadingScreen, posé
# par l'appelant AVANT cette construction, ne masque donc plus qu'un flash de
# 1-2 frames et cède aussitôt la place à CE voile, qui devient de fait le
# splash visible ; sa durée fixe est ce que le joueur perçoit comme le temps
# d'affichage du splash). ⚠ Plus de titre « ⚔ COMBAT » ASCII : reliquat de
# l'ancienne peau cyberpunk d'avant la DA réelle de Christophe, redondant
# avec le texte déjà peint dans le splash — supprimé.
func _intro() -> void:
	var visuel := CombatUiSkin.splash_ennemi_detecte()
	_voile.add_child(visuel)
	_voile.move_child(visuel, 0)

	if embuscade:
		AudioManager.play_sfx("trap_appear", -4.0)
		var amb := ExpeStyle.label_mono(Translations.T("ctb.embuscade"), 26,
				UIColors.MECH_AMBUSH)
		amb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_voile_contenu.add_child(amb)
		var sous := ExpeStyle.label_mono(Translations.T("ctb.embuscade_sub"), 13,
				UIColors.MECH_AMBUSH.lightened(0.35))
		sous.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_voile_contenu.add_child(sous)
	# Mécanique forte du Lieu (chantier 15) : annonce à l'ouverture — le
	# joueur sait sous quelle règle ce combat se joue.
	if annonce_mecanique != "":
		var meca := ExpeStyle.label_mono(Translations.T("ctb.mecanique_lieu")
				% Translations.T("meca." + annonce_mecanique), 15,
				UIColors.CYBER_ACCENT_2)
		meca.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_voile_contenu.add_child(meca)
	await _pause(DUREE_SPLASH_S)
	if not is_inside_tree():
		return
	if facteur_delais > 0.0:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_voile, "color:a", 0.0, DUREE_FONDU_SPLASH_S)
		tw.tween_property(visuel, "modulate:a", 0.0, DUREE_FONDU_SPLASH_S)
		await tw.finished
	else:
		_voile.color.a = 0.0
	visuel.queue_free()
	_voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIHelpers.clear_children_now(_voile_contenu)

# Fin de bataille : l'issue s'affiche AVANT le retour à la carte ;
# clic pour continuer (fermeture immédiate si facteur_delais = 0 — tests).
func _outro() -> void:
	_montrer_actions(false)
	_marquer_actif(null)
	# Le duel du coup FATAL se joue en entier avant l'écran d'issue (c'est le
	# moment le plus dramatique du combat) ; puis coupe-filet pour un état
	# final déterministe (scène nette, chacun à sa place, fondu du vaincu).
	if _duel_tween != null and _duel_tween.is_valid() and facteur_delais > 0.0:
		await _duel_tween.finished
		if not is_inside_tree():
			return
	_duel_interrompre()
	_rafraichir_tout()
	var gagne := moteur.victoire_joueur
	AudioManager.play_sfx("summary_victory" if gagne else "summary_defeat", -4.0)
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP
	# Issue : positif (victoire) vs rouge danger (défaite = mort en approche).
	var issue := ExpeStyle.label_mono(
			Translations.T("ctb.victoire" if gagne else "ctb.defaite"), 42,
			UIColors.CYBER_OK if gagne else UIColors.CYBER_DANGER)
	issue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(issue)
	# Récompenses du combat (chantier 6) — seulement si l'appelant les fournit.
	if gagne and recompenses_fournisseur.is_valid():
		var rec: Dictionary = recompenses_fournisseur.call()
		if not rec.is_empty() and (float(rec.get("xp", 0.0)) > 0.0
				or float(rec.get("euren", 0.0)) > 0.0):
			var recomp := ExpeStyle.label_mono(Translations.T("ctb.recompenses") % [
					int(roundf(float(rec.get("xp", 0.0)))),
					int(roundf(float(rec.get("euren", 0.0))))],
					16, UIColors.CYBER_BUTIN)
			recomp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_voile_contenu.add_child(recomp)
		# Butin de matériaux du combat (chantier 14) — ligne SEULEMENT s'il
		# y en a. L'écran reste générique : `butin` = dict {id → qté} fourni
		# par l'appelant, noms résolus par Translations.
		var butin: Dictionary = rec.get("butin", {})
		if not butin.is_empty():
			var lb := ExpeStyle.label_mono(Translations.T("ctb.recompenses_butin")
					% Translations.noms_quantites(butin), 14, UIColors.CYBER_BUTIN)
			lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_voile_contenu.add_child(lb)
	var invite := ExpeStyle.label_mono(Translations.T("ctb.continuer"), 13,
			UIColors.CYBER_TEXTE_MUTED)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(invite)
	if facteur_delais > 0.0:
		var tw := create_tween()
		tw.tween_property(_voile, "color:a", 0.72, 0.5)
		await tw.finished
		if not is_inside_tree():
			return
		await _clic_sur_voile()
		if not is_inside_tree():
			return
	fermee.emit(_recap)

func _clic_sur_voile() -> void:
	while is_inside_tree():
		var ev: InputEvent = await _voile.gui_input
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			return

func _pause(secondes: float) -> void:
	if facteur_delais <= 0.0:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(secondes * facteur_delais).timeout
