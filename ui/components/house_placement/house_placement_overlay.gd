# 房屋/花园覆盖层组件
# - place_house: 选择 position + rotation
# - add_garden: 选择 house_id + direction
# 地图选点由 game.gd 通过 MapCanvas 信号回填
class_name HousePlacementOverlay
extends Control

signal house_placement_confirmed(position: Vector2i, rotation: int)
signal garden_confirmed(house_id: String, direction: String)
signal cancelled()
signal preview_requested(action_id: String, position: Vector2i, rotation: int)
signal preview_cleared()
signal highlight_requested(action_id: String, rotation: int)
signal ui_state_changed()

@onready var hint_label: Label = $HintMargin/HintPanel/HintLabel

var _mode: String = "place_house"  # place_house | add_garden
var _selected_position: Vector2i = Vector2i(-1, -1)
var _selected_rotation: int = 0
var _selected_house_id: String = ""
var _selected_direction: String = "E"

var _house_id_by_cell: Dictionary = {}  # Vector2i -> house_id

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_ui()
	visible = false

func get_mode() -> String:
	return _mode

func get_hint_text() -> String:
	if hint_label != null:
		return hint_label.text
	return ""

func get_selected_rotation() -> int:
	return _selected_rotation

func get_selected_direction() -> String:
	return _selected_direction

func set_mode(action_id: String) -> void:
	_mode = str(action_id)
	clear_selection()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_map_data(map_data: Dictionary) -> void:
	_rebuild_house_index(map_data)
	_update_ui()
	ui_state_changed.emit()

func set_selected_position(position: Vector2i) -> void:
	if _mode == "place_house":
		_selected_position = position
		_emit_preview()
	else:
		_selected_house_id = str(_house_id_by_cell.get(position, ""))
	_update_ui()
	ui_state_changed.emit()

func set_selected_rotation(rotation: int) -> void:
	if _mode != "place_house":
		return
	_selected_rotation = _normalize_rotation(rotation)
	_emit_preview()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_selected_direction(direction: String) -> void:
	if _mode != "add_garden":
		return
	var d := str(direction).strip_edges()
	if d != "N" and d != "E" and d != "S" and d != "W":
		d = "E"
	_selected_direction = d
	_update_ui()
	ui_state_changed.emit()

func clear_selection() -> void:
	_selected_position = Vector2i(-1, -1)
	_selected_rotation = 0
	_selected_house_id = ""
	_selected_direction = "E"
	_emit_preview()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

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

func can_confirm() -> bool:
	if _mode == "add_garden":
		return not _selected_house_id.is_empty() and not _selected_direction.is_empty()
	return _selected_position != Vector2i(-1, -1)

func request_confirm() -> void:
	if not can_confirm():
		return

	if _mode == "add_garden":
		garden_confirmed.emit(_selected_house_id, _selected_direction)
		return

	house_placement_confirmed.emit(_selected_position, _selected_rotation)

func request_cancel() -> void:
	cancelled.emit()
	visible = false
	preview_cleared.emit()
	_emit_highlight_request()
	ui_state_changed.emit()

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _update_ui() -> void:
	_update_hint()

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

func _emit_highlight_request() -> void:
	if _mode != "place_house":
		return
	highlight_requested.emit(_mode, _selected_rotation)

func _emit_preview() -> void:
	if _mode != "place_house":
		preview_cleared.emit()
		return
	if _selected_position == Vector2i(-1, -1):
		preview_cleared.emit()
		return
	preview_requested.emit(_mode, _selected_position, _selected_rotation)
