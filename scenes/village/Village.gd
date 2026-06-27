# ============================================================
# Village.gd — Hub central du jeu.
#
# Éclosion : orbe cliquable (100 clics) → naissance du Village en T0.
# T0+      : hub hexagonal + panneau JRPG glissant (40/60 viewport).
#
# Widgets visuels dans scenes/village/widgets/ :
#   CircleRing, ClickOrb, HexItem, JRPGPanel, XPCard, SettingsOverlay,
#   VillageBackdrop (fond d'ambiance animé, évolue avec le palier)
#
# Le contenu des panneaux glissants (Héros / Expéditions / Forge) est délégué à
# des modules dédiés dans scenes/village/panels/ ; ils reçoivent ce nœud (host)
# pour accéder à rp_content et aux helpers partagés (make_evolve_btn, etc.).
# ============================================================
class_name Village
extends Control

# ─── Constantes ───────────────────────────────────────────────
const RING_RADIUS  := 165.0
const HEX_SIZE     := Vector2(152.0, 152.0)
# Distance (depuis le centre de l'hexagone owner, vers l'extérieur) du point
# d'énergie au bout du lien : là où flotte la boule cliquable, et d'où naît le
# quartier. Plus grand = quartiers plus éloignés du village → l'espace respire,
# maintenant qu'on peut se balader librement autour de la place centrale.
const DISTRICT_LINK_REACH := 200.0
# Départ du lien, juste hors du cercle de l'owner (sinon masqué par l'hexagone).
const DISTRICT_LINK_START := 72.0
# Écart entre l'extrémité du lien et le bord du cercle du quartier.
const DISTRICT_RING_GAP   := 20.0
# Durée de la montée de l'étincelle le long du fil avant l'éclosion du quartier.
const BOULE_TRAVEL_DUR    := 0.75
# Panneau droit : fraction de l'écran qu'il occupe quand il est ouvert.
# Le hub est réduit (HUB_PANEL_SCALE) et recentré au milieu de l'espace
# restant — le village entier doit y tenir (contenu utile ≈ 860 px).
const PANEL_FRACTION   := 0.5
const HUB_PANEL_SCALE  := 0.72
# Échelle du hub au repos (sans panneau). < 1 : on « dézoome » légèrement pour
# laisser respirer l'espace autour du village (préfigure l'espace explorable).
const HUB_BASE_SCALE   := 0.85
# Zoom molette (exploration libre) : le repos (HUB_BASE_SCALE) est le zoom MAX
# (on ne grossit pas au-delà) ; on peut dézoomer jusqu'à HUB_MIN_SCALE pour voir
# l'ensemble des quartiers. WHEEL_STEP = facteur par cran de molette.
const HUB_MIN_SCALE    := 0.35
const ZOOM_WHEEL_STEP  := 1.12
const TIER_0_COLOR := UIColors.VILLAGE_NASCENT

# La phase d'éclosion (orbe cliquable → éveil → éclosion) vit dans
# BirthSequence (scenes/village/widgets/BirthSequence.gd).

# [label, icon, tier_min, callback_name, panel_id]
# tier_min = palier de Maîtrise du VILLAGE requis pour afficher l'hexagone
# (filtrage uniforme dans _build_hub). Le Village éclot en T0 avec le héros
# et les expéditions déjà disponibles ; la Forge arrive en T1, etc.
const MENU_ITEMS: Array = [
	["HÉROS",       "👤", 0, "_go_hero",      "hero"      ],
	["EXPÉDITIONS", "⚔",  0, "_go_adventure", "adventure" ],
	["FORGE",       "🔨", 1, "_go_forge",     "forge"     ],
	["SANCTUAIRE",  "✦",  2, "_go_sanctuary", "sanctuary" ],
	["RELIQUE",     "◈",  3, "_go_relic",     "relic"     ],
	["?",           "?",  4, "_go_tbd",       "tbd"       ],
]

const PANEL_TITLES: Dictionary = {
	"hero":      "HÉROS",
	"adventure": "EXPÉDITIONS",
	"forge":     "FORGE",
	"sanctuary": "SANCTUAIRE",
	"relic":     "RELIQUE",
	"tbd":       "?",
}

# ─── Quartiers explorables ────────────────────────────────────
# Chaque élément de la place centrale (« owner » = son panel_id dans MENU_ITEMS)
# peut révéler son propre quartier : un mini-hub (widget District) aux pièces
# PROPRES — ids/icônes/libellés distincts d'un quartier à l'autre.
#   owner_id → { "title_key": clé i18n du titre, "rooms": [ [room_panel_id, icon], … ] }
# Ajouter un quartier = une entrée ici + les clés i18n (le title_key et un
# panel.<room_pid> par pièce) + le contenu des panneaux des pièces. Le lien
# d'énergie n'apparaît que lorsque l'owner est débloqué (présent sur l'anneau).
# Aucune plomberie supplémentaire (liens/boules/caméra sont génériques).
const DISTRICTS: Dictionary = {
	"hero": {
		"title_key": "district.hero.title",
		"rooms": [
			["district_house",    "👤"],
			["district_garden",   "🌿"],
			["district_training", "⚔"],
		],
	},
	"adventure": {
		"title_key": "district.adventure.title",
		"rooms": [
			["district_reliquaire", "🏆"],
			["district_tour",       "🗼"],
			["district_palissade",  "🛡"],
		],
	},
	"forge": {
		"title_key": "district.forge.title",
		"rooms": [
			["district_armurier",  "🛡"],
			["district_forgeron",  "⚒"],
			["district_joaillier", "💍"],
			["district_couturier", "🧵"],
		],
	},
}

# ─── API publique pour les panels (HeroPanel / Adventure / Forge) ──
# Les modules de scenes/village/panels/ reçoivent ce nœud (host) et ne
# doivent utiliser QUE ces membres publics (+ village_tier(),
# make_evolve_btn(), show_banner(), start_selected_expedition()).

var rp_content            : VBoxContainer  # zone de contenu scrollable du panneau droit
var adv_selected_biome_id := ""            # biome sélectionné dans le panneau Expéditions

# ─── État interne ─────────────────────────────────────────────
var _ring            : CircleRing         # anneau animé central (XP fill + tier visuel)
var _hub_root        : Control            # conteneur du hub hexagonal
var _rp_root         : Control            # panneau droit JRPG — null si fermé
var _rp_title        : Label              # label titre dans la barre du panneau droit
var _rp_scroll       : ScrollContainer    # zone de scroll du panneau droit — null si fermé
var _panel_ui_states : Dictionary = {}    # panel_id → état UI persistant (sections ouvertes…)
var _active_panel_id      := ""           # id du panneau ouvert ("hero", "adventure", …)
var _hex_items            : Dictionary = {}   # panel_id → HexItem, pour gérer l'état sélectionné

# ─── Espace explorable (dézoom + pan libre autour de la place centrale) ──
var _pan                  := Vector2.ZERO      # décalage de déplacement du hub (drag souris)
var _panning              := false             # vrai pendant un glisser-déposer de l'espace
var _zoom                 := HUB_BASE_SCALE    # échelle d'exploration courante (molette), ≤ HUB_BASE_SCALE
# ─── Dimension Village : quartiers (graphe de cercles) ──────────
# Tout est indexé par owner_id (cf. DISTRICTS) pour supporter N quartiers.
# _district_open survit aux reconstructions du hub (source de vérité « ouvert ? ») ;
# les autres dicts référencent des nœuds vivants, recréés à chaque _build_hub.
var _district_open    : Dictionary = {}   # owner_id → bool (persiste au rebuild)
var _districts        : Dictionary = {}   # owner_id → District (node vivant, absent si fermé)
var _links            : Dictionary = {}   # owner_id → EnergyLink (filament, persiste tant que le hub vit)
var _boules           : Dictionary = {}   # owner_id → EnergyBoule cliquable (absent quand le quartier est ouvert)
var _link_outward     : Dictionary = {}   # owner_id → Vector2 (axe radial de l'owner)
var _link_diffuse_end : Dictionary = {}   # owner_id → Vector2 (extrémité du lien à l'état diffus)
var _spark_traveling  : Dictionary = {}   # owner_id → bool (étincelle en cours de montée : anti double-clic)
var _birth            : BirthSequence = BirthSequence.new(self)  # phase d'éclosion (extraite)
var _settings_overlay     : Control = null     # overlay paramètres, null si fermé
var _backdrop             : VillageBackdrop    # fond d'ambiance (halo + poussières)

# ─── DEBUG : prévisualisation des paliers du Village ──────────
# Boutons « Tier − / Tier + » en bas à gauche : montent/descendent le palier
# du Village pour juger l'évolution visuelle du hub sans jouer.
# ⚠ Modifie réellement GameData.village (peut finir dans la sauvegarde).
# Mettre à false avant une release.
const DEBUG_TIER_BUTTONS := false
var _debug_tier_lbl: Label = null

# ─── Init ─────────────────────────────────────────────────────
func _ready() -> void:
	SaveManager.load_save()
	_build_ui()
	_update_badges()
	EventBus.fragment_libere.connect(_on_fragment_libere)
	EventBus.village_tier_change.connect(_on_village_tier_change)
	EventBus.biome_revele.connect(_on_biome_revele)
	EventBus.resources_changed.connect(_on_resources_changed_refresh)
	EventBus.village_buildings_changed.connect(_on_resources_changed_refresh)
	EventBus.equipement_evolue.connect(func(_id, _tier): _on_resources_changed_refresh())
	EventBus.equipment_changed.connect(_on_resources_changed_refresh)
	EventBus.equipment_unlocked.connect(_on_equipment_unlocked)
	EventBus.entity_ready_to_evolve.connect(func(_id): _update_badges())
	EventBus.entity_evolved.connect(func(_id, _t): _update_badges())
	EventBus.adventure_cycle_ended.connect(func(_s): _update_badges())
	EventBus.adventure_stopped.connect(_update_badges)
	GameSettings.language_changed.connect(_on_language_changed)

	# Message d'accueil : au-dessus de tout, avant toute interaction. Réaffiché
	# à chaque démarrage tant que le joueur n'a pas coché « ne plus voir ».
	if not GameSettings.welcome_dismissed:
		add_child(WelcomeOverlay.new())

# Échap ouvre/ferme le panneau Paramètres (les popups modaux — FileDialog —
# consomment Échap avant nous, donc pas de conflit).
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		# Priorité d'Échap : Paramètres ouverts → les fermer ; sinon un panneau
		# ouvert → le fermer ; sinon ouvrir les Paramètres.
		if _settings_overlay and is_instance_valid(_settings_overlay):
			_toggle_settings_overlay()
		elif _rp_root != null:
			_close_panel()
		else:
			_toggle_settings_overlay()

# Palier de Maîtrise du Village — détermine le layout et les couleurs du hub.
func village_tier() -> int:
	return int(GameData.village.get("maitrise_actuelle", 0))

# ─── Construction principale ──────────────────────────────────
# Point d'entrée de construction : tier 0 → orbe cliquable, tier 1+ → hub hexagonal.
func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	# Fond d'ambiance animé (derrière tout le hub, survit aux rebuilds).
	_backdrop = VillageBackdrop.new()
	add_child(_backdrop)

	# Tant que le Village n'a pas éclos : phase préliminaire (100 clics).
	# Une fois éclos, le hub est disponible dès T0 (expéditions incluses).
	if not GameData.village.get("eclos", false):
		_birth.build()
	else:
		_build_hub()

	_build_fullscreen_btn()
	_build_debug_tier_buttons()

# ─── Hub hexagonal ────────────────────────────────────────────
# Construit le hub circulaire avec les hexagones débloqués par le palier du Village.
func _build_hub() -> void:
	var village_maitrise := int(GameData.village.get("maitrise_actuelle", 0))
	var vp     := get_viewport_rect().size
	var tcolor := UIColors.tier_color(village_maitrise)
	var diam_margins := [70.0, 70.0, 82.0, 104.0, 136.0, 164.0]
	var diam: float = RING_RADIUS * 2.0 + float(diam_margins[village_maitrise])

	# Le fond d'ambiance suit le palier (halo plus présent, poussières plus denses).
	if _backdrop:
		_backdrop.set_tier(village_maitrise, tcolor)

	_hub_root = Control.new()
	_hub_root.size = vp
	# Conteneur purement visuel : il NE doit PAS capter la souris, sinon il
	# masque les boutons ⚙ / debug créés avant lui à chaque _rebuild_hub()
	# (le nouveau hub est ajouté au-dessus). Ses enfants restent cliquables.
	_hub_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hub_root)

	_ring = CircleRing.new()
	_ring.ring_color  = tcolor
	_ring.ring_radius = RING_RADIUS
	_ring.tier        = village_maitrise
	# Progression de l'anneau : critère du palier suivant (kills à Commun, bâtiments
	# T0+ à Peu Commun) sur son seuil.
	if village_maitrise < GameData.village_max_tier():
		var prog := _village_progress()
		_ring.fill_fraction = minf(1.0, float(prog[0]) / float(prog[1])) if prog[1] > 0 else 1.0
	else:
		_ring.fill_fraction = 1.0
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	_hub_root.add_child(_ring)

	# ── Centre : nom Village + palier + fragments + conditions ──
	# Centré dans l'anneau, puis LÉGÈREMENT réhaussé (un cran au-dessus du centre
	# exact, pour un meilleur cadrage sans sortir du rond).
	var center_box := VBoxContainer.new()
	var center_lift := -RING_RADIUS * 0.15
	center_box.add_theme_constant_override("separation", 2)
	center_box.anchor_left   = 0.5; center_box.anchor_right  = 0.5
	center_box.anchor_top    = 0.5; center_box.anchor_bottom = 0.5
	center_box.offset_left   = 0.0; center_box.offset_right  = 0.0
	center_box.offset_top    = center_lift; center_box.offset_bottom = center_lift
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_hub_root.add_child(center_box)

	var lname := UIHelpers.label(Translations.T("village.tier_label"), 24, tcolor)
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lname.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	lname.add_theme_constant_override("shadow_offset_y", 2)
	center_box.add_child(lname)

	# Nom du palier encadré de deux fines lignes ornementales (touche JRPG).
	var tier_row := HBoxContainer.new()
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_theme_constant_override("separation", 10)
	center_box.add_child(tier_row)

	tier_row.add_child(_ornament_line(tcolor))
	var ltier := UIHelpers.label(GameData.get_tier_name(village_maitrise), 15, tcolor.lerp(Color.WHITE, 0.40))
	ltier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_row.add_child(ltier)
	tier_row.add_child(_ornament_line(tcolor))

	# Conditions d'évolution du Village (tant que le palier max n'est pas atteint),
	# sinon mention « Palier Max atteint » (garde-fou plafond DUR global).
	if village_maitrise < GameData.village_max_tier():
		_build_village_conditions(center_box, village_maitrise, tcolor)
	else:
		var max_lbl := UIHelpers.label(Translations.T("tier.max_rank"), 12, tcolor.lerp(Color.WHITE, 0.40))
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_box.add_child(max_lbl)

	# ── HexItems : tous gated uniformément par village_maitrise ──
	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool:
		return (d[2] as int) <= village_maitrise
	)
	var n := unlocked.size()

	# Filaments d'énergie : un lien par owner de quartier débloqué, relié à un
	# point flottant dans l'espace radialement vers l'EXTÉRIEUR du hub (cohérent
	# avec la position de son hexagone). Ajoutés avant les hexagones → dessous.
	_build_district_links(unlocked, n, vp, tcolor)

	for i in n:
		var ang := -PI * 0.5 + i * TAU / n
		var pos := Vector2(cos(ang), sin(ang)) * RING_RADIUS
		var d: Array = unlocked[i]
		_make_hex(Translations.T("menu." + (d[4] as String)), d[1], tcolor, pos, Callable(self, d[3]), d[4])

	# Dézoom de repos : hub réduit, centré (pivot au milieu du canvas) et
	# décalé du pan courant (l'espace reste là où le joueur l'a laissé).
	_hub_root.pivot_offset = vp * 0.5
	_hub_root.scale = Vector2.ONE * _zoom
	_hub_root.position = _pan

	_animate_hub_entrance()

# Crée un filament d'énergie par owner de quartier débloqué (présent sur
# l'anneau). Chaque lien part JUSTE hors du cercle de l'owner et flotte vers un
# point d'énergie plus loin sur le même axe radial (vers l'extérieur du hub).
func _build_district_links(unlocked: Array, n: int, vp: Vector2, tcolor: Color) -> void:
	if n <= 0:
		return
	for owner_id in DISTRICTS:
		# Le CHEMIN (route) n'apparaît qu'une fois la route RECONSTRUITE depuis le
		# panneau du hub. Avant : aucun filament/boule/quartier (rien à reconstruire
		# tant qu'on n'a pas de ressources — gate Forge géré dans la section route).
		if not VillageBuildings.route_built(owner_id):
			continue
		var idx := -1
		for i in n:
			if (unlocked[i] as Array)[4] == owner_id:
				idx = i
				break
		if idx < 0:
			continue  # owner pas encore débloqué → pas de lien
		_build_one_link(owner_id, idx, n, vp, tcolor)

# Tend le lien d'un owner donné, puis rétablit son état (boule cliquable, ou
# quartier déjà ouvert si on reconstruit le hub).
func _build_one_link(owner_id: String, idx: int, n: int, vp: Vector2, tcolor: Color,
		animate: bool = false) -> void:
	var ang := -PI * 0.5 + idx * TAU / n
	var outward := Vector2(cos(ang), sin(ang))         # direction radiale de l'owner
	var owner_center := vp * 0.5 + outward * RING_RADIUS

	var link := EnergyLink.new()
	link.size  = vp
	# Teinte lumineuse douce (énergie) dérivée de la couleur du palier : reste
	# cohérent avec le hub tout en restant visible même aux paliers ternes.
	link.accent = tcolor.lerp(UIColors.ENERGY_ACCENT, 0.45)
	# Départ JUSTE HORS du cercle de l'owner (sinon masqué par l'hexagone) ;
	# arrivée plus loin sur le même axe radial, dans l'espace.
	var start_pt := owner_center + outward * DISTRICT_LINK_START
	var end_pt   := owner_center + outward * DISTRICT_LINK_REACH
	link.start_point = start_pt
	link.end_point   = end_pt
	_hub_root.add_child(link)

	_links[owner_id]            = link
	_link_outward[owner_id]     = outward
	_link_diffuse_end[owner_id] = end_pt

	if _district_open.get(owner_id, false):
		# Quartier déjà ouvert (reconstruction du hub) : on le rebâtit tel quel,
		# sans ré-animer ni recentrer la vue (et sans boule, consommée).
		_reveal_district(owner_id, false)
	elif animate:
		# Route fraîchement reconstruite : le filament JAILLIT du cercle vers son
		# point d'énergie, puis la boule surgit au bout (pas de reconstruction du hub).
		_grow_link(owner_id, link, start_pt, end_pt)
	else:
		_spawn_boule(owner_id)

# Anime l'apparition d'un filament de route : fondu + extension de la pointe
# (end_point) du cercle de l'owner jusqu'au point d'énergie, puis pop de la boule.
func _grow_link(owner_id: String, link: EnergyLink, start_pt: Vector2, end_pt: Vector2) -> void:
	link.modulate.a = 0.0
	link.end_point  = start_pt
	var tw := create_tween().set_parallel(true)
	tw.tween_property(link, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(link, "end_point", end_pt, 0.55) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(func() -> void:
		if not is_instance_valid(link):
			return
		_spawn_boule(owner_id)
		var boule: Variant = _boules.get(owner_id)
		if is_instance_valid(boule):
			(boule as Control).pivot_offset = (boule as Control).size * 0.5
			(boule as Control).scale = Vector2(0.4, 0.4)
			boule.create_tween().tween_property(boule, "scale", Vector2.ONE, 0.4) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

# Reconstruction d'une route depuis un panneau de hub : au lieu de tout
# reconstruire (_rebuild_hub rechargeait toute la page), on POUSSE le filament du
# quartier en douceur, puis on rafraîchit le panneau ouvert — sa section « route »
# disparaît, la route étant désormais faite.
func animate_route_creation(owner_id: String) -> void:
	# Pas de hub vivant, ou lien déjà présent → repli/refresh simple.
	if _hub_root == null or not is_instance_valid(_hub_root):
		refresh_hub_after_route()
		return
	if _links.has(owner_id) and is_instance_valid(_links[owner_id]):
		_refresh_active_panel()
		return

	var vp := get_viewport_rect().size
	var village_maitrise := int(GameData.village.get("maitrise_actuelle", 0))
	var tcolor := UIColors.tier_color(village_maitrise)
	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool:
		return (d[2] as int) <= village_maitrise)
	var n := unlocked.size()
	var idx := -1
	for i in n:
		if (unlocked[i] as Array)[4] == owner_id:
			idx = i
			break
	if idx < 0:
		refresh_hub_after_route()   # owner pas sur l'anneau (cas limite) → repli sûr
		return

	AudioManager.play_sfx("ui_select", -6.0)
	_build_one_link(owner_id, idx, n, vp, tcolor, true)
	_refresh_active_panel()

# (Re)crée la boule d'énergie CLIQUABLE au bout du lien diffus d'un owner.
# Réutilisé à la construction du hub ET à la fermeture du quartier (le lien
# redevient diffus sans reconstruire le hub).
func _spawn_boule(owner_id: String) -> void:
	var link: EnergyLink = _links.get(owner_id)
	if not is_instance_valid(link):
		return
	const BOULE_SIZE := 64.0
	var boule := EnergyBoule.new()
	boule.accent   = link.accent
	boule.size     = Vector2(BOULE_SIZE, BOULE_SIZE)
	boule.position = link.end_point - Vector2(BOULE_SIZE, BOULE_SIZE) * 0.5
	var title := Translations.T(DISTRICTS[owner_id]["title_key"] as String)
	UIHelpers.register_tooltip(boule, Translations.T("district.reveal.tt_title"),
			Translations.T("district.reveal.tt_body") % title, link.accent)
	boule.clicked.connect(func() -> void: _animate_boule_travel(owner_id))
	_hub_root.add_child(boule)
	_boules[owner_id] = boule

# Clic sur la boule : une étincelle jaune remonte le fil en BOULE_TRAVEL_DUR s,
# et CE N'EST QU'À SON ARRIVÉE (au niveau de la boule) que le quartier éclot
# (fade-in + jiggle, géré par _reveal_district). La boule reste visible le temps
# de la montée, puis est consommée par la révélation.
func _animate_boule_travel(owner_id: String) -> void:
	if _spark_traveling.get(owner_id, false):
		return  # montée déjà en cours
	var link: EnergyLink = _links.get(owner_id)
	if not is_instance_valid(link):
		return
	_spark_traveling[owner_id] = true

	const SPARK_SIZE := 30.0
	var spark := EnergySpark.new()
	spark.size = Vector2(SPARK_SIZE, SPARK_SIZE)
	spark.position = link.point_at(0.0) - Vector2(SPARK_SIZE, SPARK_SIZE) * 0.5
	_hub_root.add_child(spark)

	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(spark) and is_instance_valid(link):
			spark.position = link.point_at(t) - Vector2(SPARK_SIZE, SPARK_SIZE) * 0.5
	, 0.0, 1.0, BOULE_TRAVEL_DUR)
	tw.tween_callback(func() -> void:
		if is_instance_valid(spark):
			spark.queue_free()
		_spark_traveling.erase(owner_id)
		# Si le hub a été reconstruit pendant la montée, le lien capturé est
		# libéré → on n'éclôt pas (la boule a déjà été respawnée telle quelle).
		if is_instance_valid(link):
			_reveal_district(owner_id, true)
	)

# Révèle le quartier d'un owner : le lien devient consistant, la boule est
# consommée, et un widget District (mini-hub aux pièces propres de DISTRICTS)
# apparaît au bout du lien. Avec `animate`, la vue se recentre en douceur dessus.
func _reveal_district(owner_id: String, animate: bool) -> void:
	var link: EnergyLink = _links.get(owner_id)
	if not is_instance_valid(link):
		return
	_district_open[owner_id] = true
	link.solid = true

	# Consommer la boule de cet owner.
	var boule: Variant = _boules.get(owner_id)
	if is_instance_valid(boule):
		boule.queue_free()
	_boules.erase(owner_id)
	# Libérer un éventuel ancien node (reconstruction du hub).
	var old: Variant = _districts.get(owner_id)
	if is_instance_valid(old):
		old.queue_free()

	var outward: Vector2 = _link_outward[owner_id]
	var vtier  := int(GameData.village.get("maitrise_actuelle", 0))
	var qradius := RING_RADIUS
	# Centre du quartier, au-delà du lien ; le lien va JUSQU'AU bord du cercle.
	var dc := link.end_point + outward * (DISTRICT_RING_GAP + qradius)
	link.end_point = dc - outward * qradius
	link.queue_redraw()

	var def: Dictionary = DISTRICTS[owner_id]
	var district := District.new()
	district.center      = dc
	district.radius      = qradius
	district.ring_color  = UIColors.tier_color(vtier)
	district.tier        = vtier
	district.title_text  = Translations.T(def["title_key"] as String)
	district.rooms       = def["rooms"]
	district.active_panel_id = _active_panel_id
	district.room_clicked.connect(_open_panel)
	district.close_requested.connect(_collapse_district.bind(owner_id))
	_hub_root.add_child(district)
	district.build()
	_districts[owner_id] = district

	# Naviguer vers le quartier : centrer `dc` à l'écran (cf. transform du hub).
	if animate:
		# Apparition douce : fade-in + jiggle élastique du quartier.
		district.modulate.a = 0.0
		district.scale = Vector2(0.7, 0.7)
		var at := create_tween().set_parallel(true)
		at.tween_property(district, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
		at.tween_property(district, "scale", Vector2.ONE, 0.6) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

		var vp := get_viewport_rect().size
		# Offset d'exploration (état SANS panneau) : centre dc plein écran à l'échelle
		# de zoom courante. Mémorisé dans _pan pour la fermeture d'un panneau.
		_pan = _zoom * (vp * 0.5 - dc)
		# Cible réelle de la caméra : si un panneau est ouvert, le hub est réduit
		# (HUB_PANEL_SCALE) et recentré dans l'espace libre à GAUCHE — il faut donc
		# centrer dc dans cet espace, pas au milieu de l'écran (même calcul que
		# _open_panel). pivot_offset = vp*0.5 dans les deux cas.
		var target := _pan
		if _rp_root != null:
			var free_center := Vector2(vp.x * (1.0 - PANEL_FRACTION) * 0.5, vp.y * 0.5)
			target = free_center - vp * 0.5 - HUB_PANEL_SCALE * (dc - vp * 0.5)
		var pt := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		pt.tween_property(_hub_root, "position", target, 0.6)

# Referme le quartier d'un owner : le lien redevient diffus, la boule revient
# et le quartier se fond — SANS reconstruire le hub (le cercle du village et
# ses hexagones restent intacts). La garde évite un double déclenchement.
func _collapse_district(owner_id: String) -> void:
	if not _district_open.get(owner_id, false):
		return
	_district_open[owner_id] = false
	var d: Variant = _districts.get(owner_id)
	_districts.erase(owner_id)

	# Le lien redevient diffus et la boule cliquable revient.
	var link: EnergyLink = _links.get(owner_id)
	if is_instance_valid(link):
		link.solid = false
		link.end_point = _link_diffuse_end[owner_id]
		link.queue_redraw()
	_spawn_boule(owner_id)

	# Fondu de sortie du quartier, puis libération.
	if is_instance_valid(d):
		var dr := d as District
		dr.pivot_offset = dr.center
		var ft := create_tween().set_parallel(true)
		ft.tween_property(dr, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
		ft.tween_property(dr, "scale", Vector2(0.82, 0.82), 0.30).set_ease(Tween.EASE_IN)
		ft.chain().tween_callback(dr.queue_free)

	# Caméra : glisse en douceur jusqu'à la place centrale (aucune téléportation,
	# aucune reconstruction du hub). _pan = 0 → place centrale plein écran (état
	# sans panneau, restauré à la fermeture d'un panneau).
	_pan = Vector2.ZERO
	# Cible réelle : si un panneau est ouvert, le hub est réduit et recentré dans
	# l'espace libre à GAUCHE → centrer la place centrale (vp*0.5) là, pas au
	# milieu de l'écran (même calcul que _open_panel / _expand_district).
	var target := _pan
	if _rp_root != null:
		var vp := get_viewport_rect().size
		var free_center := Vector2(vp.x * (1.0 - PANEL_FRACTION) * 0.5, vp.y * 0.5)
		target = free_center - vp * 0.5  # focus = vp*0.5 → terme d'échelle nul
	if _hub_root:
		var ct := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		ct.tween_property(_hub_root, "position", target, 0.5)

# Owner du quartier auquel appartient une pièce (room_panel_id), "" si aucune.
func _owner_of_room(panel_id: String) -> String:
	for owner_id in DISTRICTS:
		for r: Array in DISTRICTS[owner_id]["rooms"]:
			if r[0] == panel_id:
				return owner_id
	return ""

# Déplacement libre de l'espace : CLIC-GLISSER à la souris déplace la place
# centrale, les liens et les quartiers ensemble. Géré dans _input (reçu avant
# l'UI) SANS consommer l'événement → les clics d'hexagones/boutons marchent
# toujours. Inactif avant l'éclosion (pas de hub), et tant qu'un panneau ou les
# Paramètres sont ouverts (la dimension UI prime).
func _input(event: InputEvent) -> void:
	# Les boutons sont TOUJOURS traités (sinon un relâché ignoré pendant
	# l'ouverture d'un panneau laisserait _panning bloqué à true → pan fantôme).
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# On DÉMARRE un pan sur l'espace libre (hub présent, Paramètres
			# fermés) — y compris quand un panneau est ouvert, tant que le clic
			# tombe HORS du panneau de droite (sinon glisser dedans baladerait
			# le village). Le relâché coupe toujours le pan.
			_panning = mb.pressed and _hub_root != null \
					and _settings_overlay == null \
					and not _point_over_panel(mb.position)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(mb.position, mb.button_index == MOUSE_BUTTON_WHEEL_UP)
	elif event is InputEventMouseMotion and _panning and _hub_root != null:
		_hub_root.position += (event as InputEventMouseMotion).relative
		# En exploration libre (aucun panneau), l'offset de pan est mémorisé ;
		# avec un panneau ouvert, le déplacement est éphémère — le hub revient
		# à sa position recentrée à la fermeture du panneau.
		if _rp_root == null:
			_pan = _hub_root.position

# Vrai si le point écran tombe dans le panneau de droite (s'il est ouvert).
func _point_over_panel(global_pos: Vector2) -> bool:
	return _rp_root != null \
			and Rect2(_rp_root.global_position, _rp_root.size).has_point(global_pos)

# Zoom molette en EXPLORATION LIBRE (aucun panneau, Paramètres fermés). Le repos
# (HUB_BASE_SCALE) est le zoom MAX ; on dézoome jusqu'à HUB_MIN_SCALE. Le point
# sous le curseur reste fixe (zoom ancré). Pan/zoom mémorisés dans _pan/_zoom.
func _zoom_at(cursor: Vector2, zoom_in: bool) -> void:
	if _hub_root == null or _settings_overlay != null or _rp_root != null:
		return
	var s_old := _hub_root.scale.x
	var s_new := clampf(s_old * (ZOOM_WHEEL_STEP if zoom_in else 1.0 / ZOOM_WHEEL_STEP),
			HUB_MIN_SCALE, HUB_BASE_SCALE)
	if is_equal_approx(s_new, s_old):
		return
	# Garder le point écran `cursor` au même endroit du monde après changement
	# d'échelle (cf. transform Control : screen = pos + pivot + s·(p − pivot)).
	var pivot := _hub_root.pivot_offset
	var ratio := s_new / s_old
	_hub_root.scale    = Vector2.ONE * s_new
	_hub_root.position = cursor - pivot - (cursor - _hub_root.position - pivot) * ratio
	_zoom = s_new
	_pan  = _hub_root.position
	get_viewport().set_input_as_handled()

# Fine ligne horizontale décorative (ornement du nom de palier).
func _ornament_line(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(26, 1)
	line.color               = Color(color, 0.55)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line

# Apparition du hub : l'anneau fond en douceur et les hexagones « poppent »
# l'un après l'autre autour du cercle. Rejouée à chaque rebuild (changement
# de palier, langue…) — c'est voulu : l'évolution mérite sa mise en scène.
func _animate_hub_entrance() -> void:
	_ring.modulate.a = 0.0
	var rt := create_tween()
	rt.tween_property(_ring, "modulate:a", 1.0, 0.45).set_ease(Tween.EASE_OUT)

	var i := 0
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.modulate.a = 0.0
		item.scale      = Vector2(0.6, 0.6)  # pivot déjà centré (cf. _make_hex)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(item, "modulate:a", 1.0, 0.25).set_delay(0.07 * i)
		tw.tween_property(item, "scale", Vector2.ONE, 0.40) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.07 * i)
		i += 1

# ─── Conditions d'évolution du Village ────────────────────────
# Affiche le compteur de fragments et le bouton Évoluer si la condition est remplie.
# Progression du palier courant vers le suivant : [have, need]. Critère PAR PALIER —
# kills (Commun → Peu Commun), puis bâtiments T0+ (Peu Commun → Rare).
func _village_progress() -> Array:
	if village_tier() == 0:
		return [int(GameData.village.get("kills_total", 0)), Balance.VILLAGE_SEUIL_PEU_COMMUN_KILLS]
	return [VillageBuildings.count_buildings_tier0_plus(), Balance.VILLAGE_SEUIL_RARE_BATIMENTS]

func _build_village_conditions(container: VBoxContainer, village_maitrise: int, _vcolor: Color) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	container.add_child(spacer)

	# Condition d'évolution selon le palier (kills à Commun, bâtiments T0+ à Peu
	# Commun). C'est un GATE : l'évolution reste MANUELLE (bouton ci-dessous).
	var prog := _village_progress()
	var have := int(prog[0])
	var need := int(prog[1])
	var is_kills := village_maitrise == 0
	var label := Translations.T("village.cond.kills" if is_kills else "village.cond.buildings")
	var tt_body := Translations.T("village.kills.tt_body" if is_kills else "village.buildings.tt_body")
	var met := need > 0 and have >= need
	# Accent VOYANT : ambre tant que l'objectif est en cours, vert une fois atteint
	# (impossible à rater contre le fond sombre du hub, même au palier Commun gris).
	var accent := UIColors.LOG_VICTORY if met else UIColors.FILTER_ON
	var frac := (clampf(float(have) / float(need), 0.0, 1.0) if need > 0 else 0.0)
	var icon := "⚔" if is_kills else "🏠"

	# En-tête contextuel : annonce que c'est l'objectif pour monter de palier.
	var hdr := UIHelpers.label(
			Translations.T("village.cond.ready" if met else "village.cond.header"),
			13, Color(accent.r, accent.g, accent.b, 0.95))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(hdr)

	# Carte d'objectif qui SE REMPLIT avec la progression (même DA que les cartes
	# d'XP du jeu) : icône + libellé + compteur, bordure d'accent épaisse.
	var card := UIHelpers.xp_panel(accent, frac, 0.14, 0.95, 2, 8)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(212.0, 0.0)
	var m := UIHelpers.margin_of(6)
	card.add_child(m)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(hb)
	var ic := UIHelpers.label("✓" if met else icon, 15, accent)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var txt := UIHelpers.label("%s   %d / %d" % [label, have, need], 12, Color.WHITE)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(txt)
	UIHelpers.register_tooltip(card, label, tt_body % [have, need], accent)
	container.add_child(card)

	# Respiration douce tant que l'objectif n'est pas atteint : attire l'œil sans
	# agresser (le bouton ÉVOLUER prend le relais une fois la condition remplie).
	# Pivot recentré à chaque (re)dimensionnement ; tween lié à la carte (auto-tué
	# au rebuild du hub), avec repli `ready` si la carte n'est pas encore dans l'arbre.
	if not met:
		card.resized.connect(func() -> void: card.pivot_offset = card.size * 0.5)
		var start_pulse := func() -> void:
			card.pivot_offset = card.size * 0.5
			var pulse := card.create_tween().set_loops()
			pulse.tween_property(card, "scale", Vector2(1.03, 1.03), 1.1) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			pulse.tween_property(card, "scale", Vector2.ONE, 1.1) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if card.is_inside_tree():
			start_pulse.call()
		else:
			card.ready.connect(start_pulse, CONNECT_ONE_SHOT)

	# Bouton ÉVOLUER MANUEL : apparaît quand la condition est remplie. Le joueur
	# déclenche la montée — jamais automatique (atteindre le seuil ne fait rien seul).
	if GameData.can_upgrade_village():
		var next_color := UIColors.tier_color(village_maitrise + 1)
		var ubtn := UIHelpers.evolve_button("▲  " + Translations.T("village.evolve_btn"),
				next_color, 11)
		ubtn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ubtn.custom_minimum_size = Vector2(200.0, 26.0)
		UIHelpers.register_tooltip(ubtn, Translations.T("village.evolve_btn"),
				Translations.T("village.evolve.tt_body") % GameData.get_tier_name(village_maitrise + 1),
				next_color)
		# Montée d'UN palier ; village_tier_change → _on_village_tier_change rebâtit le
		# hub (nouvelle couleur, secteur débloqué) et déclenche la sauvegarde.
		ubtn.pressed.connect(func() -> void: GameData.upgrade_village())
		container.add_child(ubtn)

# ─── Panneau droite ───────────────────────────────────────────
# Ouvre le panneau JRPG pour panel_id. Re-clic sur le même id → ferme (toggle).
func _open_panel(panel_id: String) -> void:
	var vp := get_viewport_rect().size

	# Toggle : même hex → fermer
	if _active_panel_id == panel_id and _rp_root != null:
		_close_panel()
		return

	# Sélection d'un élément du village (ouverture / changement de panneau).
	AudioManager.play_sfx("ui_select", -6.0)

	_active_panel_id = panel_id
	_update_hex_selection(panel_id)

	# Panneau déjà ouvert → swap de contenu seulement
	if _rp_root != null:
		if _rp_title:
			_rp_title.text = Translations.panel_title(panel_id)
		_swap_panel_content(panel_id)
		return

	# Réduire le hub : le village ENTIER reste visible, réduit
	# homothétiquement et RECENTRÉ au milieu de l'espace restant à gauche.
	# Pivot au centre du canvas + décalage x : le centre du hub glisse de
	# 50 % de l'écran au centre de la zone libre. On centre le POINT D'INTÉRÊT :
	# la place centrale par défaut, ou le quartier si on ouvre une de ses pièces
	# (sinon l'ouverture recadrerait sur le village et masquerait le quartier).
	var focus := vp * 0.5
	var room_owner := _owner_of_room(panel_id)
	if room_owner != "" and _district_open.get(room_owner, false):
		var d: Variant = _districts.get(room_owner)
		if is_instance_valid(d):
			focus = (d as District).center
	var free_center := Vector2(vp.x * (1.0 - PANEL_FRACTION) * 0.5, vp.y * 0.5)
	var target_pos := free_center - vp * 0.5 - HUB_PANEL_SCALE * (focus - vp * 0.5)
	_hub_root.pivot_offset = vp * 0.5
	var ht := create_tween().set_parallel(true) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "scale", Vector2.ONE * HUB_PANEL_SCALE, 0.35)
	ht.tween_property(_hub_root, "position", target_pos, 0.35)

	# Créer le panneau hors écran à droite
	_rp_root = Control.new()
	_rp_root.size     = Vector2(vp.x * PANEL_FRACTION, vp.y)
	_rp_root.position = Vector2(vp.x, 0.0)
	add_child(_rp_root)
	_build_panel_frame(panel_id)
	_raise_settings_overlay()

	# Glissement vers la droite du hub
	var pt := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	pt.tween_property(_rp_root, "position:x", vp.x * (1.0 - PANEL_FRACTION), 0.35)

# Ferme le panneau droit avec une animation de glissement vers la droite.
func _close_panel() -> void:
	if _rp_root == null:
		return
	var vp := get_viewport_rect().size
	_active_panel_id = ""
	_update_hex_selection("")

	var pt := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	pt.tween_property(_rp_root, "position:x", vp.x, 0.25)
	pt.tween_callback(func() -> void:
		if _rp_root:
			_rp_root.queue_free()
			_rp_root   = null
			rp_content = null
			_rp_title  = null
			_rp_scroll = null
	)

	var ht := create_tween().set_parallel(true) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "scale", Vector2.ONE * _zoom, 0.25)
	# Retour à l'espace exploré (pan + zoom conservés).
	ht.tween_property(_hub_root, "position", _pan, 0.25)

# Met à jour l'état is_selected de tous les HexItems selon le panneau ouvert.
func _update_hex_selection(active_id: String) -> void:
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.is_selected = (pid == active_id)
		item.queue_redraw()
	# Pièces des quartiers ouverts (même animation de sélection que le village).
	# Validité AVANT usage : après une reconstruction du hub, le dict peut
	# encore référencer des District libérés (« cast a freed object » sinon).
	for owner_id in _districts:
		var node: Variant = _districts[owner_id]
		if is_instance_valid(node):
			(node as District).set_room_selected(active_id)

# Vide rp_content et réinjecte le contenu pour panel_id (panneau déjà ouvert).
func _swap_panel_content(panel_id: String) -> void:
	UIHelpers.clear_children(rp_content)
	_fill_panel_content(panel_id)

# Reconstruit le contenu du panneau actuellement ouvert, sans le fermer.
# À utiliser pour tout rafraîchissement : rappeler _open_panel() avec le
# panneau déjà ouvert le FERMERAIT (comportement toggle).
# La position de scroll est restaurée ; les sections repliables retrouvent
# leur état grâce à panel_ui_state() (passé par les panels à UIHelpers).
func _refresh_active_panel() -> void:
	if _rp_root == null or _active_panel_id == "":
		return
	var scroll_pos: int = _rp_scroll.scroll_vertical if _rp_scroll else 0
	_swap_panel_content(_active_panel_id)
	_restore_scroll(scroll_pos)

# Restaure le scroll après reconstruction. Attend une frame : la hauteur
# du nouveau contenu n'est connue qu'après le layout.
func _restore_scroll(pos: int) -> void:
	await get_tree().process_frame
	if _rp_scroll and is_instance_valid(_rp_scroll):
		_rp_scroll.scroll_vertical = pos

# Dictionnaire d'état UI du panneau actif, conservé entre reconstructions.
# Les panels le passent à UIHelpers.collapsible_section (sections ouvertes).
func panel_ui_state() -> Dictionary:
	if not _panel_ui_states.has(_active_panel_id):
		_panel_ui_states[_active_panel_id] = {}
	return _panel_ui_states[_active_panel_id]

# ─── Construction du cadre JRPG ──────────────────────────────
# Crée le JRPGPanel, le titre, le bouton fermer et la zone scrollable.
func _build_panel_frame(panel_id: String) -> void:
	var tcolor := UIColors.tier_color(village_tier())

	var frame := JRPGPanel.new()
	frame.panel_color = tcolor
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rp_root.add_child(frame)

	# Titre
	_rp_title = UIHelpers.label(Translations.panel_title(panel_id), 16, Color.WHITE)
	_rp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rp_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_rp_title.anchor_left   = 0.0; _rp_title.anchor_right  = 1.0
	_rp_title.anchor_top    = 0.0; _rp_title.anchor_bottom = 0.0
	_rp_title.offset_left   = 6;   _rp_title.offset_right  = -40
	_rp_title.offset_top    = 8;   _rp_title.offset_bottom = 38
	frame.add_child(_rp_title)

	# Bouton fermer (toggle = re-clic hex, mais on garde une croix aussi)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", tcolor)
	close_btn.anchor_left   = 1.0; close_btn.anchor_right  = 1.0
	close_btn.anchor_top    = 0.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left   = -36; close_btn.offset_right  = -6
	close_btn.offset_top    = 5;   close_btn.offset_bottom = 35
	close_btn.pressed.connect(_close_panel)
	frame.add_child(close_btn)

	# Zone de contenu scrollable
	var scroll := ScrollContainer.new()
	scroll.anchor_left   = 0.0; scroll.anchor_right  = 1.0
	scroll.anchor_top    = 0.0; scroll.anchor_bottom = 1.0
	scroll.offset_top    = 44
	scroll.offset_left   = 10;  scroll.offset_right  = -10
	scroll.offset_bottom = -10
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_rp_scroll = scroll

	var margin := UIHelpers.margin_of(12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	rp_content = VBoxContainer.new()
	rp_content.add_theme_constant_override("separation", 10)
	rp_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(rp_content)

	_fill_panel_content(panel_id)

# ─── Contenu des panneaux ─────────────────────────────────────
# Dispatch vers la fonction de contenu correspondant à panel_id.
func _fill_panel_content(panel_id: String) -> void:
	match panel_id:
		"hero":      HeroPanel.build(self)
		"adventure": AdventurePanel.build(self)
		"forge":     ForgePanel.build(self)
		"sanctuary": _panel_soon("SANCTUAIRE")
		"relic":     _panel_soon("RELIQUE")
		"tbd":       _panel_soon("?")
		_:
			# Pièce de quartier (Chantier 4). On n'y accède QUE si le chemin existe
			# (route reconstruite) → la gestion de la route vit dans le panneau du
			# hub (BuildingPanel.build_route_section), plus ici. Pièce = bâtiment →
			# panneau de gestion ; sinon placeholder titré.
			var bid := VillageBuildings.building_for_room(panel_id)
			if bid != "":
				BuildingPanel.build(self, bid)
			elif _owner_of_room(panel_id) != "":
				_panel_soon(Translations.panel_title(panel_id))

# Lance l'aventure sur le biome sélectionné et bascule vers CombatScene.
func start_selected_expedition() -> void:
	if adv_selected_biome_id.is_empty():
		return
	GameData.player["active_biome_id"] = adv_selected_biome_id
	AdventureSystem.start_adventure(adv_selected_biome_id)
	get_tree().change_scene_to_file("res://scenes/combat/CombatScene.tscn")

# ─── Carte holographique 3D des expéditions (overlay) ─────────
# API publique appelée par le bouton « Carte » de l'AdventurePanel.
# Ouvre la carte holo 3D (orbitable) reproduisant le gabarit Excel (décor seul à
# ce stade — les LIEUX/pins cliquables sont reportés à un chantier ultérieur ; la
# sélection de biome passe par l'accordéon du panneau). Embarque HoloMap3D dans un
# SubViewport via HoloMap3DOverlay.
func open_expedition_map() -> void:
	var holo := HoloMap3DOverlay.new()
	holo.titre      = Translations.T("adv.map_title")
	holo.sous_titre = Translations.T("adv.map_hint")
	holo.chemin_xlsx = HoloMap3D.CHEMIN_GABARIT_DEFAUT   # carte lue depuis le gabarit
	holo.z_index    = 400
	holo.lieu_selectionne.connect(func(biome_id: String) -> void:
		adv_selected_biome_id = biome_id
		if is_instance_valid(holo):
			holo.queue_free()
		_refresh_active_panel()
	)
	add_child(holo)

# DORMANT (réutilisé quand les pins de lieux reviendront — chantier ultérieur) :
# construit la liste de lieux de la carte à partir des biomes découverts. Chaque
# biome occupe une cellule distincte (placement déterministe → carte stable).
func _discovered_biomes_as_lieux(grille: int) -> Array[HoloLieuData]:
	var ids: Array = []
	for eid: String in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") != Enums.EntityType.BIOME:
			continue
		if not e.get("est_decouvert", false):
			continue
		ids.append(eid)
	ids.sort()  # ordre déterministe

	var cells := _holo_spread_cells(ids.size(), grille)
	var out: Array[HoloLieuData] = []
	for i in ids.size():
		var eid: String = ids[i]
		var e := GameData.entities[eid] as Dictionary
		var tier := int(e.get("maitrise_actuelle", 0))
		# Emprise et hauteur croissent avec la rareté (les lieux rares ressortent).
		var cote := clampi(2 + tier, 2, 4)
		var emp := Vector2i(cote, cote)
		var cell: Vector2i = cells[i]
		var etages_l := 4 + tier * 3
		var sans_bati := false
		# Le Marécage Putride EST le parc : lieu SANS bâtiment, emprise calée sur
		# la zone du parc (x[2..8] y[17..23], grille 28) → pin + zone cliquable
		# par-dessus le décor vert, aucun bâtiment.
		if eid == "biome_marecage":
			emp = Vector2i(7, 7)
			cell = Vector2i(2, 17)
			etages_l = 2
			sans_bati = true
		cell.x = clampi(cell.x, 0, maxi(0, grille - emp.x))
		cell.y = clampi(cell.y, 0, maxi(0, grille - emp.y))
		var l := HoloLieuData.new()
		l.id              = eid
		l.nom_affichage_fr = Translations.entity_name(e, eid)
		l.tier            = tier
		l.lore_fr         = Translations.entity_lore(e)
		l.cellule         = cell
		l.emprise         = emp
		l.etages          = etages_l
		l.sans_batiment   = sans_bati
		l.decouvert       = true
		out.append(l)
	return out

# n cellules distinctes réparties sur la grille, mélange déterministe.
func _holo_spread_cells(n: int, grille: int) -> Array:
	var all: Array = []
	for i in grille:
		for j in grille:
			all.append(Vector2i(i, j))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260625
	for k in range(all.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp: Variant = all[k]
		all[k] = all[r]
		all[r] = tmp
	return all.slice(0, mini(n, all.size()))

# Panneau générique "Bientôt disponible" pour les fonctionnalités non implémentées.
func _panel_soon(label: String) -> void:
	var lbl := UIHelpers.label(Translations.T("village.soon") % label, 13, UIColors.TEXT_MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rp_content.add_child(lbl)

# Appelé par la section route d'un panneau de hub après une reconstruction réussie :
# reconstruit le hub (le chemin/filament du quartier apparaît) puis rouvre le panneau
# courant (la section route y disparaît, la route étant désormais faite).
func refresh_hub_after_route() -> void:
	var was_open := _active_panel_id
	_rebuild_hub()
	if was_open != "":
		_open_panel(was_open)

# ─── Village ──────────────────────────────────────────────────

# Recrée le hub (après upgrade village ou changement de tier).
# Le panneau droit éventuellement ouvert est libéré (et non orphelin) :
# l'appelant peut le rouvrir ensuite via _open_panel (cf. _on_language_changed).
func _rebuild_hub() -> void:
	if _hub_root and is_instance_valid(_hub_root):
		_hub_root.queue_free()
		_hub_root = null
	if _rp_root and is_instance_valid(_rp_root):
		_rp_root.queue_free()
	_rp_root   = null
	rp_content = null
	_rp_title  = null
	_rp_scroll = null
	_hex_items.clear()
	# Les quartiers/liens/boules sont enfants du hub libéré : on purge les refs
	# de nœuds (recréées par _build_hub). _district_open est CONSERVÉ : un
	# quartier ouvert se rebâtit automatiquement après la reconstruction.
	_districts.clear()
	_links.clear()
	_boules.clear()
	_link_outward.clear()
	_link_diffuse_end.clear()
	_spark_traveling.clear()
	_active_panel_id = ""
	if GameData.village.get("eclos", false):
		_build_hub()
	_raise_settings_overlay()

# Fragment libéré : feedback + rebuild hub (le bouton upgrade peut apparaître).
func _on_fragment_libere(fragment_id: String, _biome_id: String) -> void:
	var frag: Dictionary = GameData.get_entity(fragment_id)
	var nom  := Translations.entity_name(frag, fragment_id)
	show_banner(Translations.T("village.fragment_freed") % nom,
			Color(0.55, 0.85, 0.55), Color(0.05, 0.05, 0.20, 0.92), 2.5, 0.5)
	_rebuild_hub()

# Village tier change : rebuild hub (nouvelle couleur, nouveau bouton forge).
func _on_village_tier_change(_nouveau_tier: int) -> void:
	_rebuild_hub()

# Équipement de biome obtenu (biome → Peu Commun) : bannière dorée.
func _on_equipment_unlocked(equip_id: String) -> void:
	var e   := GameData.get_entity(equip_id)
	var nom := Translations.entity_name(e, equip_id)
	show_banner(Translations.T("village.equipment_unlocked") % nom,
			Color(0.95, 0.80, 0.40), Color(0.16, 0.11, 0.02, 0.92), 2.5, 0.5)

# Nouveau biome révélé : bannière + refresh du panneau Expéditions si ouvert.
func _on_biome_revele(biome_id: String) -> void:
	var biome := GameData.get_entity(biome_id)
	var nom   := Translations.entity_name(biome, biome_id)
	show_banner(Translations.T("village.biome_revealed") % nom,
			Color(0.4, 0.7, 1.0), Color(0.05, 0.10, 0.25, 0.92), 3.0, 0.6)
	if _active_panel_id == "adventure":
		_refresh_active_panel()

# Bannière temporaire en haut de l'écran : texte + couleur d'accent, fond `bg`,
# affichée `hold` s puis fondue en `fade` s avant disparition. Mutualisée par
# les notifications (Fragment libéré, biome révélé…).
func show_banner(text: String, accent: Color, bg: Color, hold: float, fade: float) -> void:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top    = 20
	banner.offset_bottom = 80
	banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	banner.add_theme_stylebox_override("panel", style)
	add_child(banner)

	var lbl := UIHelpers.label(text, 16, accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(lbl)

	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, fade)
	tw.tween_callback(banner.queue_free)


# Ajoute le bouton ⚙ en haut à droite pour ouvrir le panneau Paramètres.
func _build_fullscreen_btn() -> void:
	var btn := Button.new()
	btn.text = "⚙"
	btn.flat = true
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 0.0; btn.anchor_bottom = 0.0
	btn.offset_left   = -34; btn.offset_right  = -6
	btn.offset_top    = 6;   btn.offset_bottom = 34
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.pressed.connect(_toggle_settings_overlay)
	add_child(btn)

# ─── DEBUG : boutons Tier − / Tier + ──────────────────────────
# Petite barre en bas à gauche pour prévisualiser l'évolution visuelle
# du hub à chaque palier (cf. DEBUG_TIER_BUTTONS).

func _build_debug_tier_buttons() -> void:
	if not DEBUG_TIER_BUTTONS:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.anchor_left = 0.0; row.anchor_right  = 0.0
	row.anchor_top  = 1.0; row.anchor_bottom = 1.0
	row.offset_left = 8;   row.offset_right  = 160
	row.offset_top  = -34; row.offset_bottom = -8
	add_child(row)

	row.add_child(_debug_tier_btn("−", -1))
	_debug_tier_lbl = UIHelpers.label("Tier %d" % village_tier(), 11, UIColors.TEXT_MUTED)
	_debug_tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_debug_tier_lbl)
	row.add_child(_debug_tier_btn("+", 1))

func _debug_tier_btn(label: String, delta: int) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(26, 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.06, 0.30, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(UIColors.TEXT_MUTED, 0.15, 0.50, 1, 4))
	btn.pressed.connect(_debug_shift_tier.bind(delta))
	return btn

# Change le palier du Village de `delta` et reconstruit le hub.
# Force l'éclosion si nécessaire (le hub n'existe qu'après) — dans ce cas
# on recharge la scène pour nettoyer l'UI d'éclosion.
func _debug_shift_tier(delta: int) -> void:
	var was_eclos: bool = GameData.village.get("eclos", false)
	GameData.village["maitrise_actuelle"] = clampi(village_tier() + delta, 0, GameData.MAX_TIER)
	GameData.village["eclos"] = true
	if _debug_tier_lbl:
		_debug_tier_lbl.text = "Tier %d" % village_tier()
	if was_eclos:
		_rebuild_hub()
	else:
		get_tree().reload_current_scene()

# ─── Panneau Paramètres ───────────────────────────────────────
# Tout le contenu (audio, affichage, sauvegarde, langue) vit dans le
# widget SettingsOverlay ; Village ne gère que l'ouverture/fermeture.

func _toggle_settings_overlay() -> void:
	if _settings_overlay and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	_settings_overlay = SettingsOverlay.new()
	add_child(_settings_overlay)

# L'overlay Paramètres doit rester AU-DESSUS de tout : _rebuild_hub() et
# _open_panel() ajoutent leurs nœuds après lui dans l'arbre (donc par-dessus,
# pour le dessin ET la souris) — on le repasse en dernier enfant.
func _raise_settings_overlay() -> void:
	if _settings_overlay and is_instance_valid(_settings_overlay):
		_settings_overlay.move_to_front()



# ─── Bouton ÉVOLUER pulsant ──────────────────────────────────
# Fabrique un bouton ÉVOLUER avec pulsation scale 1.0→1.05→1.0 en boucle.
# La couleur du texte correspond au tier cible (from_tier + 1).
func make_evolve_btn(entity_id: String, entity_name: String,
		entity_type: String, from_tier: int) -> Button:
	var nc  := UIColors.tier_color(from_tier + 1)
	var btn := UIHelpers.evolve_button(Translations.T("btn.evolve"), nc)
	UIHelpers.register_tooltip(btn,
			Translations.T("evolve.tt_title") % entity_name,
			Translations.T("evolve.tt_body") % [GameData.get_tier_name(from_tier),
					GameData.get_tier_name(from_tier + 1)], nc)
	btn.pressed.connect(func() -> void:
		if MasterySystem.evolve_entity(entity_id):
			SaveManager.save()
			launch_evolution_ritual(entity_type, entity_id, entity_name,
					from_tier, from_tier + 1)
	)
	return btn

# ─── Rituel d'ascension ──────────────────────────────────────
# Stocke les paramètres dans GameData puis fond vers noir avant de changer de scène.
# API publique : aussi utilisée par ForgePanel après une forge réussie.
func launch_evolution_ritual(entity_type: String, entity_id: String,
		entity_name: String, from_tier: int, to_tier: int, extra: Dictionary = {}) -> void:
	GameData.pending_evolution = {
		"entity_type": entity_type,
		"entity_id":   entity_id,
		"entity_name": entity_name,
		"from_tier":   from_tier,
		"to_tier":     to_tier,
	}
	GameData.pending_evolution.merge(extra, true)
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.modulate.a = 0.0
	overlay.z_index = 500
	add_child(overlay)
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/village/EvolutionRitual.tscn")
	)

# ─── Factory hexagone ─────────────────────────────────────────
# Crée un HexItem, le positionne sur le hub et l'enregistre dans _hex_items.
# `_icon` : conservé dans la signature pour les appelants, mais plus affiché —
# l'intérieur de la bulle est désormais l'animation d'énergie (cf. HexItem).
func _make_hex(lbl: String, _icon: String, tcolor: Color, pos: Vector2, cb: Callable, panel_id: String) -> void:
	var item := HexItem.new()
	item.label_text  = lbl
	item.tier_color  = tcolor
	item.tier        = village_tier()
	item.outward_dir = pos.normalized()
	item.callback    = cb
	_center(item, pos, HEX_SIZE)
	item.pivot_offset = HEX_SIZE * 0.5
	_hub_root.add_child(item)
	_hex_items[panel_id] = item
	UIHelpers.register_tooltip(item, lbl, _hex_tooltip(panel_id), tcolor)

# Retourne la description JRPG d'un hexagone selon son panel_id.
func _hex_tooltip(panel_id: String) -> String:
	return Translations.T("hex_tt." + panel_id)

# ─── Navigation → panneaux ────────────────────────────────────
func _go_hero()       -> void: _open_panel("hero")
func _go_adventure()  -> void: _open_panel("adventure")
func _go_forge()     -> void: _open_panel("forge")
func _go_sanctuary() -> void: _open_panel("sanctuary")
func _go_relic()     -> void: _open_panel("relic")
func _go_tbd()       -> void: _open_panel("tbd")

# Met à jour les pastilles de notification sur les HexItems.
func _update_badges() -> void:
	# hero : entité active prête à évoluer OU passif prêt
	var hero_alert := false
	if MasterySystem.can_evolve("hero"):
		hero_alert = true
	if not hero_alert:
		for pid in (GameData.get_entity("hero").get("unlocked_passives", []) as Array) + \
				(GameData.player.get("active_passives", []) as Array):
			if MasterySystem.can_evolve(pid as String):
				hero_alert = true
				break

	# forge : un équipement prêt à évoluer (XP-seuil atteint, Chantier 5)
	var forge_alert := false
	for entry in ForgePanel.EQUIPS:
		if ForgeSystem.can_evolve_equipment(entry[0] as String):
			forge_alert = true
			break

	# adventure : un biome ou une créature prêt à évoluer
	var adv_alert := false
	for eid in GameData.entities:
		var e := GameData.entities[eid] as Dictionary
		if e.get("entity_type", "") in [Enums.EntityType.BIOME, Enums.EntityType.CREATURE] and MasterySystem.can_evolve(eid):
			adv_alert = true
			break

	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		match pid:
			"hero":      item.has_notification = hero_alert
			"forge":     item.has_notification = forge_alert
			"adventure": item.has_notification = adv_alert
		item.queue_redraw()

# Refresh du panneau forge ou héro si ouvert, après un drop de ressources ou une forge.
func _on_resources_changed_refresh() -> void:
	if _active_panel_id == "forge" or _active_panel_id == "hero" \
			or VillageBuildings.building_for_room(_active_panel_id) != "":
		_refresh_active_panel()
	_update_badges()

# ─── Langue ───────────────────────────────────────────────────
# Reconstruit le hub + panneau actif. Le SettingsOverlay (s'il est ouvert)
# se reconstruit tout seul : il écoute lui-même language_changed.
func _on_language_changed(_lang: String) -> void:
	var was_open := _active_panel_id
	_rebuild_hub()
	if was_open != "":
		_open_panel(was_open)

# ─── Utils ────────────────────────────────────────────────────
# Positionne ctrl centré sur pos avec la taille sz, en mode ancre centre.
func _center(ctrl: Control, pos: Vector2, sz: Vector2) -> void:
	ctrl.anchor_left   = 0.5; ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5; ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = pos.x - sz.x * 0.5
	ctrl.offset_right  = pos.x + sz.x * 0.5
	ctrl.offset_top    = pos.y - sz.y * 0.5
	ctrl.offset_bottom = pos.y + sz.y * 0.5
