# 员工实例选择状态 helper
# - 只管理 staff_id 驱动的 picker 数据与选中项
# - 不创建 UI 节点，供 overlay / panel 复用
class_name StaffPickerState
extends RefCounted

var _capability_keys: Array[String] = []
var _items: Array[Dictionary] = []
var _info_by_key: Dictionary = {}
var _selected_employee_type: String = ""
var _selected_employee_key: String = ""
var _selected_staff_id: int = -1

static func _format_staff_usage_badge(remaining: int, capacity: int) -> String:
	var safe_capacity := maxi(0, capacity)
	if safe_capacity <= 1:
		return ""
	return "%d/%d" % [maxi(0, remaining), safe_capacity]

func _init(capability_keys: Array = []) -> void:
	set_capability_keys(capability_keys)

func set_capability_keys(capability_keys: Array) -> void:
	_capability_keys.clear()
	for key_val in capability_keys:
		var key := str(key_val).strip_edges()
		if key.is_empty():
			continue
		_capability_keys.append(key)

func set_items(items: Array[Dictionary]) -> void:
	_items.clear()
	_info_by_key.clear()

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
			"badge_text": _format_staff_usage_badge(remaining, capacity),
			"tag_text": "",
			"enabled": enabled,
		}
		for capability_key in _capability_keys:
			item[capability_key] = bool(source.get(capability_key, false))

		_items.append(item)
		_info_by_key[key] = item
		if first_key.is_empty():
			first_key = key
		if enabled and first_enabled_key.is_empty():
			first_enabled_key = key
		if previous_staff_id > 0 and previous_staff_id == staff_id:
			_selected_employee_key = key

	if _items.is_empty():
		clear_selection()
	elif _selected_employee_key.is_empty() or not _info_by_key.has(_selected_employee_key):
		var fallback_key := first_enabled_key if not first_enabled_key.is_empty() else first_key
		apply_selected_key(fallback_key)
	else:
		apply_selected_key(_selected_employee_key)

func get_items() -> Array[Dictionary]:
	return _items.duplicate(true)

func is_empty() -> bool:
	return _items.is_empty()

func get_selected_employee_type() -> String:
	return _selected_employee_type

func get_selected_key() -> String:
	return _selected_employee_key

func get_selected_staff_id() -> int:
	return _selected_staff_id

func apply_selected_key(employee_key: String) -> void:
	var key := str(employee_key).strip_edges()
	if key.is_empty():
		clear_selection()
		return
	if not _info_by_key.has(key):
		var fallback_key := ""
		if not _selected_employee_key.is_empty() and _info_by_key.has(_selected_employee_key):
			fallback_key = _selected_employee_key
		if fallback_key.is_empty():
			fallback_key = _find_first_enabled_key()
		if fallback_key.is_empty():
			fallback_key = _find_first_key()
		if fallback_key.is_empty():
			clear_selection()
			return
		key = fallback_key
	var info: Dictionary = Dictionary(_info_by_key.get(key, {}))
	_selected_employee_key = key
	_selected_employee_type = str(info.get("employee_type", info.get("id", ""))).strip_edges()
	_selected_staff_id = int(info.get("staff_id", -1))

func apply_selected_employee_type(employee_type: String) -> void:
	var emp_id := str(employee_type).strip_edges()
	var matched_key := ""
	for key in _info_by_key.keys():
		var info: Dictionary = Dictionary(_info_by_key.get(key, {}))
		if str(info.get("employee_type", "")).strip_edges() != emp_id:
			continue
		if bool(info.get("enabled", true)):
			matched_key = str(key)
			break
		if matched_key.is_empty():
			matched_key = str(key)
	apply_selected_key(matched_key)

func refresh_selected() -> void:
	if _items.is_empty():
		clear_selection()
	else:
		apply_selected_key(_selected_employee_key)

func clear_selection() -> void:
	_selected_employee_key = ""
	_selected_employee_type = ""
	_selected_staff_id = -1

func _find_first_enabled_key() -> String:
	for item_val in _items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if not bool(item.get("enabled", true)):
			continue
		var key := str(item.get("key", "")).strip_edges()
		if key.is_empty():
			continue
		if _info_by_key.has(key):
			return key
	return ""

func _find_first_key() -> String:
	for item_val in _items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var key := str(item.get("key", "")).strip_edges()
		if key.is_empty():
			continue
		if _info_by_key.has(key):
			return key
	return ""
