# 餐厅放置覆盖层组件
# - 只负责收集输入：restaurant_id（可选）、rotation、position
# - 地图选点由 game.gd 通过 MapCanvas 信号回填
class_name RestaurantPlacementOverlay
extends Control

signal placement_confirmed(position: Vector2i, rotation: int, restaurant_id: String)
signal cancelled()
signal preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String)
signal preview_cleared()
signal highlight_requested(mode: String, rotation: int, restaurant_id: String)
signal ui_state_changed()

@onready var hint_label: Label = $HintMargin/HintPanel/HintLabel

var _mode: String = "place_restaurant"  # place_restaurant | move_restaurant
var _selected_position: Vector2i = Vector2i(-1, -1)
var _selected_rotation: int = 0
var _available_restaurants: Array[String] = []
var _selected_restaurant_id: String = ""
var _available_employees: Array[String] = []
var _selected_employee_type: String = ""

var _validation_ok: bool = true
var _validation_message: String = ""

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

func get_selected_position() -> Vector2i:
	return _selected_position

func get_selected_rotation() -> int:
	return _selected_rotation

func get_available_restaurants() -> Array[String]:
	return _available_restaurants.duplicate()

func get_selected_restaurant() -> String:
	return _selected_restaurant_id

func get_available_employees() -> Array[String]:
	return _available_employees.duplicate()

func get_selected_employee() -> String:
	return _selected_employee_type

func set_mode(action_id: String) -> void:
	_mode = str(action_id)
	clear_selection()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_map_data(_map_data: Dictionary) -> void:
	# 预留：后续可根据 PlacementValidator 扫描可放置位置并高亮
	pass

func set_available_restaurants(restaurant_ids: Array[String]) -> void:
	var ids: Array[String] = []
	for rid in restaurant_ids:
		var s := str(rid).strip_edges()
		if not s.is_empty():
			ids.append(s)
	ids.sort()
	_available_restaurants = ids

	if _mode == "move_restaurant":
		if ids.is_empty():
			_selected_restaurant_id = ""
		elif _selected_restaurant_id.is_empty() or not ids.has(_selected_restaurant_id):
			_selected_restaurant_id = ids[0]

	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func set_available_employees(employee_types: Array[String]) -> void:
	var ids: Array[String] = []
	var seen := {}
	for emp_val in employee_types:
		var s := str(emp_val).strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		ids.append(s)
	ids.sort()
	_available_employees = ids

	if _available_employees.is_empty():
		_selected_employee_type = ""
	elif _selected_employee_type.is_empty() or not _available_employees.has(_selected_employee_type):
		_selected_employee_type = _available_employees[0]

	_update_ui()
	ui_state_changed.emit()

func set_selected_employee(employee_type: String) -> void:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		_selected_employee_type = "" if _available_employees.is_empty() else _available_employees[0]
	elif not _available_employees.is_empty() and not _available_employees.has(emp_id):
		_selected_employee_type = _available_employees[0]
	else:
		_selected_employee_type = emp_id

	_update_ui()
	ui_state_changed.emit()

func set_selected_restaurant(restaurant_id: String) -> void:
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		_selected_restaurant_id = ""
	elif _mode == "move_restaurant" and not _available_restaurants.is_empty() and not _available_restaurants.has(rid):
		_selected_restaurant_id = _available_restaurants[0]
	else:
		_selected_restaurant_id = rid

	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func set_selected_position(position: Vector2i) -> void:
	_selected_position = position
	_emit_preview()
	_update_ui()
	ui_state_changed.emit()

func set_selected_rotation(rotation: int) -> void:
	_selected_rotation = _normalize_rotation(rotation)
	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = bool(valid)
	_validation_message = str(message).strip_edges()
	_update_ui()
	ui_state_changed.emit()

func clear_selection() -> void:
	_selected_position = Vector2i(-1, -1)
	_selected_rotation = 0
	_selected_restaurant_id = ""
	_selected_employee_type = "" if _available_employees.is_empty() else _available_employees[0]
	_validation_ok = true
	_validation_message = ""
	_emit_preview()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

func can_confirm() -> bool:
	var ok := true
	ok = ok and (_selected_position != Vector2i(-1, -1))
	if _mode == "move_restaurant":
		ok = ok and not _selected_restaurant_id.is_empty()
	ok = ok and _validation_ok
	return ok

func request_confirm() -> void:
	if not can_confirm():
		return
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	placement_confirmed.emit(_selected_position, _selected_rotation, rid)

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

	if not _validation_ok and not _validation_message.is_empty():
		hint_label.text = "无法放置：%s" % _validation_message
		return

	if _mode == "move_restaurant":
		if _selected_restaurant_id.is_empty():
			hint_label.text = "请选择要移动的餐厅，并在地图上点击目标位置"
			return
		if _selected_position == Vector2i(-1, -1):
			hint_label.text = "已选择餐厅: %s，请在地图上点击目标位置" % _selected_restaurant_id
			return
		hint_label.text = "餐厅 %s → (%d,%d) 旋转:%d°" % [
			_selected_restaurant_id,
			_selected_position.x,
			_selected_position.y,
			_selected_rotation
		]
		return

	# place_restaurant
	if _selected_position == Vector2i(-1, -1):
		hint_label.text = "请在地图上点击放置位置"
	else:
		hint_label.text = "放置位置: (%d,%d) 旋转:%d°" % [_selected_position.x, _selected_position.y, _selected_rotation]

func _emit_preview() -> void:
	if _selected_position == Vector2i(-1, -1):
		preview_cleared.emit()
		return
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	preview_requested.emit(_mode, _selected_position, _selected_rotation, rid)

func _emit_highlight_request() -> void:
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	highlight_requested.emit(_mode, _selected_rotation, rid)
