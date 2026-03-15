class_name UiPointerInput
extends RefCounted

static func is_primary_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		return e.button_index == MOUSE_BUTTON_LEFT and e.pressed
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		return t.pressed
	return false

static func is_primary_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		return e.button_index == MOUSE_BUTTON_LEFT and not e.pressed
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		return not t.pressed
	return false

static func is_primary_double_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		return e.button_index == MOUSE_BUTTON_LEFT and e.pressed and e.double_click
	return false

static func get_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	return Vector2.ZERO
