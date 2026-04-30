extends VBoxContainer

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

const ROTATE_CCW_ICON_PATH := "res://assets/ui/icons/kenney/board/arrow_counterclockwise.png"
const ROTATE_CW_ICON_PATH := "res://assets/ui/icons/kenney/board/arrow_clockwise.png"

const ACTION_ROAD := "place_lobbyists_road"
const ACTION_PARK := "place_lobbyists_park"

var _overlay: Node = null
var _syncing: bool = false

var _employee_row: VBoxContainer = null
var _employee_picker = null
var _effect_row: HBoxContainer = null
var _road_button: Button = null
var _park_button: Button = null
var _hint_label: Label = null
var _piece_section: VBoxContainer = null
var _piece_flow: HFlowContainer = null
var _rotate_left_button: Button = null
var _rotation_value_label: Label = null
var _rotate_right_button: Button = null
var _summary_label: Label = null
var _confirm_button: Button = null

func _ready() -> void:
	_build_ui()

func bind_overlay(overlay: Node) -> void:
	_overlay = overlay
	sync_from_overlay()

func sync_from_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	_build_ui()
	_syncing = true
	var mode := _get_overlay_mode()
	_sync_employee_buttons()
	_sync_effect_buttons(mode)
	_sync_hint()
	_sync_piece_section()
	_sync_rotation()
	_sync_summary()
	_sync_confirm_button(mode)
	_syncing = false

func _build_ui() -> void:
	if _employee_row != null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_employee_row = VBoxContainer.new()
	_employee_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_row.add_theme_constant_override("separation", 6)
	add_child(_employee_row)

	var employee_label := Label.new()
	employee_label.text = "选择员工"
	UiStylesClass.apply_label_dark(employee_label)
	_employee_row.add_child(employee_label)

	_employee_picker = EmployeePickerClass.new()
	_employee_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_picker.add_theme_constant_override("h_separation", 10)
	_employee_picker.add_theme_constant_override("v_separation", 10)
	_employee_picker.set("card_display_scale", 1.25)
	_employee_row.add_child(_employee_picker)
	if _employee_picker.has_signal("employee_selected"):
		_employee_picker.employee_selected.connect(_on_employee_picker_selected)

	var effect_label := Label.new()
	effect_label.text = "选择效果"
	UiStylesClass.apply_label_dark(effect_label)
	add_child(effect_label)

	_effect_row = HBoxContainer.new()
	_effect_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_row.add_theme_constant_override("separation", 8)
	add_child(_effect_row)

	_road_button = Button.new()
	_road_button.text = "放置道路"
	_road_button.toggle_mode = true
	_road_button.custom_minimum_size = Vector2(0, 36)
	_road_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_road_button)
	_effect_row.add_child(_road_button)
	_road_button.pressed.connect(_on_road_pressed)

	_park_button = Button.new()
	_park_button.text = "放置公园"
	_park_button.toggle_mode = true
	_park_button.custom_minimum_size = Vector2(0, 36)
	_park_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_park_button)
	_effect_row.add_child(_park_button)
	_park_button.pressed.connect(_on_park_pressed)

	var hint_panel := PanelContainer.new()
	hint_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster_alt(hint_panel)
	add_child(hint_panel)

	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 8)
	hint_margin.add_theme_constant_override("margin_top", 6)
	hint_margin.add_theme_constant_override("margin_right", 8)
	hint_margin.add_theme_constant_override("margin_bottom", 6)
	hint_panel.add_child(hint_margin)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_hint_label)
	hint_margin.add_child(_hint_label)

	_piece_section = VBoxContainer.new()
	_piece_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_piece_section.add_theme_constant_override("separation", 6)
	add_child(_piece_section)

	var piece_label := Label.new()
	piece_label.text = "选择板块"
	UiStylesClass.apply_label_dark(piece_label)
	_piece_section.add_child(piece_label)

	_piece_flow = HFlowContainer.new()
	_piece_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_piece_flow.add_theme_constant_override("h_separation", 6)
	_piece_flow.add_theme_constant_override("v_separation", 6)
	_piece_section.add_child(_piece_flow)

	var rotation_label := Label.new()
	rotation_label.text = "旋转"
	UiStylesClass.apply_label_dark(rotation_label)
	add_child(rotation_label)

	var rotation_row := HBoxContainer.new()
	rotation_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_row.add_theme_constant_override("separation", 6)
	add_child(rotation_row)

	_rotate_left_button = Button.new()
	_rotate_left_button.text = ""
	_rotate_left_button.tooltip_text = "向左旋转"
	_rotate_left_button.custom_minimum_size = Vector2(44, 34)
	UiStylesClass.apply_button_secondary(_rotate_left_button)
	_add_button_icon(_rotate_left_button, ROTATE_CCW_ICON_PATH)
	rotation_row.add_child(_rotate_left_button)
	_rotate_left_button.pressed.connect(_on_rotate_left_pressed)

	_rotation_value_label = Label.new()
	_rotation_value_label.text = "默认朝向"
	_rotation_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotation_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rotation_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_label_dark(_rotation_value_label)
	rotation_row.add_child(_rotation_value_label)

	_rotate_right_button = Button.new()
	_rotate_right_button.text = ""
	_rotate_right_button.tooltip_text = "向右旋转"
	_rotate_right_button.custom_minimum_size = Vector2(44, 34)
	UiStylesClass.apply_button_secondary(_rotate_right_button)
	_add_button_icon(_rotate_right_button, ROTATE_CW_ICON_PATH)
	rotation_row.add_child(_rotate_right_button)
	_rotate_right_button.pressed.connect(_on_rotate_right_pressed)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_summary_label)
	add_child(_summary_label)

	_confirm_button = Button.new()
	_confirm_button.custom_minimum_size = Vector2(0, 36)
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_confirm_button)
	add_child(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)

func _add_button_icon(button: Button, texture_path: String) -> void:
	if button == null:
		return
	var texture = load(str(texture_path).strip_edges())
	if not (texture is Texture2D):
		return
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture as Texture2D
	icon.modulate = Color(0.07, 0.07, 0.07, 1)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)

func _sync_employee_buttons() -> void:
	var items_val = _safe_call("get_available_employee_items", [])
	var items: Array[Dictionary] = []
	if items_val is Array:
		for item_val in Array(items_val):
			if item_val is Dictionary:
				items.append(Dictionary(item_val))
	_employee_row.visible = not items.is_empty()
	if not is_instance_valid(_employee_picker):
		return
	if items.is_empty():
		if _employee_picker.has_method("clear"):
			_employee_picker.call("clear")
		return
	var selected_key := str(_safe_call("get_selected_employee_key", "")).strip_edges()
	if _employee_picker.has_method("set_items"):
		_employee_picker.call("set_items", items, selected_key)

func _sync_effect_buttons(mode: String) -> void:
	_road_button.set_pressed_no_signal(mode == ACTION_ROAD)
	_park_button.set_pressed_no_signal(mode == ACTION_PARK)
	_road_button.disabled = not bool(_safe_call("is_mode_available", true, [ACTION_ROAD]))
	_park_button.disabled = not bool(_safe_call("is_mode_available", true, [ACTION_PARK]))

func _sync_hint() -> void:
	_hint_label.text = str(_safe_call("get_hint_text", ""))

func _sync_piece_section() -> void:
	for child in _piece_flow.get_children():
		child.queue_free()

	var pieces: Array[String] = []
	var pieces_val = _safe_call("get_available_pieces", [])
	if pieces_val is Array:
		for v in Array(pieces_val):
			var pid := str(v).strip_edges()
			if not pid.is_empty():
				pieces.append(pid)

	if pieces.is_empty():
		var empty_label := Label.new()
		empty_label.text = "无可用板块"
		UiStylesClass.apply_label_hint_dark(empty_label)
		_piece_flow.add_child(empty_label)
		return

	var selected := str(_safe_call("get_selected_piece", "")).strip_edges()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for pid in pieces:
		var label := _piece_button_label(pid)
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(74, 34)
		btn.button_group = group
		btn.set_pressed_no_signal(pid == selected)
		UiStylesClass.apply_button_secondary(btn)
		btn.pressed.connect(_on_piece_pressed.bind(pid))
		btn.tooltip_text = label if not label.is_empty() else pid
		_piece_flow.add_child(btn)

func _piece_button_label(piece_id: String) -> String:
	var pid := str(piece_id).strip_edges()
	var label := str(_safe_call("get_piece_display_label", pid, [pid])).strip_edges()
	if label.is_empty():
		label = pid
	match pid:
		"lobbyists_road_straight":
			return "短道路"
		"lobbyists_road_long":
			return "长道路"
		"lobbyists_road_l":
			return "转角道路"
		"lobbyists_park_line":
			return "直线公园"
		"lobbyists_park_t":
			return "T形公园"
		"lobbyists_park_l":
			return "转角公园"
		_:
			return label

func _sync_rotation() -> void:
	var rot := int(_safe_call("get_selected_rotation", 0))
	_rotation_value_label.text = _rotation_label(rot)

func _sync_summary() -> void:
	var piece_id := str(_safe_call("get_selected_piece", "")).strip_edges()
	var label := str(_safe_call("get_piece_display_label", piece_id, [piece_id])).strip_edges()
	if label.is_empty():
		label = piece_id
	var pos := Vector2i(-1, -1)
	var pos_val = _safe_call("get_selected_position", Vector2i(-1, -1))
	if pos_val is Vector2i:
		pos = Vector2i(pos_val)
	if piece_id.is_empty():
		_summary_label.text = "先选择要放置的板块。"
	elif pos == Vector2i(-1, -1):
		_summary_label.text = "已选择%s。请点击地图上的高亮位置。" % label
	else:
		_summary_label.text = "已选择%s，位置 (%d,%d)。" % [label, pos.x, pos.y]

func _sync_confirm_button(mode: String) -> void:
	_confirm_button.text = "确认放置公园" if mode == ACTION_PARK else "确认放置道路"
	_confirm_button.disabled = not bool(_safe_call("can_confirm", false))

func _get_overlay_mode() -> String:
	return str(_safe_call("get_mode", ACTION_ROAD)).strip_edges()

func _safe_call(method: StringName, fallback, args: Array = []):
	if _overlay == null or not is_instance_valid(_overlay):
		return fallback
	if not _overlay.has_method(method):
		return fallback
	return _overlay.callv(method, args)

func _on_employee_picker_selected(_employee_type: String) -> void:
	if _syncing:
		return
	if not is_instance_valid(_employee_picker):
		return
	var key := ""
	if _employee_picker.has_method("get_selected_key"):
		key = str(_employee_picker.get_selected_key()).strip_edges()
	if key.is_empty():
		return
	_safe_call("set_selected_employee_key", null, [key])

func _on_road_pressed() -> void:
	if _syncing:
		return
	_safe_call("set_mode", null, [ACTION_ROAD])

func _on_park_pressed() -> void:
	if _syncing:
		return
	_safe_call("set_mode", null, [ACTION_PARK])

func _on_piece_pressed(piece_id: String) -> void:
	if _syncing:
		return
	_safe_call("set_selected_piece", null, [piece_id])

func _on_rotate_left_pressed() -> void:
	if _syncing:
		return
	_rotate_selected(-90)

func _on_rotate_right_pressed() -> void:
	if _syncing:
		return
	_rotate_selected(90)

func _rotate_selected(delta: int) -> void:
	var rot := int(_safe_call("get_selected_rotation", 0))
	_safe_call("set_selected_rotation", null, [rot + int(delta)])

func _on_confirm_pressed() -> void:
	if _syncing:
		return
	if _confirm_button != null and _confirm_button.disabled:
		return
	_safe_call("request_confirm", null)

func _rotation_label(rotation: int) -> String:
	match _normalize_rotation(rotation):
		0:
			return "默认朝向"
		90:
			return "右转一次"
		180:
			return "转向背面"
		270:
			return "左转一次"
	return "默认朝向"

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r
