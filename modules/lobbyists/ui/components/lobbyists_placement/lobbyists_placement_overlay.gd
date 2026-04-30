class_name LobbyistsPlacementOverlay
extends Control

signal placement_confirmed(action_id: String, position: Vector2i, rotation: int, piece_id: String, employee_type: String, staff_id: int)
signal cancelled()
signal preview_requested(action_id: String, position: Vector2i, rotation: int, piece_id: String)
signal preview_cleared()
signal highlight_requested(action_id: String, rotation: int, piece_id: String)
signal ui_state_changed()

const StaffPickerStateClass = preload("res://ui/components/employee_picker/staff_picker_state.gd")

const ACTION_ROAD := "place_lobbyists_road"
const ACTION_PARK := "place_lobbyists_park"
const INVALID_POS := Vector2i(-1, -1)
const ActionPanelLobbyistsContextScenePath := "res://modules/lobbyists/ui/components/lobbyists_placement/action_panel_lobbyists_placement_context.gd"

var _mode: String = ACTION_ROAD
var _selected_position: Vector2i = INVALID_POS
var _selected_rotation: int = 0
var _piece_sets: Dictionary = {
	ACTION_ROAD: [],
	ACTION_PARK: [],
}
var _selected_piece_by_mode: Dictionary = {}
var _mode_availability: Dictionary = {
	ACTION_ROAD: true,
	ACTION_PARK: true,
}
var _staff_picker_state := StaffPickerStateClass.new(["can_place_lobbyists_road", "can_place_lobbyists_park"])
var _validation_ok: bool = true
var _validation_message: String = ""
var _hint_text: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func get_available_employee_items() -> Array[Dictionary]:
	return _staff_picker_state.get_items()

func get_selected_employee() -> String:
	return _staff_picker_state.get_selected_employee_type()

func get_selected_employee_key() -> String:
	return _staff_picker_state.get_selected_key()

func get_selected_staff_id() -> int:
	return _staff_picker_state.get_selected_staff_id()

func get_available_pieces() -> Array[String]:
	return _get_pieces_for_mode(_mode)

func get_selected_piece() -> String:
	return _get_selected_piece_for_mode(_mode)

func get_piece_display_label(piece_id: String) -> String:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return ""
	var registry = load("res://core/map/piece_registry.gd")
	if registry == null or not registry.has_method("is_loaded") or not bool(registry.call("is_loaded")):
		return pid
	if not registry.has_method("get_def"):
		return pid
	var def_val = registry.call("get_def", pid)
	if def_val != null:
		var name := str(def_val.get("display_name")).strip_edges()
		return name if not name.is_empty() else pid
	return pid

func get_mode_display_label(action_id: String = "") -> String:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		aid = _mode
	match aid:
		ACTION_PARK:
			return "放置公园"
		_:
			return "放置道路"

func is_mode_available(action_id: String) -> bool:
	var aid := _normalize_mode(action_id)
	if not bool(_mode_availability.get(aid, true)):
		return false
	return not _get_pieces_for_mode(aid).is_empty()

func get_action_panel_context_spec() -> Dictionary:
	return {
		"title": "",
		"hint": "",
		"show_chrome": false,
		"show_confirm": false,
		"show_skip_step": false,
		"confirm_text": "",
		"cancel_text": "取消",
		"custom_scene": ActionPanelLobbyistsContextScenePath,
	}

func set_mode(action_id: String) -> void:
	var next := _normalize_mode(action_id)
	if _mode == next:
		_ensure_selected_piece_for_mode(_mode)
		_update_ui()
		_emit_highlight_request()
		ui_state_changed.emit()
		return

	_mode = next
	_selected_position = INVALID_POS
	_selected_rotation = 0
	_validation_ok = true
	_validation_message = ""
	_ensure_selected_piece_for_mode(_mode)
	_update_ui()
	_emit_preview()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_mode_availability(availability: Dictionary) -> void:
	_mode_availability.clear()
	for aid in [ACTION_ROAD, ACTION_PARK]:
		_mode_availability[aid] = bool(availability.get(aid, true))
	if not is_mode_available(_mode):
		if is_mode_available(ACTION_ROAD):
			_mode = ACTION_ROAD
		elif is_mode_available(ACTION_PARK):
			_mode = ACTION_PARK
	_update_ui()
	_emit_preview()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_available_employee_items(items: Array[Dictionary]) -> void:
	_staff_picker_state.set_items(items)
	_update_ui()
	ui_state_changed.emit()

func set_selected_employee_key(employee_key: String) -> void:
	_staff_picker_state.apply_selected_key(str(employee_key).strip_edges())
	_validation_ok = true
	_validation_message = ""
	_update_ui()
	ui_state_changed.emit()

func set_selected_employee(employee_type: String) -> void:
	_staff_picker_state.apply_selected_employee_type(str(employee_type).strip_edges())
	_validation_ok = true
	_validation_message = ""
	_update_ui()
	ui_state_changed.emit()

func set_available_piece_sets(piece_sets: Dictionary) -> void:
	for aid in [ACTION_ROAD, ACTION_PARK]:
		var source_val = piece_sets.get(aid, [])
		var ids := _normalize_piece_ids(source_val if source_val is Array else [])
		_piece_sets[aid] = ids
		_ensure_selected_piece_for_mode(aid)
	if not is_mode_available(_mode):
		if is_mode_available(ACTION_ROAD):
			_mode = ACTION_ROAD
		elif is_mode_available(ACTION_PARK):
			_mode = ACTION_PARK
	_update_ui()
	_emit_preview()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_available_pieces_for_mode(action_id: String, piece_ids: Array[String]) -> void:
	var aid := _normalize_mode(action_id)
	_piece_sets[aid] = _normalize_piece_ids(piece_ids)
	_ensure_selected_piece_for_mode(aid)
	_update_ui()
	_emit_preview()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_available_pieces(piece_ids: Array[String]) -> void:
	set_available_pieces_for_mode(_mode, piece_ids)

func set_selected_piece(piece_id: String) -> void:
	var pid := str(piece_id).strip_edges()
	var pieces := _get_pieces_for_mode(_mode)
	if pid.is_empty():
		_selected_piece_by_mode[_mode] = pieces[0] if not pieces.is_empty() else ""
	elif not pieces.is_empty() and not pieces.has(pid):
		_selected_piece_by_mode[_mode] = pieces[0]
	else:
		_selected_piece_by_mode[_mode] = pid

	_validation_ok = true
	_validation_message = ""
	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func set_selected_position(position: Vector2i) -> void:
	_selected_position = position
	_validation_ok = true
	_validation_message = ""
	_emit_preview()
	_update_ui()
	ui_state_changed.emit()

func set_selected_rotation(rotation: int) -> void:
	_selected_rotation = _normalize_rotation(rotation)
	_validation_ok = true
	_validation_message = ""
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
	_validation_ok = true
	_validation_message = ""
	_staff_picker_state.refresh_selected()
	_ensure_selected_piece_for_mode(_mode)
	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

func can_confirm() -> bool:
	return (
		_validation_ok
		and _selected_position != INVALID_POS
		and not get_selected_piece().is_empty()
		and _selected_employee_can_execute()
	)

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(
		_mode,
		_selected_position,
		_selected_rotation,
		get_selected_piece(),
		get_selected_employee(),
		get_selected_staff_id()
	)

func request_cancel() -> void:
	cancelled.emit()
	visible = false
	preview_cleared.emit()
	_emit_highlight_request()
	ui_state_changed.emit()

func _normalize_mode(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid == ACTION_PARK:
		return ACTION_PARK
	return ACTION_ROAD

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _normalize_piece_ids(piece_ids: Array) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for v in piece_ids:
		var s := str(v).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out

func _get_pieces_for_mode(action_id: String) -> Array[String]:
	var aid := _normalize_mode(action_id)
	var out: Array[String] = []
	var source_val = _piece_sets.get(aid, [])
	if source_val is Array:
		for v in Array(source_val):
			var s := str(v).strip_edges()
			if not s.is_empty():
				out.append(s)
	return out

func _get_selected_piece_for_mode(action_id: String) -> String:
	var aid := _normalize_mode(action_id)
	_ensure_selected_piece_for_mode(aid)
	return str(_selected_piece_by_mode.get(aid, "")).strip_edges()

func _ensure_selected_piece_for_mode(action_id: String) -> void:
	var aid := _normalize_mode(action_id)
	var pieces := _get_pieces_for_mode(aid)
	var selected := str(_selected_piece_by_mode.get(aid, "")).strip_edges()
	if pieces.is_empty():
		_selected_piece_by_mode[aid] = ""
	elif selected.is_empty() or not pieces.has(selected):
		_selected_piece_by_mode[aid] = pieces[0]

func _selected_employee_can_execute() -> bool:
	var key := _staff_picker_state.get_selected_key()
	if key.is_empty():
		return false
	var capability := _capability_for_mode(_mode)
	for item_val in _staff_picker_state.get_items():
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("key", "")).strip_edges() != key:
			continue
		if not bool(item.get("enabled", true)):
			return false
		return bool(item.get(capability, false))
	return false

func _has_any_enabled_employee() -> bool:
	for item_val in _staff_picker_state.get_items():
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if bool(item.get("enabled", true)) and bool(item.get(_capability_for_mode(_mode), false)):
			return true
	return false

func _capability_for_mode(action_id: String) -> String:
	return "can_place_lobbyists_park" if _normalize_mode(action_id) == ACTION_PARK else "can_place_lobbyists_road"

func _update_ui() -> void:
	if not _validation_ok and not _validation_message.is_empty():
		_hint_text = "无法执行：%s" % _validation_message
		return
	if _staff_picker_state.is_empty():
		_hint_text = "没有可用的在岗说客"
		return
	if not _has_any_enabled_employee():
		_hint_text = "本子阶段可用说客次数已用完"
		return
	if get_selected_piece().is_empty():
		_hint_text = "当前效果没有可放置的板块"
		return
	var label := get_piece_display_label(get_selected_piece())
	if _selected_position == INVALID_POS:
		_hint_text = "选择%s板块，然后点击地图上的高亮位置" % label
	else:
		_hint_text = "%s @ (%d,%d) 旋转:%d度" % [
			label,
			_selected_position.x,
			_selected_position.y,
			_selected_rotation,
		]

func _emit_preview() -> void:
	if _selected_position == INVALID_POS:
		preview_cleared.emit()
		return
	preview_requested.emit(_mode, _selected_position, _selected_rotation, get_selected_piece())

func _emit_highlight_request() -> void:
	highlight_requested.emit(_mode, _selected_rotation, get_selected_piece())
