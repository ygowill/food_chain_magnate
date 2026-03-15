extends VBoxContainer

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var tile_preview: Control = $TilePreview
@onready var pick_button: Button = $ButtonsRow/PickButton
@onready var rotate_left_button: Button = $ButtonsRow/RotateLeftButton
@onready var rotation_value_label: Label = $ButtonsRow/RotationValueLabel
@onready var rotate_right_button: Button = $ButtonsRow/RotateRightButton

var _overlay: Node = null

func _ready() -> void:
	if is_instance_valid(pick_button):
		UiStylesClass.apply_button_secondary(pick_button)
	if is_instance_valid(rotate_left_button):
		UiStylesClass.apply_button_secondary(rotate_left_button)
	if is_instance_valid(rotate_right_button):
		UiStylesClass.apply_button_secondary(rotate_right_button)
	if is_instance_valid(rotation_value_label):
		UiStylesClass.apply_label_dark(rotation_value_label)

func bind_overlay(overlay: Node) -> void:
	_overlay = overlay

	if is_instance_valid(pick_button) and not pick_button.pressed.is_connected(_on_pick_pressed):
		pick_button.pressed.connect(_on_pick_pressed)
	if is_instance_valid(rotate_left_button) and not rotate_left_button.pressed.is_connected(_on_rotate_left_pressed):
		rotate_left_button.pressed.connect(_on_rotate_left_pressed)
	if is_instance_valid(rotate_right_button) and not rotate_right_button.pressed.is_connected(_on_rotate_right_pressed):
		rotate_right_button.pressed.connect(_on_rotate_right_pressed)

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

	if is_instance_valid(rotation_value_label):
		rotation_value_label.text = "%d度" % rot
	if is_instance_valid(rotate_left_button):
		rotate_left_button.disabled = tile_id.is_empty()
	if is_instance_valid(rotate_right_button):
		rotate_right_button.disabled = tile_id.is_empty()

func _on_pick_pressed() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.has_method("show_picker"):
		_overlay.call("show_picker")

func _on_rotate_left_pressed() -> void:
	_rotate(-90)

func _on_rotate_right_pressed() -> void:
	_rotate(90)

func _rotate(delta_degrees: int) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.has_method("set_selected_rotation"):
		var rot := 0
		if _overlay.has_method("get_selected_rotation"):
			rot = int(_overlay.call("get_selected_rotation"))
		_overlay.call("set_selected_rotation", rot + int(delta_degrees))
		return

	if delta_degrees > 0 and _overlay.has_method("rotate_clockwise"):
		_overlay.call("rotate_clockwise")
