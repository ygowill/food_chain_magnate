# 房屋/花园覆盖层组件
# - place_house: 选择 position + rotation + house_number
# - add_garden: 选择 house_id + direction(N/E/S/W)
# 地图选点由 GameMapInteractionController 通过 MapCanvas 信号回填
class_name HousePlacementOverlay
extends Control

signal house_placement_confirmed(position: Vector2i, rotation: int, house_number: int)
signal garden_confirmed(house_id: String, direction: String)
signal cancelled()
signal preview_requested(action_id: String, position: Vector2i, rotation: int)
signal preview_cleared()
signal highlight_requested(action_id: String, rotation: int)
signal garden_preview_requested(house_id: String, direction: String)
signal garden_preview_cleared()
signal ui_state_changed()

const INVALID_POS := Vector2i(-1, -1)
const ActionPanelHouseContextScenePath := "res://ui/components/house_placement/action_panel_house_placement_context.gd"
const DEFAULT_HOUSE_NUMBER_SUPPLY := [1, 3, 6, 9, 11, 14, 17, 19]
const DEFAULT_NORMAL_DEMAND_CAP := 3
const DEFAULT_GARDEN_DEMAND_CAP := 5
const StaffPickerStateClass = preload("res://ui/components/employee_picker/staff_picker_state.gd")

@onready var hint_label: Label = $HintMargin/HintPanel/HintLabel
@onready var hint_margin: Control = $HintMargin

var _mode: String = "place_house"  # place_house | add_garden
var _selected_position: Vector2i = INVALID_POS
var _selected_rotation: int = 0
var _selected_house_id: String = ""
var _selected_direction: String = "E"
var _selected_house_number: int = -1
var _staff_picker_state := StaffPickerStateClass.new(["can_place_house", "can_add_garden"])

var _map_data: Dictionary = {}
var _house_id_by_cell: Dictionary = {}  # Vector2i -> house_id
var _available_house_numbers: Array[int] = []
var _available_garden_house_ids: Array[String] = []
var _garden_direction_validity: Dictionary = {} # direction -> {valid: bool, message: String}

var _validation_ok: bool = true
var _validation_message: String = ""
var _hint_text: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(hint_margin):
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
	return _mode == "place_house"

func get_selected_direction() -> String:
	return _selected_direction

func get_selected_house_id() -> String:
	return _selected_house_id

func get_selected_house_number() -> int:
	return _selected_house_number

func get_available_employee_items() -> Array[Dictionary]:
	return _staff_picker_state.get_items()

func get_selected_employee() -> String:
	return _staff_picker_state.get_selected_employee_type()

func get_selected_employee_key() -> String:
	return _staff_picker_state.get_selected_key()

func get_selected_staff_id() -> int:
	return _staff_picker_state.get_selected_staff_id()

func get_available_house_numbers() -> Array[int]:
	var out: Array[int] = []
	out.append_array(_available_house_numbers)
	return out

func get_available_garden_house_ids() -> Array[String]:
	return Array(_available_garden_house_ids, TYPE_STRING, "", null)

func get_selected_house_display_label() -> String:
	return get_house_display_label(_selected_house_id)

func get_house_display_label(house_id: String) -> String:
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return ""
	var house := _get_house(hid)
	if house.is_empty():
		return "房屋 %s" % hid
	var label := _format_house_number(house.get("house_number", hid), hid)
	return "房屋 #%s" % label

func get_garden_effect_label() -> String:
	var normal_cap := _get_rule_int("demand_cap_normal", DEFAULT_NORMAL_DEMAND_CAP)
	var garden_cap := _get_rule_int("demand_cap_with_garden", DEFAULT_GARDEN_DEMAND_CAP)
	return "需求上限 %d → %d；晚餐结算时单价部分翻倍" % [normal_cap, garden_cap]

func get_direction_status(direction: String) -> Dictionary:
	var d := _normalize_direction(direction)
	if _selected_house_id.is_empty():
		return {"valid": false, "message": "请先选择房屋"}
	var status_val = _garden_direction_validity.get(d, null)
	if status_val is Dictionary:
		return Dictionary(status_val).duplicate(true)
	return {"valid": true, "message": ""}

func get_action_panel_context_spec() -> Dictionary:
	return {
		"title": "新业务拓展经理",
		"hint": "",
		"confirm_text": "确认添加花园" if _mode == "add_garden" else "确认放置",
		"cancel_text": "取消",
		"custom_scene": ActionPanelHouseContextScenePath,
	}

func set_mode(action_id: String) -> void:
	var next := str(action_id).strip_edges()
	if next != "add_garden":
		next = "place_house"
	if _mode == next:
		_update_ui()
		_emit_mode_side_effects()
		ui_state_changed.emit()
		return
	_mode = next
	_validation_ok = true
	_validation_message = ""
	_update_ui()
	_emit_mode_side_effects()
	ui_state_changed.emit()

func set_map_data(map_data: Dictionary) -> void:
	_map_data = map_data.duplicate(true)
	_rebuild_house_index()
	_rebuild_house_number_supply()
	_rebuild_available_garden_houses()
	if _mode == "add_garden":
		if not _selected_house_id.is_empty() and not _available_garden_house_ids.has(_selected_house_id):
			_selected_house_id = ""
		_rebuild_garden_direction_validity()
		_emit_garden_preview()
	_update_ui()
	ui_state_changed.emit()

func set_available_employee_items(items: Array[Dictionary]) -> void:
	_staff_picker_state.set_items(items)
	_update_ui()
	ui_state_changed.emit()

func set_selected_employee_key(employee_key: String) -> void:
	_staff_picker_state.apply_selected_key(str(employee_key).strip_edges())
	_update_ui()
	ui_state_changed.emit()

func set_selected_employee(employee_type: String) -> void:
	_staff_picker_state.apply_selected_employee_type(str(employee_type).strip_edges())
	_validation_ok = true
	_validation_message = ""
	_update_ui()
	ui_state_changed.emit()

func set_selected_position(position: Vector2i) -> void:
	if _mode == "place_house":
		_selected_position = position
		_validation_ok = true
		_validation_message = ""
		_emit_preview()
	else:
		set_selected_house_id(str(_house_id_by_cell.get(position, "")))
		return
	_update_ui()
	ui_state_changed.emit()

func set_selected_house_id(house_id: String) -> void:
	if _mode != "add_garden":
		return
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		_selected_house_id = ""
	elif not _available_garden_house_ids.is_empty() and not _available_garden_house_ids.has(hid):
		_selected_house_id = ""
		_validation_ok = false
		_validation_message = "请选择高亮的可添加花园房屋"
	else:
		_selected_house_id = hid
		_validation_ok = true
		_validation_message = ""
	_rebuild_garden_direction_validity()
	_emit_garden_preview()
	_update_ui()
	ui_state_changed.emit()

func set_selected_rotation(rotation: int) -> void:
	if _mode != "place_house":
		return
	_selected_rotation = _normalize_rotation(rotation)
	_validation_ok = true
	_validation_message = ""
	_emit_preview()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_selected_direction(direction: String) -> void:
	if _mode != "add_garden":
		return
	_selected_direction = _normalize_direction(direction)
	var status := get_direction_status(_selected_direction)
	_validation_ok = bool(status.get("valid", true))
	_validation_message = str(status.get("message", "")).strip_edges()
	_emit_garden_preview()
	_update_ui()
	ui_state_changed.emit()

func set_selected_house_number(house_number: int) -> void:
	if _mode != "place_house":
		return
	var n := int(house_number)
	if n <= 0:
		_selected_house_number = -1
	else:
		_selected_house_number = n
	_validation_ok = true
	_validation_message = ""
	_emit_preview()
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
	_selected_house_id = ""
	_selected_direction = "E"
	_selected_house_number = -1
	_staff_picker_state.refresh_selected()
	_validation_ok = true
	_validation_message = ""
	_garden_direction_validity.clear()
	_emit_preview()
	garden_preview_cleared.emit()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

func can_confirm() -> bool:
	if _mode == "add_garden":
		return not _selected_house_id.is_empty() and not _selected_direction.is_empty() and _validation_ok
	return _selected_position != INVALID_POS and _selected_house_number > 0 and _validation_ok

func request_confirm() -> void:
	if not can_confirm():
		return

	if _mode == "add_garden":
		garden_confirmed.emit(_selected_house_id, _selected_direction)
		return

	house_placement_confirmed.emit(_selected_position, _selected_rotation, _selected_house_number)

func request_cancel() -> void:
	cancelled.emit()
	visible = false
	preview_cleared.emit()
	garden_preview_cleared.emit()
	_emit_highlight_request()
	ui_state_changed.emit()

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _normalize_direction(direction: String) -> String:
	var d := str(direction).strip_edges().to_upper()
	if d != "N" and d != "E" and d != "S" and d != "W":
		d = "E"
	return d

func _update_ui() -> void:
	_update_hint()

func _update_hint() -> void:
	var next_hint := ""
	if not _validation_ok and not _validation_message.is_empty():
		next_hint = "无法执行：%s" % _validation_message
	elif _mode == "add_garden":
		if _available_garden_house_ids.is_empty():
			next_hint = "当前没有可添加花园的房屋"
		elif _selected_house_id.is_empty():
			next_hint = "请点击地图中高亮的房屋，然后选择花园方向（N/E/S/W）"
		else:
			var label := get_selected_house_display_label()
			var status := get_direction_status(_selected_direction)
			if bool(status.get("valid", true)):
				next_hint = "%s：花园方向 %s，确认后添加花园" % [label, _selected_direction]
			else:
				next_hint = "%s：方向 %s 不可用：%s" % [label, _selected_direction, str(status.get("message", ""))]
	else:
		if _available_house_numbers.is_empty():
			next_hint = "可放置房屋编号已用完"
		elif _selected_house_number <= 0:
			next_hint = "请选择房屋编号，然后点击地图上的高亮位置"
		elif _selected_position == INVALID_POS:
			next_hint = "已选择房屋 #%d，请点击地图上的高亮位置" % _selected_house_number
		else:
			next_hint = "房屋 #%d @ (%d,%d)，可用旋转按钮调整朝向" % [_selected_house_number, _selected_position.x, _selected_position.y]

	_hint_text = next_hint

	# 提示文字在右侧动作面板的当前模式 UI 内展示；地图顶部不再重复显示。
	if hint_margin != null:
		hint_margin.visible = false
	if hint_label != null:
		hint_label.text = ""

func _emit_mode_side_effects() -> void:
	if _mode == "place_house":
		garden_preview_cleared.emit()
		_emit_preview()
	else:
		preview_cleared.emit()
		_emit_garden_preview()
	_emit_highlight_request()

func _emit_highlight_request() -> void:
	highlight_requested.emit(_mode, _selected_rotation)

func _emit_preview() -> void:
	if _mode != "place_house":
		preview_cleared.emit()
		return
	if _selected_position == INVALID_POS:
		preview_cleared.emit()
		return
	preview_requested.emit(_mode, _selected_position, _selected_rotation)

func _emit_garden_preview() -> void:
	if _mode != "add_garden":
		garden_preview_cleared.emit()
		return
	if _selected_house_id.is_empty():
		garden_preview_cleared.emit()
		return
	garden_preview_requested.emit(_selected_house_id, _selected_direction)

func _rebuild_house_index() -> void:
	_house_id_by_cell.clear()

	if not _map_data.has("houses") or not (_map_data["houses"] is Dictionary):
		return
	var houses: Dictionary = _map_data["houses"]
	for hid_val in houses.keys():
		var hid: String = str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		var house := _get_house(hid)
		if house.is_empty():
			continue
		var cells_val = house.get("cells", null)
		if not (cells_val is Array):
			continue
		for p in cells_val:
			if p is Vector2i:
				_house_id_by_cell[p] = hid

func _rebuild_house_number_supply() -> void:
	_available_house_numbers.clear()

	var supply_val = _map_data.get("house_number_supply_remaining", null)
	if supply_val is Array:
		for v in Array(supply_val):
			if v is int:
				_available_house_numbers.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					_available_house_numbers.append(int(f))
	else:
		for n in DEFAULT_HOUSE_NUMBER_SUPPLY:
			_available_house_numbers.append(int(n))

	_available_house_numbers.sort()

func _rebuild_available_garden_houses() -> void:
	_available_garden_house_ids.clear()
	if not _map_data.has("houses") or not (_map_data["houses"] is Dictionary):
		return
	var houses: Dictionary = _map_data["houses"]
	for hid_val in houses.keys():
		var hid := str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		var house := _get_house(hid)
		if house.is_empty():
			continue
		if bool(house.get("has_garden", false)):
			continue
		_available_garden_house_ids.append(hid)
	_available_garden_house_ids.sort_custom(func(a, b):
		return _house_sort_key(str(a)) < _house_sort_key(str(b))
	)

func _rebuild_garden_direction_validity() -> void:
	_garden_direction_validity.clear()
	if _selected_house_id.is_empty():
		return
	for d in ["N", "E", "S", "W"]:
		_garden_direction_validity[d] = _validate_garden_direction(_selected_house_id, d)

func _validate_garden_direction(house_id: String, direction: String) -> Dictionary:
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return {"valid": false, "message": "请先选择房屋"}
	var house := _get_house(hid)
	if house.is_empty():
		return {"valid": false, "message": "房屋不存在"}
	if bool(house.get("has_garden", false)):
		return {"valid": false, "message": "房屋已有花园"}

	var garden_cells := _compute_garden_cells(house, direction)
	if garden_cells.is_empty():
		return {"valid": false, "message": "房屋占地无效"}

	var grid_size: Vector2i = _map_data.get("grid_size", Vector2i.ZERO)
	var map_origin: Vector2i = _map_data.get("map_origin", Vector2i.ZERO)
	var cells_val = _map_data.get("cells", null)
	if grid_size == Vector2i.ZERO or not (cells_val is Array):
		return {"valid": false, "message": "地图数据无效"}
	var cells: Array = cells_val

	for cell_pos in garden_cells:
		var idx := cell_pos + map_origin
		if idx.x < 0 or idx.y < 0 or idx.x >= grid_size.x or idx.y >= grid_size.y:
			return {"valid": false, "message": "花园位置超出边界: %s" % str(cell_pos)}
		if idx.y >= cells.size() or not (cells[idx.y] is Array):
			return {"valid": false, "message": "无法读取地图格子: %s" % str(cell_pos)}
		var row: Array = cells[idx.y]
		if idx.x >= row.size() or not (row[idx.x] is Dictionary):
			return {"valid": false, "message": "无法读取地图格子: %s" % str(cell_pos)}
		var cell: Dictionary = row[idx.x]

		var road_segments_val = cell.get("road_segments", null)
		if road_segments_val is Array and not (road_segments_val as Array).is_empty():
			return {"valid": false, "message": "花园位置有道路: %s" % str(cell_pos)}
		var structure_val = cell.get("structure", null)
		if structure_val is Dictionary and not (structure_val as Dictionary).is_empty():
			return {"valid": false, "message": "花园位置有建筑: %s" % str(cell_pos)}
		if bool(cell.get("blocked", false)):
			return {"valid": false, "message": "花园位置被阻塞: %s" % str(cell_pos)}

	var mk := _validate_no_marketing_overlap(garden_cells)
	if not bool(mk.get("valid", true)):
		return mk
	return {"valid": true, "message": ""}

func _validate_no_marketing_overlap(garden_cells: Array[Vector2i]) -> Dictionary:
	var placements_val = _map_data.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return {"valid": true, "message": ""}
	var placements: Dictionary = placements_val
	for key in placements.keys():
		var p_val = placements.get(key, null)
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if str(p.get("type", "")) == "airplane":
			continue
		var anchor_val = p.get("world_pos", null)
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var size := Vector2i.ONE
		var fs_val = p.get("footprint_size", null)
		if fs_val is Vector2i:
			size = Vector2i(fs_val)
		elif fs_val is Array and (fs_val as Array).size() == 2:
			var arr: Array = fs_val
			size = Vector2i(int(arr[0]), int(arr[1]))
		var rotation := int(p.get("rotation", 0))
		if rotation == 90 or rotation == 270:
			size = Vector2i(size.y, size.x)
		for cell_pos in garden_cells:
			if cell_pos.x < anchor.x or cell_pos.y < anchor.y:
				continue
			if cell_pos.x >= anchor.x + size.x or cell_pos.y >= anchor.y + size.y:
				continue
			var board_number := str(p.get("board_number", key))
			return {"valid": false, "message": "位置 %s 与营销板件重叠: #%s" % [str(cell_pos), board_number]}
	return {"valid": true, "message": ""}

func get_selected_garden_cells() -> Array[Vector2i]:
	if _selected_house_id.is_empty():
		return []
	var house := _get_house(_selected_house_id)
	return _compute_garden_cells(house, _selected_direction)

func get_selected_merged_garden_house_cells() -> Array[Vector2i]:
	if _selected_house_id.is_empty():
		return []
	var house := _get_house(_selected_house_id)
	var cells: Array[Vector2i] = []
	var hv = house.get("cells", [])
	if hv is Array:
		for p in Array(hv):
			if p is Vector2i:
				cells.append(Vector2i(p))
	for p in _compute_garden_cells(house, _selected_direction):
		cells.append(p)
	return cells

func _compute_garden_cells(house: Dictionary, direction: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if house.is_empty():
		return out
	var cells_val = house.get("cells", null)
	if not (cells_val is Array):
		return out
	var any := false
	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	for p_val in Array(cells_val):
		if not (p_val is Vector2i):
			continue
		var p: Vector2i = p_val
		any = true
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)
	if not any:
		return out

	match _normalize_direction(direction):
		"N":
			for x in range(min_x, max_x + 1):
				out.append(Vector2i(x, min_y - 1))
		"S":
			for x in range(min_x, max_x + 1):
				out.append(Vector2i(x, max_y + 1))
		"W":
			for y in range(min_y, max_y + 1):
				out.append(Vector2i(min_x - 1, y))
		"E":
			for y in range(min_y, max_y + 1):
				out.append(Vector2i(max_x + 1, y))
	return out

func _get_house(house_id: String) -> Dictionary:
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return {}
	if not _map_data.has("houses") or not (_map_data["houses"] is Dictionary):
		return {}
	var houses: Dictionary = _map_data["houses"]
	var house_val = houses.get(hid, null)
	if house_val is Dictionary:
		return Dictionary(house_val)
	return {}

func _house_sort_key(house_id: String) -> float:
	var house := _get_house(house_id)
	var hn = house.get("house_number", house_id)
	if hn is int or hn is float:
		return float(hn)
	var s := str(hn)
	if s.is_valid_float():
		return s.to_float()
	return 999999.0


func _format_house_number(value, fallback: String = "?") -> String:
	if value is int:
		return str(int(value))
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return str(int(f))
		return str(snappedf(f, 0.01))
	var s := str(value).strip_edges()
	return s if not s.is_empty() else fallback

func _get_rule_int(key: String, fallback: int) -> int:
	var rules_val = _map_data.get("rules", null)
	if rules_val is Dictionary:
		var rules: Dictionary = rules_val
		var v = rules.get(key, null)
		if v is int:
			return int(v)
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				return int(f)
	return int(fallback)
