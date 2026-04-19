# 可复用员工选择器（以 EmployeeCard 缩略卡展示）
# - 支持选中态/禁用态
# - 支持角标（数量）与标签（例如：预支/在岗/步数）
class_name EmployeePicker
extends HFlowContainer

signal employee_selected(employee_id: String)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@export var card_variant: EmployeeCard.CardVariant = EmployeeCard.CardVariant.COMPACT
@export var card_display_scale: float = 1.0

var selected_employee_id: String = ""
var selected_item_key: String = ""
var _items_by_key: Dictionary = {} # item_key -> EmployeePickerItem
var _item_keys_in_order: Array[String] = []

func clear() -> void:
	for child in get_children():
		if is_instance_valid(child):
			remove_child(child)
			child.queue_free()
	_items_by_key.clear()
	_item_keys_in_order.clear()
	selected_employee_id = ""
	selected_item_key = ""

func set_items(items: Array[Dictionary], selected_id: String = "") -> void:
	clear()
	var desired := str(selected_id).strip_edges()

	for item_val in items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var emp_id := str(item.get("id", "")).strip_edges()
		if emp_id.is_empty():
			continue

		var item_key := str(item.get("key", emp_id)).strip_edges()
		if item_key.is_empty():
			item_key = emp_id
		# 允许同类型多张卡：若 key 冲突则自动加后缀，确保唯一性。
		if _items_by_key.has(item_key):
			var i := 2
			while _items_by_key.has("%s#%d" % [item_key, i]):
				i += 1
			item_key = "%s#%d" % [item_key, i]

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
		picker_item.item_key = item_key
		picker_item.employee_def = emp_def
		picker_item.badge_text = badge_text
		picker_item.tag_text = tag_text
		picker_item.card_variant = card_variant
		picker_item.card_scale = card_display_scale
		picker_item.pressed.connect(_on_item_pressed)
		picker_item.set_enabled(enabled)
		add_child(picker_item)
		_items_by_key[item_key] = picker_item
		_item_keys_in_order.append(item_key)

	# 选中逻辑：兼容旧调用（selected_id 可能是 employee_id），也允许直接传 item_key。
	if not desired.is_empty():
		if _items_by_key.has(desired):
			selected_item_key = desired
			selected_employee_id = _items_by_key[desired].employee_id
		else:
			# 按 employee_id 选中第一个可用实例
			selected_item_key = _find_first_enabled_key_for_employee(desired)
			if selected_item_key.is_empty():
				selected_item_key = _find_first_key_for_employee(desired)
			selected_employee_id = desired if not selected_item_key.is_empty() else ""

	_apply_selection()

func set_selected(employee_id: String) -> void:
	var desired := str(employee_id).strip_edges()
	if desired.is_empty():
		selected_employee_id = ""
		selected_item_key = ""
		_apply_selection()
		return

	# 允许直接按 item_key 选中
	if _items_by_key.has(desired):
		selected_item_key = desired
		selected_employee_id = _items_by_key[desired].employee_id
		_apply_selection()
		return

	# 兼容：按 employee_id 选中第一个可用实例
	selected_item_key = _find_first_enabled_key_for_employee(desired)
	if selected_item_key.is_empty():
		selected_item_key = _find_first_key_for_employee(desired)
	selected_employee_id = desired if not selected_item_key.is_empty() else ""
	_apply_selection()

func _apply_selection() -> void:
	for key in _item_keys_in_order:
		var item_val = _items_by_key.get(key, null)
		if not (item_val is EmployeePickerItem):
			continue
		var item: EmployeePickerItem = item_val
		if is_instance_valid(item):
			item.set_selected(key == selected_item_key and not key.is_empty())

func _on_item_pressed(item_key: String) -> void:
	var key := str(item_key).strip_edges()
	if key.is_empty():
		return
	if not _items_by_key.has(key):
		return

	var item: EmployeePickerItem = _items_by_key[key]
	var id := str(item.employee_id).strip_edges()
	if id.is_empty():
		return
	if selected_item_key == key:
		# 不做 toggle：再次点击保持选中（由外部 clear_selection 控制）
		employee_selected.emit(id)
		return

	selected_item_key = key
	selected_employee_id = id
	_apply_selection()
	employee_selected.emit(id)

func get_selected_key() -> String:
	return selected_item_key

func get_selected_employee_id() -> String:
	return selected_employee_id

func _find_first_key_for_employee(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return ""
	for key in _item_keys_in_order:
		var item_val = _items_by_key.get(key, null)
		if item_val is EmployeePickerItem and str((item_val as EmployeePickerItem).employee_id) == emp_id:
			return key
	return ""

func _find_first_enabled_key_for_employee(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return ""
	for key in _item_keys_in_order:
		var item_val = _items_by_key.get(key, null)
		if not (item_val is EmployeePickerItem):
			continue
		var item: EmployeePickerItem = item_val
		if str(item.employee_id) == emp_id and item.is_enabled():
			return key
	return ""

func _find_first_enabled_key() -> String:
	for key in _item_keys_in_order:
		var item_val = _items_by_key.get(key, null)
		if item_val is EmployeePickerItem and (item_val as EmployeePickerItem).is_enabled():
			return key
	return ""


class EmployeePickerItem extends Control:
	signal pressed(item_key: String)

	const BADGE_BAR_HEIGHT := 22

	var employee_id: String = ""
	var item_key: String = ""
	var employee_def: Dictionary = {}
	var badge_text: String = ""
	var tag_text: String = ""
	var card_variant: int = EmployeeCard.CardVariant.COMPACT
	var card_scale: float = 1.0

	var _enabled: bool = true
	var _selected: bool = false

	var _card: EmployeeCard = null
	var _tag_panel: PanelContainer = null
	var _tag_label: Label = null
	var _badge_panel: PanelContainer = null
	var _badge_label: Label = null

	func _ready() -> void:
		_build_ui()

	func _sc_f(v: float) -> float:
		return float(v) * clampf(float(card_scale), 0.5, 2.0)

	func _sc_i(v: int, min_value: int = 1) -> int:
		return maxi(min_value, int(round(float(v) * clampf(float(card_scale), 0.5, 2.0))))

	func _build_ui() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := clampf(float(card_scale), 0.5, 2.0)
		var base_size := EmployeeCard.FULL_SIZE if int(card_variant) == int(EmployeeCard.CardVariant.FULL) else EmployeeCard.COMPACT_SIZE
		var badge_h := int(round(float(BADGE_BAR_HEIGHT) * s))
		# FlowContainer 布局依赖子控件的 minimum size。EmployeeCard 的 min size 不会自动上推到父 Control。
		# 这里额外预留顶部 badge 区域，避免数量/步数标记遮挡卡片标题（issue_tracker #34 / #ui-polish-10）。
		custom_minimum_size = Vector2(round(base_size.x * s), round(base_size.y * s)) + Vector2(0, badge_h)

		_card = EmployeeCardClass.new()
		_card.variant = card_variant
		_card.display_scale = s
		_card.draggable = false
		_card.employee_id = employee_id
		_card.setup(employee_def)
		_card.card_clicked.connect(_on_card_clicked)
		add_child(_card)
		_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		_card.offset_left = 0
		_card.offset_top = badge_h
		_card.offset_right = 0
		_card.offset_bottom = 0

		# Tag badge (left of count badge)
		_tag_panel = _build_badge_panel(
			Vector2(_sc_i(40), _sc_i(18)),
			Vector2(-_sc_f(78), _sc_f(4)),
			Vector2(-_sc_f(32), _sc_f(22)),
			_sc_i(10, 7)
		)
		_tag_label = _get_badge_label(_tag_panel)

		# Count badge (top-right)
		_badge_panel = _build_badge_panel(
			Vector2(_sc_i(26), _sc_i(18)),
			Vector2(-_sc_f(28), _sc_f(4)),
			Vector2(-_sc_f(4), _sc_f(22)),
			_sc_i(11, 8)
		)
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
		style.bg_color = Color(0.73, 0.23, 0.18, 0.85)
		style.border_color = Color(0.73, 0.23, 0.18, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", Color(0.97, 0.93, 0.82, 1))
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

	func is_enabled() -> bool:
		return _enabled

	func set_selected(selected: bool) -> void:
		_selected = selected
		if _card != null and is_instance_valid(_card):
			_card.set_selected(_selected)

	func _update_display() -> void:
		if _card != null and is_instance_valid(_card):
			_card.mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_IGNORE
			_card.set_selected(_selected)
		# Disabled state should visually gray out even when EmployeeCard updates its own modulate
		# (e.g. selection toggles call EmployeeCard.set_selected which resets modulate).
		modulate = Color(1, 1, 1, 1) if _enabled else Color(0.75, 0.75, 0.8, 0.65)

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
		pressed.emit(item_key if not item_key.is_empty() else employee_id)
