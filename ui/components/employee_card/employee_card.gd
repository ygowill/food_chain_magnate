# 员工卡牌组件
# 显示单张员工卡的信息
class_name EmployeeCard
extends PanelContainer

signal card_clicked(employee_id: String)
signal card_drag_started(employee_id: String)
signal card_drag_ended(employee_id: String, drop_position: Vector2)

@export var employee_id: String = ""
@export var show_salary_indicator: bool = true
@export var draggable: bool = true

# 职责颜色映射（与 EmployeeDef 保持一致）
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

var _employee_def: Dictionary = {}
var _selected: bool = false
var _busy: bool = false
var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO

# UI 子节点
var _role_color_rect: ColorRect
var _name_label: Label
var _salary_indicator: Label
var _description_label: Label
var _level_label: Label

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _build_ui() -> void:
	custom_minimum_size = Vector2(120, 80)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	# 顶部：角色颜色条 + 名称
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(top_hbox)

	_role_color_rect = ColorRect.new()
	_role_color_rect.custom_minimum_size = Vector2(6, 20)
	top_hbox.add_child(_role_color_rect)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(_name_label)

	_salary_indicator = Label.new()
	_salary_indicator.add_theme_font_size_override("font_size", 14)
	_salary_indicator.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1))
	top_hbox.add_child(_salary_indicator)

	# 中部：等级指示
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	vbox.add_child(_level_label)

	# 底部：简短描述
	_description_label = Label.new()
	_description_label.add_theme_font_size_override("font_size", 10)
	_description_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(_description_label)

	_update_style()

func setup(employee_def: Dictionary) -> void:
	_employee_def = employee_def
	employee_id = str(employee_def.get("id", ""))
	_update_display()

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func set_busy(busy: bool) -> void:
	_busy = busy
	_update_style()

func _update_display() -> void:
	if _name_label == null:
		return

	var name: String = str(_employee_def.get("name", employee_id))
	_name_label.text = name

	var role: String = str(_employee_def.get("role", "special"))
	var color: Color = ROLE_COLORS.get(role, Color(0.5, 0.5, 0.5, 1))
	_role_color_rect.color = color

	var salary: bool = bool(_employee_def.get("salary", true))
	_salary_indicator.text = "$" if (salary and show_salary_indicator) else ""
	_salary_indicator.visible = salary and show_salary_indicator

	# 等级：根据是否可培训推断
	var train_to: Array = Array(_employee_def.get("train_to", []))
	var is_entry = _employee_def.get("tags", []).has("entry_level") if _employee_def.has("tags") else false
	if is_entry:
		_level_label.text = "Lv.1 (入门级)"
	elif train_to.is_empty():
		_level_label.text = "Lv.3 (高级)"
	else:
		_level_label.text = "Lv.2 (中级)"

	var desc: String = str(_employee_def.get("description", ""))
	if desc.length() > 30:
		desc = desc.substr(0, 30) + "..."
	_description_label.text = desc

func _update_style() -> void:
	var style := StyleBoxFlat.new()

	if _busy:
		style.bg_color = Color(0.3, 0.3, 0.35, 0.5)
		modulate = Color(0.6, 0.6, 0.6, 0.8)
	elif _selected:
		style.bg_color = Color(0.3, 0.5, 0.7, 0.6)
		style.border_color = Color(0.5, 0.8, 1.0, 0.9)
		style.set_border_width_all(2)
		modulate = Color(1, 1, 1, 1)
	else:
		style.bg_color = Color(0.18, 0.2, 0.22, 0.9)
		modulate = Color(1, 1, 1, 1)

	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_start_pos = e.position
				_dragging = false
				card_clicked.emit(employee_id)
			else:
				if _dragging and draggable:
					_dragging = false
					card_drag_ended.emit(employee_id, get_global_mouse_position())

	if event is InputEventMouseMotion and draggable:
		var e2: InputEventMouseMotion = event
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var distance := e2.position.distance_to(_drag_start_pos)
			if distance > 5.0 and not _dragging:
				_dragging = true
				card_drag_started.emit(employee_id)
