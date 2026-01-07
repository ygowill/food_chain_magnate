# 发薪日面板组件
# 显示员工薪资计算，支持解雇选择
class_name PaydayPanel
extends Control

signal fire_employees(employee_ids: Array[String])
signal pay_confirmed()

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var salary_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SalaryListContainer
@onready var discount_label: Label = $MarginContainer/VBoxContainer/SummarySection/DiscountLabel
@onready var total_label: Label = $MarginContainer/VBoxContainer/SummarySection/TotalLabel
@onready var cash_label: Label = $MarginContainer/VBoxContainer/SummarySection/CashLabel
@onready var fire_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/FireButton
@onready var pay_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/PayButton

var _employee_registry = null
var _all_employees: Array[String] = []
var _busy_marketers: Array[String] = []
var _salary_items: Dictionary = {}  # employee_type -> SalaryItem
var _selected_for_fire: Array[String] = []

var _discount_amount: int = 0
var _player_cash: int = 0
var _salary_per_employee: int = 5  # 默认薪水 $5

func _ready() -> void:
	if fire_btn != null:
		fire_btn.pressed.connect(_on_fire_pressed)
		fire_btn.disabled = true
	if pay_btn != null:
		pay_btn.pressed.connect(_on_pay_pressed)

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_employees(employees: Array[String], busy_marketers: Array[String]) -> void:
	_all_employees = employees.duplicate()
	_busy_marketers = busy_marketers.duplicate()
	_selected_for_fire.clear()
	_rebuild_salary_list()
	_update_summary()

func set_discount(amount: int) -> void:
	_discount_amount = amount
	_update_summary()

func set_player_cash(cash: int) -> void:
	_player_cash = cash
	_update_summary()

func calculate_total() -> int:
	var base_salary: int = 0

	for emp_type in _all_employees:
		if _selected_for_fire.has(emp_type):
			continue
		var emp_def := _get_employee_def(emp_type)
		if _requires_salary(emp_def):
			base_salary += _salary_per_employee

	var final := maxi(0, base_salary - _discount_amount)
	return final

func refresh() -> void:
	_rebuild_salary_list()
	_update_summary()

func _rebuild_salary_list() -> void:
	# 清除旧列表
	for item in _salary_items.values():
		if is_instance_valid(item):
			item.queue_free()
	_salary_items.clear()

	if salary_list_container == null:
		return

		for emp_type in _all_employees:
			var emp_def := _get_employee_def(emp_type)
			var requires_salary := _requires_salary(emp_def)
			var is_busy := _busy_marketers.has(emp_type)

			var item := SalaryItem.new()
			item.employee_type = emp_type
			item.employee_def = emp_def
			item.requires_salary = requires_salary
			item.is_busy = is_busy
			item.salary_amount = _salary_per_employee if requires_salary else 0
			item.fire_toggled.connect(_on_fire_toggled)
			salary_list_container.add_child(item)
			_salary_items[emp_type] = item

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

func _requires_salary(emp_def: Dictionary) -> bool:
	return bool(emp_def.get("salary", true))

func _update_summary() -> void:
	var base_salary: int = 0
	var salary_count: int = 0

	for emp_type in _all_employees:
		if _selected_for_fire.has(emp_type):
			continue
		var emp_def := _get_employee_def(emp_type)
		if _requires_salary(emp_def):
			base_salary += _salary_per_employee
			salary_count += 1

	var final_total := maxi(0, base_salary - _discount_amount)

	if discount_label != null:
		if _discount_amount > 0:
			discount_label.text = "招聘折扣: -$%d" % _discount_amount
			discount_label.visible = true
		else:
			discount_label.visible = false

	if total_label != null:
		total_label.text = "应付薪资: $%d（%d人 × $%d）" % [final_total, salary_count, _salary_per_employee]

	if cash_label != null:
		cash_label.text = "当前现金: $%d" % _player_cash
		if _player_cash < final_total:
			cash_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1))
		else:
			cash_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 1))

	if fire_btn != null:
		fire_btn.disabled = _selected_for_fire.is_empty()

	if pay_btn != null:
		pay_btn.disabled = _player_cash < final_total

func _on_fire_toggled(employee_type: String, selected: bool) -> void:
	if selected:
		if not _selected_for_fire.has(employee_type):
			_selected_for_fire.append(employee_type)
	else:
		_selected_for_fire.erase(employee_type)

	_update_summary()

func _on_fire_pressed() -> void:
	if _selected_for_fire.is_empty():
		return

	var to_fire: Array[String] = _selected_for_fire.duplicate()
	fire_employees.emit(to_fire)

	# 从列表中移除已解雇员工
	for emp_type in to_fire:
		_all_employees.erase(emp_type)
		if _salary_items.has(emp_type):
			var item = _salary_items[emp_type]
			if is_instance_valid(item):
				item.queue_free()
			_salary_items.erase(emp_type)

	_selected_for_fire.clear()
	_update_summary()

func _on_pay_pressed() -> void:
	pay_confirmed.emit()


# === 内部类：薪资列表项 ===
class SalaryItem extends PanelContainer:
	signal fire_toggled(employee_type: String, selected: bool)

	var employee_type: String = ""
	var employee_def: Dictionary = {}
	var requires_salary: bool = false
	var is_busy: bool = false
	var salary_amount: int = 0

	var _fire_checkbox: CheckBox
	var _name_label: Label
	var _salary_label: Label
	var _status_label: Label

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
		custom_minimum_size = Vector2(300, 40)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.17, 0.2, 0.8)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		add_child(hbox)

		# 解雇复选框
		_fire_checkbox = CheckBox.new()
		_fire_checkbox.toggled.connect(_on_checkbox_toggled)
		hbox.add_child(_fire_checkbox)

		# 角色颜色条
		var role_color := ColorRect.new()
		role_color.custom_minimum_size = Vector2(6, 30)
		var role: String = str(employee_def.get("role", "special"))
		role_color.color = ROLE_COLORS.get(role, Color(0.5, 0.5, 0.5, 1))
		hbox.add_child(role_color)

		# 员工名称
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 14)
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(_name_label)

		# 状态标签（忙碌）
		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(_status_label)

		# 薪资标签
		_salary_label = Label.new()
		_salary_label.add_theme_font_size_override("font_size", 14)
		_salary_label.custom_minimum_size = Vector2(60, 0)
		_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(_salary_label)

		update_display()

	func update_display() -> void:
		if _name_label != null:
			var name: String = str(employee_def.get("name", employee_type))
			_name_label.text = name

		if _salary_label != null:
			if requires_salary:
				_salary_label.text = "$%d" % salary_amount
				_salary_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.5, 1))
			else:
				_salary_label.text = "-"
				_salary_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))

		if _status_label != null:
			if is_busy:
				_status_label.text = "[忙碌]"
				_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4, 1))
				# 忙碌营销员通常不能解雇
				if _fire_checkbox != null:
					_fire_checkbox.disabled = true
			else:
				_status_label.text = ""

	func _on_checkbox_toggled(toggled: bool) -> void:
		fire_toggled.emit(employee_type, toggled)
