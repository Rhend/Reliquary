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
# Panneau droit : fraction de l'écran qu'il occupe quand il est ouvert.
# Le hub est réduit (HUB_PANEL_SCALE) et recentré au milieu de l'espace
# restant — le village entier doit y tenir (contenu utile ≈ 860 px).
const PANEL_FRACTION   := 0.5
const HUB_PANEL_SCALE  := 0.72
const TIER_0_COLOR := Color(0.38, 0.38, 0.52)

# ─── Éveil (phase d'éclosion) ─────────────────────────────────
# L'orbe se réchauffe vers cette couleur à mesure que l'âme s'éveille.
const ECLOSION_AWAKEN_COLOR := Color(1.0, 0.86, 0.55)

# Probabilité, à chaque clic d'éclosion, de faire surgir un court chuchotement
# d'ambiance (fragment narratif) à une position aléatoire de l'écran.
const BIRTH_WHISPER_CHANCE := 0.22
const BIRTH_WHISPER_COUNT  := 10   # nombre de clés birth.whisper.N dans Translations

# Phrases d'éveil : seuils fixes, textes lus depuis Translations au moment de l'affichage.
func _birth_phrases() -> Array:
	return [
		[0.25, Translations.T("birth.phrase_25")],
		[0.50, Translations.T("birth.phrase_50")],
		[0.75, Translations.T("birth.phrase_75")],
	]

# Pool des chuchotements d'ambiance (courts) tirés au hasard pendant les clics.
func _birth_whispers() -> Array:
	var out: Array = []
	for i in range(1, BIRTH_WHISPER_COUNT + 1):
		out.append(Translations.T("birth.whisper." + str(i)))
	return out

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

# ─── API publique pour les panels (HeroPanel / Adventure / Forge) ──
# Les modules de scenes/village/panels/ reçoivent ce nœud (host) et ne
# doivent utiliser QUE ces membres publics (+ village_tier(),
# make_evolve_btn(), show_banner(), start_selected_expedition()).

var rp_content            : VBoxContainer  # zone de contenu scrollable du panneau droit
var adv_selected_biome_id := ""            # biome sélectionné dans le panneau Expéditions

# ─── État interne ─────────────────────────────────────────────
var _ring            : CircleRing         # anneau animé central (XP fill + tier visuel)
var _xp_label        : Label              # compteur de clics sous l'orbe (phase d'éclosion)
var _hub_root        : Control            # conteneur du hub hexagonal
var _rp_root         : Control            # panneau droit JRPG — null si fermé
var _rp_title        : Label              # label titre dans la barre du panneau droit
var _rp_scroll       : ScrollContainer    # zone de scroll du panneau droit — null si fermé
var _panel_ui_states : Dictionary = {}    # panel_id → état UI persistant (sections ouvertes…)
var _active_panel_id      := ""           # id du panneau ouvert ("hero", "adventure", …)
var _hex_items            : Dictionary = {}   # panel_id → HexItem, pour gérer l'état sélectionné
var _birth_orb            : ClickOrb           # orbe d'éclosion (juice d'éveil)
var _birth_phrase         : Label              # phrase d'éveil affichée actuellement
var _birth_phrase_idx     := 0                 # index de la prochaine phrase d'éveil à montrer
var _birth_hatching       := false             # vrai pendant le battement final avant l'éclosion
var _settings_overlay     : Control = null     # overlay paramètres, null si fermé
var _backdrop             : VillageBackdrop    # fond d'ambiance (halo + poussières)

# ─── DEBUG : prévisualisation des paliers du Village ──────────
# Boutons « Tier − / Tier + » en bas à gauche : montent/descendent le palier
# du Village pour juger l'évolution visuelle du hub sans jouer.
# ⚠ Modifie réellement GameData.village (peut finir dans la sauvegarde).
# Mettre à false avant une release.
const DEBUG_TIER_BUTTONS := true
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
		_build_birth()
	else:
		_build_hub()

	_build_fullscreen_btn()
	_build_debug_tier_buttons()

# ─── Phase d'éclosion : naissance du Village (pré-T0) ─────────
# Le Village n'existe pas encore : on clique Balance.ECLOSION_CLICS fois pour
# faire éclore l'incarnation. Au dernier clic → éclosion en T0 + cinématique.
# UI minimale : orbe cliquable + compteur + message (pas d'anneau).
func _build_birth() -> void:
	var clics    := int(GameData.village.get("clics_eclosion", 0))
	var needed   := Balance.ECLOSION_CLICS
	var progress := clampf(float(clics) / float(needed), 0.0, 1.0)

	# Ambiance discrète : le fond se réchauffe avec la progression de l'éveil.
	if _backdrop:
		_backdrop.set_tier(0, TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, progress))

	var orb := ClickOrb.new()
	orb.tier_color   = TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, progress)
	orb.callback     = Callable(self, "_on_birth_click")
	_center(orb, Vector2(0.0, -10.0), Vector2(96.0, 96.0))
	orb.pivot_offset = Vector2(48.0, 48.0)
	add_child(orb)
	_birth_orb = orb

	_xp_label = Label.new()
	_xp_label.text = "%d / %d" % [clics, needed]
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 15)
	_xp_label.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.3))
	_center(_xp_label, Vector2(0.0, 56.0), Vector2(160.0, 24.0))
	add_child(_xp_label)

	var flavor := Label.new()
	flavor.text = Translations.T("birth.flavor")
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_font_size_override("font_size", 12)
	flavor.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_center(flavor, Vector2(0.0, 92.0), Vector2(320.0, 44.0))
	add_child(flavor)

	# Reprend la séquence d'éveil là où elle en est : on saute les paliers déjà
	# franchis pour ne pas les rejouer après un rechargement de scène.
	_birth_phrase = null
	_birth_phrase_idx = 0
	_birth_hatching = false
	var _bp := _birth_phrases()
	while _birth_phrase_idx < _bp.size() \
			and progress + 0.0001 >= float(_bp[_birth_phrase_idx][0]):
		_birth_phrase_idx += 1

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
	# Progression de l'anneau : fragments collectés / coût du palier courant
	var frag_count: int = (GameData.village.get("fragments_collectes", []) as Array).size()
	if village_maitrise < Balance.VILLAGE_FRAGMENT_COSTS.size():
		var frag_cost := Balance.VILLAGE_FRAGMENT_COSTS[village_maitrise]
		_ring.fill_fraction = minf(1.0, float(frag_count) / float(frag_cost))
	else:
		_ring.fill_fraction = 1.0
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	_hub_root.add_child(_ring)

	# ── Centre : nom Village + palier + fragments + conditions ──
	var center_box := VBoxContainer.new()
	center_box.add_theme_constant_override("separation", 2)
	center_box.anchor_left   = 0.5; center_box.anchor_right  = 0.5
	center_box.anchor_top    = 0.5; center_box.anchor_bottom = 0.5
	center_box.offset_left   = 0.0; center_box.offset_right  = 0.0
	center_box.offset_top    = 0.0; center_box.offset_bottom = 0.0
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_hub_root.add_child(center_box)

	var lname := Label.new()
	lname.text = Translations.T("village.tier_label")
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lname.add_theme_font_size_override("font_size", 24)
	lname.add_theme_color_override("font_color", tcolor)
	lname.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	lname.add_theme_constant_override("shadow_offset_y", 2)
	center_box.add_child(lname)

	# Nom du palier encadré de deux fines lignes ornementales (touche JRPG).
	var tier_row := HBoxContainer.new()
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_theme_constant_override("separation", 10)
	center_box.add_child(tier_row)

	tier_row.add_child(_ornament_line(tcolor))
	var ltier := Label.new()
	ltier.text = GameData.get_tier_name(village_maitrise)
	ltier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ltier.add_theme_font_size_override("font_size", 15)
	ltier.add_theme_color_override("font_color", tcolor.lerp(Color.WHITE, 0.40))
	tier_row.add_child(ltier)
	tier_row.add_child(_ornament_line(tcolor))

	# Conditions d'évolution du Village (tant que le palier max n'est pas atteint)
	if village_maitrise < Balance.VILLAGE_FRAGMENT_COSTS.size():
		_build_village_conditions(center_box, village_maitrise, tcolor)

	# ── Hint contextuel (objectif courant) ───────────────────────
	var hint := _current_hint(village_maitrise)
	if hint != "":
		var hint_lbl := Label.new()
		hint_lbl.text = hint
		hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_lbl.anchor_left   = 0.0; hint_lbl.anchor_right  = 1.0
		hint_lbl.anchor_top    = 1.0; hint_lbl.anchor_bottom = 1.0
		hint_lbl.offset_top    = -36; hint_lbl.offset_bottom = -8
		hint_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		hint_lbl.add_theme_font_size_override("font_size", 12)
		hint_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.70))
		hint_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
		hint_lbl.add_theme_constant_override("shadow_offset_y", 1)
		_hub_root.add_child(hint_lbl)

	# ── HexItems : tous gated uniformément par village_maitrise ──
	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool:
		return (d[2] as int) <= village_maitrise
	)
	var n := unlocked.size()
	for i in n:
		var ang := -PI * 0.5 + i * TAU / n
		var pos := Vector2(cos(ang), sin(ang)) * RING_RADIUS
		var d: Array = unlocked[i]
		_make_hex(Translations.T("menu." + (d[4] as String)), d[1], tcolor, pos, Callable(self, d[3]), d[4])

	_animate_hub_entrance()

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

# Retourne le texte du hint contextuel selon la progression actuelle.
# Couvre toute la partie : démarrage → premier Fragment → évolution du
# Village prête → Forge → Fragments manquants pour le palier suivant.
func _current_hint(village_maitrise: int) -> String:
	var frags := (GameData.village.get("fragments_collectes", []) as Array).size()
	var hero_tier := int(GameData.get_entity("hero").get("maitrise_actuelle", 0))
	if GameData.can_upgrade_village():
		return Translations.T("hint.upgrade_ready")
	if village_maitrise == 0 and hero_tier == 0 and frags == 0:
		return Translations.T("hint.start")
	if village_maitrise == 0 and frags == 0:
		return Translations.T("hint.reach_rare")
	if village_maitrise >= 1 and not GameData.can_forge("equipment_arme") \
			and not GameData.can_forge("equipment_anneau") \
			and not GameData.can_forge("equipment_armure"):
		return Translations.T("hint.forge_ready")
	if village_maitrise < Balance.VILLAGE_FRAGMENT_COSTS.size():
		var missing := Balance.VILLAGE_FRAGMENT_COSTS[village_maitrise] - frags
		return Translations.T("hint.need_fragments") % missing
	return ""

# ─── Conditions d'évolution du Village ────────────────────────
# Affiche le compteur de fragments et le bouton Évoluer si la condition est remplie.
func _build_village_conditions(container: VBoxContainer, village_maitrise: int, vcolor: Color) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	container.add_child(spacer)

	var frag_need := Balance.VILLAGE_FRAGMENT_COSTS[village_maitrise]
	var frag_have: int = (GameData.village.get("fragments_collectes", []) as Array).size()
	var met := frag_have >= frag_need
	var row := Label.new()
	row.text = "%s%s  %d / %d" % ["✓ " if met else "• ", Translations.T("village.cond.fragments"), frag_have, frag_need]
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_font_size_override("font_size", 11)
	row.add_theme_color_override("font_color", UIColors.LOG_VICTORY if met else UIColors.TEXT_MUTED)
	# Les Labels ignorent la souris par défaut → STOP pour que le tooltip
	# « comment obtenir des Fragments » soit accessible au survol.
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	UIHelpers.register_tooltip(row, Translations.T("village.frag.tt_title"),
			Translations.T("village.frag.tt_body") % [frag_have, frag_need], vcolor)
	container.add_child(row)

	if GameData.can_upgrade_village():
		var next_color := UIColors.tier_color(village_maitrise + 1)
		var ubtn := UIHelpers.evolve_button("▲  " + Translations.T("village.evolve_btn"),
				next_color, 11)
		ubtn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ubtn.custom_minimum_size = Vector2(200.0, 26.0)
		UIHelpers.register_tooltip(ubtn, Translations.T("village.evolve_btn"),
				Translations.T("village.evolve.tt_body") \
						% GameData.get_tier_name(village_maitrise + 1), next_color)
		ubtn.pressed.connect(func() -> void:
			if GameData.upgrade_village():
				_rebuild_hub()
		)
		container.add_child(ubtn)

# ─── Panneau droite ───────────────────────────────────────────
# Ouvre le panneau JRPG pour panel_id. Re-clic sur le même id → ferme (toggle).
func _open_panel(panel_id: String) -> void:
	var vp := get_viewport_rect().size

	# Toggle : même hex → fermer
	if _active_panel_id == panel_id and _rp_root != null:
		_close_panel()
		return

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
	# 50 % de l'écran au centre de la zone libre.
	var hub_center := (1.0 - PANEL_FRACTION) * 0.5
	_hub_root.pivot_offset = vp * 0.5
	var ht := create_tween().set_parallel(true) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "scale", Vector2.ONE * HUB_PANEL_SCALE, 0.35)
	ht.tween_property(_hub_root, "position:x", vp.x * (hub_center - 0.5), 0.35)

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
	ht.tween_property(_hub_root, "scale", Vector2.ONE, 0.25)
	ht.tween_property(_hub_root, "position:x", 0.0, 0.25)

# Met à jour l'état is_selected de tous les HexItems selon le panneau ouvert.
func _update_hex_selection(active_id: String) -> void:
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.is_selected = (pid == active_id)
		item.queue_redraw()

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
	_rp_title = Label.new()
	_rp_title.text = Translations.panel_title(panel_id)
	_rp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rp_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_rp_title.add_theme_font_size_override("font_size", 16)
	_rp_title.add_theme_color_override("font_color", Color.WHITE)
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

# Lance l'aventure sur le biome sélectionné et bascule vers CombatScene.
func start_selected_expedition() -> void:
	if adv_selected_biome_id.is_empty():
		return
	GameData.player["active_biome_id"] = adv_selected_biome_id
	AdventureSystem.start_adventure(adv_selected_biome_id)
	get_tree().change_scene_to_file("res://scenes/combat/CombatScene.tscn")

# Panneau générique "Bientôt disponible" pour les fonctionnalités non implémentées.
func _panel_soon(label: String) -> void:
	var lbl := Label.new()
	lbl.text = Translations.T("village.soon") % label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	rp_content.add_child(lbl)

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

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", accent)
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
	_debug_tier_lbl = Label.new()
	_debug_tier_lbl.text = "Tier %d" % village_tier()
	_debug_tier_lbl.add_theme_font_size_override("font_size", 11)
	_debug_tier_lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
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


# ─── Phase d'éclosion : clic ─────────────────────────────────
# Incrémente le compteur de clics ; au dernier, déclenche l'éclosion en T0.
func _on_birth_click() -> void:
	if GameData.village.get("eclos", false) or _birth_hatching:
		return
	var needed   := Balance.ECLOSION_CLICS
	var clics    := int(GameData.village.get("clics_eclosion", 0)) + Balance.ECLOSION_CLIC_VALUE
	GameData.village["clics_eclosion"] = clics
	var progress := clampf(float(clics) / float(needed), 0.0, 1.0)

	if is_instance_valid(_xp_label):
		_xp_label.text = "%d / %d" % [mini(clics, needed), needed]
		_xp_label.add_theme_color_override("font_color",
				TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, progress).lightened(0.2))

	# L'étincelle se réchauffe à mesure que l'âme s'éveille.
	if is_instance_valid(_birth_orb):
		_birth_orb.tier_color = TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, progress)

	# Phrases d'éveil au franchissement des paliers (25 / 50 / 75 %).
	var bp := _birth_phrases()
	while _birth_phrase_idx < bp.size() \
			and progress + 0.0001 >= float(bp[_birth_phrase_idx][0]):
		_show_birth_phrase(bp[_birth_phrase_idx][1], false)
		_birth_phrase_idx += 1

	# Chuchotements d'ambiance : fragments narratifs courts qui surgissent au
	# hasard durant les clics, à une position aléatoire, en fondu entrant/sortant.
	if not _birth_hatching and randf() < BIRTH_WHISPER_CHANCE:
		_show_birth_whisper()

	if clics >= needed:
		# Éveil final : phrase forte + voile chaud, puis éclosion après un battement.
		_birth_hatching = true
		_show_birth_phrase(Translations.T("birth.phrase_100"), true)
		_birth_awaken_flash()
		var tw := create_tween()
		tw.tween_interval(1.8)
		tw.tween_callback(_hatch_village)

# Affiche une phrase d'éveil au-dessus de l'orbe : fondu entrant + léger « pop ».
# La phrase précédente s'efface en douceur. Une phrase `final` reste affichée
# (l'éclosion enchaîne par-dessus). Le reste se fond après quelques secondes.
func _show_birth_phrase(text: String, final: bool) -> void:
	if is_instance_valid(_birth_phrase):
		var old := _birth_phrase
		var ot := old.create_tween()   # lié à `old` → auto-tué si `old` est libéré
		ot.tween_property(old, "modulate:a", 0.0, 0.3)
		ot.tween_callback(old.queue_free)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 19 if final else 15)
	lbl.add_theme_color_override("font_color",
			ECLOSION_AWAKEN_COLOR if final else TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, 0.7))
	lbl.modulate.a = 0.0
	lbl.scale = Vector2(0.96, 0.96)
	lbl.resized.connect(func() -> void: lbl.pivot_offset = lbl.size * 0.5)
	_center(lbl, Vector2(0.0, -150.0), Vector2(480.0, 90.0))
	add_child(lbl)
	_birth_phrase = lbl

	var t_in := lbl.create_tween().set_parallel(true)
	t_in.tween_property(lbl, "modulate:a", 1.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t_in.tween_property(lbl, "scale", Vector2.ONE, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	if not final:
		var t_out := lbl.create_tween()
		t_out.tween_interval(2.9)
		t_out.tween_property(lbl, "modulate:a", 0.0, 0.9)
		t_out.tween_callback(lbl.queue_free)

# Chuchotement d'ambiance : court fragment narratif tiré au hasard, posé à une
# position aléatoire de l'écran (périphérie, hors de l'orbe et des phrases),
# fondu entrant PUIS sortant symétriques avant de se libérer.
func _show_birth_whisper() -> void:
	var pool := _birth_whispers()
	if pool.is_empty():
		return

	var lbl := Label.new()
	lbl.text = pool[randi() % pool.size()] as String
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", TIER_0_COLOR.lerp(ECLOSION_AWAKEN_COLOR, 0.45))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.modulate.a    = 0.0
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE   # ne vole pas le clic de l'orbe
	lbl.z_index       = 50

	var w := 300.0
	var h := 40.0
	lbl.position = _random_whisper_pos(get_viewport_rect().size, w, h)
	lbl.size     = Vector2(w, h)
	add_child(lbl)

	# Fondu entrant puis sortant SYMÉTRIQUES (même durée, même courbe), avec un
	# court palier visible entre les deux.
	var fade := 0.9
	var tw := lbl.create_tween()   # lié à `lbl` → auto-tué si libéré
	tw.tween_property(lbl, "modulate:a", 0.9, fade).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, fade).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(lbl.queue_free)

# Position aléatoire bornée aux marges de l'écran, en évitant un rectangle
# central (orbe + compteur + phrases d'éveil) pour ne pas brouiller la lecture.
func _random_whisper_pos(vp: Vector2, w: float, h: float) -> Vector2:
	var margin := 50.0
	var min_x := margin
	var max_x := maxf(vp.x - w - margin, min_x)
	var min_y := margin
	var max_y := maxf(vp.y - h - margin, min_y)
	var exclusion := Rect2(vp.x * 0.5 - 280.0, vp.y * 0.5 - 200.0, 560.0, 400.0)
	for _i in 12:
		var p := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if not exclusion.intersects(Rect2(p, Vector2(w, h))):
			return p
	return Vector2(min_x, min_y)   # repli (écran trop petit) : coin haut-gauche

# Bref voile chaud sur tout l'écran au moment de l'éveil final.
func _birth_awaken_flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(ECLOSION_AWAKEN_COLOR.r, ECLOSION_AWAKEN_COLOR.g, ECLOSION_AWAKEN_COLOR.b, 0.0)
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 400
	add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.22, 0.30).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "color:a", 0.0, 1.30).set_ease(Tween.EASE_IN)
	tw.tween_callback(flash.queue_free)

# Fait éclore le Village en T0, sauvegarde, puis lance la cinématique d'éclosion.
func _hatch_village() -> void:
	GameData.village["eclos"] = true
	SaveManager.save()
	# entity_id volontairement "village" (absent du catalogue d'entités) : le rituel
	# retombe alors sur le nom passé ("Village"). Passer "hero" affichait "Héros".
	launch_evolution_ritual(Enums.EntityType.VILLAGE, "village", "Village", 0, 0, {"eclosion": true})

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

	# forge : un équipement avec XP pleine
	var forge_alert := false
	for entry in ForgePanel.BIOME_EQUIP:
		if GameData.equipment_xp_full(entry[1] as String):
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
	if _active_panel_id == "forge" or _active_panel_id == "hero":
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
