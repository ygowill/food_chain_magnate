# 回放控制条（嵌入式）
# 说明：仅负责展示与发射交互信号；具体 seek/load/退出逻辑由 GameScene 处理。
extends PanelContainer

signal seek_requested(target_index: int)

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const COLOR_SLIDER_TRACK := Color(0.86, 0.81, 0.70, 0.95)
const COLOR_SLIDER_BORDER := Color(0.17, 0.13, 0.09, 0.26)
const COLOR_SLIDER_FILL := Color(0.73, 0.23, 0.18, 0.32)
const COLOR_SLIDER_FILL_HOVER := Color(0.73, 0.23, 0.18, 0.45)

@onready var first_button: Button = $MarginContainer/VBox/BottomRow/FirstButton
@onready var prev_button: Button = $MarginContainer/VBox/BottomRow/PrevButton
@onready var next_button: Button = $MarginContainer/VBox/BottomRow/NextButton
@onready var last_button: Button = $MarginContainer/VBox/BottomRow/LastButton
@onready var slider: HSlider = $MarginContainer/VBox/TopRow/Slider
@onready var status_label: Label = $MarginContainer/VBox/TopRow/StatusLabel

var _head_index: int = -1
var _cursor_index: int = -1
var _read_only: bool = false
var _status_extra: String = ""
var _suppress_slider_signal: bool = false

func _ready() -> void:
	_apply_theme()
	_connect_signals()
	_update_ui()

func set_timeline(head_index: int, cursor_index: int, read_only: bool, status_extra: String = "") -> void:
	_head_index = int(head_index)
	_cursor_index = int(cursor_index)
	_read_only = bool(read_only)
	_status_extra = str(status_extra).strip_edges()
	_update_ui()

func set_active(visible_active: bool) -> void:
	visible = bool(visible_active)

func _connect_signals() -> void:
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

func _apply_theme() -> void:
	UiStylesClass.apply_panel_poster_alt(self)
	var buttons: Array[Button] = [
		first_button,
		prev_button,
		next_button,
		last_button,
	]
	for btn in buttons:
		if btn == null:
			continue
		UiStylesClass.apply_button_secondary(btn)
		btn.add_theme_font_size_override("font_size", 12)

	if status_label != null:
		UiStylesClass.apply_label_dark(status_label)
		status_label.add_theme_font_size_override("font_size", 12)

	if slider != null:
		slider.add_theme_stylebox_override("slider", _make_slider_track_style())
		slider.add_theme_stylebox_override("grabber_area", _make_slider_fill_style(COLOR_SLIDER_FILL))
		slider.add_theme_stylebox_override("grabber_area_highlight", _make_slider_fill_style(COLOR_SLIDER_FILL_HOVER))

func _make_slider_track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SLIDER_TRACK
	style.border_color = COLOR_SLIDER_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_top = 2
	style.content_margin_right = 0
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style

func _make_slider_fill_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(bg.r, bg.g, bg.b, 0.9)
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_top = 2
	style.content_margin_right = 0
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style

func _update_ui() -> void:
	if status_label != null:
		var mode := "只读回放" if _read_only else "时间线"
		var extra := (" | %s" % _status_extra) if not _status_extra.is_empty() else ""
		status_label.text = "%s：%d / %d%s" % [mode, _cursor_index, _head_index, extra]

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
