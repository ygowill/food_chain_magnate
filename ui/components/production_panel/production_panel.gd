# 生产面板组件
# 对齐 gameplay：`produce_food`/`procure_drinks` 仅需 `employee_type`
class_name ProductionPanel
extends Control

signal production_requested(employee_type: String, production_type: String)
signal cancelled()
signal producer_changed(employee_type: String, production_type: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var products_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ProductsContainer
@onready var summary_label: Label = $MarginContainer/VBoxContainer/SummaryLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

var _production_type: String = "food"  # food | drinks
var _available_producers: Array[String] = []
var _current_inventory: Dictionary = {}

var _employee_option: OptionButton = null
var _info_label: Label = null
var _selected_employee_type: String = ""

func _ready() -> void:
	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	_rebuild()

func set_production_type(production_type: String) -> void:
	_production_type = production_type
	_rebuild()

func set_available_producers(producers: Array[String]) -> void:
	_available_producers = producers.duplicate()
	_rebuild()

func set_current_inventory(inventory: Dictionary) -> void:
	_current_inventory = inventory.duplicate()
	_update_info()

func _rebuild() -> void:
	_update_header()
	_rebuild_content()
	_update_confirm_state()
	_update_info()

func _update_header() -> void:
	var is_drinks := _production_type == "drinks"
	if title_label != null:
		title_label.text = "采购饮料" if is_drinks else "生产食物"
	if mode_label != null:
		mode_label.text = "选择员工并执行采购（路线将自动规划）" if is_drinks else "选择厨师并执行生产（产品由员工卡决定）"
	if confirm_btn != null:
		confirm_btn.text = "确认采购" if is_drinks else "确认生产"

func _rebuild_content() -> void:
	if products_container == null:
		return

	for child in products_container.get_children():
		if is_instance_valid(child):
			child.queue_free()

	_employee_option = OptionButton.new()
	_employee_option.custom_minimum_size = Vector2(380, 0)
	_employee_option.item_selected.connect(_on_employee_selected)
	products_container.add_child(_employee_option)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	products_container.add_child(_info_label)

	_rebuild_employee_options()

func _rebuild_employee_options() -> void:
	_selected_employee_type = ""
	if _employee_option == null:
		return

	_employee_option.clear()

	var counts: Dictionary = {}
	for v in _available_producers:
		var emp_id := str(v)
		if emp_id.is_empty():
			continue
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

	var ids: Array[String] = []
	for k in counts.keys():
		ids.append(str(k))
	ids.sort()

	for emp_id2 in ids:
		var count: int = int(counts.get(emp_id2, 0))
		var label := "%s ×%d" % [_get_employee_display_name(emp_id2), count]
		_employee_option.add_item(label)
		var idx := _employee_option.get_item_count() - 1
		_employee_option.set_item_metadata(idx, emp_id2)

	if _employee_option.get_item_count() > 0:
		_employee_option.disabled = false
		_employee_option.select(0)
		_apply_selected_employee(0)
	else:
		_employee_option.disabled = true
	_selected_changed()

func _apply_selected_employee(index: int) -> void:
	if _employee_option == null:
		return
	if index < 0 or index >= _employee_option.get_item_count():
		return
	var meta = _employee_option.get_item_metadata(index)
	_selected_employee_type = str(meta)

func _on_employee_selected(index: int) -> void:
	_apply_selected_employee(index)
	_selected_changed()
	_update_confirm_state()
	_update_info()

func _selected_changed() -> void:
	producer_changed.emit(_selected_employee_type, _production_type)

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return
	confirm_btn.disabled = _selected_employee_type.is_empty()

func _update_info() -> void:
	if summary_label != null:
		summary_label.text = ""
	if _info_label == null:
		return
	if _selected_employee_type.is_empty():
		_info_label.text = "没有可用员工"
		return

	var emp_name := _get_employee_display_name(_selected_employee_type)
	if _production_type == "drinks":
		_info_label.text = "%s 将执行一次采购饮料（系统自动规划路线并拾取饮料源）。" % emp_name
		return

	# food
	if not EmployeeRegistryClass.is_loaded():
		_info_label.text = "%s 将执行一次生产（产品由员工卡决定）。" % emp_name
		return

	var def_val = EmployeeRegistryClass.get_def(_selected_employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		_info_label.text = "%s 将执行一次生产（产品由员工卡决定）。" % emp_name
		return
	var def: EmployeeDef = def_val
	var info: Dictionary = def.get_production_info()
	if info.is_empty():
		_info_label.text = "%s 无法生产食物。" % emp_name
		return

	var food_type := str(info.get("food_type", ""))
	var amount := int(info.get("amount", 0))
	var food_name := food_type
	if ProductRegistryClass.is_loaded():
		var p_def_val = ProductRegistryClass.get_def(food_type)
		if p_def_val != null and (p_def_val is ProductDef):
			food_name = str((p_def_val as ProductDef).name)
	var current := int(_current_inventory.get(food_type, 0))
	_info_label.text = "%s 将生产：%s ×%d（当前库存: %d）。" % [emp_name, food_name, amount, current]

func _get_employee_display_name(employee_type: String) -> String:
	if employee_type.is_empty():
		return ""
	if not EmployeeRegistryClass.is_loaded():
		return employee_type
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		return employee_type
	var def: EmployeeDef = def_val
	return def.name if not def.name.is_empty() else employee_type

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_employee_type.is_empty():
		return
	production_requested.emit(_selected_employee_type, _production_type)

func _on_cancel_pressed() -> void:
	cancelled.emit()
