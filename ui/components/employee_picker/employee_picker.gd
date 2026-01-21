# 可复用员工选择器（以 EmployeeCard 缩略卡展示）
# - 支持选中态/禁用态
# - 支持角标（数量）与标签（例如：预支/在岗/步数）
class_name EmployeePicker
extends HFlowContainer

signal employee_selected(employee_id: String)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

var selected_employee_id: String = ""
var _items: Dictionary = {} # employee_id -> EmployeePickerItem

func clear() -> void:
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()
	_items.clear()
	selected_employee_id = ""

func set_items(items: Array[Dictionary], selected_id: String = "") -> void:
	clear()
	selected_employee_id = str(selected_id).strip_edges()

	for item_val in items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var emp_id := str(item.get("id", "")).strip_edges()
		if emp_id.is_empty():
			continue

		var enabled := true
		var enabled_val = item.get("enabled", null)
		if enabled_val is bool:
			enabled = bool(enabled_val)

		var badge_text := ""
		var badge_val = item.get("badge_text", null)
		if badge_val != null:
			badge_text = str(badge_val).strip_edges()

		var tag_text := ""
		var tag_val = item.get("tag_text", null)
		if tag_val != null:
			tag_text = str(tag_val).strip_edges()

		var emp_def: Dictionary = {}
		var def_val = item.get("employee_def", null)
		if def_val is Dictionary:
			emp_def = Dictionary(def_val).duplicate(true)
		elif EmployeeRegistryClass.is_loaded():
			var reg_def_val = EmployeeRegistryClass.get_def(emp_id)
			if reg_def_val != null and reg_def_val.has_method("to_dict"):
				emp_def = reg_def_val.to_dict()
		if emp_def.is_empty():
			emp_def = {"id": emp_id, "name": emp_id}

		var picker_item := EmployeePickerItem.new()
		picker_item.employee_id = emp_id
		picker_item.employee_def = emp_def
		picker_item.badge_text = badge_text
		picker_item.tag_text = tag_text
		picker_item.pressed.connect(_on_item_pressed)
		picker_item.set_enabled(enabled)
		add_child(picker_item)
		_items[emp_id] = picker_item

	_apply_selection()

func set_selected(employee_id: String) -> void:
	selected_employee_id = str(employee_id).strip_edges()
	_apply_selection()

func _apply_selection() -> void:
	for k in _items.keys():
		var id := str(k)
		var item_val = _items[k]
		if not (item_val is EmployeePickerItem):
			continue
		var item: EmployeePickerItem = item_val
		if is_instance_valid(item):
			item.set_selected(id == selected_employee_id and not id.is_empty())

func _on_item_pressed(employee_id: String) -> void:
	var id := str(employee_id).strip_edges()
	if id.is_empty():
		return
	if selected_employee_id == id:
		# 不做 toggle：再次点击保持选中（由外部 clear_selection 控制）
		employee_selected.emit(id)
		return
	selected_employee_id = id
	_apply_selection()
	employee_selected.emit(id)


class EmployeePickerItem extends Control:
	signal pressed(employee_id: String)

	var employee_id: String = ""
	var employee_def: Dictionary = {}
	var badge_text: String = ""
	var tag_text: String = ""

	var _enabled: bool = true
	var _selected: bool = false

	var _card: EmployeeCard = null
	var _tag_panel: PanelContainer = null
	var _tag_label: Label = null
	var _badge_panel: PanelContainer = null
	var _badge_label: Label = null

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# FlowContainer 布局依赖子控件的 minimum size。EmployeeCard 的 min size 不会自动上推到父 Control，
		# 若不设置会导致父容器高度偏小，卡片绘制溢出并覆盖下方内容（issue_tracker #34）。
		custom_minimum_size = EmployeeCard.COMPACT_SIZE

		_card = EmployeeCardClass.new()
		_card.variant = EmployeeCard.CardVariant.COMPACT
		_card.draggable = false
		_card.employee_id = employee_id
		_card.setup(employee_def)
		_card.card_clicked.connect(_on_card_clicked)
		add_child(_card)
		_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		_card.offset_left = 0
		_card.offset_top = 0
		_card.offset_right = 0
		_card.offset_bottom = 0

		# Tag badge (left of count badge)
		_tag_panel = _build_badge_panel(Vector2(40, 18), Vector2(-78, 4), Vector2(-32, 22), 10)
		_tag_label = _get_badge_label(_tag_panel)

		# Count badge (top-right)
		_badge_panel = _build_badge_panel(Vector2(26, 18), Vector2(-28, 4), Vector2(-4, 22), 11)
		_badge_label = _get_badge_label(_badge_panel)

		_update_display()

	func _build_badge_panel(min_size: Vector2, offset_lt: Vector2, offset_rb: Vector2, font_size: int) -> PanelContainer:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = min_size
		add_child(panel)
		panel.anchor_left = 1.0
		panel.anchor_top = 0.0
		panel.anchor_right = 1.0
		panel.anchor_bottom = 0.0
		panel.offset_left = offset_lt.x
		panel.offset_top = offset_lt.y
		panel.offset_right = offset_rb.x
		panel.offset_bottom = offset_rb.y

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.65)
		style.border_color = Color(1, 1, 1, 0.25)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 0
		label.offset_top = 0
		label.offset_right = 0
		label.offset_bottom = 0
		panel.add_child(label)

		return panel

	func _get_badge_label(panel: PanelContainer) -> Label:
		if panel == null or not is_instance_valid(panel):
			return null
		if panel.get_child_count() <= 0:
			return null
		var c = panel.get_child(0)
		return c as Label

	func set_enabled(enabled: bool) -> void:
		_enabled = enabled
		_update_display()

	func set_selected(selected: bool) -> void:
		_selected = selected
		if _card != null and is_instance_valid(_card):
			_card.set_selected(_selected)

	func _update_display() -> void:
		if _card != null and is_instance_valid(_card):
			_card.mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_IGNORE
			_card.modulate = Color(1, 1, 1, 1) if _enabled else Color(0.75, 0.75, 0.8, 0.65)
			_card.set_selected(_selected)

		if _tag_panel != null and is_instance_valid(_tag_panel):
			var show_tag := not tag_text.is_empty()
			_tag_panel.visible = show_tag
			if _tag_label != null and is_instance_valid(_tag_label):
				_tag_label.text = tag_text

		if _badge_panel != null and is_instance_valid(_badge_panel):
			var show := not badge_text.is_empty()
			_badge_panel.visible = show
			if _badge_label != null and is_instance_valid(_badge_label):
				_badge_label.text = badge_text

	func _on_card_clicked(_id: String) -> void:
		if not _enabled:
			return
		pressed.emit(employee_id)
