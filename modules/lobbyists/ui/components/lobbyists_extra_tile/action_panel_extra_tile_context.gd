extends VBoxContainer

@onready var tile_preview: Control = $TilePreview
@onready var pick_button: Button = $ButtonsRow/PickButton
@onready var rotate_button: Button = $ButtonsRow/RotateButton

var _overlay: Node = null

func bind_overlay(overlay: Node) -> void:
	_overlay = overlay

	if is_instance_valid(pick_button) and not pick_button.pressed.is_connected(_on_pick_pressed):
		pick_button.pressed.connect(_on_pick_pressed)
	if is_instance_valid(rotate_button) and not rotate_button.pressed.is_connected(_on_rotate_pressed):
		rotate_button.pressed.connect(_on_rotate_pressed)

	sync_from_overlay()

func sync_from_overlay() -> void:
	var tile_id := ""
	var rot := 0

	if _overlay != null and is_instance_valid(_overlay):
		if _overlay.has_method("get_selected_tile_id"):
			tile_id = str(_overlay.call("get_selected_tile_id")).strip_edges()
		if _overlay.has_method("get_selected_rotation"):
			rot = int(_overlay.call("get_selected_rotation"))

	if is_instance_valid(tile_preview) and tile_preview.has_method("set_tile"):
		tile_preview.call("set_tile", tile_id, rot)

	if is_instance_valid(pick_button):
		pick_button.text = "重新选择板块" if not tile_id.is_empty() else "选择板块"

	if is_instance_valid(rotate_button):
		rotate_button.text = "旋转 ↻ %d°" % rot
		rotate_button.disabled = tile_id.is_empty()

func _on_pick_pressed() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.has_method("show_picker"):
		_overlay.call("show_picker")

func _on_rotate_pressed() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.has_method("rotate_clockwise"):
		_overlay.call("rotate_clockwise")
