extends VBoxContainer

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

var _overlay: Node = null
var _syncing: bool = false

var _mode_row: HBoxContainer = null
var _place_house_button: Button = null
var _add_garden_button: Button = null
var _hint_panel: PanelContainer = null
var _hint_label: Label = null
var _employee_row: VBoxContainer = null
var _employee_picker = null
var _house_section: VBoxContainer = null
var _garden_section: VBoxContainer = null
var _house_numbers_flow: HFlowContainer = null
var _rotate_left_button: Button = null
var _rotation_value_label: Label = null
var _rotate_right_button: Button = null
var _house_summary_label: Label = null
var _garden_house_label: Label = null
var _garden_effect_label: Label = null
var _garden_direction_buttons: Dictionary = {}
var _garden_summary_label: Label = null

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
	_sync_mode_buttons(mode)
	_sync_hint()
	_sync_employee_buttons()
	_house_section.visible = (mode == "place_house")
	_garden_section.visible = (mode == "add_garden")
	if mode == "place_house":
		_sync_house_section()
	else:
		_sync_garden_section()
	_syncing = false

func _build_ui() -> void:
	if _mode_row != null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_mode_row = HBoxContainer.new()
	_mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_row.add_theme_constant_override("separation", 8)
	add_child(_mode_row)

	_place_house_button = Button.new()
	_place_house_button.text = "放置房屋"
	_place_house_button.toggle_mode = true
	_place_house_button.custom_minimum_size = Vector2(0, 36)
	_place_house_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_place_house_button)
	_mode_row.add_child(_place_house_button)
	_place_house_button.pressed.connect(_on_place_house_pressed)

	_add_garden_button = Button.new()
	_add_garden_button.text = "添加花园"
	_add_garden_button.toggle_mode = true
	_add_garden_button.custom_minimum_size = Vector2(0, 36)
	_add_garden_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_add_garden_button)
	_mode_row.add_child(_add_garden_button)
	_add_garden_button.pressed.connect(_on_add_garden_pressed)

	_hint_panel = PanelContainer.new()
	_hint_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster_alt(_hint_panel)
	add_child(_hint_panel)

	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 8)
	hint_margin.add_theme_constant_override("margin_top", 6)
	hint_margin.add_theme_constant_override("margin_right", 8)
	hint_margin.add_theme_constant_override("margin_bottom", 6)
	_hint_panel.add_child(hint_margin)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_hint_label)
	hint_margin.add_child(_hint_label)

	_employee_row = VBoxContainer.new()
	_employee_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_row.add_theme_constant_override("separation", 4)
	add_child(_employee_row)

	var employee_label := Label.new()
	employee_label.text = "员工"
	UiStylesClass.apply_label_dark(employee_label)
	_employee_row.add_child(employee_label)

	_employee_picker = EmployeePickerClass.new()
	_employee_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_row.add_child(_employee_picker)
	if _employee_picker.has_signal("employee_selected"):
		_employee_picker.employee_selected.connect(_on_employee_picker_selected)

	_house_section = VBoxContainer.new()
	_house_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_section.add_theme_constant_override("separation", 6)
	add_child(_house_section)
	_build_house_section()

	_garden_section = VBoxContainer.new()
	_garden_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_garden_section.add_theme_constant_override("separation", 6)
	add_child(_garden_section)
	_build_garden_section()

func _build_house_section() -> void:
	var number_label := Label.new()
	number_label.text = "房屋编号"
	UiStylesClass.apply_label_dark(number_label)
	_house_section.add_child(number_label)

	_house_numbers_flow = HFlowContainer.new()
	_house_numbers_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_numbers_flow.add_theme_constant_override("h_separation", 6)
	_house_numbers_flow.add_theme_constant_override("v_separation", 6)
	_house_section.add_child(_house_numbers_flow)

	var rotation_label := Label.new()
	rotation_label.text = "旋转"
	UiStylesClass.apply_label_dark(rotation_label)
	_house_section.add_child(rotation_label)

	var rotation_row := HBoxContainer.new()
	rotation_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_row.add_theme_constant_override("separation", 6)
	_house_section.add_child(rotation_row)

	_rotate_left_button = Button.new()
	_rotate_left_button.text = "↺"
	_rotate_left_button.tooltip_text = "向左旋转"
	_rotate_left_button.custom_minimum_size = Vector2(44, 34)
	UiStylesClass.apply_button_secondary(_rotate_left_button)
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
	_rotate_right_button.text = "↻"
	_rotate_right_button.tooltip_text = "向右旋转"
	_rotate_right_button.custom_minimum_size = Vector2(44, 34)
	UiStylesClass.apply_button_secondary(_rotate_right_button)
	rotation_row.add_child(_rotate_right_button)
	_rotate_right_button.pressed.connect(_on_rotate_right_pressed)

	_house_summary_label = Label.new()
	_house_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_house_summary_label)
	_house_section.add_child(_house_summary_label)

func _build_garden_section() -> void:
	var target_label := Label.new()
	target_label.text = "目标房屋"
	UiStylesClass.apply_label_dark(target_label)
	_garden_section.add_child(target_label)

	_garden_house_label = Label.new()
	_garden_house_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_garden_house_label)
	_garden_section.add_child(_garden_house_label)

	_garden_effect_label = Label.new()
	_garden_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_garden_effect_label)
	_garden_section.add_child(_garden_effect_label)

	var direction_label := Label.new()
	direction_label.text = "花园方向"
	UiStylesClass.apply_label_dark(direction_label)
	_garden_section.add_child(direction_label)

	var direction_flow := HFlowContainer.new()
	direction_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direction_flow.add_theme_constant_override("h_separation", 6)
	direction_flow.add_theme_constant_override("v_separation", 6)
	_garden_section.add_child(direction_flow)

	for d in ["N", "E", "S", "W"]:
		var btn := Button.new()
		btn.text = _direction_label(d)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(56, 34)
		UiStylesClass.apply_button_secondary(btn)
		btn.pressed.connect(_on_direction_pressed.bind(d))
		direction_flow.add_child(btn)
		_garden_direction_buttons[d] = btn

	_garden_summary_label = Label.new()
	_garden_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_garden_summary_label)
	_garden_section.add_child(_garden_summary_label)

func _sync_mode_buttons(mode: String) -> void:
	_place_house_button.set_pressed_no_signal(mode == "place_house")
	_add_garden_button.set_pressed_no_signal(mode == "add_garden")

func _sync_hint() -> void:
	_hint_label.text = str(_safe_call("get_hint_text", ""))

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
		_employee_picker.clear()
		return
	var selected_key := str(_safe_call("get_selected_employee_key", "")).strip_edges()
	_employee_picker.set_items(items, selected_key)

func _sync_house_section() -> void:
	_rebuild_house_number_buttons()
	var rot := int(_safe_call("get_selected_rotation", 0))
	_rotation_value_label.text = _rotation_label(rot)
	var selected_number := int(_safe_call("get_selected_house_number", -1))
	var pos := Vector2i(-1, -1)
	var selected_pos = _safe_call("get_selected_position", Vector2i(-1, -1))
	if selected_pos is Vector2i:
		pos = Vector2i(selected_pos)
	if selected_number <= 0:
		_house_summary_label.text = "先选择一个房屋编号。"
	elif pos == Vector2i(-1, -1):
		_house_summary_label.text = "已选择房屋 #%d。请点击地图上的高亮位置。" % selected_number
	else:
		_house_summary_label.text = "已选择房屋 #%d，位置 (%d,%d)。" % [selected_number, pos.x, pos.y]

func _rebuild_house_number_buttons() -> void:
	for child in _house_numbers_flow.get_children():
		child.queue_free()
	var nums: Array[int] = []
	var val = _safe_call("get_available_house_numbers", [])
	if val is Array:
		for n in Array(val):
			nums.append(int(n))
	nums.sort()
	var selected := int(_safe_call("get_selected_house_number", -1))
	if nums.is_empty():
		var empty_label := Label.new()
		empty_label.text = "无可用编号"
		UiStylesClass.apply_label_hint_dark(empty_label)
		_house_numbers_flow.add_child(empty_label)
		return
	for n in nums:
		var btn := Button.new()
		btn.text = str(n)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(42, 34)
		btn.set_pressed_no_signal(n == selected)
		UiStylesClass.apply_button_secondary(btn)
		btn.pressed.connect(_on_house_number_pressed.bind(n))
		_house_numbers_flow.add_child(btn)

func _sync_garden_section() -> void:
	var house_label := str(_safe_call("get_selected_house_display_label", "")).strip_edges()
	if house_label.is_empty():
		house_label = "未选择房屋（请点击地图中高亮的房屋）"
	_garden_house_label.text = house_label
	_garden_effect_label.text = str(_safe_call("get_garden_effect_label", "添加花园会提高需求上限，并提升该房屋晚餐价值。"))

	var selected_direction := str(_safe_call("get_selected_direction", "E")).strip_edges()
	for d in ["N", "E", "S", "W"]:
		var btn: Button = _garden_direction_buttons[d]
		btn.set_pressed_no_signal(d == selected_direction)
		var status := _get_direction_status(d)
		var valid := bool(status.get("valid", true))
		btn.disabled = not valid
		var msg := str(status.get("message", "")).strip_edges()
		btn.tooltip_text = msg if not valid else "花园方向 %s" % d

	var selected_house := str(_safe_call("get_selected_house_id", "")).strip_edges()
	if selected_house.is_empty():
		_garden_summary_label.text = "先选择房屋；之后可选 N/E/S/W 方向。"
	else:
		var status := _get_direction_status(selected_direction)
		if bool(status.get("valid", true)):
			_garden_summary_label.text = "已选择方向 %s，确认后添加花园。" % selected_direction
		else:
			_garden_summary_label.text = "方向 %s 不可用：%s" % [selected_direction, str(status.get("message", ""))]

func _get_direction_status(direction: String) -> Dictionary:
	var val = _safe_call("get_direction_status", {"valid": true, "message": ""}, [direction])
	return Dictionary(val) if val is Dictionary else {"valid": true, "message": ""}

func _get_overlay_mode() -> String:
	return str(_safe_call("get_mode", "place_house")).strip_edges()

func _safe_call(method: StringName, fallback, args: Array = []):
	if _overlay == null or not is_instance_valid(_overlay):
		return fallback
	if not _overlay.has_method(method):
		return fallback
	return _overlay.callv(method, args)

func _on_place_house_pressed() -> void:
	if _syncing:
		return
	_safe_call("set_mode", null, ["place_house"])

func _on_add_garden_pressed() -> void:
	if _syncing:
		return
	_safe_call("set_mode", null, ["add_garden"])

func _on_house_number_pressed(number: int) -> void:
	if _syncing:
		return
	_safe_call("set_selected_house_number", null, [int(number)])

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

func _on_direction_pressed(direction: String) -> void:
	if _syncing:
		return
	_safe_call("set_selected_direction", null, [direction])

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

func _direction_label(direction: String) -> String:
	match str(direction).strip_edges():
		"N":
			return "N ↑"
		"E":
			return "E →"
		"S":
			return "S ↓"
		"W":
			return "W ←"
	return str(direction)

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
