# ============================================================
# CombatUiSkin — DA RÉELLE de Christophe pour l'écran de combat CTB
# (livraison « Ui combat », 07/09/2026). class_name statique (pattern
# ExpeStyle/Balance/UIHelpers, PAS un autoload).
#
# Remplace, POUR L'ÉCRAN DE COMBAT SEULEMENT, la peau cyberpunk intérimaire
# (`ExpeStyle`/`UIColors.CYBER_*`) par les textures livrées :
# `assets/ui/Combat/*.png` + `assets/ui/Icone/*.png` + `assets/ui/UI_Cursor.png`.
# Les autres écrans d'expédition (lancement, carte, recap, Game Over) restent
# sur la peau intérimaire — elle n'a pas encore reçu sa propre DA.
#
# ⚠ ROUGE (`*_Ennemis`) : la règle projet « rouge réservé à l'Artefact/danger »
# visait la peau intérimaire. Christophe livre ICI un rouge net pour tout le
# camp adverse (boutons/panneaux/HP/portraits) — c'est un choix de chara design
# assumé (mockups `assets/ui/UI_Concept2..4.png`), pas une régression : la
# règle ne s'applique plus à cet écran une fois sa vraie DA posée.
#
# Chaque famille d'assets est livrée en couches à EMPILER (mêmes dimensions
# entre couches d'une même famille) : *_Back (fond plein), *_Border (contour,
# transparent au centre), *_Aura (halo, optionnel) — jamais un seul fichier
# « fini ». `_composer()` les fusionne UNE fois en une texture (cache par clé),
# `_style_texture()` l'enveloppe dans un StyleBoxTexture prêt à poser sur un
# thème (`modulate_color` gère l'atténuation « désactivé » sans recomposer).
#
# Chantier UI_Concept2 (07/09/2026, retour Rhend « précision de l'intégration ») :
# Panel_Separator_01/02/03 et Cyber_Line sont désormais BRANCHÉS —
# `CombatPanneauStats` (panneau de stats bas d'écran) et les traits
# bouton → héros de `CombatCtbUi._dessiner_liens_actions`. Reste sans usage
# identifié : Icone_Sapiens.
# ============================================================
class_name CombatUiSkin

const DOSSIER := "res://assets/ui/Combat/"
const DOSSIER_ICONES := "res://assets/ui/Icone/"

# ── Bouton d'action (Attaquer/Défendre/Compétence/Objet/Annuler) : TOUJOURS
# le camp joueur, l'IA n'affiche jamais de bouton. Le mockup n'a qu'UN style
# de bouton pour toutes les actions — le texte seul distingue leur nature.
const BOUTON_BACK   := preload(DOSSIER + "UI_Combat_Bouton_Back_Hero.png")
const BOUTON_BORDER := preload(DOSSIER + "UI_Combat_Bouton_Border_Hero.png")
const BOUTON_AURA   := preload(DOSSIER + "UI_Combat_Bouton_Aura_Hero.png")

# ── Panneau de carte combattant (par camp).
const PANEL_BACK_HERO     := preload(DOSSIER + "UI_Combat_Panel_Back_Hero.png")
const PANEL_BORDER_HERO   := preload(DOSSIER + "UI_Combat_Panel_Border_Hero.png")
const PANEL_AURA_HERO     := preload(DOSSIER + "UI_Combat_Panel_Aura_Hero.png")
const PANEL_BACK_ENNEMI   := preload(DOSSIER + "UI_Combat_Panel_Back_Ennemis.png")
const PANEL_BORDER_ENNEMI := preload(DOSSIER + "UI_Combat_Panel_Border_Ennemis.png")
const PANEL_AURA_ENNEMI   := preload(DOSSIER + "UI_Combat_Panel_Aura_Ennemis.png")

# ── Barre de PV (TextureProgressBar : under/progress/over natifs, les trois
# calques partagent exactement la même taille source — fait pour ça).
const HP_BACK           := preload(DOSSIER + "UI_Combat_HP_Back.png")
const HP_LIFE           := preload(DOSSIER + "UI_Combat_HP_Life.png")
const HP_BORDER_HERO    := preload(DOSSIER + "UI_Combat_HP_Border_Hero.png")
const HP_BORDER_ENNEMI  := preload(DOSSIER + "UI_Combat_HP_Border_Ennemis.png")

# ── Cadre de la file d'initiative (par camp), halo pour l'entrée en tête.
const TOUR_BACK           := preload(DOSSIER + "UI_Combat_Turn_back.png")
const TOUR_BORDER_HERO    := preload(DOSSIER + "UI_Combat_Turn_Border_Hero.png")
const TOUR_BORDER_ENNEMI  := preload(DOSSIER + "UI_Combat_Turn_Border_Ennemis.png")
const TOUR_AURA_HERO      := preload(DOSSIER + "UI_Combat_Turn_back_Aura_Hero.png")
const TOUR_AURA_ENNEMI    := preload(DOSSIER + "UI_Combat_Turn_back_Aura_Ennemis.png")

# ── Splash d'intro (« ENNEMY DETECTED », voir UI_Concept1.png).
const INTRO_BACK       := preload(DOSSIER + "UI_Combat_Intro_Back.png")
const INTRO_BACK_CYBER := preload(DOSSIER + "UI_Combat_Intro_Back_Cyber.png")
const INTRO_SPEAR      := preload(DOSSIER + "UI_Combat_Intro_Spear_Artefact.png")
const ICONE_ARTEFACT   := preload(DOSSIER_ICONES + "UI_Icone_Artefact.png")

# ── Réticule de ciblage (remplace le "▼" ASCII dessiné en scène).
const RETICULE := preload(DOSSIER_ICONES + "UI_Icone_Arrow_2.png")

# ── Soulignements décoratifs du panneau de stats (CombatPanneauStats) —
# posés sous les labels DMG/PROT/le titre Status, HÉRO uniquement livré.
const SEPARATEUR_01 := preload(DOSSIER + "UI_Combat_Panel_Separator_01_Hero.png")
const SEPARATEUR_02 := preload(DOSSIER + "UI_Combat_Panel_Separator_02_Hero.png")
const SEPARATEUR_03 := preload(DOSSIER + "UI_Combat_Panel_Separator_03_Hero.png")

# ── Chevron compact (compteur de tour de la file d'initiative).
const CHEVRON := preload(DOSSIER_ICONES + "UI_Icone_Arrow_1.png")

# ── Connecteur bouton → personnage (file d'initiative + éventail d'actions).
const CYBER_LINE := preload(DOSSIER + "UI_Combat_Cyber_Line.png")

# ── Portraits par personnage (file d'initiative compacte) — livraison
# « Turn_Icone_Ennemis » du 16/09/2026 : PAS un fichier par id de combat
# (l'ancien contrat, jamais livré dans ce dossier) mais un fichier par
# CRÉATURE × PALIER, sous `Combat/Turn_Icone/`, nommé sur le NOM affiché
# dans le registre (`FlameBot`/`WorkBot`, voir SpinePersonnagesData) — pas
# l'id bestiaire `creature_*`.
const DOSSIER_TOUR_ICONE := DOSSIER + "Turn_Icone/"

# Splash « ENNEMY DETECTED » (3 calques + glyphe), PARTAGÉ entre l'intro de
# CombatCtbUi et l'écran de chargement affiché pendant sa construction
# (CombatLoadingScreen, retour Rhend 07/09/2026 : le décor de ville parallaxé
# + le sprite Spine du héros se montent en un bloc synchrone assez long pour
# figer l'écran — ce splash y est déjà posé, poser le MÊME dès l'ouverture du
# combat masque ce blocage au lieu de le laisser geler l'écran précédent) —
# une seule source, jamais deux copies qui pourraient diverger.
static func splash_ennemi_detecte() -> Control:
	var visuel := Control.new()
	visuel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for texture in [INTRO_BACK, INTRO_BACK_CYBER, INTRO_SPEAR]:
		var couche := TextureRect.new()
		couche.texture = texture
		# EXPAND_IGNORE_SIZE : sans lui, le TextureRect garde la taille NATIVE
		# de la texture (4770×2655) au lieu de suivre son rect. STRETCH_SCALE
		# (pas d'aspect) partout : les 3 calques partagent EXACTEMENT le même
		# canevas source, un mode différent désalignerait les lances par
		# rapport au circuit.
		couche.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		couche.stretch_mode = TextureRect.STRETCH_SCALE
		couche.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		couche.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visuel.add_child(couche)
	var glyphe := TextureRect.new()
	glyphe.texture = ICONE_ARTEFACT
	glyphe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyphe.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyphe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyphe.set_anchors_preset(Control.PRESET_CENTER)
	glyphe.offset_left = -90.0
	glyphe.offset_top = -90.0
	glyphe.offset_right = 90.0
	glyphe.offset_bottom = 90.0
	visuel.add_child(glyphe)
	return visuel

# ── Curseur personnalisé (source 1032×1032 — Godot plafonne un curseur à
# 256×256 ; redimensionné une fois, en cache).
const CURSEUR_SOURCE := preload("res://assets/ui/UI_Cursor.png")
# Taille réduite de MOITIÉ (retour Rhend 17/09/2026 : « le nouveau curseur est
# trop gros ») — hotspot mis à l'échelle avec elle pour que la pointe de la
# flèche reste au même coin relatif.
const CURSEUR_TAILLE_PX := 24
const CURSEUR_HOTSPOT := Vector2(2, 2)   # pointe de la flèche, coin haut-gauche

static var _cache_textures: Dictionary = {}   # clé (String) → ImageTexture composée
static var _curseur_texture: ImageTexture = null

# ─── Composition de couches (Back [+ Aura] + Border) ─────────

static func _image_de(tex: Texture2D) -> Image:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img

# Les calques d'une famille (Back/Aura/Border) sont livrés sur un canevas
# souvent plus grand que leur contenu VISIBLE (marge morte transparente
# autour du rectangle dessiné). Sans recadrage, la texture composée traîne
# cette marge : stretchée à un ratio très éloigné du natif (le panneau de
# stats, très large et bas, contre le rectangle quasi carré d'origine), le
# CONTENU posé dessus (marges calculées sur le Control réel) se retrouvait
# visuellement décalé par rapport à la bordure dessinée — retour Rhend :
# « le texte déborde ». `get_used_rect()` (calculé sur le premier calque,
# Back) donne le rectangle réellement peint ; recadrer TOUS les calques sur
# CE même rectangle (pas leur propre used_rect, qui pourrait légèrement
# différer d'un calque à l'autre) les garde alignés entre eux.
static func _composer(couches: Array) -> ImageTexture:
	var base: Image = _image_de(couches[0])
	var rect := base.get_used_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		rect = Rect2i(Vector2i.ZERO, base.get_size())
	base = base.get_region(rect)
	for i in range(1, couches.size()):
		var c: Image = _image_de(couches[i]).get_region(rect)
		base.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(base)

static func _texture_composee(cle: String, couches: Array) -> ImageTexture:
	if not _cache_textures.has(cle):
		_cache_textures[cle] = _composer(couches)
	return _cache_textures[cle]

static func _style_texture(cle: String, couches: Array, alpha := 1.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _texture_composee(cle, couches)
	s.modulate_color = Color(1, 1, 1, alpha)
	return s

# ─── Bouton d'action ──────────────────────────────────────────

# Marge intérieure du bouton : SANS elle, le texte touche (voire déborde de)
# la bordure — la texture composée n'a aucune marge de contenu par défaut
# (retour Rhend : « les textes dépassent de leur conteneur »).
const BOUTON_MARGE_H := 14.0
const BOUTON_MARGE_V := 6.0

static func _style_bouton(etat: String) -> StyleBoxTexture:
	var s: StyleBoxTexture
	match etat:
		"survol", "presse":
			s = _style_texture("bouton_survol", [BOUTON_BACK, BOUTON_AURA, BOUTON_BORDER])
		"desactive":
			s = _style_texture("bouton_normal", [BOUTON_BACK, BOUTON_BORDER], 0.45)
		_:
			s = _style_texture("bouton_normal", [BOUTON_BACK, BOUTON_BORDER])
	s.content_margin_left = BOUTON_MARGE_H
	s.content_margin_right = BOUTON_MARGE_H
	s.content_margin_top = BOUTON_MARGE_V
	s.content_margin_bottom = BOUTON_MARGE_V
	return s

# Bouton d'action neuf : chrome RÉEL de Christophe, style unique quelle que
# soit l'action (le mockup ne distingue les actions que par leur texte — plus
# d'accent par catégorie comme sur la peau intérimaire).
static func bouton(texte: String, taille_police := 16, taille_min := Vector2(0, 46)) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = taille_min
	b.add_theme_font_override("font", ExpeStyle.police_mono())
	b.add_theme_font_size_override("font_size", taille_police)
	b.add_theme_color_override("font_color", UIColors.CYBER_TEXTE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", UIColors.CYBER_TEXTE_MUTED)
	b.add_theme_stylebox_override("normal", _style_bouton("normal"))
	b.add_theme_stylebox_override("hover", _style_bouton("survol"))
	b.add_theme_stylebox_override("pressed", _style_bouton("presse"))
	b.add_theme_stylebox_override("disabled", _style_bouton("desactive"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

# ─── Panneau de carte combattant ──────────────────────────────

# `actif` pose le halo (Aura) — l'état « ciblable » (or) reste un OVERLAY
# procédural posé par l'appelant (CarteCombattantCtb) : aucune texture or
# n'a été livrée, et c'est un état de JEU (pas un habillage).
static func style_panneau_carte(camp_joueur: bool, actif: bool) -> StyleBoxTexture:
	var back: Texture2D = PANEL_BACK_HERO if camp_joueur else PANEL_BACK_ENNEMI
	var border: Texture2D = PANEL_BORDER_HERO if camp_joueur else PANEL_BORDER_ENNEMI
	var aura: Texture2D = PANEL_AURA_HERO if camp_joueur else PANEL_AURA_ENNEMI
	var cle := "panel_%s_%s" % [str(camp_joueur), str(actif)]
	var couches: Array = [back]
	if actif:
		couches.append(aura)
	couches.append(border)
	return _style_texture(cle, couches)

# ─── Barre de PV ──────────────────────────────────────────────

# TextureProgressBar : under/progress/over correspondent EXACTEMENT à
# Back/Life/Border (mêmes dimensions sources) — pas de composition nécessaire.
# `nine_patch_stretch` = true : SANS lui, Godot impose la taille NATIVE de
# `texture_under` (328×48) comme taille minimale — la barre restait énorme
# quelle que soit `custom_minimum_size` (retour Rhend 07/09/2026). Marges à
# 0 : simple étirement, pas un vrai 9-slice (le contour n'a pas de coins à
# préserver). Le remplissage (Life) reste NON teinté par la fraction de PV
# (choix DA de Christophe, cf. mockups) : le texte "PV : x/y" garde l'info
# exacte, posé PAR-DESSUS la barre par l'appelant (CarteCombattantCtb) pour
# gagner la hauteur qu'occupait sa propre ligne — et la couleur de la
# fraction bascule sur CE texte (CarteCombattantCtb._couleur_pv).
static func barre_pv(camp_joueur: bool) -> TextureProgressBar:
	var b := TextureProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	b.texture_under = HP_BACK
	b.texture_progress = HP_LIFE
	b.texture_over = HP_BORDER_HERO if camp_joueur else HP_BORDER_ENNEMI
	b.nine_patch_stretch = true
	b.custom_minimum_size = Vector2(0, 20)
	return b

# ─── Cadre de la file d'initiative ────────────────────────────

static func style_chip_tour(camp_joueur: bool, en_tete: bool) -> StyleBoxTexture:
	var border: Texture2D = TOUR_BORDER_HERO if camp_joueur else TOUR_BORDER_ENNEMI
	var aura: Texture2D = TOUR_AURA_HERO if camp_joueur else TOUR_AURA_ENNEMI
	var cle := "tour_%s_%s" % [str(camp_joueur), str(en_tete)]
	var couches: Array = [TOUR_BACK]
	if en_tete:
		couches.append(aura)
	couches.append(border)
	return _style_texture(cle, couches)

# Portrait d'un ENNEMI pour sa puce de file d'initiative, au palier affiché
# (0 = Commun … 4 = Légendaire, mêmes indices que ses skins Spine de palier —
# `nom` et `palier` viennent de `SpinePersonnagesData`/`CombatCtbUi.
# _palier_ennemi`, jamais lus ici). `null` si la livraison n'a pas (encore)
# ce personnage/ce palier ; l'appelant retombe alors sur l'initiale du nom
# (repli propre, même esprit que SpriteSpinePersonnage face à un squelette
# manquant).
static func portrait_ennemi(nom: String, palier: int) -> Texture2D:
	var chemin := "%sUI_Combat_Turn_back_%s_Nv_%d.png" % [DOSSIER_TOUR_ICONE, nom, palier + 1]
	if not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Texture2D

# Portrait du HÉROS, même contrat, indexé par NIVEAU D'ÉQUIPEMENT (1..6, pas
# un palier de rareté 0-based — cohérent avec `SpriteSpinePersonnage.
# creer_heros`). ⚠ PAS ENCORE LIVRÉ à cette date (seuls les ennemis le sont,
# commit « Turn_Icone_Ennemis ») : le nom de fichier ci-dessous est une
# ANTICIPATION de la convention déjà vue sur les ennemis (`<Nom>_Nv_<n>`) —
# à vérifier contre le fichier réel le jour de la livraison, `ResourceLoader.
# exists` dégrade proprement en attendant (repli sur l'initiale, comme
# aujourd'hui).
static func portrait_heros(niveau: int) -> Texture2D:
	var chemin := "%sUI_Combat_Turn_back_Relic_Nv_%d.png" % [DOSSIER_TOUR_ICONE, niveau]
	if not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Texture2D

# ─── Portrait du héros GÉNÉRÉ à la volée (aucun fichier livré) ────────
#
# `portrait_heros` ci-dessus n'a AUCUNE livraison pour le héros à ce jour —
# retour Rhend 17/09/2026 : au lieu d'attendre, on rend nous-mêmes une
# vignette via un SubViewport isolé, avec un sprite Spine JETABLE monté pour
# l'occasion. Cadrage demandé : « juste la tête et le cou sans l'épée avec
# les cheveux » — `SpriteSpinePersonnage.poser_skin_portrait` purge tout le
# reste (torse, bras, jambes, épée, VFX) et rend les BORNES RÉELLEMENT
# dessinées de ce qui reste ; ce sont CES bornes qui cadrent le SubViewport,
# pas un ratio deviné à la main — robuste à n'importe quel niveau
# d'équipement/coiffure/visage.
#
# ASYNCHRONE : le rendu d'un SubViewport est DIFFÉRÉ d'au moins une frame —
# l'appelant doit `await` (ou lancer en fire-and-forget, voir CombatCtbUi.
# _demarrer_generation_portrait_heros). `hote` = un nœud DÉJÀ dans l'arbre,
# utilisé UNIQUEMENT comme point d'attache temporaire du SubViewport (`hote.
# add_child`) — retiré et libéré (`queue_free`) dès la capture faite, rien ne
# persiste que la texture mise en CACHE (par niveau/cosmétique/coiffure/genre :
# gratuit dès la 2e fois pour la même apparence, y compris d'un combat à
# l'autre). `null` en tête headless (aucun contexte de rendu réel à capturer,
# même garde que `installer_curseur`) ou si le runtime spine-godot/le
# registre/l'apparence manquent — dégradation propre, comme le reste de ce
# fichier face à un export absent.
const TAILLE_PORTRAIT_GENERE_PX := 96
const MARGE_PORTRAIT_FRAC := 0.12   # marge de chaque côté du cadrage mesuré

static var _cache_portraits_heros: Dictionary = {}   # "niv_cos_coif_genre" → Texture2D

static func generer_portrait_heros(niveau: int, cosmetique: int, coiffure: int,
		hote: Node, genre: int = 0) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var cle := "%d_%d_%d_%d" % [niveau, cosmetique, coiffure, genre]
	if _cache_portraits_heros.has(cle):
		# Un retour synchrone ici casserait le contrat "toujours différé d'au
		# moins une frame" (voir doc au-dessus) : l'appelant fire-and-forget
		# (CombatCtbUi._demarrer_generation_portrait_heros) le suppose pour
		# rafraîchir la file APRÈS la construction en cours — un cache hit
		# pendant `_construire()` (2e combat avec la même apparence, ex.
		# ScreenshotTool) rappellerait sinon `_rafraichir_file()` alors que
		# `_file_box` n'existe pas encore.
		await Engine.get_main_loop().process_frame
		return _cache_portraits_heros[cle]
	if not SpriteSpinePersonnage.disponible() or not is_instance_valid(hote) \
			or not hote.is_inside_tree():
		return null
	var registre := SpinePersonnagesData.charger()
	var entree: Dictionary = registre.heros() if registre != null else {}
	if entree.is_empty():
		return null
	entree = SpinePersonnagesData.avec_genre(entree, genre)
	var apparences := SpinePersonnagesData.apparences(entree, cosmetique, coiffure)
	if apparences.is_empty():
		return null
	var apparence: Dictionary = apparences[clampi(niveau - 1, 0, apparences.size() - 1)]
	var sprite := SpriteSpinePersonnage.creer(str(entree.get("skel", "")),
			str(entree.get("atlas", "")), apparence,
			SpinePersonnagesData.hauteur_cible_px(entree))
	if sprite == null:
		return null
	var bornes := sprite.poser_skin_portrait(apparence)
	if bornes.size.x <= 0.0 or bornes.size.y <= 0.0:
		sprite.free()
		return null
	var rect_local := sprite.rect_local_depuis_bornes(bornes)
	var cote := maxf(rect_local.size.x, rect_local.size.y) * (1.0 + MARGE_PORTRAIT_FRAC * 2.0)
	if cote <= 0.0:
		sprite.free()
		return null

	var vp := SubViewport.new()
	vp.size = Vector2i(TAILLE_PORTRAIT_GENERE_PX, TAILLE_PORTRAIT_GENERE_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(sprite)
	hote.add_child(vp)

	# Cadre le rect mesuré, CENTRÉ, SANS étirement anisotrope : le plus grand
	# côté du rect pilote l'échelle des DEUX axes (un visage déformé se
	# verrait immédiatement) — TextureRect (CombatCtbUi._rafraichir_file)
	# complète ensuite en STRETCH_KEEP_ASPECT_COVERED, comme les ennemis.
	var echelle := float(TAILLE_PORTRAIT_GENERE_PX) / cote
	sprite.scale = Vector2.ONE * echelle
	var centre := rect_local.position + rect_local.size * 0.5
	sprite.position = Vector2.ONE * (float(TAILLE_PORTRAIT_GENERE_PX) * 0.5) - centre * echelle

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return null
	var img := vp.get_texture().get_image()
	var tex: Texture2D = null
	if img != null:
		# Le cadrage ci-dessus (bornes Spine + marge) laisse une marge morte
		# transparente bien plus large que la marge visée — les bornes
		# `get_bounds()` des attachements débordent leur silhouette RÉELLE
		# (constaté visuellement : la tête n'occupait qu'une fraction du
		# canevas 96×96, contre un cadrage bord-à-bord sur les portraits
		# d'ennemis livrés). On retaille donc sur le rectangle RÉELLEMENT
		# peint (alpha non nul) après coup, plutôt que de fiabiliser la
		# mesure Spine en amont — la puce (TextureRect, STRETCH_KEEP_ASPECT_
		# COVERED) fait ensuite le reste, bord-à-bord comme les ennemis.
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			img = img.get_region(used)
		tex = ImageTexture.create_from_image(img)
		_cache_portraits_heros[cle] = tex
	vp.queue_free()
	return tex

# ─── Panneau de stats détaillé (bas d'écran, CombatPanneauStats) ─────

# Mêmes calques Back/Border que la carte de combattant (`style_panneau_carte`),
# sans Aura : ce sont déjà de simples rectangles étirables (validé sur la
# carte, qui les étire de 2485×541 à 240×~80 sans 9-slice), donc directement
# réutilisables à l'aspect ratio du panneau bas, plus large.
static func style_panneau_stats(camp_joueur: bool) -> StyleBoxTexture:
	var back: Texture2D = PANEL_BACK_HERO if camp_joueur else PANEL_BACK_ENNEMI
	var border: Texture2D = PANEL_BORDER_HERO if camp_joueur else PANEL_BORDER_ENNEMI
	return _style_texture("panel_stats_%s" % str(camp_joueur), [back, border])

# ─── Pastille de statut (CarteCombattantCtb) ──────────────────
#
# Remplace `ExpeStyle.style_chip` POUR LE COMBAT SEULEMENT (17/09/2026,
# retour Rhend : « travail propre d'highlight/ombre-lumière sur toute l'UI
# de combat ») — `style_chip` reste un plat fond+bordure sans aucun modelé de
# lumière, correct pour la carte d'expédition mais plat une fois posé sur un
# décor maintenant éclairé (voir CombatCtbUi.VOILE_ALPHA_DEFAUT). Une vraie
# pastille de chrome a une OMBRE PORTÉE douce (elle « flotte » au-dessus du
# décor, cohérent avec l'ombre portée sous chaque personnage) et un fond
# légèrement plus clair pour se détacher — pas de dégradé (StyleBoxFlat n'en
# fait pas nativement) mais l'ombre suffit à donner du relief sans passer par
# un Control à dessin procédural pour un si petit élément.
static func style_pill(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIColors.CYBER_BG_PANEL_2, 0.92).lightened(0.06)
	s.border_color = Color(accent, 0.85)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.shadow_color = Color(0, 0, 0, 0.40)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	return s

# ─── Connecteur bouton → personnage ───────────────────────────────────

static var _couleur_lien_cache := Color(0, 0, 0, 0)

# Couleur du trait bouton → personnage, ÉCHANTILLONNÉE sur `CYBER_LINE` au
# runtime (premier pixel opaque trouvé — l'asset est un simple trait uni,
# n'importe lequel convient) plutôt que recopiée à la main : elle suit
# Christophe si le fichier est reteinté. La géométrie, elle, reste
# PROCÉDURALE (`CombatCtbUi._dessiner_liens_actions`) — un angle fixe ne se
# stretch pas vers une cible arbitraire, seule la couleur vient de l'asset.
static func couleur_lien() -> Color:
	if _couleur_lien_cache.a <= 0.0:
		var img := _image_de(CYBER_LINE)
		var taille := img.get_size()
		for y in taille.y:
			for x in taille.x:
				var p := img.get_pixel(x, y)
				if p.a > 0.5:
					_couleur_lien_cache = p
					break
			if _couleur_lien_cache.a > 0.0:
				break
		if _couleur_lien_cache.a <= 0.0:
			_couleur_lien_cache = UIColors.CYBER_ACCENT   # repli si l'asset venait à manquer
	return _couleur_lien_cache

# ─── Curseur personnalisé ─────────────────────────────────────

# Sans effet en tête headless (aucun DisplayServer réel) — évite un
# avertissement inutile dans les suites de tests CI.
static func installer_curseur() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _curseur_texture == null:
		var img: Image = CURSEUR_SOURCE.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CURSEUR_TAILLE_PX, CURSEUR_TAILLE_PX, Image.INTERPOLATE_LANCZOS)
		_curseur_texture = ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(_curseur_texture, Input.CURSOR_ARROW, CURSEUR_HOTSPOT)

static func retirer_curseur() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
