# 单个玩家信息项组件
class_name PlayerInfoItem
extends PanelContainer

const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

signal item_clicked(player_id: int)

var player_id: int = -1
var player_color: Color = Color.WHITE

var color_rect: ColorRect = null
var name_label: Label = null
var cash_label: Label = null
var employee_label: Label = null
var restaurant_label: Label = null

var _is_current: bool = false
var _is_view: bool = false
var _last_cash: int = -999999

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _build_ui() -> void:
	if is_instance_valid(color_rect):
		return
	custom_minimum_size = Vector2(240, 36)

	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	# 玩家颜色标识
	color_rect = ColorRect.new()
	color_rect.name = "ColorRect"
	color_rect.custom_minimum_size = Vector2(8, 0)
	color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(color_rect)

	# 玩家名称
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	# 现金
	cash_label = Label.new()
	cash_label.name = "CashLabel"
	cash_label.custom_minimum_size = Vector2(60, 0)
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cash_label)

	# 员工数
	employee_label = Label.new()
	employee_label.name = "EmployeeLabel"
	employee_label.custom_minimum_size = Vector2(40, 0)
	employee_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	employee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	employee_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(employee_label)

	# 餐厅数
	restaurant_label = Label.new()
	restaurant_label.name = "RestaurantLabel"
	restaurant_label.custom_minimum_size = Vector2(40, 0)
	restaurant_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	restaurant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	restaurant_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(restaurant_label)

	apply_font_settings()

func apply_font_settings() -> void:
	var scale := 1.0
	if Globals != null:
		scale = clampf(float(Globals.font_scale), 0.5, 2.0)
	custom_minimum_size = Vector2(240, float(maxi(36, int(round(36.0 * scale)))))

	var fs_main := 14
	var fs_small := 12
	if Globals != null:
		fs_main = int(Globals.get_scaled_font_size(14))
		fs_small = int(Globals.get_scaled_font_size(12))

	if is_instance_valid(name_label):
		name_label.add_theme_font_size_override("font_size", fs_main)
	if is_instance_valid(cash_label):
		cash_label.add_theme_font_size_override("font_size", fs_main)
	if is_instance_valid(employee_label):
		employee_label.add_theme_font_size_override("font_size", fs_small)
	if is_instance_valid(restaurant_label):
		restaurant_label.add_theme_font_size_override("font_size", fs_small)

func update_data(player: Dictionary) -> void:
	if not is_instance_valid(color_rect):
		_build_ui()
	if not is_instance_valid(color_rect):
		return

	color_rect.color = player_color
	name_label.text = Globals.get_player_name(player_id)

	var cash: int = int(player.get("cash", 0))
	cash_label.text = "$%d" % cash
	_animate_cash_change(cash)

	var emp_count: int = 0
	emp_count += Array(player.get("employees", [])).size()
	emp_count += Array(player.get("reserve_employees", [])).size()
	emp_count += Array(player.get("busy_marketers", [])).size()
	employee_label.text = "%d人" % emp_count

	var rest_count: int = Array(player.get("restaurants", [])).size()
	restaurant_label.text = "%d店" % rest_count

func set_selection(is_current: bool, is_view: bool) -> void:
	_is_current = is_current
	_is_view = is_view
	_update_style()

func set_highlighted(highlighted: bool) -> void:
	set_selection(highlighted, highlighted)

func _animate_cash_change(new_cash: int) -> void:
	if OS.has_feature("headless"):
		_last_cash = new_cash
		return
	if not is_instance_valid(cash_label):
		_last_cash = new_cash
		return

	if _last_cash != -999999 and _last_cash != new_cash:
		var delta := new_cash - _last_cash
		var pulse := Color(0.6, 1.0, 0.6, 1) if delta > 0 else Color(1.0, 0.6, 0.6, 1)
		var tween := create_tween()
		tween.tween_property(cash_label, "modulate", pulse, 0.08)
		tween.tween_property(cash_label, "modulate", Color(1, 1, 1, 1), 0.25)

	_last_cash = new_cash

func _update_style() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)

	if _is_view:
		style.bg_color = Color(player_color.r, player_color.g, player_color.b, 0.22)
		style.border_color = player_color
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.92, 0.88, 0.78, 0.6)
		style.border_color = Color(0.25, 0.25, 0.3, 0.7)
		style.set_border_width_all(1)

	# 当前行动玩家：优先白色边框
	if _is_current:
		style.border_color = Color(0.95, 0.95, 0.95, 0.9)
		style.set_border_width_all(2)

	add_theme_stylebox_override("panel", style)

func _on_gui_input(event: InputEvent) -> void:
	if UiPointerInputClass.is_primary_press(event):
		item_clicked.emit(player_id)
