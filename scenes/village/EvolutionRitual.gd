# ============================================================
# EvolutionRitual.gd — Séquence cinématique d'ascension de palier.
#
# Lit GameData.pending_evolution au démarrage puis joue :
#   Phase 2 (0.5s)  : carte apparaît (fade + scale in)
#   Phase 3 (2.0s)  : 3 battements cardiaques + couleur + drone
#   Phase 4 (0.7s)  : flash + gros texte tombe remplacer l'ancien
#   Phase 5 (1.5s)  : carte monte + texte bonus apparaît en dessous
#   Phase 6 (0.3s)  : fondu noir → retour Village
#
# Skipable dès la Phase 4 (clic, Espace, Échap, Entrée).
# ============================================================
extends Control

const VILLAGE_SCENE := "res://scenes/village/village.tscn"

# ─── Nœuds UI ────────────────────────────────────────────────
var _card:           Control           = null
var _card_style:     StyleBoxFlat      = null
var _from_tier_lbl:  Label             = null   # label tier à l'intérieur de la carte
var _tier_label:     Label             = null   # grand texte palier (en haut)
var _flash:          ColorRect         = null
var _particles:      CPUParticles2D    = null
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
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

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

func _build_entity_card() -> void:
	var from_tier  := _params.get("from_tier", 0) as int
	var from_color := UIColors.tier_color(from_tier)

	_card_style = StyleBoxFlat.new()
	_card_style.bg_color      = Color(from_color.r, from_color.g, from_color.b, 0.12)
	_card_style.border_color  = Color(from_color.r, from_color.g, from_color.b, 0.80)
	_card_style.border_width_left  = 3
	_card_style.border_width_right = 3
	_card_style.border_width_top   = 3
	_card_style.border_width_bottom = 3
	_card_style.corner_radius_top_left     = 10
	_card_style.corner_radius_top_right    = 10
	_card_style.corner_radius_bottom_left  = 10
	_card_style.corner_radius_bottom_right = 10

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 140)
	card.add_theme_stylebox_override("panel", _card_style)
	card.anchor_left  = 0.5; card.anchor_right  = 0.5
	card.anchor_top   = 0.5; card.anchor_bottom = 0.5
	card.offset_left  = -140.0; card.offset_right  = 140.0
	card.offset_top   = -70.0;  card.offset_bottom = 70.0
	card.pivot_offset = Vector2(140, 70)
	card.modulate.a   = 0.0
	card.scale        = Vector2(0.8, 0.8)

	var margin := UIHelpers.margin_of(16)
	card.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)

	var entity_name := (_params.get("entity_name", "Entité") as String).to_upper()
	var name_lbl := Label.new()
	name_lbl.text = entity_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(name_lbl)

	_from_tier_lbl = Label.new()
	_from_tier_lbl.text = GameData.get_tier_name(from_tier).to_upper()
	_from_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_from_tier_lbl.add_theme_font_size_override("font_size", 13)
	_from_tier_lbl.add_theme_color_override("font_color", from_color)
	vb.add_child(_from_tier_lbl)

	add_child(card)
	_card = card

func _build_tier_label() -> void:
	var to_tier := _params.get("to_tier", 1) as int

	_tier_label = Label.new()
	_tier_label.text                 = GameData.get_tier_name(to_tier).to_upper()
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_font_size_override("font_size", 56)
	_tier_label.add_theme_color_override("font_color", Color.WHITE)
	_tier_label.add_theme_constant_override("font_size", 56)
	_tier_label.add_theme_constant_override("outline_size", 5)
	_tier_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	# Centré horizontalement, 80 px au-dessus de la carte
	_tier_label.anchor_left   = 0.5; _tier_label.anchor_right  = 0.5
	_tier_label.anchor_top    = 0.5; _tier_label.anchor_bottom = 0.5
	_tier_label.offset_left   = -220.0; _tier_label.offset_right  = 220.0
	_tier_label.offset_top    = -215.0; _tier_label.offset_bottom = -155.0
	_tier_label.pivot_offset  = Vector2(220.0, 30.0)
	_tier_label.modulate.a    = 0.0
	_tier_label.scale         = Vector2(0.5, 0.5)
	_tier_label.z_index       = 100
	add_child(_tier_label)

func _build_particles() -> void:
	var vp      := get_viewport_rect().size
	var to_tier := _params.get("to_tier", 1) as int
	var color   := _get_tier_particle_color(to_tier)

	_particles = CPUParticles2D.new()
	_particles.emitting              = false
	_particles.amount                = 60
	_particles.lifetime              = 2.5
	_particles.explosiveness         = 0.0
	_particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(vp.x * 0.5, 5.0)
	_particles.position              = Vector2(vp.x * 0.5, vp.y + 20.0)
	_particles.direction             = Vector2(0.0, -1.0)
	_particles.spread                = 10.0
	_particles.gravity               = Vector2(0.0, -150.0)
	_particles.initial_velocity_min  = 80.0
	_particles.initial_velocity_max  = 120.0
	_particles.scale_amount_min      = 0.4
	_particles.scale_amount_max      = 0.9
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

# ─── Sons générés procéduralement ────────────────────────────

func _build_sounds() -> void:
	_drone = AudioStreamPlayer.new()
	_drone.volume_db   = -8.0
	_drone.pitch_scale = 0.7
	_drone.stream      = _generate_drone_wav()
	add_child(_drone)

	_crystal = AudioStreamPlayer.new()
	_crystal.volume_db = -4.0
	_crystal.stream    = _generate_crystal_wav()
	add_child(_crystal)

func _generate_drone_wav() -> AudioStreamWAV:
	var sr        := 11025
	var frequency := 160.0
	var n_samples := sr * 3
	var data      := PackedByteArray()
	data.resize(n_samples * 2)
	for i: int in n_samples:
		var t        := float(i) / float(sr)
		var envelope := 1.0
		if t < 0.3:   envelope = t / 0.3
		elif t > 2.7: envelope = 1.0 - (t - 2.7) / 0.3
		var v := int(sin(t * frequency * TAU) * 0.35 * 32767.0 * envelope)
		v = clampi(v, -32768, 32767)
		data[i * 2 + 0] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = sr
	wav.data     = data
	return wav

func _generate_crystal_wav() -> AudioStreamWAV:
	var sr        := 11025
	var frequency := 2400.0
	var n_samples := int(sr * 0.6)
	var data      := PackedByteArray()
	data.resize(n_samples * 2)
	for i: int in n_samples:
		var t        := float(i) / float(sr)
		var envelope := exp(-t * 8.0)
		var sample_f := (sin(t * frequency * TAU) * 0.55
					   + sin(t * frequency * 2.01 * TAU) * 0.28
					   + sin(t * frequency * 2.99 * TAU) * 0.12) * envelope
		var v := int(sample_f * 0.55 * 32767.0)
		v = clampi(v, -32768, 32767)
		data[i * 2 + 0] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = sr
	wav.data     = data
	return wav

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

	# Phase 4 — révélation + descente du texte (0.7 s) ; skip activé
	_can_skip = true
	_phase4_revelation()
	await get_tree().create_timer(0.7).timeout

	if _skip_triggered: return

	# Phase 5 — carte monte + bonus (1.5 s)
	_phase5_celebration()
	await get_tree().create_timer(1.5).timeout

	_phase6_return()

# ─── Phase 2 : fade in + scale in ───────────────────────────
func _phase2_card_appear() -> void:
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.5)
	tw.tween_property(_card, "scale",      Vector2.ONE, 0.5)

# ─── Phase 3 : 3 battements cardiaques + couleur + drone ────
func _phase3_ascension_start() -> void:
	_particles.emitting = true

	_drone.play()
	create_tween().set_ease(Tween.EASE_IN_OUT) \
		.tween_property(_drone, "pitch_scale", 1.8, 2.0)

	# Battement cardiaque × 3 : montée rapide, chute, rebond (0.66 s/cycle ≈ 2 s)
	var pulse := create_tween()
	for _i: int in 3:
		pulse.tween_property(_card, "scale", Vector2(1.20, 1.20), 0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		pulse.tween_property(_card, "scale", Vector2(0.94, 0.94), 0.18) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		pulse.tween_property(_card, "scale", Vector2.ONE, 0.36) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# Transition de couleur de la carte (from_tier → to_tier)
	var from_color := UIColors.tier_color(_params.get("from_tier", 0) as int)
	var to_color   := UIColors.tier_color(_params.get("to_tier",   1) as int)
	create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE) \
		.tween_method(_update_card_color.bind(from_color, to_color), 0.0, 1.0, 2.0)

func _update_card_color(progress: float, from_c: Color, to_c: Color) -> void:
	var c := from_c.lerp(to_c, progress)
	_card_style.bg_color     = Color(c.r, c.g, c.b, 0.12)
	_card_style.border_color = Color(c.r, c.g, c.b, 0.80)
	if is_instance_valid(_card):
		_card.queue_redraw()

# ─── Phase 4 : flash + texte descend dans la carte ──────────
func _phase4_revelation() -> void:
	_flash.modulate.a = 1.0
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.2)
	_crystal.play()

	# Grand texte palier : apparaît (0.25 s), puis descend dans la carte (0.4 s)
	_tier_label.modulate.a = 1.0
	_tier_label.scale      = Vector2(0.5, 0.5)
	var appear_tw := create_tween()
	appear_tw.tween_property(_tier_label, "scale", Vector2.ONE, 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
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
	clone.add_theme_font_size_override("font_size", 56)
	clone.add_theme_color_override("font_color", Color.WHITE)
	clone.add_theme_constant_override("outline_size", 5)
	clone.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	clone.anchor_left   = 0.0; clone.anchor_right  = 0.0
	clone.anchor_top    = 0.0; clone.anchor_bottom = 0.0
	clone.position      = tier_rect.position
	clone.size          = tier_rect.size
	clone.pivot_offset  = tier_rect.size * 0.5
	clone.z_index       = 100
	add_child(clone)

	# Masquer l'original (le clone s'en charge)
	_tier_label.modulate.a = 0.0

	# Calculer la position cible : centré sur from_lbl
	var scale_target := 13.0 / 56.0
	var from_center  := from_rect.get_center()
	var scaled_size  := tier_rect.size * scale_target
	var target_pos   := from_center - scaled_size * 0.5

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
	_from_tier_lbl.add_theme_color_override("font_color", to_color)
	create_tween().tween_property(_from_tier_lbl, "modulate:a", 1.0, 0.15)

# ─── Phase 5 : carte monte + texte bonus ────────────────────
func _phase5_celebration() -> void:
	# Carte glisse vers le tiers supérieur de l'écran
	var slide := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	slide.set_parallel(true)
	slide.tween_property(_card, "offset_top",    -210.0, 0.5)
	slide.tween_property(_card, "offset_bottom",  -70.0, 0.5)

	# Texte bonus en dessous (après 0.35 s)
	var bonus_text := _get_evolution_text()
	if not bonus_text.is_empty():
		var to_tier  := _params.get("to_tier", 1) as int
		var to_color := UIColors.tier_color(to_tier)

		var bonus := Label.new()
		bonus.text                 = bonus_text
		bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bonus.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		bonus.add_theme_font_size_override("font_size", 15)
		bonus.add_theme_color_override("font_color", to_color.lerp(Color.WHITE, 0.4))
		bonus.add_theme_constant_override("outline_size", 3)
		bonus.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		bonus.anchor_left   = 0.5; bonus.anchor_right  = 0.5
		bonus.anchor_top    = 0.5; bonus.anchor_bottom = 0.5
		bonus.offset_left   = -230.0; bonus.offset_right  = 230.0
		bonus.offset_top    = -20.0;  bonus.offset_bottom = 80.0
		bonus.modulate.a    = 0.0
		bonus.z_index       = 50
		add_child(bonus)

		var bonus_tw := create_tween()
		bonus_tw.tween_interval(0.35)
		bonus_tw.tween_property(bonus, "modulate:a", 1.0, 0.4)

# Retourne le texte explicatif du passage au nouveau palier,
# selon l'entité et le tier cible.
func _get_evolution_text() -> String:
	var entity_type := _params.get("entity_type", "") as String
	var entity_id   := _params.get("entity_id", "")   as String
	var to_tier     := _params.get("to_tier", 1)       as int

	# Village / Héro — textes figés par tier
	if entity_id == "hero" or entity_type == "hero":
		match to_tier:
			1: return "Vous pouvez maintenant\npartir en expédition !"
			2: return "La Forge est déverrouillée !"
			3: return "Le Sanctuaire est accessible !"
			4: return "La Relique est accessible !"
			5: return "Le mystère ultime s'ouvre…"
			_: return ""

	# Entités génériques — lire tier_effects + passive_slots
	var entity := GameData.get_entity(entity_id)
	if entity.is_empty(): return ""

	var lines: Array[String] = []

	var te_list: Array = entity.get("tier_effects", [])
	if to_tier < te_list.size():
		for eff: Dictionary in te_list[to_tier].get("effects", []):
			var desc := eff.get("description", "") as String
			if not desc.is_empty():
				lines.append("• " + desc)

	for slot: Dictionary in entity.get("passive_slots", []):
		if slot.get("unlock_tier", -1) == to_tier:
			var pid   := slot.get("passive_id", "") as String
			var pdata := GameData.get_entity(pid)
			var pname := pdata.get("name", pid) as String
			lines.append("Passif débloqué : " + pname)

	return "\n".join(lines)

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

	var do_skip := false
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed:
		do_skip = true
	elif event is InputEventKey \
			and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SPACE or kc == KEY_ESCAPE or kc == KEY_ENTER:
			do_skip = true

	if do_skip:
		_skip_triggered = true
		_phase6_return()
