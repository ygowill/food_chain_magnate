# GameLogPanel：动作组标题行（时间线视图）
extends PanelContainer

signal clicked(timeline_index: int)
signal primary_entry_clicked(entry_id: int)
signal primary_entry_double_clicked(entry_id: int)
signal fold_toggled(step_index: int, expanded: bool)

var step_index: int = -1
var summary: String = ""
var primary_entry_id: int = -1
var primary_entry: Dictionary = {}
var fold_enabled: bool = false
var expanded: bool = true
var child_event_count: int = 0

var _label: RichTextLabel
var _toggle_btn: Button
var _panel_style: StyleBoxFlat = null
var _timeline_is_future: bool = false
var _timeline_is_cursor: bool = false

const EmployeeLinksClass = preload("res://ui/components/game_log/game_log_employee_preview_links.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

func _ready() -> void:
	_build_ui()

func configure_action_group(
	next_step_index: int,
	next_summary: String,
	next_primary_entry_id: int,
	next_primary_entry: Dictionary,
	next_fold_enabled: bool,
	next_expanded: bool,
	next_child_event_count: int
) -> void:
	step_index = int(next_step_index)
	summary = str(next_summary)
	primary_entry_id = int(next_primary_entry_id)
	primary_entry = next_primary_entry.duplicate(true) if (next_primary_entry is Dictionary) else {}
	fold_enabled = bool(next_fold_enabled)
	expanded = bool(next_expanded)
	child_event_count = int(next_child_event_count)
	if _label != null:
		_update_text()
		_apply_timeline_visuals()

func _build_ui() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.91, 0.82, 0.75)
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

	_label = RichTextLabel.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("normal_font_size", maxi(9, int(round(11.0 * scale))))
	_label.add_theme_color_override("default_color", Color(0.17, 0.13, 0.09, 1))
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_label.meta_clicked.connect(_on_label_meta_clicked)
	_label.meta_hover_started.connect(_on_label_meta_hover_started)
	_label.meta_hover_ended.connect(_on_label_meta_hover_ended)
	_label.gui_input.connect(_on_label_gui_input)
	hbox.add_child(_label)

	_update_text()
	_apply_timeline_visuals()

func _update_text() -> void:
	var sum := str(summary).strip_edges()
	if sum.is_empty():
		sum = "(无摘要)"

	var text := sum
	if fold_enabled and child_event_count > 0 and not expanded:
		text = "%s (+%d)" % [sum, child_event_count]

	if _label != null and is_instance_valid(_label):
		var details_val = primary_entry.get("details", null)
		var details: Dictionary = details_val if (details_val is Dictionary) else {}
		EmployeeLinksClass.build_label(_label, text, details)

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
	var next_is_future := (cursor < head and step_index >= 0 and step_index > cursor)
	var next_is_cursor := (step_index == cursor)
	if next_is_future == _timeline_is_future and next_is_cursor == _timeline_is_cursor:
		return
	_timeline_is_future = next_is_future
	_timeline_is_cursor = next_is_cursor
	_apply_timeline_visuals()

func _apply_timeline_visuals() -> void:
	if _panel_style != null:
		_panel_style.bg_color = Color(0.88, 0.82, 0.68, 0.85) if _timeline_is_cursor else Color(0.95, 0.91, 0.82, 0.75)
	modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
	if _toggle_btn != null:
		_toggle_btn.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	if _label != null:
		_label.add_theme_font_size_override("normal_font_size", maxi(9, int(round(11.0 * scale))))
	_update_text()

func _gui_input(event: InputEvent) -> void:
	if not UiPointerInputClass.is_primary_press(event):
		return
	if UiPointerInputClass.is_primary_double_press(event):
		if primary_entry_id >= 0:
			primary_entry_double_clicked.emit(primary_entry_id)
			return
	if primary_entry_id >= 0:
		primary_entry_clicked.emit(primary_entry_id)
		return
	clicked.emit(get_timeline_index())

func _get_preview_manager():
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group("employee_card_preview_manager"):
		if n != null and is_instance_valid(n) and n.has_method("request_preview"):
			return n
	return null

func _show_employee_preview(employee_id: String, immediate: bool) -> void:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		return
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	var pos := get_global_mouse_position()
	if immediate and mgr.has_method("show_immediate"):
		mgr.show_immediate(eid, pos)
	else:
		mgr.request_preview(eid, pos)

func _hide_employee_preview() -> void:
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_preview"):
		mgr.hide_preview()

func _on_label_meta_hover_started(meta) -> void:
	if not EmployeeLinksClass.is_preview_meta(meta):
		return
	var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
	_show_ref_preview(ref, false)

func _on_label_meta_hover_ended(_meta) -> void:
	_hide_employee_preview()

func _on_label_meta_clicked(meta) -> void:
	if not EmployeeLinksClass.is_preview_meta(meta):
		return
	var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
	_show_ref_preview(ref, true)

func _on_label_gui_input(event: InputEvent) -> void:
	# 员工名字点击：显示预览并阻止时间线定位/详情双击。
	if not UiPointerInputClass.is_primary_press(event):
		return
	if _label == null or not is_instance_valid(_label):
		return
	if _label.has_method("get_meta_under_cursor"):
		var meta = _label.call("get_meta_under_cursor")
		if EmployeeLinksClass.is_preview_meta(meta):
			var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
			_show_ref_preview(ref, true)
			_label.accept_event()

func _show_ref_preview(ref: Dictionary, immediate: bool) -> void:
	if ref == null or ref.is_empty():
		return
	var kind := str(ref.get("kind", "")).strip_edges()
	var id := str(ref.get("id", "")).strip_edges()
	if id.is_empty():
		return
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	var pos := get_global_mouse_position()
	if kind == "milestone":
		if immediate and mgr.has_method("show_milestone_immediate"):
			mgr.show_milestone_immediate(id, pos)
		elif mgr.has_method("request_milestone_preview"):
			mgr.request_milestone_preview(id, pos)
		return

	if immediate and mgr.has_method("show_immediate"):
		mgr.show_immediate(id, pos)
	else:
		mgr.request_preview(id, pos)
