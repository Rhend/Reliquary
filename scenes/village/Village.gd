# ============================================================
# Village.gd — Hub central du jeu.
#
# Éclosion : orbe cliquable (100 clics) → naissance du Village en T0.
# T0+      : hub hexagonal + panneau JRPG glissant (40/60 viewport).
#
# Widgets visuels dans scenes/village/widgets/ :
#   CircleRing, ClickOrb, HexItem, JRPGPanel, XPCard
#
# Le contenu des panneaux glissants (Héro / Expéditions / Forge) est délégué à
# des modules dédiés dans scenes/village/panels/ ; ils reçoivent ce nœud (host)
# pour accéder à _rp_content et aux helpers partagés (_make_evolve_btn, etc.).
# ============================================================
class_name Village
extends Control

# ─── Constantes ───────────────────────────────────────────────
const RING_RADIUS  := 165.0
const HEX_SIZE     := Vector2(152.0, 152.0)
const TIER_0_COLOR := Color(0.38, 0.38, 0.52)

# [label, icon, tier_min, callback_name, panel_id]
# tier_min = palier du héro requis ; exception : FORGE est gated par le Tier du Village.
# Gates décalés d'un rang : le Village éclot en T0 et débloque déjà les expéditions.
const MENU_ITEMS: Array = [
	["HÉRO",        "👤", 0, "_go_hero",      "hero"      ],
	["EXPÉDITIONS", "⚔",  0, "_go_adventure", "adventure" ],
	["FORGE",       "🔨", 1, "_go_forge",     "forge"     ],
	["SANCTUAIRE",  "✦",  2, "_go_sanctuary", "sanctuary" ],
	["RELIQUE",     "◈",  3, "_go_relic",     "relic"     ],
	["?",           "?",  4, "_go_tbd",       "tbd"       ],
]

const PANEL_TITLES: Dictionary = {
	"hero":      "HÉRO",
	"adventure": "EXPÉDITIONS",
	"forge":     "FORGE",
	"sanctuary": "SANCTUAIRE",
	"relic":     "RELIQUE",
	"tbd":       "?",
}

# ─── État ─────────────────────────────────────────────────────
var _ring            : CircleRing         # anneau animé central (XP fill + tier visuel)
var _xp_label        : Label              # compteur de clics sous l'orbe (phase d'éclosion)
var _hub_root        : Control            # conteneur du hub hexagonal
var _rp_root         : Control            # panneau droit JRPG — null si fermé
var _rp_content      : VBoxContainer      # zone de contenu scrollable du panneau droit
var _rp_title        : Label              # label titre dans la barre du panneau droit
var _active_panel_id      := ""           # id du panneau ouvert ("hero", "adventure", …)
var _adv_selected_biome_id := ""          # biome sélectionné dans le panneau Expéditions
var _hex_items            : Dictionary = {}   # panel_id → HexItem, pour gérer l'état sélectionné

# ─── Init ─────────────────────────────────────────────────────
func _ready() -> void:
	SaveManager.load_save()
	_build_ui()
	EventBus.fragment_libere.connect(_on_fragment_libere)
	EventBus.village_tier_change.connect(_on_village_tier_change)
	EventBus.biome_revele.connect(_on_biome_revele)

# Retourne le dictionnaire d'entité de la créature active, ou {} si absente.
func _active_creature() -> Dictionary:
	var cid := GameData.player.get("active_creature_id", "") as String
	if cid.is_empty(): return {}
	return GameData.get_entity(cid)

# Tier actuel de la créature active — détermine le layout et les couleurs du hub.
func _maitrise_actuelle() -> int:
	return _active_creature().get("maitrise_actuelle", 0) as int

# ─── Construction principale ──────────────────────────────────
# Point d'entrée de construction : tier 0 → orbe cliquable, tier 1+ → hub hexagonal.
func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = UIColors.BG_DARK
	add_child(bg)

	var creature := _active_creature()
	var tier     := creature.get("maitrise_actuelle", 0) as int
	# Tant que le Village n'a pas éclos : phase préliminaire (100 clics).
	# Une fois éclos, le hub est disponible dès T0 (expéditions incluses).
	if not GameData.village.get("eclos", false):
		_build_birth(creature)
	else:
		_build_hub(creature, tier)

	_build_debug_buttons()
	_build_fullscreen_btn()

# ─── Phase d'éclosion : naissance du Village (pré-T0) ─────────
# Le Village n'existe pas encore : on clique Balance.ECLOSION_CLICS fois pour
# faire éclore l'incarnation. Au dernier clic → éclosion en T0 + cinématique.
# UI minimale : orbe cliquable + compteur + message (pas d'anneau).
func _build_birth(_creature: Dictionary) -> void:
	var clics  := int(GameData.village.get("clics_eclosion", 0))
	var needed := Balance.ECLOSION_CLICS

	var orb := ClickOrb.new()
	orb.tier_color   = TIER_0_COLOR
	orb.callback     = Callable(self, "_on_birth_click")
	_center(orb, Vector2(0.0, -10.0), Vector2(96.0, 96.0))
	orb.pivot_offset = Vector2(48.0, 48.0)
	add_child(orb)

	_xp_label = Label.new()
	_xp_label.text = "%d / %d" % [clics, needed]
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 15)
	_xp_label.add_theme_color_override("font_color", TIER_0_COLOR.lightened(0.3))
	_center(_xp_label, Vector2(0.0, 56.0), Vector2(160.0, 24.0))
	add_child(_xp_label)

	var flavor := Label.new()
	flavor.text = "Frappez l'étincelle pour faire éclore le Village…"
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_font_size_override("font_size", 12)
	flavor.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_center(flavor, Vector2(0.0, 92.0), Vector2(320.0, 44.0))
	add_child(flavor)

# ─── Tier 1+ : hub hexagonal ──────────────────────────────────
# Construit le hub circulaire avec les hexagones débloqués par le tier.
func _build_hub(_creature: Dictionary, tier: int) -> void:
	var vp     := get_viewport_rect().size
	var tcolor := UIColors.tier_color(tier)
	var diam_margins := [70.0, 70.0, 82.0, 104.0, 136.0, 164.0]
	var diam: float = RING_RADIUS * 2.0 + float(diam_margins[tier])

	_hub_root = Control.new()
	_hub_root.size = vp
	add_child(_hub_root)

	_ring = CircleRing.new()
	_ring.ring_color  = tcolor
	_ring.ring_radius = RING_RADIUS
	_ring.tier        = tier
	_center(_ring, Vector2.ZERO, Vector2(diam, diam))
	_hub_root.add_child(_ring)

	var lname := Label.new()
	lname.text = "Village"
	lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lname.add_theme_font_size_override("font_size", 24)
	lname.add_theme_color_override("font_color", tcolor)
	_center(lname, Vector2(0.0, -17.0), Vector2(180.0, 32.0))
	_hub_root.add_child(lname)

	var ltier := Label.new()
	ltier.text = GameData.get_tier_name(tier)
	ltier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ltier.add_theme_font_size_override("font_size", 15)
	ltier.add_theme_color_override("font_color", tcolor.lerp(Color.WHITE, 0.40))
	_center(ltier, Vector2(0.0, 16.0), Vector2(150.0, 24.0))
	_hub_root.add_child(ltier)

	# ── Info Village (tier + fragments) ──────────────────────
	var vtier := GameData.village.get("tier_actuel", 0) as int
	var vcolor := Color(0.55, 0.85, 0.55) if vtier >= 1 else Color(0.6, 0.6, 0.7)

	var vlabel := Label.new()
	vlabel.text = "Village T%d" % vtier
	vlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlabel.add_theme_font_size_override("font_size", 12)
	vlabel.add_theme_color_override("font_color", vcolor)
	_center(vlabel, Vector2(0.0, 40.0), Vector2(150.0, 18.0))
	_hub_root.add_child(vlabel)

	if vtier < GameData.VILLAGE_TIER_REQUIREMENTS.size():
		var frags_needed := GameData.VILLAGE_TIER_REQUIREMENTS[vtier]
		var frags_have: int = (GameData.village.get("fragments_collectes", []) as Array).size()
		var fprog := Label.new()
		fprog.text = "🔮 %d / %d fragment%s" % [frags_have, frags_needed, "s" if frags_needed > 1 else ""]
		fprog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fprog.add_theme_font_size_override("font_size", 11)
		fprog.add_theme_color_override("font_color", UIColors.FILTER_ON if frags_have >= frags_needed else UIColors.TEXT_MUTED)
		_center(fprog, Vector2(0.0, 57.0), Vector2(180.0, 16.0))
		_hub_root.add_child(fprog)

		if GameData.can_upgrade_village():
			var ubtn := Button.new()
			ubtn.text = "▲  Faire évoluer le Village"
			ubtn.add_theme_font_size_override("font_size", 11)
			ubtn.add_theme_color_override("font_color", vcolor)
			ubtn.add_theme_stylebox_override("normal", UIHelpers.card_style(vcolor, 0.12, 1.0, 1, 4))
			ubtn.add_theme_stylebox_override("hover",  UIHelpers.card_style(vcolor, 0.28, 1.0, 1, 4))
			ubtn.pressed.connect(func() -> void:
				if GameData.upgrade_village():
					_rebuild_hub()
			)
			_center(ubtn, Vector2(0.0, 78.0), Vector2(200.0, 26.0))
			_hub_root.add_child(ubtn)

	# ── Hex items (forge débloquée par village tier, reste par hero tier) ──
	var unlocked: Array = MENU_ITEMS.filter(func(d: Array) -> bool:
		var pid := d[4] as String
		if pid == "forge":
			return vtier >= (d[2] as int)
		return (d[2] as int) <= tier
	)
	var n := unlocked.size()
	for i in n:
		var ang := -PI * 0.5 + i * TAU / n
		var pos := Vector2(cos(ang), sin(ang)) * RING_RADIUS
		var d: Array = unlocked[i]
		_make_hex(d[0], d[1], tcolor, pos, Callable(self, d[3]), d[4])

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
			_rp_title.text = PANEL_TITLES.get(panel_id, panel_id.to_upper())
		_swap_panel_content(panel_id)
		return

	# Réduire le hub à 40 %
	var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "size:x", vp.x * 0.4, 0.35)

	# Créer le panneau hors écran à droite
	_rp_root = Control.new()
	_rp_root.size     = Vector2(vp.x * 0.6, vp.y)
	_rp_root.position = Vector2(vp.x, 0.0)
	add_child(_rp_root)
	_build_panel_frame(panel_id)

	# Glissement vers la droite du hub
	var pt := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	pt.tween_property(_rp_root, "position:x", vp.x * 0.4, 0.35)

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
			_rp_root    = null
			_rp_content = null
			_rp_title   = null
	)

	var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ht.tween_property(_hub_root, "size:x", vp.x, 0.25)

# Met à jour l'état is_selected de tous les HexItems selon le panneau ouvert.
func _update_hex_selection(active_id: String) -> void:
	for pid in _hex_items:
		var item := _hex_items[pid] as HexItem
		item.is_selected = (pid == active_id)
		item.queue_redraw()

# Vide _rp_content et réinjecte le contenu pour panel_id (panneau déjà ouvert).
func _swap_panel_content(panel_id: String) -> void:
	UIHelpers.clear_children(_rp_content)
	_fill_panel_content(panel_id)

# ─── Construction du cadre JRPG ──────────────────────────────
# Crée le JRPGPanel, le titre, le bouton fermer et la zone scrollable.
func _build_panel_frame(panel_id: String) -> void:
	var tcolor := UIColors.tier_color(_maitrise_actuelle())

	var frame := JRPGPanel.new()
	frame.panel_color = tcolor
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rp_root.add_child(frame)

	# Titre
	_rp_title = Label.new()
	_rp_title.text = PANEL_TITLES.get(panel_id, panel_id.to_upper())
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

	var margin := UIHelpers.margin_of(12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	_rp_content = VBoxContainer.new()
	_rp_content.add_theme_constant_override("separation", 10)
	_rp_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_rp_content)

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
func _on_start_selected_expedition() -> void:
	if _adv_selected_biome_id.is_empty():
		return
	GameData.player["active_biome_id"] = _adv_selected_biome_id
	AdventureSystem.start_adventure(_adv_selected_biome_id)
	get_tree().change_scene_to_file("res://scenes/combat/CombatScene.tscn")

# Panneau générique "Bientôt disponible" pour les fonctionnalités non implémentées.
func _panel_soon(label: String) -> void:
	var lbl := Label.new()
	lbl.text = "✦  %s  ✦\n\nBientôt disponible" % label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_rp_content.add_child(lbl)

# ─── Village ──────────────────────────────────────────────────

# Recrée le hub (après upgrade village ou changement de tier).
func _rebuild_hub() -> void:
	if _hub_root and is_instance_valid(_hub_root):
		_hub_root.queue_free()
		_hub_root = null
	_rp_root = null
	_rp_content = null
	_hex_items.clear()
	_active_panel_id = ""
	var creature := _active_creature()
	var tier     := creature.get("maitrise_actuelle", 0) as int
	if GameData.village.get("eclos", false):
		_build_hub(creature, tier)

# Fragment libéré : feedback + rebuild hub (le bouton upgrade peut apparaître).
func _on_fragment_libere(fragment_id: String, _biome_id: String) -> void:
	var frag: Dictionary = GameData.get_entity(fragment_id)
	var nom  := frag.get("nom_affichage_fr", fragment_id) as String
	_show_fragment_banner(nom)
	_rebuild_hub()

# Village tier change : rebuild hub (nouvelle couleur, nouveau bouton forge).
func _on_village_tier_change(_nouveau_tier: int) -> void:
	_rebuild_hub()

# Nouveau biome révélé : bannière + refresh du panneau Expéditions si ouvert.
func _on_biome_revele(biome_id: String) -> void:
	var biome := GameData.get_entity(biome_id)
	var nom   := biome.get("nom_affichage_fr", biome_id) as String
	_show_biome_revele_banner(nom)
	if _active_panel_id == "adventure":
		_open_panel("adventure")

func _show_biome_revele_banner(biome_nom: String) -> void:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top    = 20
	banner.offset_bottom = 80
	banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.05, 0.10, 0.25, 0.92)
	style.border_color = Color(0.4, 0.7, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	banner.add_theme_stylebox_override("panel", style)
	add_child(banner)

	var lbl := Label.new()
	lbl.text = "✦  Nouveau biome révélé : %s  ✦" % biome_nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(lbl)

	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)
	tw.tween_callback(banner.queue_free)

# Bannière temporaire lors de la libération d'un Fragment.
func _show_fragment_banner(fragment_nom: String) -> void:
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top    = 20
	banner.offset_bottom = 80
	banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.05, 0.05, 0.20, 0.92)
	style.border_color = Color(0.55, 0.85, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	banner.add_theme_stylebox_override("panel", style)
	add_child(banner)

	var lbl := Label.new()
	lbl.text = "🔮  Fragment libéré : %s" % fragment_nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(lbl)

	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)
	tw.tween_callback(banner.queue_free)

# ─── Debug : boutons tier ─────────────────────────────────────
# Ajoute les boutons "Tier +/-" pour tester visuellement les tiers sans sauvegarder.
func _build_debug_buttons() -> void:
	var vb := VBoxContainer.new()
	vb.anchor_left   = 0.0; vb.anchor_top    = 0.0
	vb.anchor_right  = 0.0; vb.anchor_bottom = 0.0
	vb.offset_left   = 10;  vb.offset_top    = 10
	vb.offset_right  = 10;  vb.offset_bottom = 10
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vb.add_child(row1)

	var up := Button.new()
	up.text = "Tier +"
	up.pressed.connect(_debug_tier_up)
	row1.add_child(up)

	var dn := Button.new()
	dn.text = "Tier −"
	dn.pressed.connect(_debug_tier_down)
	row1.add_child(dn)

# Incrémente le tier du héro, réinitialise son XP et recharge la scène.
func _debug_tier_up() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("maitrise_actuelle", 0) as int
	if tier < GameData.MAX_TIER:
		hero["maitrise_actuelle"] = tier + 1
		hero["xp_maitrise_actuelle"]   = 0.0
		SaveManager.save()
		_launch_evolution_ritual("village", "hero", "Village", tier, tier + 1)

# Décrémente le tier du héro, réinitialise son XP et recharge la scène.
func _debug_tier_down() -> void:
	var hero := GameData.get_entity("hero")
	var tier := hero.get("maitrise_actuelle", 0) as int
	if tier > 0:
		hero["maitrise_actuelle"] = tier - 1
		hero["xp_maitrise_actuelle"]   = 0.0
		SaveManager.save()
		_launch_evolution_ritual("village", "hero", "Village", tier, tier - 1)

# Ajoute le bouton ⛶ en haut à droite pour basculer le plein écran.
func _build_fullscreen_btn() -> void:
	var btn := Button.new()
	btn.text = "⛶"
	btn.flat = true
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 0.0; btn.anchor_bottom = 0.0
	btn.offset_left   = -34; btn.offset_right  = -6
	btn.offset_top    = 6;   btn.offset_bottom = 34
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.tooltip_text = "Plein écran  (F11)"
	btn.pressed.connect(func() -> void: GameSettings.set_fullscreen(not GameSettings.fullscreen))
	add_child(btn)

# ─── Phase d'éclosion : clic ─────────────────────────────────
# Incrémente le compteur de clics ; au dernier, déclenche l'éclosion en T0.
func _on_birth_click() -> void:
	if GameData.village.get("eclos", false):
		return
	var needed := Balance.ECLOSION_CLICS
	var clics  := int(GameData.village.get("clics_eclosion", 0)) + Balance.ECLOSION_CLIC_VALUE
	GameData.village["clics_eclosion"] = clics
	if is_instance_valid(_xp_label):
		_xp_label.text = "%d / %d" % [mini(clics, needed), needed]
	if clics >= needed:
		_hatch_village()

# Fait éclore le Village en T0, sauvegarde, puis lance la cinématique d'éclosion.
func _hatch_village() -> void:
	GameData.village["eclos"] = true
	SaveManager.save()
	_launch_evolution_ritual("village", "hero", "Village", 0, 0, {"eclosion": true})

# ─── Bouton ÉVOLUER pulsant ──────────────────────────────────
# Fabrique un bouton ÉVOLUER avec pulsation scale 1.0→1.05→1.0 en boucle.
# La couleur du texte correspond au tier cible (from_tier + 1).
func _make_evolve_btn(entity_id: String, entity_name: String,
		entity_type: String, from_tier: int) -> Button:
	var nc  := UIColors.tier_color(from_tier + 1)
	var btn := Button.new()
	btn.text = "ÉVOLUER ▲"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_color_override("font_color", nc)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.resized.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5
	)
	btn.ready.connect(func() -> void:
		var tw := btn.create_tween().set_loops()
		tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.6) \
				.set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_IN_OUT)
	)
	btn.pressed.connect(func() -> void:
		if MasterySystem.evolve_entity(entity_id):
			SaveManager.save()
			_launch_evolution_ritual(entity_type, entity_id, entity_name,
					from_tier, from_tier + 1)
	)
	return btn

# ─── Rituel d'ascension ──────────────────────────────────────
# Stocke les paramètres dans GameData puis fond vers noir avant de changer de scène.
func _launch_evolution_ritual(entity_type: String, entity_id: String,
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
func _make_hex(lbl: String, icon: String, tcolor: Color, pos: Vector2, cb: Callable, panel_id: String) -> void:
	var item := HexItem.new()
	item.icon_text   = icon
	item.label_text  = lbl
	item.tier_color  = tcolor
	item.tier        = _maitrise_actuelle()
	item.outward_dir = pos.normalized()
	item.callback    = cb
	_center(item, pos, HEX_SIZE)
	item.pivot_offset = HEX_SIZE * 0.5
	_hub_root.add_child(item)
	_hex_items[panel_id] = item

# ─── Navigation → panneaux ────────────────────────────────────
func _go_hero()       -> void: _open_panel("hero")
func _go_adventure()  -> void: _open_panel("adventure")
func _go_forge()     -> void: _open_panel("forge")
func _go_sanctuary() -> void: _open_panel("sanctuary")
func _go_relic()     -> void: _open_panel("relic")
func _go_tbd()       -> void: _open_panel("tbd")

# ─── Utils ────────────────────────────────────────────────────
# Positionne ctrl centré sur pos avec la taille sz, en mode ancre centre.
func _center(ctrl: Control, pos: Vector2, sz: Vector2) -> void:
	ctrl.anchor_left   = 0.5; ctrl.anchor_right  = 0.5
	ctrl.anchor_top    = 0.5; ctrl.anchor_bottom = 0.5
	ctrl.offset_left   = pos.x - sz.x * 0.5
	ctrl.offset_right  = pos.x + sz.x * 0.5
	ctrl.offset_top    = pos.y - sz.y * 0.5
	ctrl.offset_bottom = pos.y + sz.y * 0.5
