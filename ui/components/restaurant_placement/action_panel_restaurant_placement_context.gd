extends VBoxContainer

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

const ROTATE_CCW_ICON: Texture2D = preload("res://assets/ui/icons/kenney/board/arrow_counterclockwise.png")
const ROTATE_CW_ICON: Texture2D = preload("res://assets/ui/icons/kenney/board/arrow_clockwise.png")

var _overlay: Node = null
var _syncing: bool = false

var _employee_row: VBoxContainer = null
var _employee_picker = null
var _mode_row: HBoxContainer = null
var _place_restaurant_button: Button = null
var _move_restaurant_button: Button = null
var _place_section: VBoxContainer = null
var _move_section: VBoxContainer = null
var _place_hint_label: Label = null
var _move_hint_label: Label = null
var _restaurant_flow: HFlowContainer = null
var _restaurant_summary_label: Label = null
var _rotation_value_label: Label = null
var _rotate_left_button: Button = null
var _rotate_right_button: Button = null
var _position_summary_label: Label = null
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
	_sync_mode_buttons(mode)
	_sync_hint()
	_place_section.visible = (mode == "place_restaurant")
	_move_section.visible = (mode == "move_restaurant")
	if mode == "move_restaurant":
		_sync_move_section()
	else:
		_sync_place_section()
	_sync_rotation_controls()
	_sync_confirm_button(mode)
	_syncing = false

func _build_ui() -> void:
	if _mode_row != null:
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

	_mode_row = HBoxContainer.new()
	_mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_row.add_theme_constant_override("separation", 8)
	add_child(_mode_row)

	_place_restaurant_button = Button.new()
	_place_restaurant_button.text = "放置餐厅"
	_place_restaurant_button.toggle_mode = true
	_place_restaurant_button.custom_minimum_size = Vector2(0, 36)
	_place_restaurant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_place_restaurant_button)
	_mode_row.add_child(_place_restaurant_button)
	_place_restaurant_button.pressed.connect(_on_place_restaurant_pressed)

	_move_restaurant_button = Button.new()
	_move_restaurant_button.text = "移动餐厅"
	_move_restaurant_button.toggle_mode = true
	_move_restaurant_button.custom_minimum_size = Vector2(0, 36)
	_move_restaurant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_move_restaurant_button)
	_mode_row.add_child(_move_restaurant_button)
	_move_restaurant_button.pressed.connect(_on_move_restaurant_pressed)

	_place_section = VBoxContainer.new()
	_place_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_section.add_theme_constant_override("separation", 6)
	add_child(_place_section)
	_build_place_section()

	_move_section = VBoxContainer.new()
	_move_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_move_section.add_theme_constant_override("separation", 6)
	add_child(_move_section)
	_build_move_section()

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
	_add_button_icon(_rotate_left_button, ROTATE_CCW_ICON)
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
	_add_button_icon(_rotate_right_button, ROTATE_CW_ICON)
	rotation_row.add_child(_rotate_right_button)
	_rotate_right_button.pressed.connect(_on_rotate_right_pressed)

	_position_summary_label = Label.new()
	_position_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_position_summary_label)
	add_child(_position_summary_label)

	_confirm_button = Button.new()
	_confirm_button.custom_minimum_size = Vector2(0, 36)
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_confirm_button)
	add_child(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)

func _build_place_section() -> void:
	_place_hint_label = _add_mode_hint(_place_section)

func _build_move_section() -> void:
	_move_hint_label = _add_mode_hint(_move_section)

	var restaurant_label := Label.new()
	restaurant_label.text = "选择餐厅"
	UiStylesClass.apply_label_dark(restaurant_label)
	_move_section.add_child(restaurant_label)

	_restaurant_flow = HFlowContainer.new()
	_restaurant_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restaurant_flow.add_theme_constant_override("h_separation", 6)
	_restaurant_flow.add_theme_constant_override("v_separation", 6)
	_move_section.add_child(_restaurant_flow)

	_restaurant_summary_label = Label.new()
	_restaurant_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(_restaurant_summary_label)
	_move_section.add_child(_restaurant_summary_label)

func _add_mode_hint(parent: VBoxContainer) -> Label:
	var hint_panel := PanelContainer.new()
	hint_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster_alt(hint_panel)
	parent.add_child(hint_panel)

	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 8)
	hint_margin.add_theme_constant_override("margin_top", 6)
	hint_margin.add_theme_constant_override("margin_right", 8)
	hint_margin.add_theme_constant_override("margin_bottom", 6)
	hint_panel.add_child(hint_margin)

	var hint_label := Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_hint_dark(hint_label)
	hint_margin.add_child(hint_label)
	return hint_label

func _add_button_icon(button: Button, texture: Texture2D) -> void:
	if button == null:
		return
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
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
		_employee_picker.clear()
		return
	var selected_key := str(_safe_call("get_selected_employee_key", "")).strip_edges()
	_employee_picker.set_items(items, selected_key)

func _sync_mode_buttons(mode: String) -> void:
	var can_place := _is_mode_available("place_restaurant")
	var can_move := _is_mode_available("move_restaurant")
	_place_restaurant_button.set_pressed_no_signal(mode == "place_restaurant")
	_move_restaurant_button.set_pressed_no_signal(mode == "move_restaurant")
	_place_restaurant_button.disabled = not can_place
	_move_restaurant_button.disabled = not can_move
	_place_restaurant_button.tooltip_text = "" if can_place else "当前员工不能放置餐厅"
	if can_move:
		_move_restaurant_button.tooltip_text = ""
	else:
		_move_restaurant_button.tooltip_text = "需要可移动餐厅和可执行移动的员工"

func _sync_hint() -> void:
	var text := str(_safe_call("get_hint_text", ""))
	if _place_hint_label != null:
		_place_hint_label.text = text
	if _move_hint_label != null:
		_move_hint_label.text = text

func _sync_place_section() -> void:
	var pos := _get_selected_position()
	if pos == Vector2i(-1, -1):
		_position_summary_label.text = "请点击地图上的高亮位置。"
	else:
		_position_summary_label.text = "新餐厅位置 (%d,%d)。" % [pos.x, pos.y]

func _sync_move_section() -> void:
	_rebuild_restaurant_buttons()
	var selected_restaurant := str(_safe_call("get_selected_restaurant", "")).strip_edges()
	if selected_restaurant.is_empty():
		_restaurant_summary_label.text = "先选择要移动的餐厅。"
	else:
		_restaurant_summary_label.text = str(_safe_call("get_restaurant_display_label", selected_restaurant, [selected_restaurant]))

	var pos := _get_selected_position()
	if pos == Vector2i(-1, -1):
		_position_summary_label.text = "请选择餐厅，然后点击地图上的高亮目标位置。"
	else:
		_position_summary_label.text = "目标位置 (%d,%d)。" % [pos.x, pos.y]

func _rebuild_restaurant_buttons() -> void:
	for child in _restaurant_flow.get_children():
		child.queue_free()

	var ids: Array[String] = []
	var val = _safe_call("get_available_restaurants", [])
	if val is Array:
		for rid_val in Array(val):
			var rid := str(rid_val).strip_edges()
			if not rid.is_empty():
				ids.append(rid)
	ids.sort()

	if ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前没有可移动餐厅"
		UiStylesClass.apply_label_hint_dark(empty_label)
		_restaurant_flow.add_child(empty_label)
		return

	var selected := str(_safe_call("get_selected_restaurant", "")).strip_edges()
	var can_move := _is_mode_available("move_restaurant")
	for rid in ids:
		var btn := Button.new()
		var label := str(_safe_call("get_restaurant_display_label", rid, [rid])).strip_edges()
		btn.text = label if not label.is_empty() else rid
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 34)
		btn.set_pressed_no_signal(rid == selected)
		btn.disabled = not can_move
		UiStylesClass.apply_button_secondary(btn)
		btn.pressed.connect(_on_restaurant_pressed.bind(rid))
		_restaurant_flow.add_child(btn)

func _sync_rotation_controls() -> void:
	var rot := int(_safe_call("get_selected_rotation", 0))
	_rotation_value_label.text = _rotation_label(rot)

func _sync_confirm_button(mode: String) -> void:
	if _confirm_button == null:
		return
	_confirm_button.text = "确认移动" if mode == "move_restaurant" else "确认放置"
	_confirm_button.disabled = not bool(_safe_call("can_confirm", false))

func _get_selected_position() -> Vector2i:
	var pos_val = _safe_call("get_selected_position", Vector2i(-1, -1))
	if pos_val is Vector2i:
		return Vector2i(pos_val)
	return Vector2i(-1, -1)

func _get_overlay_mode() -> String:
	return str(_safe_call("get_mode", "place_restaurant")).strip_edges()

func _is_mode_available(action_id: String) -> bool:
	return bool(_safe_call("is_mode_available", str(action_id).strip_edges() != "move_restaurant", [action_id]))

func _safe_call(method: StringName, fallback, args: Array = []):
	if _overlay == null or not is_instance_valid(_overlay):
		return fallback
	if not _overlay.has_method(method):
		return fallback
	return _overlay.callv(method, args)

func _on_place_restaurant_pressed() -> void:
	if _syncing:
		return
	if _place_restaurant_button != null and _place_restaurant_button.disabled:
		return
	_safe_call("set_mode", null, ["place_restaurant"])

func _on_move_restaurant_pressed() -> void:
	if _syncing:
		return
	if _move_restaurant_button != null and _move_restaurant_button.disabled:
		return
	_safe_call("set_mode", null, ["move_restaurant"])

func _on_restaurant_pressed(restaurant_id: String) -> void:
	if _syncing:
		return
	_safe_call("set_selected_restaurant", null, [restaurant_id])

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
