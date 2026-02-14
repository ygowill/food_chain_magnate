class_name PanelZoomBar
extends HBoxContainer

signal zoom_changed(zoom_factor: float)

@onready var zoom_out_button: Button = $ZoomOutButton
@onready var zoom_slider: HSlider = $ZoomSlider
@onready var zoom_in_button: Button = $ZoomInButton
@onready var zoom_label: Label = $ZoomLabel

var _min_percent: int = 50
var _max_percent: int = 200
var _step_percent: int = 10
var _zoom_percent: int = 100
var _suppress_slider_signal: bool = false

func _ready() -> void:
	if is_instance_valid(zoom_out_button):
		zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	if is_instance_valid(zoom_in_button):
		zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	if is_instance_valid(zoom_slider):
		zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	_refresh_ui()

func configure(min_percent: int = 50, max_percent: int = 200, step_percent: int = 10, initial_percent: int = 100) -> void:
	_min_percent = maxi(1, int(min_percent))
	_max_percent = maxi(_min_percent, int(max_percent))
	_step_percent = maxi(1, int(step_percent))
	_zoom_percent = _snap_percent(_clamp_percent(int(initial_percent)))
	_refresh_ui()

func set_zoom_percent(percent: int, emit_signal: bool = false) -> void:
	var p := _snap_percent(_clamp_percent(int(percent)))
	if _zoom_percent == p:
		_refresh_ui()
		return
	_zoom_percent = p
	_refresh_ui()
	if emit_signal:
		zoom_changed.emit(get_zoom_factor())

func set_zoom_factor(zoom_factor: float, emit_signal: bool = false) -> void:
	set_zoom_percent(int(round(zoom_factor * 100.0)), emit_signal)

func get_zoom_percent() -> int:
	return _zoom_percent

func get_zoom_factor() -> float:
	return float(_zoom_percent) / 100.0

func set_enabled(enabled: bool) -> void:
	var disabled := not enabled
	if is_instance_valid(zoom_out_button):
		zoom_out_button.disabled = disabled
	if is_instance_valid(zoom_in_button):
		zoom_in_button.disabled = disabled
	if is_instance_valid(zoom_slider):
		zoom_slider.editable = enabled

func _clamp_percent(percent: int) -> int:
	return clampi(percent, _min_percent, _max_percent)

func _snap_percent(percent: int) -> int:
	var clamped := _clamp_percent(percent)
	var offset := clamped - _min_percent
	var steps := int(round(float(offset) / float(_step_percent)))
	return _clamp_percent(_min_percent + steps * _step_percent)

func _refresh_ui() -> void:
	if is_instance_valid(zoom_slider):
		zoom_slider.min_value = float(_min_percent)
		zoom_slider.max_value = float(_max_percent)
		zoom_slider.step = float(_step_percent)
		var target := float(_zoom_percent)
		if not is_equal_approx(zoom_slider.value, target):
			_suppress_slider_signal = true
			zoom_slider.value = target
			_suppress_slider_signal = false
	if is_instance_valid(zoom_label):
		zoom_label.text = "%d%%" % _zoom_percent

func _on_zoom_out_pressed() -> void:
	set_zoom_percent(_zoom_percent - _step_percent, true)

func _on_zoom_in_pressed() -> void:
	set_zoom_percent(_zoom_percent + _step_percent, true)

func _on_zoom_slider_changed(value: float) -> void:
	if _suppress_slider_signal:
		return
	set_zoom_percent(int(round(value)), true)
