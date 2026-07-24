# ============================================================
# CombatCtbUi — Écran de combat CTB JOUABLE (Rework Combat, chantier 5).
#
# Écran scindé (référence Advanced Wars) : camp joueur à gauche, camp adverse
# à droite (jusqu'à 3 combattants par camp — architecture N-vs-N actée), Lieu
# en fond purement COSMÉTIQUE (BiomeBackground scindé en diagonale — CONSERVÉ
# à la demande de Rhend, la peau cyberpunk du chantier 10 habille le chrome
# par-dessus : panneaux opaques, tokens UIColors.CYBER_*, ExpeStyle). Scène de
# bataille : SOL + emplacements des sprites — le personnage principal est le
# sprite Spine RÉEL de Christophe (SpriteSpinePersonnage : Idle en boucle,
# Attack sur son action ; retombe sur le placeholder si le runtime
# spine-godot manque) ; les adversaires restent des boules de lumière
# (EnergyBoule) en attendant leurs assets. L'attaque du JOUEUR déclenche un
# ZOOM-DUEL façon Darkest Dungeon : les deux personnages glissent au centre
# de l'écran face à face, punch-in fort (crit = plus marqué), puis retour —
# activations ennemies SANS effet de caméra ; seule la scène zoome, le
# chrome UI reste fixe. DA finale hors scope (Christophe).
#
# Pilote un CtbMoteur DÉJÀ démarré, en pull-based :
#   • activation du camp joueur → attend l'input (Attaquer / Défendre —
#     PAS de bouton Objet : les consommables n'existent pas, « contenu
#     absent, pas grisé ») ; Attaquer → choix de cible parmi les ennemis
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

# Zoom-DUEL sur l'attaque du JOUEUR uniquement (recette Darkest Dungeon 1,
# resserrée — retour Rhend) : l'attaquant et sa cible GLISSENT au centre de
# l'écran face à face, comme pour un coup final, pendant que la scène
# punch-in fort ; tenue le temps du coup, puis chacun regagne son
# emplacement. Les activations ennemies n'ont AUCUN effet de caméra. Seule
# la scène (_couche_scene) bouge — le chrome UI reste fixe.
const DUEL_ZOOM := 1.40
const DUEL_ZOOM_CRIT := 1.55       # un crit frappe plus fort → caméra aussi
const DUEL_ECART_PX := 120.0       # distance des deux pieds au centre (face à face)
const DUEL_FOCUS_HAUT_PX := 60.0   # remonte le pivot des pieds vers les torses
const DUEL_DUREE_IN := 0.14
# Tenue calibrée pour que le duel (in + tenue + out = 0.89 s) soit ENTIÈREMENT
# retombé avant la première activation ennemie qui suit (pause post-action
# 0.35 s + pause de bandeau 0.55 s = 0.90 s) — sinon le coup ennemi se
# jouerait pendant le dé-zoom, contredisant « ennemis sans effet de caméra ».
const DUEL_TENUE := 0.45
const DUEL_DUREE_OUT := 0.30

var moteur: CtbMoteur
var embuscade := false
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

const SOL_Y_FRAC := 0.60           # hauteur du sol de la scène (fraction écran)
const SOL_X_JOUEUR := 0.34         # ancrage des emplacements du camp joueur
const SOL_X_ADVERSE := 0.66        # ancrage des emplacements du camp adverse
const SOL_PAS := Vector2(64, 46)   # décalage diagonal entre emplacements
const ORBE_TAILLE := Vector2(64, 64)

var _cartes: Dictionary = {}   # CtbCombattant → CarteCombattantCtb
var _couche_scene: Control = null   # couches zoomables (fonds + sol + sprites)
var _duel_tween: Tween = null
var _duel_restaure: Array = []      # paires [CanvasItem, position d'origine]
var _duel_acteurs: Array = []       # [attaquant, cible] du duel en cours
var _sol: Control = null       # scène : sol + emplacements des futurs sprites
var _orbes: Dictionary = {}    # CtbCombattant → EnergyBoule (placeholder sprite)
var _sprites: Dictionary = {}  # CtbCombattant → SpriteSpinePersonnage (sprite RÉEL)
var _pieds: Dictionary = {}    # CtbCombattant → point d'appui au sol (dessin)
var _file_box: HBoxContainer
var _bandeau_tour: Label
var _btn_attaquer: Button
var _btn_defendre: Button
var _btn_objet: Button = null          # créé SEULEMENT si inventaire non vide
var _rangee_boutons: HBoxContainer
var _rangee_cibles: HBoxContainer
var _objet_en_attente: ConsommableData = null   # objet ciblé en attente de cible
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
# `sur_fermee` est appelée après libération (rafraîchissement chez l'appelant).
static func pour_run(run: ExpeRun, avec_embuscade: bool, sur_fermee: Callable) -> CombatCtbUi:
	var ui := CombatCtbUi.new(run.combat_en_cours, avec_embuscade)
	ui.recompenses_fournisseur = func() -> Dictionary:
		return run.dernier_combat_recompenses
	ui.inventaire_fournisseur = func() -> Array:
		return run.inventaire
	ui.sur_objet_utilise = func(objet: ConsommableData) -> void:
		run.consommer(objet)
	ui.fermee.connect(func(_recap: Dictionary) -> void:
		ui.queue_free()
		sur_fermee.call())
	return ui

func _ready() -> void:
	# and_offsets : set_anchors_preset seul CONSERVE les offsets courants —
	# ajouté à un SubViewport (ScreenshotTool), l'écran restait en 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloque la carte en dessous
	_construire()
	moteur.evenement.connect(_sur_evenement)
	moteur.victoire.connect(func(r: Dictionary) -> void: _recap = r)
	moteur.defaite.connect(func(r: Dictionary) -> void: _recap = r)
	_boucle()

# ─── Construction (100 % code — règle projet) ────────────────

func _construire() -> void:
	# Fond scindé : ambiance Ville côté joueur, biome côté adverse (presets
	# BiomeBackground — placeholder du Lieu, purement cosmétique). RESTAURÉ à
	# la demande de Rhend après la passe cyberpunk : les biomes restent
	# visibles, la peau habille le chrome PAR-DESSUS (panneaux opaques).
	# Conteneur ZOOMABLE de la scène de bataille (fonds + diagonale + sol +
	# sprites) : le zoom d'attaque façon Darkest Dungeon ne scale que lui —
	# le chrome UI (file, cartes, actions, FX) reste fixe par-dessus.
	_couche_scene = Control.new()
	_couche_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_couche_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_couche_scene)
	var fond_joueur := BiomeBackground.new()
	fond_joueur.apply_preset("city")
	fond_joueur.set_split(1, BANDE_VS_PX)
	_couche_scene.add_child(fond_joueur)
	var fond_adverse := BiomeBackground.new()
	fond_adverse.apply_preset("forest")
	fond_adverse.set_split(2, BANDE_VS_PX)
	_couche_scene.add_child(fond_adverse)
	var seam := Control.new()
	seam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seam.draw.connect(_dessiner_diagonale.bind(seam))
	seam.resized.connect(seam.queue_redraw)
	_couche_scene.add_child(seam)

	# Scène de bataille : SOL + emplacements des futurs sprites de personnages
	# (placeholder : boules de lumière — retour Rhend, chantier 10).
	_sol = Control.new()
	_sol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sol.draw.connect(_dessiner_sol)
	_sol.resized.connect(_placer_orbes)
	_couche_scene.add_child(_sol)
	for cb in moteur.combattants:
		# Personnage principal : sprite Spine RÉEL (DA Christophe, Idle en
		# boucle + Attack sur son action) quand le runtime spine-godot et
		# les assets sont là — sinon placeholder EnergyBoule, comme les
		# adversaires (leurs sprites n'existent pas encore).
		if cb == moteur.avatar():
			var sprite := SpriteSpinePersonnage.creer()
			if sprite != null:
				_sprites[cb] = sprite
				_sol.add_child(sprite)
				continue
		var orbe := EnergyBoule.new()
		orbe.accent = ExpeStyle.accent_camp(cb.est_joueur())
		orbe.size = ORBE_TAILLE
		_orbes[cb] = orbe
		_sol.add_child(orbe)
		# Placeholder de sprite, pas un élément interactif (EnergyBoule est
		# cliquable par défaut au Village) : souris ignorée.
		orbe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placer_orbes()

	# Colonne générale : file d'initiative / arène / barre d'actions.
	var colonne := VBoxContainer.new()
	colonne.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	colonne.add_theme_constant_override("separation", 8)
	add_child(colonne)

	# File d'initiative ENCADRÉE, fond opaque (retour Rhend : elle doit se
	# détacher du biome visuel derrière).
	var panneau_file := PanelContainer.new()
	panneau_file.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style_file := ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 1.0)
	style_file.bg_color = UIColors.CYBER_BG   # opaque — jamais le biome au travers
	panneau_file.add_theme_stylebox_override("panel", style_file)
	colonne.add_child(panneau_file)
	var haut := VBoxContainer.new()
	haut.add_theme_constant_override("separation", 2)
	panneau_file.add_child(haut)
	var titre_file := ExpeStyle.label_mono(Translations.T("ctb.file_titre"), 11,
			UIColors.CYBER_TEXTE_MUTED)
	titre_file.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	haut.add_child(titre_file)
	var centre_file := HBoxContainer.new()
	centre_file.alignment = BoxContainer.ALIGNMENT_CENTER
	haut.add_child(centre_file)
	_file_box = HBoxContainer.new()
	_file_box.add_theme_constant_override("separation", 6)
	centre_file.add_child(_file_box)

	# Arène scindée : cartes du camp joueur | vide central | cartes adverses.
	var arene := HBoxContainer.new()
	arene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(arene)
	var camp_joueur := _colonne_camp(arene, BoxContainer.ALIGNMENT_CENTER)
	var milieu := Control.new()
	milieu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	milieu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arene.add_child(milieu)
	var camp_adverse := _colonne_camp(arene, BoxContainer.ALIGNMENT_CENTER)
	for cb in moteur.combattants:
		var carte := CarteCombattantCtb.new(cb)
		carte.cliquee.connect(_sur_cible_cliquee)
		_cartes[cb] = carte
		(camp_joueur if cb.est_joueur() else camp_adverse).add_child(carte)

	# Barre d'actions (bas) : bandeau de tour + Attaquer / Défendre + cibles.
	# AUCUN bouton Objet : contenu absent, pas grisé (pilier projet).
	var bas := PanelContainer.new()
	var style_bas := ExpeStyle.style_panneau(UIColors.CYBER_ACCENT, 0.90)
	style_bas.set_content_margin_all(10)
	bas.add_theme_stylebox_override("panel", style_bas)
	colonne.add_child(bas)
	var bas_v := VBoxContainer.new()
	bas_v.add_theme_constant_override("separation", 6)
	bas.add_child(bas_v)
	_bandeau_tour = ExpeStyle.label_mono("", 14, UIColors.CYBER_TEXTE)
	_bandeau_tour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bas_v.add_child(_bandeau_tour)
	_rangee_boutons = HBoxContainer.new()
	_rangee_boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	_rangee_boutons.add_theme_constant_override("separation", 12)
	bas_v.add_child(_rangee_boutons)
	_btn_attaquer = ExpeStyle.bouton(Translations.T("ctb.attaquer"), UIColors.CYBER_ACCENT)
	_btn_attaquer.pressed.connect(_sur_attaquer)
	_rangee_boutons.add_child(_btn_attaquer)
	_btn_defendre = ExpeStyle.bouton(Translations.T("ctb.defendre"), UIColors.SHIELD)
	_btn_defendre.pressed.connect(func() -> void:
		_valider_action({"type": Enums.ActionCtb.DEFENDRE}))
	_rangee_boutons.add_child(_btn_defendre)
	# PAS de bouton Objet ici : il n'existe que si l'inventaire de run est
	# non vide, recréé à chaque tour joueur (_montrer_actions).
	_rangee_cibles = HBoxContainer.new()
	_rangee_cibles.alignment = BoxContainer.ALIGNMENT_CENTER
	_rangee_cibles.add_theme_constant_override("separation", 8)
	bas_v.add_child(_rangee_cibles)
	_montrer_actions(false)

	# Couche FX (dégâts flottants) au-dessus de tout le contenu de jeu.
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	# Scanlines sobres (sous le voile de transition, au-dessus du jeu).
	ExpeStyle.scanlines(self)

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

func _colonne_camp(parent: Control, alignement: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = alignement as BoxContainer.AlignmentMode
	v.add_theme_constant_override("separation", 10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var marge := UIHelpers.margin_of(16)
	marge.add_child(v)
	parent.add_child(marge)
	return v

# Bande diagonale entre les deux fonds biome scindés — liseré double aux
# accents de la peau (cyan/magenta), seule touche cyberpunk du fond.
func _dessiner_diagonale(seam: Control) -> void:
	var w := seam.size.x
	var h := seam.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var xt := w * 0.5 + BANDE_VS_PX * 0.5
	var xb := w * 0.5 - BANDE_VS_PX * 0.5
	seam.draw_line(Vector2(xt, 0), Vector2(xb, h), Color(UIColors.CYBER_ACCENT, 0.55), 2.0)
	seam.draw_line(Vector2(xt + 5, 0), Vector2(xb + 5, h),
			Color(UIColors.CYBER_ACCENT_2, 0.35), 1.0)

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
	_sol.queue_redraw()

# Sol de la scène : ligne d'horizon + bande dégradée, et ellipse
# d'emplacement sous chaque personnage (tokens CYBER_SOL / accents de camp).
func _dessiner_sol() -> void:
	var w := _sol.size.x
	if w <= 0.0:
		return
	var y := _sol.size.y * SOL_Y_FRAC
	_sol.draw_line(Vector2(0, y), Vector2(w, y), UIColors.CYBER_SOL, 2.0)
	for i in 3:
		_sol.draw_rect(Rect2(0.0, y + float(i) * 16.0, w, 16.0),
				Color(UIColors.CYBER_SOL, UIColors.CYBER_SOL.a * (0.45 - 0.13 * float(i))))
	for cb: CtbCombattant in _pieds:
		var accent := ExpeStyle.accent_camp(cb.est_joueur())
		var pied: Vector2 = _pieds[cb]
		_sol.draw_set_transform(pied, 0.0, Vector2(1.0, 0.38))
		_sol.draw_circle(Vector2.ZERO, 34.0, Color(UIColors.CYBER_BG, 0.55))
		_sol.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, Color(accent, 0.65), 2.0)
		_sol.draw_set_transform(Vector2.ZERO)

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
			_bandeau_tour.text = Translations.T("ctb.a_toi") % CarteCombattantCtb.nom_ui(c.data)
			_montrer_actions(true)
			await _action_choisie
			if not is_inside_tree():
				return
			_montrer_actions(false)
			moteur.jouer(_action_en_attente)
		else:
			_bandeau_tour.text = CarteCombattantCtb.nom_ui(c.data)
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

func _montrer_actions(on: bool) -> void:
	_btn_attaquer.visible = on
	_btn_defendre.visible = on
	_objet_en_attente = null
	# Bouton Objet : n'existe que si l'inventaire de run est non vide
	# (« contenu absent, pas grisé ») — retiré immédiatement sinon.
	if _btn_objet != null:
		_rangee_boutons.remove_child(_btn_objet)
		_btn_objet.queue_free()
		_btn_objet = null
	if on and inventaire_fournisseur.is_valid():
		var inv: Array = inventaire_fournisseur.call()
		if not inv.is_empty():
			_btn_objet = ExpeStyle.bouton(Translations.T("ctb.objet"), UIColors.CYBER_BUTIN)
			_btn_objet.pressed.connect(_sur_objet)
			_rangee_boutons.add_child(_btn_objet)
	UIHelpers.clear_children_now(_rangee_cibles)
	if not on:
		_bandeau_tour.text = ""
		_mettre_cibles_en_avant(false)

func _sur_attaquer() -> void:
	if not _btn_attaquer.visible:
		return   # pas d'activation joueur ouverte (press programmatique hors tour)
	_objet_en_attente = null
	var vivants: Array[CtbCombattant] = _ennemis_vivants()
	if vivants.size() <= 1:
		_valider_action({"type": Enums.ActionCtb.ATTAQUER,
				"cible": vivants[0] if vivants.size() == 1 else null})
		return
	_montrer_choix_cibles(vivants)

# Rangée de choix de cible (attaque OU objet ciblé — _objet_en_attente) :
# boutons nominatifs + cartes ennemies cliquables + Annuler.
func _montrer_choix_cibles(vivants: Array[CtbCombattant]) -> void:
	UIHelpers.clear_children_now(_rangee_cibles)
	_rangee_cibles.add_child(ExpeStyle.label_mono(
			Translations.T("ctb.choisir_cible"), 12, UIColors.CYBER_TEXTE_MUTED))
	for cb in vivants:
		var b := ExpeStyle.bouton(CarteCombattantCtb.nom_ui(cb.data),
				UIColors.CYBER_ACCENT_2, 13, Vector2(0, 34))
		b.pressed.connect(_sur_cible_cliquee.bind(cb))
		_rangee_cibles.add_child(b)
	var annuler := ExpeStyle.bouton(Translations.T("ctb.annuler"),
			UIColors.CYBER_TEXTE_MUTED, 13, Vector2(0, 34))
	annuler.pressed.connect(func() -> void:
		_objet_en_attente = null
		UIHelpers.clear_children_now(_rangee_cibles)
		_mettre_cibles_en_avant(false))
	_rangee_cibles.add_child(annuler)
	_mettre_cibles_en_avant(true)
	AudioManager.play_sfx("ui_select", -10.0)

# Choix d'un objet (chantier 7) : liste de l'inventaire (doublons regroupés
# « ×n »), puis cible si l'effet en demande une.
func _sur_objet() -> void:
	if _btn_objet == null or not _btn_objet.visible:
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
		var b := ExpeStyle.bouton(
				nom if int(grp["n"]) == 1 else "%s ×%d" % [nom, int(grp["n"])],
				UIColors.CYBER_BUTIN, 13, Vector2(0, 34))
		b.pressed.connect(_sur_objet_choisi.bind(objet))
		_rangee_cibles.add_child(b)
	var annuler := ExpeStyle.bouton(Translations.T("ctb.annuler"),
			UIColors.CYBER_TEXTE_MUTED, 13, Vector2(0, 34))
	annuler.pressed.connect(func() -> void:
		UIHelpers.clear_children_now(_rangee_cibles))
	_rangee_cibles.add_child(annuler)
	AudioManager.play_sfx("ui_select", -10.0)

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
	_action_en_attente = action
	_action_choisie.emit()

func _mettre_cibles_en_avant(on: bool) -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).marquer_ciblable(
				on and not cb.est_joueur() and cb.est_vivant())

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
	_rafraichir_file()
	_rafraichir_orbes()

# File d'initiative : ordre des N_FILE prochaines activations (sans valeurs
# numériques — l'ordre suffit), recalculée après chaque action.
func _rafraichir_file() -> void:
	UIHelpers.clear_children_now(_file_box)
	for cb in moteur.prevoir_ordre(N_FILE):
		var couleur := ExpeStyle.accent_camp(cb.est_joueur())
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", ExpeStyle.style_chip(couleur))
		var m := UIHelpers.margin_of(4)
		m.add_child(ExpeStyle.label_mono(CarteCombattantCtb.nom_ui(cb.data), 11,
				couleur.lightened(0.35)))
		chip.add_child(m)
		_file_box.add_child(chip)

func _marquer_actif(c: CtbCombattant) -> void:
	for cb: CtbCombattant in _cartes:
		(_cartes[cb] as CarteCombattantCtb).marquer_actif(cb == c)

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
	if _couche_scene != null:
		_couche_scene.scale = Vector2.ONE
	if not _duel_acteurs.is_empty():
		_duel_acteurs = []
		_rafraichir_orbes()   # réapplique le fondu différé d'un vaincu du duel

# Zoom-DUEL (attaque du joueur seulement — voir les constantes DUEL_*) :
# glissement simultané des deux personnages vers le centre + punch-in de la
# scène, tenue le temps du coup, puis retour aux emplacements. Crit = zoom
# plus marqué.
func _duel_attaque(att: CtbCombattant, cible: CtbCombattant, crit: bool) -> void:
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
	# Le joueur vient de gauche, sa cible lui fait face à droite.
	var pos_att := _pos_depuis_pied(att, centre + Vector2(-DUEL_ECART_PX * 0.5, 0.0))
	var pos_cib := _pos_depuis_pied(cible, centre + Vector2(DUEL_ECART_PX * 0.5, 0.0))
	_duel_restaure = [[noeud_att, noeud_att.position], [noeud_cib, noeud_cib.position]]
	_duel_acteurs = [att, cible]
	_couche_scene.pivot_offset = centre - Vector2(0.0, DUEL_FOCUS_HAUT_PX)
	var zoom := DUEL_ZOOM_CRIT if crit else DUEL_ZOOM
	var f := facteur_delais
	_duel_tween = create_tween()
	_duel_tween.tween_property(_couche_scene, "scale", Vector2.ONE * zoom,
			DUEL_DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_duel_tween.parallel().tween_property(noeud_att, "position", pos_att,
			DUEL_DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_duel_tween.parallel().tween_property(noeud_cib, "position", pos_cib,
			DUEL_DUREE_IN * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_duel_tween.tween_interval(DUEL_TENUE * f)
	_duel_tween.tween_property(_couche_scene, "scale", Vector2.ONE,
			DUEL_DUREE_OUT * f).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_duel_tween.parallel().tween_property(noeud_att, "position",
			_duel_restaure[0][1] as Vector2, DUEL_DUREE_OUT * f)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_duel_tween.parallel().tween_property(noeud_cib, "position",
			_duel_restaure[1][1] as Vector2, DUEL_DUREE_OUT * f)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_duel_tween.finished.connect(func() -> void:
		_duel_restaure.clear()
		_duel_tween = null
		_duel_acteurs = []
		_rafraichir_orbes())   # fondu différé du vaincu, une fois le duel joué

func _sur_evenement(e: Dictionary) -> void:
	if not is_inside_tree():
		return
	match str(e.get("type", "")):
		"attaque":
			# Sprites Spine : l'attaquant joue Attack_CaC, la cible joue Hit
			# (ou Death si le coup tue — jouer_mort est prioritaire et
			# verrouille les animations suivantes).
			var sprite_att: SpriteSpinePersonnage = _sprites.get(e["attaquant"])
			if sprite_att != null:
				sprite_att.jouer_attaque()
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
			# les activations ennemies restent sobres (retour Rhend).
			var attaquant := e["attaquant"] as CtbCombattant
			if attaquant.est_joueur():
				_duel_attaque(attaquant, cible, crit)
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
func _intro() -> void:
	var titre := ExpeStyle.label_mono(Translations.T("ctb.combat_titre"), 34,
			UIColors.CYBER_ACCENT)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voile_contenu.add_child(titre)
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
	await _pause(1.1 if embuscade else 0.7)
	if not is_inside_tree():
		return
	if facteur_delais > 0.0:
		var tw := create_tween()
		tw.tween_property(_voile, "color:a", 0.0, 0.45)
		await tw.finished
	else:
		_voile.color.a = 0.0
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
