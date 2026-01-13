# 招聘面板组件
# 显示可招聘的入门级员工，支持招聘操作
class_name RecruitPanel
extends Control

signal recruit_requested(employee_type: String)
signal cancelled()
signal right_panel_footer_changed()

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var counter_label: Label = $MarginContainer/VBoxContainer/CounterRow/CounterLabel
@onready var items_container: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ItemsContainer
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton

var _employee_pool: Dictionary = {}  # employee_type -> count
var _employee_registry = null
var _recruit_remaining: int = 0
var _recruit_total: int = 0
var _pool_cards: Dictionary = {}  # employee_type -> PoolCard
var _selected_employee_type: String = ""
var _relayout_scheduled: bool = false
var _embedded_in_right_panel: bool = false
var _base_custom_minimum_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
		confirm_btn.disabled = true
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)
	if has_signal("resized"):
		resized.connect(_request_relayout)
	if has_signal("visibility_changed"):
		visibility_changed.connect(_request_relayout)
	right_panel_footer_changed.emit()
	_request_relayout()

func set_embedded_in_right_panel(embedded: bool) -> void:
	_embedded_in_right_panel = embedded
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	custom_minimum_size = Vector2.ZERO if embedded else _base_custom_minimum_size
	var row = get_node_or_null("MarginContainer/VBoxContainer/ButtonRow")
	if row is Control:
		(row as Control).visible = not embedded
	right_panel_footer_changed.emit()
	_request_relayout()

func right_panel_get_footer_config() -> Dictionary:
	if confirm_btn == null:
		return {}
	return {
		"show_cancel": true,
		"cancel_text": "取消",
		"cancel_enabled": true,
		"show_primary": true,
		"primary_text": str(confirm_btn.text),
		"primary_enabled": not confirm_btn.disabled,
	}

func right_panel_footer_primary() -> void:
	_on_confirm_pressed()

func set_employee_registry(registry) -> void:
	_employee_registry = registry
	_rebuild_pool_cards()

func set_employee_pool(pool: Dictionary) -> void:
	_employee_pool = pool.duplicate()
	_rebuild_pool_cards()
	_update_confirm_state()
	_request_relayout()

func set_recruit_count(remaining: int, total: int) -> void:
	_recruit_remaining = remaining
	_recruit_total = total
	_update_counter()
	_update_card_states()
	_update_confirm_state()

func refresh() -> void:
	_rebuild_pool_cards()
	_update_counter()
	_update_confirm_state()
	_request_relayout()

func clear_selection() -> void:
	_selected_employee_type = ""
	_update_card_states()
	_update_confirm_state()

func _rebuild_pool_cards() -> void:
	# 清除旧卡牌
	for card in _pool_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_pool_cards.clear()

	if items_container == null:
		return

	# 获取入门级员工列表
	var entry_level_ids := _get_entry_level_employee_ids()

	for emp_type in entry_level_ids:
		var count: int = int(_employee_pool.get(emp_type, 0))
		var emp_def := _get_employee_def(emp_type)

		var card := PoolCard.new()
		card.employee_type = emp_type
		card.pool_count = count
		card.employee_def = emp_def
		card.selected.connect(_on_card_selected)
		items_container.add_child(card)
		_pool_cards[emp_type] = card

	_update_card_states()
	_request_relayout()

func _request_relayout() -> void:
	if _relayout_scheduled:
		return
	_relayout_scheduled = true
	call_deferred("_apply_relayout")

func _apply_relayout() -> void:
	_relayout_scheduled = false
	if not is_inside_tree():
		return
	if items_container == null or not is_instance_valid(items_container):
		return
	# HFlowContainer 在首次嵌入 RightPanel/首次显示时，可能在 size 还未稳定时完成布局，
	# 导致卡片不换行并溢出到右侧；延迟到布局稳定后强制重排一次。
	await get_tree().process_frame
	await get_tree().process_frame
	if items_container != null and is_instance_valid(items_container):
		items_container.queue_sort()

func _get_entry_level_employee_ids() -> Array[String]:
	var result: Array[String] = []

	# 优先：使用静态 EmployeeRegistry（模块系统 V2 在初始化时配置）
	if EmployeeRegistryClass.is_loaded():
		for key in _employee_pool.keys():
			var emp_type := str(key)
			var emp_def := _get_employee_def(emp_type)
			var tags: Array = Array(emp_def.get("tags", []))
			if tags.has("entry_level"):
				result.append(emp_type)
	elif _employee_registry != null and _employee_registry.has_method("get_all_employee_ids"):
		# 兼容：旧式注入 registry
		var all_ids: Array = _employee_registry.get_all_employee_ids()
		for id in all_ids:
			var emp_def2 := _get_employee_def(str(id))
			var tags2: Array = Array(emp_def2.get("tags", []))
			if tags2.has("entry_level"):
				result.append(str(id))
	else:
		# 兜底：从 pool 中推断（pool 中的都是可招聘的）
		for key2 in _employee_pool.keys():
			result.append(str(key2))

	result.sort()
	return result

func _get_employee_def(employee_type: String) -> Dictionary:
	if _employee_registry != null and _employee_registry.has_method("get_employee"):
		var emp = _employee_registry.get_employee(employee_type)
		if emp != null and emp.has_method("to_dict"):
			return emp.to_dict()

	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val != null and def_val.has_method("to_dict"):
			return def_val.to_dict()

	return {"id": employee_type, "name": employee_type}

func _update_counter() -> void:
	if counter_label != null:
		counter_label.text = "招聘次数: %d / %d" % [_recruit_remaining, _recruit_total]

func _update_card_states() -> void:
	var can_recruit := _recruit_remaining > 0

	if not can_recruit:
		_selected_employee_type = ""
	elif not _selected_employee_type.is_empty():
		var selected_count: int = int(_employee_pool.get(_selected_employee_type, 0))
		if selected_count <= 0:
			_selected_employee_type = ""

	for emp_type in _pool_cards.keys():
		var card: PoolCard = _pool_cards[emp_type]
		if is_instance_valid(card):
			var count: int = int(_employee_pool.get(emp_type, 0))
			card.pool_count = count
			card.set_enabled(can_recruit and count > 0)
			card.set_selected(emp_type == _selected_employee_type)
			card.update_display()
	right_panel_footer_changed.emit()

func _on_card_selected(employee_type: String) -> void:
	_selected_employee_type = employee_type
	_update_card_states()
	_update_confirm_state()

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return

	var ok := true
	ok = ok and _recruit_remaining > 0
	ok = ok and not _selected_employee_type.is_empty()
	if ok:
		var selected_count: int = int(_employee_pool.get(_selected_employee_type, 0))
		ok = ok and selected_count > 0

	confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_employee_type.is_empty():
		return

	var emp_type := _selected_employee_type
	clear_selection()
	recruit_requested.emit(emp_type)

func _on_cancel_pressed() -> void:
	clear_selection()
	cancelled.emit()


# === 内部类：供应池卡牌 ===
class PoolCard extends PanelContainer:
	signal selected(employee_type: String)

	var employee_type: String = ""
	var pool_count: int = 0
	var employee_def: Dictionary = {}

	var _enabled: bool = true
	var _selected: bool = false
	var _name_label: Label
	var _count_label: Label
	var _recruit_btn: Button
	var _role_color: ColorRect

	const ROLE_COLORS: Dictionary = {
		"manager": Color("#000000"),
		"recruit_train": Color("#bdb6b5"),
		"produce_food": Color("#94a869"),
		"procure_drink": Color("#adce91"),
		"price": Color("#eba791"),
		"marketing": Color("#94c1c7"),
		"new_shop": Color("#aa3c34"),
		"special": Color("#ae94c0"),
	}

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(140, 100)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		add_child(vbox)

		# 顶部：角色颜色 + 名称
		var top_hbox := HBoxContainer.new()
		top_hbox.add_theme_constant_override("separation", 4)
		vbox.add_child(top_hbox)

		_role_color = ColorRect.new()
		_role_color.custom_minimum_size = Vector2(6, 20)
		top_hbox.add_child(_role_color)

		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 13)
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_hbox.add_child(_name_label)

		# 库存数量
		_count_label = Label.new()
		_count_label.add_theme_font_size_override("font_size", 14)
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(_count_label)

		# 招聘按钮
		_recruit_btn = Button.new()
		_recruit_btn.text = "选择"
		_recruit_btn.add_theme_font_size_override("font_size", 12)
		_recruit_btn.pressed.connect(_on_select_pressed)
		vbox.add_child(_recruit_btn)

		update_display()
		_update_style()

	func update_display() -> void:
		if _name_label != null:
			var name: String = str(employee_def.get("name", employee_type))
			_name_label.text = name

		if _role_color != null:
			var role: String = str(employee_def.get("role", "special"))
			_role_color.color = ROLE_COLORS.get(role, Color(0.5, 0.5, 0.5, 1))

		if _count_label != null:
			_count_label.text = "库存: %d" % pool_count
			if pool_count <= 0:
				_count_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
			else:
				_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))

		if _recruit_btn != null:
			_recruit_btn.text = "已选择" if _selected else "选择"
			_recruit_btn.disabled = not _enabled or pool_count <= 0

	func set_enabled(enabled: bool) -> void:
		_enabled = enabled
		if _recruit_btn != null:
			_recruit_btn.disabled = not _enabled or pool_count <= 0
		_update_style()

	func set_selected(selected: bool) -> void:
		_selected = selected
		update_display()
		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _enabled and pool_count > 0:
			style.bg_color = Color(0.18, 0.2, 0.22, 0.9)
		else:
			style.bg_color = Color(0.15, 0.15, 0.18, 0.6)
		style.set_corner_radius_all(4)
		if _selected:
			style.border_color = Color(0.4, 0.7, 1.0, 0.9)
			style.set_border_width_all(2)
		add_theme_stylebox_override("panel", style)

	func _on_select_pressed() -> void:
		if _enabled and pool_count > 0:
			selected.emit(employee_type)
