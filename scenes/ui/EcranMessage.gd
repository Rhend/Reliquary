# ============================================================
# EcranMessage — Écran de message SOBRE plein écran (chantier 9).
# Placeholder assumé (la DA du Game Over viendra plus tard) : fond noir,
# message centré, invite discrète, un clic (ou Entrée/Espace) → `confirme`
# (une seule fois — l'appelant enchaîne et libère l'écran).
#
# Utilisé par la séquence de Game Over : message 1 « R-004 est détruit... »
# (sur l'écran d'expédition) puis message 2 « Reconstruction de R-005
# complète. » (sur le Village, après rechargement).
# ============================================================
class_name EcranMessage
extends Control

signal confirme

# Définis AVANT add_child par l'appelant.
var message := ""
var accent: Color = UIColors.CYBER_TEXTE

var _confirme_emis := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # modal : rien ne passe dessous

	var fond := ColorRect.new()
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.color = Color(UIColors.CYBER_BG, 0.97)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fond)

	# Cadre fin lumineux autour du message (peau cyberpunk, chantier 10).
	var boite := PanelContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.custom_minimum_size = Vector2(520, 0)
	boite.add_theme_stylebox_override("panel", ExpeStyle.style_panneau(accent, 0.35, 1, 2))
	boite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boite.resized.connect(func() -> void:
		boite.position = (size - boite.size) * 0.5)
	add_child(boite)

	var m := UIHelpers.margin_of(24)
	boite.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	m.add_child(vb)

	# Pas d'autowrap : messages courts (une ligne) — un Label autowrap dans
	# cette chaîne de conteneurs centrés gonfle la hauteur au premier layout.
	var lbl := ExpeStyle.label_mono(message, 26, accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)

	var invite := ExpeStyle.label_mono(Translations.T("ctb.continuer"), 12,
			UIColors.CYBER_TEXTE_MUTED)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(invite)

	ExpeStyle.scanlines(self)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_confirmer()

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo \
			and ev.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_confirmer()

# API publique (clic, clavier, ou piloté par un test) : une seule émission.
func confirmer() -> void:
	_confirmer()

func _confirmer() -> void:
	if _confirme_emis:
		return
	_confirme_emis = true
	confirme.emit()
