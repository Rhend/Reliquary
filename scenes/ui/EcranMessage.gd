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
var accent := Color(0.85, 0.88, 0.95)

var _confirme_emis := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # modal : rien ne passe dessous

	var fond := ColorRect.new()
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.color = Color(0.0, 0.0, 0.0, 0.96)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fond)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.add_theme_constant_override("separation", 24)
	vb.resized.connect(func() -> void:
		vb.position = (size - vb.size) * 0.5)
	add_child(vb)

	var lbl := UIHelpers.label(message, 26, accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)

	var invite := UIHelpers.label(Translations.T("ctb.continuer"), 12, UIColors.TEXT_MUTED)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(invite)

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
