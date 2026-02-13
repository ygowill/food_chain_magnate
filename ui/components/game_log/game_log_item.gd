# GameLogPanel：平铺日志条目（legacy/tests）
extends PanelContainer

signal entry_clicked(entry_id: int)
signal entry_double_clicked(entry_id: int)

var entry_data: Dictionary = {}
var log_type: int = 0

var _time_label: Label
var _type_label: Label
var _message_label: RichTextLabel
var _panel_style: StyleBoxFlat = null
var _timeline_is_future: bool = false
var _timeline_is_cursor: bool = false

const EmployeeLinksClass = preload("res://ui/components/game_log/game_log_employee_preview_links.gd")

const LOG_TYPE_COLORS: Dictionary = {
	0: Color(0.5, 0.45, 0.35, 1),  # SYSTEM
	1: Color(0.2, 0.4, 0.6, 1),  # PHASE
	2: Color(0.17, 0.13, 0.09, 1),  # PLAYER
	3: Color(0.6, 0.4, 0.15, 1),  # GAME_EVENT
	4: Color(0.28, 0.55, 0.22, 1),  # DEBUG
}

const LOG_TYPE_NAMES: Dictionary = {
	0: "系统",
	1: "阶段",
	2: "玩家",
	3: "事件",
	4: "调试",
}

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, float(maxi(28, int(round(28.0 * scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.91, 0.82, 0.6)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)
	_panel_style = style

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# 时间
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(50, 0)
	_time_label.add_theme_font_size_override("font_size", maxi(8, int(round(10.0 * scale))))
	_time_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	hbox.add_child(_time_label)

	# 类型
	_type_label = Label.new()
	_type_label.custom_minimum_size = Vector2(40, 0)
	_type_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	hbox.add_child(_type_label)

	# 消息
	_message_label = RichTextLabel.new()
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.add_theme_font_size_override("normal_font_size", maxi(10, int(round(12.0 * scale))))
	_message_label.bbcode_enabled = false
	_message_label.fit_content = true
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.scroll_active = false
	_message_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_message_label.meta_clicked.connect(_on_message_meta_clicked)
	_message_label.meta_hover_started.connect(_on_message_meta_hover_started)
	_message_label.meta_hover_ended.connect(_on_message_meta_hover_ended)
	_message_label.gui_input.connect(_on_message_gui_input)
	hbox.add_child(_message_label)

	update_display()
	_apply_timeline_visuals()

func apply_timeline_state(cursor_index: int, head_index: int) -> void:
	var cmd_index := _get_entry_command_index()
	_timeline_is_future = (cursor_index < head_index and cmd_index >= 0 and cmd_index > cursor_index)
	_timeline_is_cursor = (cmd_index == cursor_index)
	_apply_timeline_visuals()

func get_timeline_index() -> int:
	return _get_entry_command_index()

func _get_entry_command_index() -> int:
	# timeline index: prefer step_index (M4.2), fallback to command_index.
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
	var details_val = entry_data.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var si2_val = details.get("step_index", null)
		if si2_val is int:
			return int(si2_val)
		if si2_val is float:
			var sf2: float = float(si2_val)
			if sf2 == floor(sf2):
				return int(sf2)
		var ci2_val = details.get("command_index", null)
		if ci2_val is int:
			return int(ci2_val)
		if ci2_val is float:
			var f2: float = float(ci2_val)
			if f2 == floor(f2):
				return int(f2)
	return -999

func _apply_timeline_visuals() -> void:
	if _panel_style != null:
		_panel_style.bg_color = Color(0.88, 0.82, 0.68, 0.85) if _timeline_is_cursor else Color(0.95, 0.91, 0.82, 0.6)

	if _timeline_is_cursor:
		modulate = Color(1, 1, 1, 1)
	elif _timeline_is_future:
		modulate = Color(0.85, 0.85, 0.85, 0.55)
	else:
		modulate = Color(1, 1, 1, 1)

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
	custom_minimum_size = Vector2(0, float(maxi(28, int(round(28.0 * scale)))))
	if _time_label != null:
		_time_label.add_theme_font_size_override("font_size", maxi(8, int(round(10.0 * scale))))
	if _type_label != null:
		_type_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
	if _message_label != null:
		_message_label.add_theme_font_size_override("normal_font_size", maxi(10, int(round(12.0 * scale))))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var entry_id: int = int(entry_data.get("id", -1))
			if entry_id < 0:
				return
			if event.double_click:
				entry_double_clicked.emit(entry_id)
			else:
				entry_clicked.emit(entry_id)

func update_display() -> void:
	if _time_label != null:
		var timestamp: String = str(entry_data.get("timestamp", ""))
		# 只显示时间部分
		if timestamp.length() >= 8:
			_time_label.text = timestamp.substr(timestamp.length() - 8, 5)
		else:
			_time_label.text = timestamp

	if _type_label != null:
		var type_name: String = LOG_TYPE_NAMES.get(log_type, "?")
		_type_label.text = "[%s]" % type_name
		var type_color: Color = LOG_TYPE_COLORS.get(log_type, Color.WHITE)
		_type_label.add_theme_color_override("font_color", type_color)

	if _message_label != null:
		var msg := str(entry_data.get("message", ""))
		var details_val = entry_data.get("details", null)
		var details: Dictionary = details_val if (details_val is Dictionary) else {}
		EmployeeLinksClass.build_label(_message_label, msg, details)

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

func _on_message_meta_hover_started(meta) -> void:
	if not EmployeeLinksClass.is_preview_meta(meta):
		return
	var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
	_show_ref_preview(ref, false)

func _on_message_meta_hover_ended(_meta) -> void:
	_hide_employee_preview()

func _on_message_meta_clicked(meta) -> void:
	if not EmployeeLinksClass.is_preview_meta(meta):
		return
	var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
	_show_ref_preview(ref, true)

func _on_message_gui_input(event: InputEvent) -> void:
	# 员工名字点击：显示预览并阻止行点击（不影响其它区域的行点击/双击）。
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _message_label == null or not is_instance_valid(_message_label):
		return
	if _message_label.has_method("get_meta_under_cursor"):
		var meta = _message_label.call("get_meta_under_cursor")
		if EmployeeLinksClass.is_preview_meta(meta):
			var ref := EmployeeLinksClass.preview_ref_from_meta(meta)
			_show_ref_preview(ref, true)
			_message_label.accept_event()

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

	# 默认 employee
	if immediate and mgr.has_method("show_immediate"):
		mgr.show_immediate(id, pos)
	else:
		mgr.request_preview(id, pos)
