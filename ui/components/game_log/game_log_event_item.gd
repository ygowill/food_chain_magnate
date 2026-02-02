# GameLogPanel：动作组子事件条目（时间线视图）
extends PanelContainer

signal entry_clicked(entry_id: int)
signal entry_double_clicked(entry_id: int)

var entry_data: Dictionary = {}
var indent_level: int = 0

var _label: Label
var _panel_style: StyleBoxFlat = null
var _timeline_is_future: bool = false
var _timeline_is_cursor: bool = false

const LOG_TYPE_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6, 1),  # SYSTEM
	1: Color(0.5, 0.7, 0.9, 1),  # PHASE
	2: Color(0.9, 0.9, 0.9, 1),  # PLAYER
	3: Color(0.9, 0.7, 0.4, 1),  # GAME_EVENT
	4: Color(0.5, 0.8, 0.5, 1),  # DEBUG
}

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, float(maxi(22, int(round(22.0 * scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.6)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)
	_panel_style = style

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# 缩进：默认作为 ActionGroup 的子项
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14 + 14 * maxi(0, indent_level - 1), 0)
	hbox.add_child(spacer)

	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(_label)

	update_display()
	_apply_timeline_visuals()

func update_display() -> void:
	if _label == null:
		return
	_label.text = str(entry_data.get("message", ""))
	var t := int(entry_data.get("type", 0))
	_label.add_theme_color_override("font_color", LOG_TYPE_COLORS.get(t, Color(0.85, 0.85, 0.85, 1)))

func get_timeline_index() -> int:
	return _get_entry_timeline_index()

func _get_entry_timeline_index() -> int:
	var si_val = entry_data.get("step_index", null)
	if si_val is int:
		return int(si_val)
	if si_val is float:
		var sf: float = float(si_val)
		if sf == floor(sf):
			return int(sf)
	var ci_val = entry_data.get("command_index", null)
	if ci_val is int:
		return int(ci_val)
	if ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			return int(f)
	return -999

func apply_timeline_state(cursor_index: int, head_index: int) -> void:
	var idx := _get_entry_timeline_index()
	_timeline_is_future = (cursor_index < head_index and idx >= 0 and idx > cursor_index)
	_timeline_is_cursor = (idx == cursor_index)
	_apply_timeline_visuals()

func _apply_timeline_visuals() -> void:
	if _panel_style != null:
		_panel_style.bg_color = Color(0.20, 0.20, 0.28, 0.85) if _timeline_is_cursor else Color(0.12, 0.12, 0.14, 0.6)
	modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	custom_minimum_size = Vector2(0, float(maxi(22, int(round(22.0 * scale)))))
	if _label != null:
		_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var entry_id: int = int(entry_data.get("id", -1))
		if entry_id < 0:
			return
		if event.double_click:
			entry_double_clicked.emit(entry_id)
		else:
			entry_clicked.emit(entry_id)

