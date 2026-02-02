# GameLogPanel：回合标题行（时间线视图）
extends PanelContainer

signal clicked(timeline_index: int)

# 点击跳转到该回合段落的第一条 ActionGroup（即 start_step_index）
var round_number: int = -1
var start_step_index: int = -1

var _label: Label
var _panel_style: StyleBoxFlat = null
var _timeline_is_future: bool = false

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, float(maxi(24, int(round(24.0 * scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.9)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)
	_panel_style = style

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))
	_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(_label)

	var rn := int(round_number)
	_label.text = ("回合 %d" % rn) if rn > 0 else "回合 ?"
	_apply_timeline_visuals()

func get_timeline_index() -> int:
	return int(start_step_index)

func apply_timeline_state(cursor_index: int, head_index: int) -> void:
	var cursor := int(cursor_index)
	var head := int(head_index)
	_timeline_is_future = (cursor < head and start_step_index >= 0 and start_step_index > cursor)
	_apply_timeline_visuals()

func _apply_timeline_visuals() -> void:
	modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	custom_minimum_size = Vector2(0, float(maxi(24, int(round(24.0 * scale)))))
	if _label != null:
		_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(get_timeline_index())

