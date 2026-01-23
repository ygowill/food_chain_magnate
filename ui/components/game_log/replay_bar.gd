# 回放控制条（嵌入式）
# 说明：仅负责展示与发射交互信号；具体 seek/load/退出逻辑由 GameScene 处理。
extends PanelContainer

signal seek_requested(target_index: int)
signal load_requested()
signal close_requested()
signal return_latest_requested()

@onready var load_button: Button = $MarginContainer/HBox/LoadButton
@onready var first_button: Button = $MarginContainer/HBox/FirstButton
@onready var prev_button: Button = $MarginContainer/HBox/PrevButton
@onready var next_button: Button = $MarginContainer/HBox/NextButton
@onready var last_button: Button = $MarginContainer/HBox/LastButton
@onready var latest_button: Button = $MarginContainer/HBox/LatestButton
@onready var close_button: Button = $MarginContainer/HBox/CloseButton
@onready var slider: HSlider = $MarginContainer/HBox/Slider
@onready var status_label: Label = $MarginContainer/HBox/StatusLabel

var _head_index: int = -1
var _cursor_index: int = -1
var _read_only: bool = false
var _suppress_slider_signal: bool = false

func _ready() -> void:
	_connect_signals()
	_update_ui()

func set_timeline(head_index: int, cursor_index: int, read_only: bool) -> void:
	_head_index = int(head_index)
	_cursor_index = int(cursor_index)
	_read_only = bool(read_only)
	_update_ui()

func set_active(visible_active: bool) -> void:
	visible = bool(visible_active)

func _connect_signals() -> void:
	if is_instance_valid(load_button):
		load_button.pressed.connect(func() -> void:
			load_requested.emit()
		)
	if is_instance_valid(close_button):
		close_button.pressed.connect(func() -> void:
			close_requested.emit()
		)
	if is_instance_valid(latest_button):
		latest_button.pressed.connect(func() -> void:
			return_latest_requested.emit()
		)
	if is_instance_valid(first_button):
		first_button.pressed.connect(func() -> void:
			seek_requested.emit(-1)
		)
	if is_instance_valid(prev_button):
		prev_button.pressed.connect(func() -> void:
			seek_requested.emit(_cursor_index - 1)
		)
	if is_instance_valid(next_button):
		next_button.pressed.connect(func() -> void:
			seek_requested.emit(_cursor_index + 1)
		)
	if is_instance_valid(last_button):
		last_button.pressed.connect(func() -> void:
			seek_requested.emit(_head_index)
		)
	if is_instance_valid(slider):
		slider.value_changed.connect(_on_slider_value_changed)

func _on_slider_value_changed(value: float) -> void:
	if _suppress_slider_signal:
		return
	seek_requested.emit(int(value))

func _update_ui() -> void:
	if status_label != null:
		var mode := "只读回放" if _read_only else "时间线"
		status_label.text = "%s：%d / %d" % [mode, _cursor_index, _head_index]

	if slider != null:
		_suppress_slider_signal = true
		slider.min_value = -1
		slider.max_value = maxi(-1, _head_index)
		slider.step = 1
		slider.value = clampi(_cursor_index, -1, _head_index)
		_suppress_slider_signal = false

	var has_timeline := _head_index >= -1
	var at_first := _cursor_index <= -1
	var at_last := (_cursor_index >= _head_index and _head_index >= -1)

	if first_button != null:
		first_button.disabled = not has_timeline or at_first
	if prev_button != null:
		prev_button.disabled = not has_timeline or at_first
	if next_button != null:
		next_button.disabled = not has_timeline or at_last
	if last_button != null:
		last_button.disabled = not has_timeline or at_last

	if latest_button != null:
		latest_button.disabled = not has_timeline or (_cursor_index == _head_index)
