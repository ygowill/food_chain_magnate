# 房屋/花园覆盖层组件
# - place_house: 选择 position + rotation
# - add_garden: 选择 house_id + direction
# 地图选点由 game.gd 通过 MapCanvas 信号回填
class_name HousePlacementOverlay
extends Control

signal house_placement_confirmed(position: Vector2i, rotation: int)
signal garden_confirmed(house_id: String, direction: String)
signal cancelled()

@onready var hint_label: Label = $HintPanel/HintLabel
@onready var bottom_bar: HBoxContainer = $BottomBar
@onready var garden_checkbox: CheckBox = $BottomBar/GardenCheck
@onready var confirm_btn: Button = $BottomBar/ConfirmButton
@onready var cancel_btn: Button = $BottomBar/CancelButton

var _mode: String = "place_house"  # place_house | add_garden
var _selected_position: Vector2i = Vector2i(-1, -1)
var _selected_rotation: int = 0
var _selected_house_id: String = ""
var _selected_direction: String = "E"

var _rotation_option: OptionButton = null
var _direction_option: OptionButton = null
var _house_id_by_cell: Dictionary = {}  # Vector2i -> house_id

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	_ensure_controls()
	_update_ui()
	visible = false

func set_mode(action_id: String) -> void:
	_mode = action_id
	clear_selection()
	_update_ui()

func set_map_data(map_data: Dictionary) -> void:
	_rebuild_house_index(map_data)
	_update_ui()

func set_selected_position(position: Vector2i) -> void:
	if _mode == "place_house":
		_selected_position = position
	else:
		_selected_house_id = str(_house_id_by_cell.get(position, ""))
	_update_ui()

func clear_selection() -> void:
	_selected_position = Vector2i(-1, -1)
	_selected_rotation = 0
	_selected_house_id = ""
	_selected_direction = "E"
	_sync_rotation_selection()
	_sync_direction_selection()
	_update_ui()

func _ensure_controls() -> void:
	if bottom_bar == null:
		return

	if garden_checkbox != null:
		garden_checkbox.visible = false

	if _rotation_option == null:
		_rotation_option = OptionButton.new()
		_rotation_option.custom_minimum_size = Vector2(110, 0)
		_rotation_option.item_selected.connect(_on_rotation_selected)
		bottom_bar.add_child(_rotation_option)
		bottom_bar.move_child(_rotation_option, 0)

	if _direction_option == null:
		_direction_option = OptionButton.new()
		_direction_option.custom_minimum_size = Vector2(110, 0)
		_direction_option.item_selected.connect(_on_direction_selected)
		bottom_bar.add_child(_direction_option)
		bottom_bar.move_child(_direction_option, 1)

	_rebuild_rotation_options()
	_rebuild_direction_options()

func _rebuild_house_index(map_data: Dictionary) -> void:
	_house_id_by_cell.clear()

	if not map_data.has("houses") or not (map_data["houses"] is Dictionary):
		return
	var houses: Dictionary = map_data["houses"]
	for hid_val in houses.keys():
		var hid: String = str(hid_val)
		if hid.is_empty():
			continue
		var house_val = houses.get(hid_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var cells_val = house.get("cells", null)
		if not (cells_val is Array):
			continue
		for p in cells_val:
			if p is Vector2i:
				_house_id_by_cell[p] = hid

func _rebuild_rotation_options() -> void:
	if _rotation_option == null:
		return
	_rotation_option.clear()

	for rot in [0, 90, 180, 270]:
		_rotation_option.add_item("%d°" % rot)
		var idx := _rotation_option.get_item_count() - 1
		_rotation_option.set_item_metadata(idx, rot)

	_sync_rotation_selection()

func _rebuild_direction_options() -> void:
	if _direction_option == null:
		return
	_direction_option.clear()

	for d in ["N", "E", "S", "W"]:
		_direction_option.add_item(d)
		var idx := _direction_option.get_item_count() - 1
		_direction_option.set_item_metadata(idx, d)

	_sync_direction_selection()

func _sync_rotation_selection() -> void:
	if _rotation_option == null:
		return
	for i in range(_rotation_option.get_item_count()):
		if int(_rotation_option.get_item_metadata(i)) == _selected_rotation:
			_rotation_option.select(i)
			return
	if _rotation_option.get_item_count() > 0:
		_rotation_option.select(0)
		_selected_rotation = int(_rotation_option.get_item_metadata(0))

func _sync_direction_selection() -> void:
	if _direction_option == null:
		return
	for i in range(_direction_option.get_item_count()):
		if str(_direction_option.get_item_metadata(i)) == _selected_direction:
			_direction_option.select(i)
			return
	if _direction_option.get_item_count() > 0:
		_direction_option.select(0)
		_selected_direction = str(_direction_option.get_item_metadata(0))

func _on_rotation_selected(index: int) -> void:
	if _rotation_option == null:
		return
	var meta = _rotation_option.get_item_metadata(index)
	_selected_rotation = int(meta)
	_update_ui()

func _on_direction_selected(index: int) -> void:
	if _direction_option == null:
		return
	var meta = _direction_option.get_item_metadata(index)
	_selected_direction = str(meta)
	_update_ui()

func _update_ui() -> void:
	if _rotation_option != null:
		_rotation_option.visible = (_mode == "place_house")
		_rotation_option.disabled = (_mode != "place_house")
	if _direction_option != null:
		_direction_option.visible = (_mode == "add_garden")
		_direction_option.disabled = (_mode != "add_garden")

	if confirm_btn != null:
		confirm_btn.text = "确认添加花园" if _mode == "add_garden" else "确认放置"

	_update_hint()
	_update_confirm_state()

func _update_hint() -> void:
	if hint_label == null:
		return

	if _mode == "add_garden":
		if _selected_house_id.is_empty():
			hint_label.text = "请点击房屋选择目标，并选择花园方向"
			return
		hint_label.text = "房屋 %s 方向:%s" % [_selected_house_id, _selected_direction]
		return

	# place_house
	if _selected_position == Vector2i(-1, -1):
		hint_label.text = "请在地图上点击放置位置"
	else:
		hint_label.text = "放置位置: (%d,%d) 旋转:%d°" % [_selected_position.x, _selected_position.y, _selected_rotation]

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return

	var ok := true
	if _mode == "add_garden":
		ok = ok and not _selected_house_id.is_empty()
		ok = ok and not _selected_direction.is_empty()
	else:
		ok = ok and (_selected_position != Vector2i(-1, -1))

	confirm_btn.disabled = not ok

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return

	if _mode == "add_garden":
		if _selected_house_id.is_empty() or _selected_direction.is_empty():
			return
		garden_confirmed.emit(_selected_house_id, _selected_direction)
	else:
		if _selected_position == Vector2i(-1, -1):
			return
		house_placement_confirmed.emit(_selected_position, _selected_rotation)

func _on_cancel_pressed() -> void:
	cancelled.emit()
	visible = false
