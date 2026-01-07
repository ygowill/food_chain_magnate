# 单个玩家信息项组件
class_name PlayerInfoItem
extends PanelContainer

signal item_clicked(player_id: int)

var player_id: int = -1
var player_color: Color = Color.WHITE

var color_rect: ColorRect = null
var name_label: Label = null
var cash_label: Label = null
var employee_label: Label = null
var restaurant_label: Label = null

var _highlighted: bool = false

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _build_ui() -> void:
	custom_minimum_size = Vector2(200, 36)

	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# 玩家颜色标识
	color_rect = ColorRect.new()
	color_rect.name = "ColorRect"
	color_rect.custom_minimum_size = Vector2(8, 0)
	color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(color_rect)

	# 玩家名称
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_label)

	# 现金
	cash_label = Label.new()
	cash_label.name = "CashLabel"
	cash_label.custom_minimum_size = Vector2(60, 0)
	cash_label.add_theme_font_size_override("font_size", 14)
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(cash_label)

	# 员工数
	employee_label = Label.new()
	employee_label.name = "EmployeeLabel"
	employee_label.custom_minimum_size = Vector2(40, 0)
	employee_label.add_theme_font_size_override("font_size", 12)
	employee_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	employee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(employee_label)

	# 餐厅数
	restaurant_label = Label.new()
	restaurant_label.name = "RestaurantLabel"
	restaurant_label.custom_minimum_size = Vector2(40, 0)
	restaurant_label.add_theme_font_size_override("font_size", 12)
	restaurant_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	restaurant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(restaurant_label)

func update_data(player: Dictionary) -> void:
	if not is_instance_valid(color_rect):
		return

	color_rect.color = player_color
	name_label.text = "P%d" % (player_id + 1)

	var cash: int = int(player.get("cash", 0))
	cash_label.text = "$%d" % cash

	var emp_count: int = 0
	emp_count += Array(player.get("employees", [])).size()
	emp_count += Array(player.get("reserve_employees", [])).size()
	emp_count += Array(player.get("busy_marketers", [])).size()
	employee_label.text = "%d人" % emp_count

	var rest_count: int = Array(player.get("restaurants", [])).size()
	restaurant_label.text = "%d店" % rest_count

func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_update_style()

func _update_style() -> void:
	if _highlighted:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.5, 0.7, 0.4)
		style.border_color = Color(0.5, 0.7, 0.9, 0.8)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 0.6)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			item_clicked.emit(player_id)
