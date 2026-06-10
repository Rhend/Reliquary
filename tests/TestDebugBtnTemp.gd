extends Node
# Test TEMPORAIRE : Tier + doit fonctionner par VRAIS clics, plusieurs fois.

func _ready() -> void:
	await get_tree().process_frame
	GameData.village["eclos"] = true
	GameData.village["maitrise_actuelle"] = 0
	var village: Control = load("res://scenes/village/village.tscn").instantiate()
	get_tree().root.add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame

	var plus := _find_button(village, "+")
	for i in 3:
		_click(plus.global_position + plus.size * 0.5)
		await get_tree().process_frame
		await get_tree().process_frame
		print("clic %d → tier = %d" % [i + 1, GameData.village["maitrise_actuelle"]])

	# Le bouton ⚙ doit aussi rester cliquable après les rebuilds.
	var gear := _find_button(village, "⚙")
	_click(gear.global_position + gear.size * 0.5)
	await get_tree().process_frame
	var overlay_open := _find_overlay(village) != null
	print("gear cliquable après rebuilds : ", overlay_open)

	var ok: bool = int(GameData.village["maitrise_actuelle"]) == 3 and overlay_open
	print("RESULTAT: ", "OK" if ok else "ECHEC")
	get_tree().quit(0 if ok else 1)

func _click(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(ev)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found: return found
	return null

func _find_overlay(node: Node) -> SettingsOverlay:
	if node is SettingsOverlay and not node.is_queued_for_deletion():
		return node
	for child in node.get_children():
		var found := _find_overlay(child)
		if found: return found
	return null
