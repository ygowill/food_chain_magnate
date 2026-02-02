# GameLogPanel：动作组标题行（时间线视图）
extends PanelContainer

signal clicked(timeline_index: int)
signal primary_entry_double_clicked(entry_id: int)
signal fold_toggled(step_index: int, expanded: bool)

var step_index: int = -1
var summary: String = ""
var primary_entry_id: int = -1
var fold_enabled: bool = false
var expanded: bool = true
var child_event_count: int = 0

var _label: Label
var _toggle_btn: Button
var _panel_style: StyleBoxFlat = null
var _timeline_is_future: bool = false
var _timeline_is_cursor: bool = false

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.75)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)
	_panel_style = style

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# PhaseHeader 下一级缩进
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	hbox.add_child(spacer)

	_toggle_btn = Button.new()
	_toggle_btn.flat = true
	_toggle_btn.focus_mode = Control.FOCUS_NONE
	_toggle_btn.custom_minimum_size = Vector2(18, 0)
	_toggle_btn.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	hbox.add_child(_toggle_btn)

	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85, 1))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(_label)

	_update_text()
	_apply_timeline_visuals()

func _update_text() -> void:
	var sum := str(summary).strip_edges()
	if sum.is_empty():
		sum = "(无摘要)"
	if fold_enabled and child_event_count > 0 and not expanded:
		_label.text = "%s (+%d)" % [sum, child_event_count]
	else:
		_label.text = sum
	_update_fold_button()

func _update_fold_button() -> void:
	if _toggle_btn == null:
		return
	var can_fold := fold_enabled and child_event_count > 0
	_toggle_btn.visible = can_fold
	if not can_fold:
		return
	_toggle_btn.text = "v" if expanded else ">"

func _on_toggle_pressed() -> void:
	if not fold_enabled:
		return
	if child_event_count <= 0:
		return
	expanded = not expanded
	fold_toggled.emit(step_index, expanded)

func get_timeline_index() -> int:
	return int(step_index)

func apply_timeline_state(cursor_index: int, head_index: int) -> void:
	var cursor := int(cursor_index)
	var head := int(head_index)
	_timeline_is_future = (cursor < head and step_index >= 0 and step_index > cursor)
	_timeline_is_cursor = (step_index == cursor)
	_apply_timeline_visuals()

func _apply_timeline_visuals() -> void:
	if _panel_style != null:
		_panel_style.bg_color = Color(0.20, 0.20, 0.28, 0.85) if _timeline_is_cursor else Color(0.12, 0.12, 0.14, 0.75)
	modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
	if _toggle_btn != null:
		_toggle_btn.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	if _label != null:
		_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	_update_text()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if mb.double_click:
		if primary_entry_id >= 0:
			primary_entry_double_clicked.emit(primary_entry_id)
			return
	clicked.emit(get_timeline_index())

