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

const INVALID_POS := Vector2i(-1, -1)

@onready var hint_margin: Control = $HintMargin
@onready var hint_label: Label = $HintMargin/HintPanel/HintLabel

var _mode: String = "place_restaurant"  # place_restaurant | move_restaurant
var _selected_position: Vector2i = INVALID_POS
var _selected_rotation: int = 0
var _available_restaurants: Array[String] = []
var _selected_restaurant_id: String = ""
var _employee_items: Array[Dictionary] = []
var _employee_info_by_key: Dictionary = {}
var _selected_employee_type: String = ""
var _selected_employee_key: String = ""
var _selected_staff_id: int = -1

var _map_data: Dictionary = {}
var _restaurant_index_by_id: Dictionary = {} # restaurant_id -> 1-based index (stable for current list)

var _validation_ok: bool = true
var _validation_message: String = ""
var _hint_text: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint_margin != null:
		hint_margin.visible = false
	_update_ui()
	visible = false

func get_mode() -> String:
	return _mode

func get_hint_text() -> String:
	return _hint_text

func get_selected_position() -> Vector2i:
	return _selected_position

func get_selected_rotation() -> int:
	return _selected_rotation

func can_rotate() -> bool:
	return true

func get_available_restaurants() -> Array[String]:
	return _available_restaurants.duplicate()

func get_selected_restaurant() -> String:
	return _selected_restaurant_id

func get_available_employee_items() -> Array[Dictionary]:
	return _employee_items.duplicate(true)

func get_available_employees() -> Array[String]:
	var out: Array[String] = []
	for item_val in _employee_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var emp_id := str(item.get("employee_type", item.get("id", ""))).strip_edges()
		if emp_id.is_empty():
			continue
		out.append(emp_id)
	return out

func get_selected_employee() -> String:
	return _selected_employee_type

func get_selected_employee_key() -> String:
	return _selected_employee_key

func get_selected_staff_id() -> int:
	return _selected_staff_id

func set_mode(action_id: String) -> void:
	_mode = str(action_id)
	clear_selection()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_map_data(map_data: Dictionary) -> void:
	_map_data = map_data
	_update_ui()

func set_available_restaurants(restaurant_ids: Array[String]) -> void:
	var ids: Array[String] = []
	for rid in restaurant_ids:
		var s := str(rid).strip_edges()
		if not s.is_empty():
			ids.append(s)
	ids.sort()
	_available_restaurants = ids
	_rebuild_restaurant_indices()

	if _mode == "move_restaurant":
		if ids.is_empty():
			_selected_restaurant_id = ""
		elif _selected_restaurant_id.is_empty() or not ids.has(_selected_restaurant_id):
			_selected_restaurant_id = ids[0]

	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func get_restaurant_display_label(restaurant_id: String) -> String:
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		return ""

	var idx := int(_restaurant_index_by_id.get(rid, 0))
	if idx <= 0 and not _available_restaurants.is_empty():
		var i := _available_restaurants.find(rid)
		idx = i + 1 if i >= 0 else 0

	var entrance := _get_restaurant_entrance_pos(rid)
	if entrance != Vector2i(-1, -1):
		if idx > 0:
			return "餐厅 %d @ (%d,%d)" % [idx, entrance.x, entrance.y]
		return "餐厅 @ (%d,%d)" % [entrance.x, entrance.y]

	return "餐厅 %d" % idx if idx > 0 else rid

func _rebuild_restaurant_indices() -> void:
	_restaurant_index_by_id.clear()
	for i in range(_available_restaurants.size()):
		var rid := str(_available_restaurants[i]).strip_edges()
		if rid.is_empty():
			continue
		_restaurant_index_by_id[rid] = i + 1

func _get_restaurant_entrance_pos(restaurant_id: String) -> Vector2i:
	if _map_data.is_empty():
		return Vector2i(-1, -1)
	if not _map_data.has("restaurants") or not (_map_data["restaurants"] is Dictionary):
		return Vector2i(-1, -1)
	var restaurants: Dictionary = _map_data["restaurants"]
	if not restaurants.has(restaurant_id):
		return Vector2i(-1, -1)
	var rest_val = restaurants[restaurant_id]
	if not (rest_val is Dictionary):
		return Vector2i(-1, -1)
	var rest: Dictionary = rest_val
	var ep_val = rest.get("entrance_pos", null)
	if ep_val is Vector2i:
		return Vector2i(ep_val)
	return Vector2i(-1, -1)

func set_available_employee_items(items: Array[Dictionary]) -> void:
	_employee_items.clear()
	_employee_info_by_key.clear()
	var previous_staff_id := _selected_staff_id
	var first_enabled_key := ""
	var first_key := ""
	for item_val in items:
		if not (item_val is Dictionary):
			continue
		var source: Dictionary = item_val
		var staff_id := int(source.get("staff_id", -1))
		var emp_id := str(source.get("employee_type", source.get("id", ""))).strip_edges()
		if staff_id <= 0 or emp_id.is_empty():
			continue
		var key := "staff:%d" % staff_id
		var remaining := int(source.get("remaining", 0))
		var capacity := int(source.get("capacity", 0))
		var enabled := remaining > 0
		var item := {
			"id": emp_id,
			"key": key,
			"employee_type": emp_id,
			"staff_id": staff_id,
			"badge_text": "%d/%d" % [maxi(0, remaining), maxi(0, capacity)],
			"tag_text": "可用" if enabled else "已用",
			"enabled": enabled,
			"can_place_restaurant": bool(source.get("can_place_restaurant", false)),
			"can_move_restaurant": bool(source.get("can_move_restaurant", false)),
		}
		_employee_items.append(item)
		_employee_info_by_key[key] = item
		if first_key.is_empty():
			first_key = key
		if enabled and first_enabled_key.is_empty():
			first_enabled_key = key
		if previous_staff_id > 0 and previous_staff_id == staff_id:
			_selected_employee_key = key

	if _employee_items.is_empty():
		_selected_employee_type = ""
		_selected_employee_key = ""
		_selected_staff_id = -1
	elif _selected_employee_key.is_empty() or not _employee_info_by_key.has(_selected_employee_key):
		var fallback_key := first_enabled_key if not first_enabled_key.is_empty() else first_key
		_apply_selected_employee_key(fallback_key)
	else:
		_apply_selected_employee_key(_selected_employee_key)

	_update_ui()
	ui_state_changed.emit()

func set_available_employees(employee_types: Array[String]) -> void:
	var items: Array[Dictionary] = []
	var seq := 1
	for emp_val in employee_types:
		var s := str(emp_val).strip_edges()
		if s.is_empty():
			continue
		items.append({
			"id": s,
			"employee_type": s,
			"staff_id": seq,
			"key": "legacy:%d" % seq,
			"badge_text": "",
			"tag_text": "",
			"enabled": true,
		})
		seq += 1
	set_available_employee_items(items)

func set_selected_employee_key(employee_key: String) -> void:
	_apply_selected_employee_key(str(employee_key).strip_edges())
	_update_ui()
	ui_state_changed.emit()

func set_selected_employee(employee_type: String) -> void:
	var emp_id := str(employee_type).strip_edges()
	var matched_key := ""
	for key in _employee_info_by_key.keys():
		var info: Dictionary = Dictionary(_employee_info_by_key.get(key, {}))
		if str(info.get("employee_type", "")).strip_edges() != emp_id:
			continue
		if bool(info.get("enabled", true)):
			matched_key = str(key)
			break
		if matched_key.is_empty():
			matched_key = str(key)
	_apply_selected_employee_key(matched_key)

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
	_selected_position = INVALID_POS
	_selected_rotation = 0
	_selected_restaurant_id = ""
	if _employee_items.is_empty():
		_selected_employee_type = ""
		_selected_employee_key = ""
		_selected_staff_id = -1
	else:
		_apply_selected_employee_key(_selected_employee_key)
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
	ok = ok and (_selected_position != INVALID_POS)
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

func _apply_selected_employee_key(employee_key: String) -> void:
	var key := str(employee_key).strip_edges()
	if key.is_empty() or not _employee_info_by_key.has(key):
		_selected_employee_key = ""
		_selected_employee_type = ""
		_selected_staff_id = -1
		return
	var info: Dictionary = Dictionary(_employee_info_by_key.get(key, {}))
	_selected_employee_key = key
	_selected_employee_type = str(info.get("employee_type", info.get("id", ""))).strip_edges()
	_selected_staff_id = int(info.get("staff_id", -1))

func _update_ui() -> void:
	_update_hint()

func _update_hint() -> void:
	var next_hint := ""
	if not _validation_ok and not _validation_message.is_empty():
		next_hint = "无法放置：%s" % _validation_message
	elif _mode == "move_restaurant":
		if _selected_restaurant_id.is_empty():
			next_hint = "请选择要移动的餐厅，并在地图上点击目标位置"
		else:
			var label := get_restaurant_display_label(_selected_restaurant_id)
			if _selected_position == INVALID_POS:
				next_hint = "已选择: %s，请在地图上点击目标位置" % label
			else:
				next_hint = "%s -> (%d,%d) 旋转:%d度" % [
					label,
					_selected_position.x,
					_selected_position.y,
					_selected_rotation
				]
	else:
		if _selected_position == INVALID_POS:
			next_hint = "请在地图上点击放置位置"
		else:
			next_hint = "放置位置: (%d,%d) 旋转:%d度" % [_selected_position.x, _selected_position.y, _selected_rotation]

	_hint_text = next_hint

	# 提示文字已在右侧动作面板的上下文区域展示；地图顶部不再重复显示纯文字条。
	if hint_margin != null:
		hint_margin.visible = false
	if hint_label != null:
		hint_label.text = ""

func _emit_preview() -> void:
	if _selected_position == INVALID_POS:
		preview_cleared.emit()
		return
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	preview_requested.emit(_mode, _selected_position, _selected_rotation, rid)

func _emit_highlight_request() -> void:
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	highlight_requested.emit(_mode, _selected_rotation, rid)
