# 右侧 Dock 面板可嵌入控件的通用基类：
# - 统一 set_embedded_in_right_panel / footer 配置 / relayout 调度
# - 避免每个面板重复 _ready 样板
class_name RightPanelEmbeddablePanel
extends Control

signal right_panel_footer_changed()

const UiNodeAccessClass = preload("res://ui/utils/node_access.gd")

const _DEFAULT_BUTTON_ROW_PATH := NodePath("MarginContainer/VBoxContainer/ButtonRow")

var _embedded_in_right_panel: bool = false
var _base_custom_minimum_size: Vector2 = Vector2.ZERO
var _relayout_scheduled: bool = false

func _ready() -> void:
	_capture_base_custom_minimum_size()
	_connect_common_signals()
	_connect_footer_buttons()

	_on_panel_ready()

	right_panel_footer_changed.emit()
	_request_relayout()

func set_embedded_in_right_panel(embedded: bool) -> void:
	_embedded_in_right_panel = embedded
	_capture_base_custom_minimum_size()
	custom_minimum_size = Vector2.ZERO if embedded else _base_custom_minimum_size
	_apply_embedding(embedded)
	right_panel_footer_changed.emit()
	_request_relayout()

func is_embedded_in_right_panel() -> bool:
	return _embedded_in_right_panel

func right_panel_get_footer_config() -> Dictionary:
	var confirm := _get_confirm_button()
	if confirm == null or not is_instance_valid(confirm):
		return {}
	return {
		"show_cancel": true,
		"cancel_text": "取消",
		"cancel_enabled": true,
		"show_primary": true,
		"primary_text": str(confirm.text),
		"primary_enabled": not confirm.disabled,
	}

func right_panel_footer_primary() -> void:
	_on_confirm_pressed()

func _capture_base_custom_minimum_size() -> void:
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size

func _connect_common_signals() -> void:
	var cb := Callable(self, "_request_relayout")
	if not resized.is_connected(cb):
		resized.connect(cb)
	if not visibility_changed.is_connected(cb):
		visibility_changed.connect(cb)

func _connect_footer_buttons() -> void:
	var confirm := _get_confirm_button()
	if confirm != null and is_instance_valid(confirm):
		var cb_confirm := Callable(self, "_on_confirm_pressed")
		if not confirm.pressed.is_connected(cb_confirm):
			confirm.pressed.connect(cb_confirm)
		# 通用约定：面板初始默认不可确认；由子类在数据同步后解锁
		confirm.disabled = true

	var cancel := _get_cancel_button()
	if cancel != null and is_instance_valid(cancel):
		var cb_cancel := Callable(self, "_on_cancel_pressed")
		if not cancel.pressed.is_connected(cb_cancel):
			cancel.pressed.connect(cb_cancel)

func _apply_embedding(embedded: bool) -> void:
	var row := UiNodeAccessClass.get_control(self, _DEFAULT_BUTTON_ROW_PATH)
	if row != null:
		row.visible = not embedded

func _request_relayout() -> void:
	if _relayout_scheduled:
		return
	_relayout_scheduled = true
	call_deferred("_apply_relayout_internal")

func _apply_relayout_internal() -> void:
	_relayout_scheduled = false
	if not is_inside_tree():
		return

	var frames := maxi(0, int(_get_relayout_delay_frames()))
	for _i in range(frames):
		await get_tree().process_frame
		if not is_inside_tree():
			return

	_on_relayout()

# === Hooks (override in subclasses) ===

func _on_panel_ready() -> void:
	pass

func _on_confirm_pressed() -> void:
	pass

func _on_cancel_pressed() -> void:
	pass

func _get_confirm_button() -> Button:
	return null

func _get_cancel_button() -> Button:
	return null

func _get_relayout_delay_frames() -> int:
	return 0

func _on_relayout() -> void:
	pass
