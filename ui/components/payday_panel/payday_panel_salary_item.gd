# PaydayPanel：薪资列表项（从 payday_panel.gd 抽取）
extends PanelContainer

signal fire_toggled(item_key: String, selected: bool)

var item_key: String = ""
var employee_id: String = ""
var location: String = ""
var employee_def: Dictionary = {}
var requires_salary: bool = false
var is_busy: bool = false
var salary_amount: int = 0
var can_be_fired: bool = true
var _fire_enabled: bool = true

var _fire_checkbox: CheckBox
var _name_label: Label
var _salary_label: Label
var _status_label: Label
var _location_label: Label

const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 40)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.88, 0.78, 0.95)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# 解雇复选框
	_fire_checkbox = CheckBox.new()
	UiStylesClass.apply_check_box_field(_fire_checkbox)
	_fire_checkbox.toggled.connect(_on_checkbox_toggled)
	hbox.add_child(_fire_checkbox)

	# 角色颜色条
	var role_color := ColorRect.new()
	role_color.custom_minimum_size = Vector2(6, 30)
	var role: String = str(employee_def.get("role", "special"))
	role_color.color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))
	hbox.add_child(role_color)

	# 员工名称
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	UiStylesClass.apply_label_dark(_name_label)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_name_label)

	_location_label = Label.new()
	_location_label.add_theme_font_size_override("font_size", 12)
	_location_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	hbox.add_child(_location_label)

	# 状态标签（忙碌）
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_dark(_status_label)
	hbox.add_child(_status_label)

	# 薪资标签
	_salary_label = Label.new()
	_salary_label.add_theme_font_size_override("font_size", 14)
	_salary_label.custom_minimum_size = Vector2(60, 0)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_salary_label)

	update_display()

func set_fire_enabled(enabled: bool) -> void:
	_fire_enabled = enabled
	update_display()

func set_selected(selected: bool) -> void:
	if _fire_checkbox != null:
		_fire_checkbox.set_pressed_no_signal(selected)

func update_display() -> void:
	if _name_label != null:
		var name: String = str(employee_def.get("name", employee_id))
		_name_label.text = name

	if _salary_label != null:
		if requires_salary:
			_salary_label.text = "$%d" % salary_amount
			_salary_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
		else:
			_salary_label.text = "-"
			_salary_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))

	if _location_label != null:
		match location:
			"active":
				_location_label.text = "[在岗]"
			"reserve":
				_location_label.text = "[待命]"
			"busy":
				_location_label.text = "[忙碌]"
			_:
				_location_label.text = ""

	if _status_label != null:
		_status_label.text = ""

	if _fire_checkbox != null:
		_fire_checkbox.disabled = (not can_be_fired) or (not _fire_enabled)

func _on_checkbox_toggled(toggled: bool) -> void:
	fire_toggled.emit(item_key, toggled)
