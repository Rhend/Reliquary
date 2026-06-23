# ============================================================
# CombatStinger.gd — Bandeau d'événement central (extrait de CombatScene).
#
# Annonce piège / bénédiction de façon impossible à rater : flash plein écran
# teinté + slam-in (scale TRANS_BACK), maintien ~Balance.AFFICHAGE_EVENEMENT,
# puis fondu. Résout « je ne vois jamais les pièges/bénédictions » (sans journal,
# le seul indice était le nom dans la colonne ennemie pendant 2,5 s).
#
# S'appuie sur le host (CombatScene) pour le parentage, les tweens et le
# screen-shake (effet partagé qui reste côté host). Aucune connexion de signal.
# ============================================================
class_name CombatStinger
extends RefCounted

var _host: Control
var _current: Control = null   # bandeau actuel (libéré avant d'en afficher un nouveau)

func _init(host: Control) -> void:
	_host = host

func show(title: String, name_txt: String, detail: String, color: Color, danger: bool) -> void:
	if is_instance_valid(_current):
		_current.queue_free()

	# Flash plein écran teinté (rouge danger / vert bénédiction).
	var flash := ColorRect.new()
	flash.color = Color(color.r, color.g, color.b, 0.18)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 90
	_host.add_child(flash)
	var ftw := _host.create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	ftw.tween_callback(flash.queue_free)

	# Bandeau centré dans le tiers haut de la zone de combat.
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.anchor_bottom = 0.58
	holder.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	holder.z_index       = 95
	_host.add_child(holder)
	_current = holder

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.04, 0.05, 0.09, 0.94)
	ps.border_color = Color(color.r, color.g, color.b, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.shadow_color = Color(color.r, color.g, color.b, 0.35)
	ps.shadow_size  = 16
	panel.add_theme_stylebox_override("panel", ps)
	holder.add_child(panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)

	var kind_lbl := UIHelpers.label(title, 12, color.lightened(0.25))
	kind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(kind_lbl)

	var name_lbl := UIHelpers.label(name_txt.to_upper(), 24, Color.WHITE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	vb.add_child(name_lbl)

	if detail != "":
		var detail_lbl := UIHelpers.label(detail, 17, color.lightened(0.30))
		detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_lbl.add_theme_constant_override("outline_size", 4)
		detail_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		vb.add_child(detail_lbl)

	if danger:
		_host._screen_shake()

	# Slam-in → maintien → fondu de sortie.
	holder.modulate.a = 0.0
	var tw := _host.create_tween()
	tw.tween_callback(func() -> void:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(1.35, 1.35)
	)
	tw.set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# set_parallel(false) : tout ce qui suit redevient séquentiel (chain()
	# ne chaînerait que le tweener suivant, le fondu partirait trop tôt).
	tw.set_parallel(false)
	tw.tween_interval(maxf(Balance.AFFICHAGE_EVENEMENT - 0.3, 0.6))
	tw.tween_property(holder, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)
