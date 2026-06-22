# ============================================================
# EvolutionRitual.gd — Séquence cinématique d'ascension de palier.
#
# Lit GameData.pending_evolution au démarrage puis joue :
#   Phase 2 (0.5s)  : carte apparaît (fade + scale in)
#   Phase 3 (2.0s)  : pulse fluide ×2 + couleur + drone
#   Phase 4 (1.0s)  : flash + gros texte haut (élastique) + descente dans carte
#   Phase 5 (0.75s) : carte remonte au 1/3 supérieur + texte bonus surgit en dessous
#   Stable (1.6s)   : célébration — skipable dès l'apparition du texte bonus
#   Phase 6 (0.3s)  : fondu noir → retour Village
#
# Skipable uniquement dès la Phase 5 stable (clic, Espace, Échap, Entrée).
# ============================================================
extends Control

const VILLAGE_SCENE := "res://scenes/village/village.tscn"
const ECLOSION_COLOR := Color(1.0, 0.85, 0.4)  # doré chaud — naissance du Village

# ─── Nœuds UI ────────────────────────────────────────────────
var _card:           Control           = null
var _card_style:     StyleBoxFlat      = null
var _from_tier_lbl:  Label             = null   # label tier à l'intérieur de la carte
var _name_lbl:       Label             = null   # nom d'entité (peut changer au palier)
var _tier_chip_style: StyleBoxFlat     = null   # pastille du tier dans la carte
var _icon_lbl:       Label             = null   # icône d'entité dans la carte
var _tier_label:     Label             = null   # grand texte palier (en haut)
var _flash:          ColorRect         = null
var _particles:      CPUParticles2D    = null
var _rays:           GodRays           = null   # rayons divins derrière la carte
var _title_fx:       SummaryFX         = null   # burst d'étincelles sur le titre
var _drone:          AudioStreamPlayer = null
var _crystal:        AudioStreamPlayer = null

# ─── État séquence ───────────────────────────────────────────
var _params:         Dictionary = {}
var _can_skip:       bool       = false
var _skip_triggered: bool       = false
var _returning:      bool       = false

# ─── Init ─────────────────────────────────────────────────────
func _ready() -> void:
	_params = GameData.pending_evolution.duplicate()
	GameData.pending_evolution.clear()

	if _params.is_empty():
		get_tree().change_scene_to_file(VILLAGE_SCENE)
		return

	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	_run_sequence()

# ═══════════════════════════════════════════════════════════
#  Construction UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UIColors.BG_DARK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Rayons divins (halo + rayons rotatifs + onde de choc), foyer sur la carte.
	var from_color := UIColors.tier_color(_params.get("from_tier", 0) as int)
	if _params.get("eclosion", false):
		from_color = Color(0.35, 0.35, 0.45)
	_rays = GodRays.new()
	_rays.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rays.color = from_color
	add_child(_rays)

	_build_entity_card()
	_build_tier_label()
	_build_particles()

	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_flash.modulate.a = 0.0
	_flash.z_index = 300
	add_child(_flash)

	_build_sounds()

# Icône d'entité selon le type — même langage visuel que le récap de cycle.
func _entity_icon() -> String:
	if _params.get("eclosion", false):
		return "🏠"
	match _params.get("entity_type", "") as String:
		Enums.EntityType.CREATURE:                                return "🐾"
		Enums.EntityType.TRAP:                                    return "▲"
		Enums.EntityType.BENEDICTION:                             return "✦"
		Enums.EntityType.BIOME:                                   return "🌿"
		Enums.EntityType.EQUIPMENT:                               return "🔨"
		Enums.EntityType.HERO:                                    return "⚔"
		Enums.EntityType.VILLAGE:                                 return "🏠"
		Enums.EntityType.PASSIVE, Enums.EntityType.PASSIF_UNIQUE: return "⚡"
		_:                                                        return "✦"

func _build_entity_card() -> void:
	var from_tier  := _params.get("from_tier", 0) as int
	var from_color := UIColors.tier_color(from_tier)

	_card_style = StyleBoxFlat.new()
	_card_style.bg_color      = Color(0.05, 0.06, 0.10, 0.94)
	_card_style.border_color  = Color(from_color.r, from_color.g, from_color.b, 0.80)
	_card_style.set_border_width_all(2)
	_card_style.set_corner_radius_all(14)
	_card_style.shadow_color  = Color(0, 0, 0, 0.55)
	_card_style.shadow_size   = 22

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 190)
	card.add_theme_stylebox_override("panel", _card_style)
	card.anchor_left  = 0.5; card.anchor_right  = 0.5
	card.anchor_top   = 0.5; card.anchor_bottom = 0.5
	card.offset_left  = -150.0; card.offset_right  = 150.0
	card.offset_top   = -95.0;  card.offset_bottom = 95.0
	card.pivot_offset = Vector2(150, 95)
	card.modulate.a   = 0.0
	card.scale        = Vector2(0.8, 0.8)

	var margin := UIHelpers.margin_of(16)
	card.add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)

	# Icône d'entité — remplit l'espace mort de l'ancienne carte.
	_icon_lbl = Label.new()
	_icon_lbl.text = _entity_icon()
	_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_lbl.add_theme_font_size_override("font_size", 44)
	_icon_lbl.add_theme_color_override("font_color", from_color.lightened(0.25))
	vb.add_child(_icon_lbl)

	# Nom AU PALIER DE DÉPART : certaines entités changent de nom en évoluant ;
	# le nouveau nom est révélé au morph de palier (_finish_tier_replacement).
	var display_name := _entity_name_at(from_tier)
	_name_lbl = Label.new()
	_name_lbl.text = display_name.to_upper()
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.add_theme_font_size_override("font_size", 21)
	_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	_name_lbl.add_theme_constant_override("outline_size", 4)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	vb.add_child(_name_lbl)

	# Pastille de tier (le grand texte du palier vient s'y morpher).
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tier_chip_style = UIHelpers.card_style(from_color, 0.16, 0.85, 1, 10)
	chip.add_theme_stylebox_override("panel", _tier_chip_style)
	vb.add_child(chip)

	var chip_m := MarginContainer.new()
	chip_m.add_theme_constant_override("margin_left", 12)
	chip_m.add_theme_constant_override("margin_right", 12)
	chip_m.add_theme_constant_override("margin_top", 3)
	chip_m.add_theme_constant_override("margin_bottom", 3)
	chip.add_child(chip_m)

	_from_tier_lbl = Label.new()
	_from_tier_lbl.text = GameData.get_tier_name(from_tier).to_upper()
	_from_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_from_tier_lbl.add_theme_font_size_override("font_size", 13)
	_from_tier_lbl.add_theme_color_override("font_color", from_color.lightened(0.20))
	chip_m.add_child(_from_tier_lbl)

	add_child(card)
	_card = card

func _build_tier_label() -> void:
	var to_tier := _params.get("to_tier", 1) as int
	var accent  := _accent_color()

	_tier_label = Label.new()
	_tier_label.text                 = Translations.T("ritual.eclosion_title") if _params.get("eclosion", false) else GameData.get_tier_name(to_tier).to_upper()
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_font_size_override("font_size", 64)
	_tier_label.add_theme_color_override("font_color", accent.lightened(0.35))
	_tier_label.add_theme_constant_override("outline_size", 8)
	_tier_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	# En haut de l'écran (~100px depuis le top), centré horizontalement (±320px)
	_tier_label.anchor_left   = 0.5; _tier_label.anchor_right  = 0.5
	_tier_label.anchor_top    = 0.0; _tier_label.anchor_bottom = 0.0
	_tier_label.offset_left   = -320.0; _tier_label.offset_right  = 320.0
	_tier_label.offset_top    = 60.0;   _tier_label.offset_bottom = 160.0
	_tier_label.pivot_offset  = Vector2(320.0, 50.0)
	_tier_label.modulate.a    = 0.0
	_tier_label.scale         = Vector2(0.5, 0.5)
	_tier_label.z_index       = 100
	add_child(_tier_label)

	# Étincelles de révélation, par-dessus le grand texte.
	_title_fx = SummaryFX.new()
	_title_fx.mode   = SummaryFX.Mode.BANNER
	_title_fx.accent = accent
	_title_fx.shine  = false   # burst seul, qui déborde librement du titre
	_title_fx.anchor_left  = 0.5; _title_fx.anchor_right  = 0.5
	_title_fx.anchor_top   = 0.0; _title_fx.anchor_bottom = 0.0
	_title_fx.offset_left  = -320.0; _title_fx.offset_right  = 320.0
	_title_fx.offset_top   = 60.0;   _title_fx.offset_bottom = 160.0
	_title_fx.z_index      = 110
	add_child(_title_fx)

func _build_particles() -> void:
	var vp      := get_viewport_rect().size
	var to_tier := _params.get("to_tier", 1) as int
	var color   := _get_tier_particle_color(to_tier)
	if _params.get("eclosion", false):
		color = ECLOSION_COLOR

	_particles = CPUParticles2D.new()
	_particles.emitting              = false
	_particles.amount                = 110
	_particles.lifetime              = 3.0
	_particles.explosiveness         = 0.0
	_particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(vp.x * 0.5, 5.0)
	_particles.position              = Vector2(vp.x * 0.5, vp.y + 20.0)
	_particles.direction             = Vector2(0.0, -1.0)
	_particles.spread                = 12.0
	_particles.gravity               = Vector2(0.0, -180.0)
	_particles.initial_velocity_min  = 90.0
	_particles.initial_velocity_max  = 170.0
	_particles.scale_amount_min      = 0.6
	_particles.scale_amount_max      = 1.6
	_particles.color                 = Color.WHITE
	_particles.texture               = _make_particle_texture()

	var gradient := Gradient.new()
	gradient.set_color(0,  Color(color.r, color.g, color.b, 0.0))
	gradient.set_offset(0, 0.0)
	gradient.set_color(1,  Color(color.r, color.g, color.b, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.add_point(0.15, Color(color.r, color.g, color.b, 1.0))
	gradient.add_point(0.70, Color(color.r, color.g, color.b, 1.0))
	_particles.color_ramp = gradient
	add_child(_particles)

func _make_particle_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x: int in 8:
		for y: int in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(1.0 - d / 3.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _get_tier_particle_color(tier: int) -> Color:
	match tier:
		1: return Color(0.47, 0.87, 0.24)
		2: return Color(0.12, 0.56, 1.00)
		3: return Color(0.72, 0.20, 1.00)
		4: return Color(1.00, 0.65, 0.10)
		5: return Color(1.00, 0.10, 0.80)
		_: return Color.WHITE

# Couleur d'accent de la séquence : dorée pour l'éclosion, sinon couleur du palier cible.
func _accent_color() -> Color:
	if _params.get("eclosion", false):
		return ECLOSION_COLOR
	return UIColors.tier_color(_params.get("to_tier", 1) as int)

# ─── Sons (streams fournis par AudioManager) ─────────────────
# Players locaux conservés : le rituel pilote finement le drone (pitch tweené
# pendant la montée) et déclenche le crystal au flash. Seuls les STREAMS sont
# mutualisés via AudioManager (bus « SFX »).

func _build_sounds() -> void:
	_drone = AudioStreamPlayer.new()
	_drone.volume_db   = -8.0
	_drone.pitch_scale = 0.7
	_drone.bus         = AudioManager.SFX_BUS
	_drone.stream      = AudioManager.stream("ritual_drone")
	add_child(_drone)

	_crystal = AudioStreamPlayer.new()
	_crystal.volume_db = -4.0
	_crystal.bus       = AudioManager.SFX_BUS
	_crystal.stream    = AudioManager.stream("ritual_crystal")
	add_child(_crystal)

# ═══════════════════════════════════════════════════════════
#  Séquence
# ═══════════════════════════════════════════════════════════

func _run_sequence() -> void:
	# Phase 2 — carte apparaît (0.5 s)
	_phase2_card_appear()
	await get_tree().create_timer(0.5).timeout

	# Phase 3 — montée rituelle (2.0 s)
	_phase3_ascension_start()
	await get_tree().create_timer(2.0).timeout

	# Phase 4 — flash + texte haut (élastique 0.3 s) + pause (0.25 s) + descente (0.4 s)
	#            → total ~1.0 s avant que la carte soit prête à remonter
	_phase4_revelation()
	await get_tree().create_timer(1.0).timeout

	if _skip_triggered: return

	# Phase 5 — carte remonte (0.4 s) + texte bonus surgit (délai 0.35 s + fade 0.3 s)
	#            → attendre 0.75 s avant d'activer le skip
	_phase5_celebration()
	await get_tree().create_timer(0.75).timeout

	if _skip_triggered: return

	# Célébration stable — bouton visible, skip autorisé
	_can_skip = true
	_show_return_button()

# ─── Phase 2 : fade in + scale in ───────────────────────────
func _phase2_card_appear() -> void:
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.5)
	tw.tween_property(_card, "scale",      Vector2.ONE, 0.5)

# ─── Phase 3 : 3 battements cardiaques + couleur + drone ────
func _phase3_ascension_start() -> void:
	_particles.emitting = true

	# Les rayons divins s'éveillent pendant la montée rituelle.
	create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE) \
		.tween_property(_rays, "intensity", 0.55, 2.0)

	_drone.play()
	create_tween().set_ease(Tween.EASE_IN_OUT) \
		.tween_property(_drone, "pitch_scale", 1.8, 2.0)

	# Pulse fluide × 2 : montée et descente organiques (1.0 s/cycle × 2 = 2 s)
	var pulse := create_tween()
	pulse.set_loops(2)
	pulse.tween_property(_card, "scale", Vector2(1.20, 1.20), 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_card, "scale", Vector2.ONE, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Transition de couleur de la carte (from_tier → to_tier)
	var from_color := UIColors.tier_color(_params.get("from_tier", 0) as int)
	var to_color   := UIColors.tier_color(_params.get("to_tier",   1) as int)
	if _params.get("eclosion", false):
		from_color = Color(0.15, 0.15, 0.20)  # ténèbres avant la naissance
		to_color   = ECLOSION_COLOR
	create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE) \
		.tween_method(_update_card_color.bind(from_color, to_color), 0.0, 1.0, 2.0)

func _update_card_color(progress: float, from_c: Color, to_c: Color) -> void:
	var c := from_c.lerp(to_c, progress)
	_card_style.border_color = Color(c.r, c.g, c.b, 0.80)
	_tier_chip_style.bg_color     = Color(c.r, c.g, c.b, 0.16)
	_tier_chip_style.border_color = Color(c.r, c.g, c.b, 0.85)
	_rays.color = c
	if is_instance_valid(_icon_lbl):
		_icon_lbl.add_theme_color_override("font_color", c.lightened(0.25))
	if is_instance_valid(_card):
		_card.queue_redraw()

# ─── Phase 4 : flash + texte descend dans la carte ──────────
func _phase4_revelation() -> void:
	_flash.modulate.a = 1.0
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.2)
	_crystal.play()

	# Onde de choc + pic d'intensité des rayons, puis ils se posent.
	_rays.fire_shockwave()
	_title_fx.fire_burst()
	var rays_tw := create_tween()
	rays_tw.tween_property(_rays, "intensity", 1.0, 0.15).set_ease(Tween.EASE_OUT)
	rays_tw.tween_property(_rays, "intensity", 0.50, 0.80) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Grand texte palier : apparaît en deux temps élastiques, puis descend dans la carte
	_tier_label.modulate.a = 1.0
	_tier_label.scale      = Vector2(0.5, 0.5)
	var appear_tw := create_tween()
	appear_tw.tween_property(_tier_label, "scale", Vector2(1.2, 1.2), 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	appear_tw.tween_property(_tier_label, "scale", Vector2.ONE, 0.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	appear_tw.tween_interval(0.25)  # pause visible en haut avant la descente
	# Éclosion : naissance (pas une montée de palier) → pas de morph dans la carte.
	if not _params.get("eclosion", false):
		appear_tw.tween_callback(_start_tier_descent)

func _start_tier_descent() -> void:
	if not is_instance_valid(_from_tier_lbl): return
	if not is_instance_valid(_tier_label):    return

	# Capturer les positions écran AVANT tout changement d'ancre
	var tier_rect := _tier_label.get_global_rect()
	var from_rect := _from_tier_lbl.get_global_rect()

	# Créer un clone du grand texte en positionnement absolu (anchor 0,0)
	var clone := Label.new()
	clone.text                 = _tier_label.text
	clone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clone.add_theme_font_size_override("font_size", 64)
	clone.add_theme_color_override("font_color", _accent_color().lightened(0.35))
	clone.add_theme_constant_override("outline_size", 8)
	clone.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	clone.anchor_left   = 0.0; clone.anchor_right  = 0.0
	clone.anchor_top    = 0.0; clone.anchor_bottom = 0.0
	clone.position      = tier_rect.position
	clone.size          = tier_rect.size
	clone.pivot_offset  = tier_rect.size * 0.5
	clone.z_index       = 100
	add_child(clone)

	# Masquer l'original (le clone s'en charge)
	_tier_label.modulate.a = 0.0

	# Calculer la position cible : le pivot_offset (centre du clone) doit atterrir sur from_center
	var scale_target := 13.0 / 64.0
	var from_center  := from_rect.get_center()
	var target_pos   := from_center - tier_rect.size * 0.5  # pivot_offset = size/2

	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(clone, "position", target_pos, 0.4)
	tw.tween_property(clone, "scale",    Vector2(scale_target, scale_target), 0.4)
	tw.tween_property(_from_tier_lbl, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		clone.queue_free()
		_finish_tier_replacement()
	)

func _finish_tier_replacement() -> void:
	if not is_instance_valid(_from_tier_lbl): return
	var to_tier  := _params.get("to_tier", 1) as int
	var to_color := UIColors.tier_color(to_tier)
	_from_tier_lbl.text = GameData.get_tier_name(to_tier).to_upper()
	_from_tier_lbl.add_theme_color_override("font_color", to_color.lightened(0.20))
	create_tween().tween_property(_from_tier_lbl, "modulate:a", 1.0, 0.15)
	_reveal_new_name(to_tier, to_color)

# Nom d'affichage de l'entité au palier donné (fallback : nom passé en
# paramètre du rituel — éclosion, équipement forgé, outils de test).
func _entity_name_at(tier: int) -> String:
	var entity := GameData.get_entity(_params.get("entity_id", "") as String)
	var fallback := _params.get("entity_name", "?") as String
	if entity.is_empty():
		return fallback
	return Translations.entity_name_at(entity, tier, fallback)

# Si l'entité change de nom au nouveau palier : flash + pop du nom, teinté
# un instant à la couleur du palier — la créature « devient » autre chose.
func _reveal_new_name(to_tier: int, to_color: Color) -> void:
	if not is_instance_valid(_name_lbl):
		return
	var new_name := _entity_name_at(to_tier).to_upper()
	if new_name == _name_lbl.text:
		return
	var tw := create_tween()
	tw.tween_property(_name_lbl, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_name_lbl.text = new_name
		_name_lbl.pivot_offset = _name_lbl.size * 0.5
		_name_lbl.scale = Vector2(1.35, 1.35)
		_name_lbl.add_theme_color_override("font_color", to_color.lightened(0.35))
	)
	tw.set_parallel(true)
	tw.tween_property(_name_lbl, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_OUT)
	tw.tween_property(_name_lbl, "scale", Vector2.ONE, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_interval(0.45)
	tw.chain().tween_callback(func() -> void:
		_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	)

# ─── Phase 5 : carte remonte au tiers supérieur + texte bonus surgit ────────
func _phase5_celebration() -> void:
	# Éclosion : le grand mot « ÉCLOSION » disparaît en fondu (pas de morph dans la carte).
	if _params.get("eclosion", false) and is_instance_valid(_tier_label):
		create_tween().tween_property(_tier_label, "modulate:a", 0.0, 0.3)

	# Carte glisse vers le tiers supérieur avec effet élastique d'arrivée ;
	# le foyer des rayons la suit.
	var slide := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	slide.set_parallel(true)
	slide.tween_property(_card, "offset_top",    -235.0, 0.4)
	slide.tween_property(_card, "offset_bottom",  -45.0, 0.4)
	slide.tween_property(_rays, "center_offset", Vector2(0.0, -140.0), 0.4)
	slide.tween_property(_rays, "intensity", 0.35, 0.6)

	# Panneau cadre sous la carte : lignes de stats animées (avant + gain →
	# après) puis texte des débloquages. Hauteur libre (grandit vers le bas).
	var stat_rows  := _stat_pairs()
	var bonus_text := _get_evolution_text(not stat_rows.is_empty())
	if not (stat_rows.is_empty() and bonus_text.is_empty()):
		var to_color := _accent_color()

		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color     = Color(0.05, 0.06, 0.10, 0.92)
		panel_style.border_color = Color(to_color.r, to_color.g, to_color.b, 0.55)
		panel_style.set_border_width_all(1)
		panel_style.set_corner_radius_all(10)
		panel_style.shadow_color = Color(0, 0, 0, 0.45)
		panel_style.shadow_size  = 14

		var bonus_panel := PanelContainer.new()
		bonus_panel.add_theme_stylebox_override("panel", panel_style)
		bonus_panel.anchor_left   = 0.5; bonus_panel.anchor_right  = 0.5
		bonus_panel.anchor_top    = 0.5; bonus_panel.anchor_bottom = 0.5
		bonus_panel.offset_left   = -250.0; bonus_panel.offset_right = 250.0
		bonus_panel.offset_top    =   80.0; bonus_panel.offset_bottom = 80.0  # surgit : 80→70
		bonus_panel.grow_vertical = Control.GROW_DIRECTION_END  # hauteur = contenu
		bonus_panel.modulate.a    = 0.0
		bonus_panel.z_index       = 50

		var inner_margin := UIHelpers.margin_of(14)
		bonus_panel.add_child(inner_margin)

		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 6)
		inner_margin.add_child(content)

		var built_rows: Array = []
		for data: Dictionary in stat_rows:
			var r := _build_stat_row(data)
			content.add_child(r["row"] as Control)
			built_rows.append(r)

		if not bonus_text.is_empty():
			var bonus := Label.new()
			bonus.text                 = bonus_text
			bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bonus.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
			bonus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# C4 : le texte s'écoule sur TOUTE la largeur du panneau (500 − 2×14 de
			# marge), pour qu'autowrap ne coupe pas les phrases sur une largeur réduite.
			bonus.custom_minimum_size  = Vector2(472.0, 0.0)
			bonus.add_theme_font_size_override("font_size", 17)
			bonus.add_theme_color_override("font_color", Color.WHITE)
			bonus.add_theme_constant_override("outline_size", 3)
			bonus.add_theme_constant_override("line_spacing", 6)
			bonus.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			content.add_child(bonus)
		add_child(bonus_panel)

		# Fade in + légère remontée simultanés, après délai de 0.35 s
		var bonus_tw := create_tween().set_parallel(true)
		bonus_tw.tween_property(bonus_panel, "modulate:a", 1.0, 0.3).set_delay(0.35)
		bonus_tw.tween_property(bonus_panel, "offset_top", 70.0, 0.3) \
			.set_delay(0.35).set_ease(Tween.EASE_OUT)

		# Puis les gains se déversent dans les valeurs, ligne après ligne.
		for i in built_rows.size():
			_animate_stat_row(built_rows[i] as Dictionary, 0.85 + 0.45 * float(i))

# Retourne le texte explicatif du passage au nouveau palier, selon l'entité
# et le tier cible. has_stat_rows = des lignes de stats animées sont déjà
# affichées au-dessus → pas de texte générique de remplissage.
func _get_evolution_text(has_stat_rows: bool = false) -> String:
	var entity_type := _params.get("entity_type", "") as String
	var entity_id   := _params.get("entity_id", "")   as String
	var from_tier   := _params.get("from_tier", 0)     as int
	var to_tier     := _params.get("to_tier", 1)       as int

	# Éclosion du Village (phase préliminaire) → ouverture des expéditions.
	if _params.get("eclosion", false):
		return Translations.T("ritual.eclosion_text")

	# Village — jalons du hub par palier du héros (gates décalés d'un rang).
	if entity_type == Enums.EntityType.VILLAGE:
		if to_tier in [2, 3, 4]:
			return Translations.T("ritual.village." + str(to_tier))
		return Translations.T("ritual.village.default")

	# Entités génériques — lire tier_effects + passifs_par_palier
	var entity := GameData.get_entity(entity_id)
	if entity.is_empty(): return ""

	var lines: Array[String] = []

	# Biome — liste ce que CE palier vient de débloquer (Fragment, mécanique,
	# zone, équipement, biome secondaire), mêmes clés que le panneau Expéditions.
	if entity_type == Enums.EntityType.BIOME:
		lines.append_array(_biome_unlock_lines(entity_id, entity, to_tier))

	# Effets de passifs : rappel de l'ancien effet → nouvel effet.
	var te_list: Array = entity.get("tier_effects", [])
	if to_tier < te_list.size():
		var prev_effects: Array = []
		if from_tier < te_list.size():
			prev_effects = te_list[from_tier].get("effects", []) as Array
		var effects: Array = te_list[to_tier].get("effects", [])
		for i in effects.size():
			var desc := Translations.effect_desc(effects[i] as Dictionary)
			if desc.is_empty():
				continue
			var line := "✦ " + desc
			if i < prev_effects.size():
				var old := Translations.effect_desc(prev_effects[i] as Dictionary)
				if not old.is_empty() and old != desc:
					line = "✦ %s  →  %s" % [old, desc]
			lines.append(line)

	var passifs := entity.get("passifs_par_palier", {}) as Dictionary
	if passifs.has(to_tier):
		var pid   := str(passifs[to_tier])
		var pdata := GameData.get_entity(pid)
		var pname := Translations.entity_name(pdata, pid)
		lines.append(Translations.T("ritual.passive_unlocked") % pname)

	if lines.is_empty():
		return "" if has_stat_rows else Translations.T("ritual.new_tier")
	return "\n".join(lines)

# Ce que le passage du biome au palier t vient de débloquer — mêmes règles
# (Balance/BiomeMechanics) et mêmes clés que « Prochain palier » du panneau
# Expéditions. Le Fragment n'est cité que s'il vient VRAIMENT d'être libéré.
func _biome_unlock_lines(biome_id: String, biome: Dictionary, t: int) -> Array[String]:
	var out: Array[String] = []
	if t == Balance.EQUIPMENT_UNLOCK_BIOME_TIER:
		out.append("✦ " + Translations.T("adv.next.equipment"))
	if GameData.last_freed_fragment_biome == biome_id:
		GameData.last_freed_fragment_biome = ""
		out.append("✦ " + Translations.T("adv.next.fragment"))
	var mech_id := biome.get("mecanique_forte_id", "") as String
	if t == BiomeMechanics.UNLOCK_TIER and mech_id != "":
		out.append("✦ " + Translations.T("adv.next.mechanic") % Translations.mech_name(mech_id))
	if Balance.max_unlocked_zone(t) > Balance.max_unlocked_zone(t - 1):
		out.append("✦ " + Translations.T("adv.next.zone") % Translations.zone_name(Balance.max_unlocked_zone(t)))
	if t == Balance.SECONDARY_BIOME_REVEAL_TIER and str(biome.get("biome_secondaire_id", "")) != "":
		out.append("✦ " + Translations.T("adv.next.secondary"))
	return out

# ─── Stats avant / après évolution ───────────────────────────

# Paires de stats avant/après pour les types qui en ont (héros, créature,
# équipement). L'entité est DÉJÀ au nouveau palier quand le rituel démarre :
# les valeurs « avant » sont relues dans les tables, pas dans l'état vivant.
func _stat_pairs() -> Array:
	var entity_type := _params.get("entity_type", "") as String
	var entity_id   := _params.get("entity_id", "")   as String
	var from_tier   := _params.get("from_tier", 0)    as int
	var to_tier     := _params.get("to_tier", 1)      as int
	var entity      := GameData.get_entity(entity_id)

	var before: Dictionary = {}
	var after:  Dictionary = {}
	match entity_type:
		Enums.EntityType.HERO:
			var f := clampi(from_tier, 0, Balance.HERO_HP_PER_TIER.size() - 1)
			var t := clampi(to_tier,   0, Balance.HERO_HP_PER_TIER.size() - 1)
			before = {"hp": Balance.HERO_HP_PER_TIER[f], "atk": Balance.HERO_ATK_PER_TIER[f], "def": Balance.HERO_DEF_PER_TIER[f]}
			after  = {"hp": Balance.HERO_HP_PER_TIER[t], "atk": Balance.HERO_ATK_PER_TIER[t], "def": Balance.HERO_DEF_PER_TIER[t]}
		Enums.EntityType.CREATURE:
			if entity.is_empty(): return []
			before = GameData.stats_at_tier(entity, from_tier)
			after  = GameData.stats_at_tier(entity, to_tier)
		Enums.EntityType.EQUIPMENT:
			if entity.is_empty(): return []
			var spp := entity.get("stats_par_palier", {}) as Dictionary
			before = spp.get(from_tier, {}) as Dictionary
			after  = spp.get(to_tier,   {}) as Dictionary
		_:
			return []

	# [clé stat, libellé, couleur, suffixe d'affichage]
	var defs: Array = [
		["hp",  Translations.T("hero.stat.hp"),  UIColors.STAT_HP,   ""],
		["atk", Translations.T("hero.stat.atk"), UIColors.STAT_ATK,  ""],
		["def", Translations.T("hero.stat.def"), UIColors.STAT_DEF,  ""],
		["vit", Translations.T("hero.stat.vit"), UIColors.FILTER_ON, ""],
		["attack_speed_pct", Translations.T("hero.stat.vit"), UIColors.FILTER_ON, " %"],
	]
	var rows: Array = []
	for d: Array in defs:
		var b := int(before.get(d[0], 0))
		var a := int(after.get(d[0], 0))
		if a > b:
			rows.append({"label": d[1], "color": d[2], "before": b, "after": a, "suffix": d[3]})
	return rows

# Ligne « ATK   10   +4 » — valeur et bonus animés ensuite par _animate_stat_row.
func _build_stat_row(data: Dictionary) -> Dictionary:
	var color := data["color"] as Color
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var name_lbl := Label.new()
	name_lbl.text = str(data["label"])
	name_lbl.custom_minimum_size  = Vector2(70.0, 0.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", color)
	row.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.text = str(int(data["before"])) + str(data["suffix"])
	value_lbl.custom_minimum_size  = Vector2(76.0, 0.0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.add_theme_font_size_override("font_size", 22)
	value_lbl.add_theme_color_override("font_color", Color.WHITE)
	value_lbl.add_theme_constant_override("outline_size", 3)
	value_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	row.add_child(value_lbl)

	var bonus_lbl := Label.new()
	bonus_lbl.text = "+%d%s" % [int(data["after"]) - int(data["before"]), data["suffix"]]
	bonus_lbl.custom_minimum_size = Vector2(70.0, 0.0)
	bonus_lbl.add_theme_font_size_override("font_size", 17)
	bonus_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
	row.add_child(bonus_lbl)

	return {"row": row, "value": value_lbl, "bonus": bonus_lbl,
			"before": int(data["before"]), "after": int(data["after"]),
			"suffix": str(data["suffix"])}

# Le gain se déverse dans la valeur : « 10  +4 » → « 11  +3 » → … → « 14 ».
# Pop discret à chaque tick, puis flash vert de la valeur finale.
func _animate_stat_row(r: Dictionary, delay: float) -> void:
	var value_lbl := r["value"] as Label
	var bonus_lbl := r["bonus"] as Label
	var before: int = r["before"]
	var after:  int = r["after"]
	var suffix: String = r["suffix"]
	var gain := after - before
	var dur  := clampf(0.12 * float(gain), 0.5, 1.2)
	var last: Array = [before]   # mutable partagé avec la lambda

	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void:
		var cur := int(floor(v))
		if cur == last[0]:
			return
		last[0] = cur
		value_lbl.text = str(cur) + suffix
		var left := after - cur
		bonus_lbl.text = ("+%d%s" % [left, suffix]) if left > 0 else ""
		value_lbl.pivot_offset = value_lbl.size * 0.5
		value_lbl.scale = Vector2(1.22, 1.22)
		value_lbl.create_tween().tween_property(value_lbl, "scale", Vector2.ONE, 0.10)
	, float(before), float(after), dur).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		value_lbl.text = str(after) + suffix
		bonus_lbl.text = ""
		value_lbl.add_theme_color_override("font_color", UIColors.TEXT_BONUS)
	)
	tw.tween_interval(0.30)
	tw.tween_callback(func() -> void:
		value_lbl.add_theme_color_override("font_color", Color.WHITE)
	)

# ─── Bouton retour village ───────────────────────────────────
func _show_return_button() -> void:
	var to_color := _accent_color()

	var btn := Button.new()
	btn.text = Translations.T("cycle.back_village")
	btn.add_theme_stylebox_override("normal",   UIHelpers.card_style(to_color, 0.10, 0.70, 1, 8))
	btn.add_theme_stylebox_override("hover",    UIHelpers.card_style(to_color, 0.22, 1.00, 1, 8))
	btn.add_theme_stylebox_override("pressed",  UIHelpers.card_style(to_color, 0.40, 1.00, 1, 8))
	btn.add_theme_stylebox_override("focus",    UIHelpers.card_style(to_color, 0.10, 0.70, 1, 8))
	btn.add_theme_color_override("font_color", to_color.lightened(0.25))
	btn.add_theme_color_override("font_hover_color", to_color.lightened(0.50))
	btn.add_theme_font_size_override("font_size", 16)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.anchor_left   = 0.5; btn.anchor_right  = 0.5
	btn.anchor_top    = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left   = -160.0; btn.offset_right  = 160.0
	btn.offset_top    = -72.0;  btn.offset_bottom = -26.0
	btn.pivot_offset  = Vector2(160.0, 23.0)
	btn.modulate.a    = 0.0
	btn.z_index       = 60
	add_child(btn)

	btn.mouse_entered.connect(func() -> void:
		var tw := btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.12)
	)
	btn.mouse_exited.connect(func() -> void:
		var tw := btn.create_tween().set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.10)
	)
	btn.pressed.connect(func() -> void:
		var tw := btn.create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(btn, "scale", Vector2(0.90, 0.90), 0.07)
		tw.tween_callback(_phase6_return)
	)

	create_tween().tween_property(btn, "modulate:a", 1.0, 0.4)

# ─── Phase 6 : fondu noir + changement de scène ─────────────
func _phase6_return() -> void:
	if _returning: return
	_returning = true

	_particles.emitting = false

	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.modulate.a = 0.0
	overlay.z_index    = 400
	add_child(overlay)

	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(VILLAGE_SCENE)
	)

# ═══════════════════════════════════════════════════════════
#  Input — skip
# ═══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not _can_skip or _returning:
		return
	if event is InputEventKey \
			and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SPACE or kc == KEY_ESCAPE or kc == KEY_ENTER:
			_skip_triggered = true
			_phase6_return()
