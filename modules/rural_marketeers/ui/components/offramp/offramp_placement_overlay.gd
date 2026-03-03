class_name RuralMarketeersOfframpPlacementOverlay
extends Control

signal placement_confirmed(connect_pos: Vector2i)
signal ui_state_changed()

var _has_selected_target: bool = false
var _selected_connect_pos: Vector2i = Vector2i(-1, -1)
var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func get_selected_position() -> Vector2i:
	return _selected_connect_pos

func set_selected_target(connect_pos: Vector2i) -> void:
	_has_selected_target = true
	_selected_connect_pos = Vector2i(connect_pos)
	_validation_ok = true
	_validation_message = ""
	ui_state_changed.emit()

func clear_target() -> void:
	_has_selected_target = false
	_selected_connect_pos = Vector2i(-1, -1)
	_validation_ok = true
	_validation_message = ""
	ui_state_changed.emit()

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = bool(valid)
	_validation_message = str(message).strip_edges()
	ui_state_changed.emit()

func can_confirm() -> bool:
	return _has_selected_target and _validation_ok and _selected_connect_pos != Vector2i(-1, -1)

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(_selected_connect_pos)

func request_cancel() -> void:
	# "重新选择"：清除当前目标，但保持 context 不关闭（由 ActionPanelContextController 控制）。
	clear_target()

func get_hint_text() -> String:
	if not _validation_ok and not _validation_message.is_empty():
		return "无法放置：%s" % _validation_message
	if not _has_selected_target:
		return "请点击地图上高亮的边缘道路格，选择高速公路出口的连接位置"
	return "已选择连接格: %s" % str(_selected_connect_pos)

func get_action_panel_context_spec() -> Dictionary:
	return {
		"title": "放置高速公路出口",
		"hint": get_hint_text(),
		"confirm_text": "确认放置",
		"cancel_text": "重新选择",
		"clear_on_cancel": false
	}
