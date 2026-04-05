# 通用“板块放置”覆盖层组件
# - 用于收集 piece_id + anchor_pos + rotation（参数名由调用方负责匹配动作执行器）
# - 地图选点由 GameMapInteractionController 根据 mode 决定如何回填
class_name PiecePlacementOverlay
extends Control

signal placement_confirmed(position: Vector2i, rotation: int, piece_id: String)
signal cancelled()
signal preview_requested(action_id: String, position: Vector2i, rotation: int, piece_id: String)
signal preview_cleared()
signal highlight_requested(action_id: String, rotation: int, piece_id: String)
signal ui_state_changed()

const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

@onready var hint_label: Label = $HintMargin/HintPanel/HintLabel
@onready var hint_margin: Control = $HintMargin

var _mode: String = "" # action_id
var _selected_position: Vector2i = Vector2i(-1, -1)
var _selected_rotation: int = 0
var _available_pieces: Array[String] = []
var _selected_piece_id: String = ""

var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(hint_margin):
		hint_margin.visible = false
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

func can_rotate() -> bool:
	return true

func get_available_pieces() -> Array[String]:
	return _available_pieces.duplicate()

func get_selected_piece() -> String:
	return _selected_piece_id

func get_piece_display_label(piece_id: String) -> String:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return ""
	if not PieceRegistryClass.is_loaded():
		return pid
	var def_val = PieceRegistryClass.get_def(pid)
	if def_val != null and (def_val is PieceDef):
		var def: PieceDef = def_val
		var name := str(def.display_name).strip_edges()
		return name if not name.is_empty() else pid
	return pid

func set_mode(action_id: String) -> void:
	_mode = str(action_id).strip_edges()
	clear_selection()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func set_available_pieces(piece_ids: Array[String]) -> void:
	var ids: Array[String] = []
	var seen := {}
	for v in piece_ids:
		var s := str(v).strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		ids.append(s)
	_available_pieces = ids

	if _available_pieces.is_empty():
		_selected_piece_id = ""
	elif _selected_piece_id.is_empty() or not _available_pieces.has(_selected_piece_id):
		_selected_piece_id = _available_pieces[0]

	_emit_preview()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func set_selected_piece(piece_id: String) -> void:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		_selected_piece_id = "" if _available_pieces.is_empty() else _available_pieces[0]
	elif not _available_pieces.is_empty() and not _available_pieces.has(pid):
		_selected_piece_id = _available_pieces[0]
	else:
		_selected_piece_id = pid

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
	_validation_ok = true
	_validation_message = ""
	if _available_pieces.is_empty():
		_selected_piece_id = ""
	elif _selected_piece_id.is_empty() or not _available_pieces.has(_selected_piece_id):
		_selected_piece_id = _available_pieces[0]
	_emit_preview()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

func can_confirm() -> bool:
	return (not _selected_piece_id.is_empty()) and (_selected_position != Vector2i(-1, -1)) and _validation_ok

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(_selected_position, _selected_rotation, _selected_piece_id)

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

	if _selected_piece_id.is_empty():
		hint_label.text = "请选择要放置的板块"
		return

	var label := get_piece_display_label(_selected_piece_id)
	if _selected_position == Vector2i(-1, -1):
		hint_label.text = "已选择: %s，请在地图上点击放置位置" % label
		return

	hint_label.text = "%s @ (%d,%d) 旋转:%d度" % [
		label,
		_selected_position.x,
		_selected_position.y,
		_selected_rotation,
	]

func _emit_preview() -> void:
	if _selected_position == Vector2i(-1, -1):
		preview_cleared.emit()
		return
	preview_requested.emit(_mode, _selected_position, _selected_rotation, _selected_piece_id)

func _emit_highlight_request() -> void:
	highlight_requested.emit(_mode, _selected_rotation, _selected_piece_id)
