# 生产面板组件
# 对齐 gameplay：`produce_food` 仅需 `employee_type`；`procure_drinks`：`errand_boy` 需 `drink_type`，其它员工需 `route/selected_sources`（由上层组装下发）
class_name ProductionPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal production_requested(employee_type: String, production_type: String)
signal cancelled()
signal producer_changed(employee_type: String, production_type: String)
signal drinks_clear_requested()
signal drinks_undo_requested()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var products_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ProductsContainer
@onready var summary_label: Label = $MarginContainer/VBoxContainer/SummaryLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")

var _production_type: String = "food"  # food | drinks
var _available_producers: Array[String] = []
var _current_inventory: Dictionary = {}

var _employee_option: OptionButton = null
var _info_label: Label = null
var _selected_employee_type: String = ""

var _food_type_option: OptionButton = null
var _food_type_label: Label = null
var _available_food_types: Array[String] = []
var _selected_food_type: String = ""

var _drink_type_option: OptionButton = null
var _drink_type_label: Label = null
var _drinks_selection_label: Label = null
var _drinks_error_label: Label = null
var _drinks_undo_btn: Button = null
var _drinks_clear_btn: Button = null

var _available_drink_types: Array[String] = []
var _selected_drink_type: String = ""
var _drinks_selected_sources_count: int = 0
var _drinks_confirm_ready: bool = false

func _get_confirm_button() -> Button:
	return confirm_btn

func _get_cancel_button() -> Button:
	return cancel_btn

func _on_panel_ready() -> void:
	_rebuild()
	_apply_embedding_layout()

func _apply_embedding(embedded: bool) -> void:
	super._apply_embedding(embedded)
	_apply_embedding_layout()

func set_production_type(production_type: String) -> void:
	_production_type = production_type
	_rebuild()

func set_available_producers(producers: Array[String]) -> void:
	_available_producers = producers.duplicate()
	_rebuild()

func set_current_inventory(inventory: Dictionary) -> void:
	_current_inventory = inventory.duplicate()
	_update_info()

func set_available_drink_types(types: Array[String]) -> void:
	_available_drink_types.clear()
	for t in types:
		if t.is_empty():
			continue
		if _available_drink_types.has(t):
			continue
		_available_drink_types.append(t)
	_available_drink_types.sort()
	_rebuild_drink_type_options()
	_update_confirm_state()
	_update_info()

func get_selected_drink_type() -> String:
	return _selected_drink_type

func get_selected_food_type() -> String:
	return _selected_food_type

func set_drinks_procurement_state(selected_sources_count: int, confirm_ready: bool, error_text: String = "") -> void:
	_drinks_selected_sources_count = maxi(0, selected_sources_count)
	_drinks_confirm_ready = confirm_ready
	if _drinks_error_label != null:
		_drinks_error_label.text = str(error_text).strip_edges()
		_drinks_error_label.visible = not _drinks_error_label.text.is_empty()
	_update_drinks_selection_label()
	_update_confirm_state()
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
		mode_label.text = "选择员工并执行采购（饮料需要手动选点生成路线）" if is_drinks else "选择厨师并执行生产（产品由员工卡决定）"
	if confirm_btn != null:
		confirm_btn.text = "确认采购" if is_drinks else "确认生产"

func _rebuild_content() -> void:
	if products_container == null:
		return

	UiRebuildHelpersClass.free_children(products_container)

	var embedded := is_embedded_in_right_panel()
	_employee_option = OptionButton.new()
	_employee_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_option.custom_minimum_size = Vector2.ZERO if embedded else Vector2(380, 0)
	_employee_option.item_selected.connect(_on_employee_selected)
	products_container.add_child(_employee_option)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	products_container.add_child(_info_label)

	_food_type_label = null
	_food_type_option = null
	_available_food_types.clear()
	_selected_food_type = ""

	_drink_type_label = null
	_drink_type_option = null
	_drinks_selection_label = null
	_drinks_error_label = null
	_drinks_undo_btn = null
	_drinks_clear_btn = null
	_drinks_selected_sources_count = 0
	_drinks_confirm_ready = false
	_selected_drink_type = ""

	if _production_type == "food":
		_build_food_controls(products_container)

	if _production_type == "drinks":
		_build_drinks_controls(products_container)

	_rebuild_employee_options()
	_rebuild_food_type_options()
	_update_food_controls_visibility()
	_update_drinks_controls_visibility()
	_update_drinks_selection_label()
	_apply_embedding_layout()

func _apply_embedding_layout() -> void:
	var embedded := is_embedded_in_right_panel()
	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if embedded else ScrollContainer.SCROLL_MODE_DISABLED
	if _employee_option != null:
		_employee_option.custom_minimum_size = Vector2.ZERO if embedded else Vector2(380, 0)
	if _food_type_option != null:
		_food_type_option.custom_minimum_size = Vector2.ZERO if embedded else Vector2(380, 0)
	if _drink_type_option != null:
		_drink_type_option.custom_minimum_size = Vector2.ZERO if embedded else Vector2(380, 0)

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
	_rebuild_food_type_options()
	_update_food_controls_visibility()
	_update_drinks_controls_visibility()
	_update_confirm_state()
	_update_info()

func _selected_changed() -> void:
	producer_changed.emit(_selected_employee_type, _production_type)

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return
	var enabled := not _selected_employee_type.is_empty()
	if _production_type == "drinks":
		if _selected_employee_type == "errand_boy":
			enabled = enabled and not _selected_drink_type.is_empty()
		else:
			enabled = enabled and _drinks_confirm_ready
	elif _production_type == "food":
		if not _available_food_types.is_empty():
			enabled = enabled and not _selected_food_type.is_empty()
	confirm_btn.disabled = not enabled
	right_panel_footer_changed.emit()

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
		if _selected_employee_type == "errand_boy":
			var drink_text := _selected_drink_type if not _selected_drink_type.is_empty() else "（请选择）"
			_info_label.text = "%s：选择 1 种饮料并直接获得 1 瓶（%s）。" % [emp_name, drink_text]
		else:
			var suffix := "（请点击地图上的饮料点）"
			if _drinks_selected_sources_count > 0:
				suffix = "（已选进货点: %d）" % _drinks_selected_sources_count
			_info_label.text = "%s：点击地图饮料点逐个选择 → 系统生成路线 → 确认后开始采购%s" % [emp_name, suffix]
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

	var options_val = info.get("food_options", null)
	if options_val is Array:
		var amount2 := int(info.get("amount", 1))
		var chosen := _selected_food_type
		var chosen_text := "（请选择）"
		var current2 := 0
		if not chosen.is_empty():
			chosen_text = _get_product_display_name(chosen)
			current2 = int(_current_inventory.get(chosen, 0))
		_info_label.text = "%s：选择生产 %s ×%d（当前库存: %d）。" % [emp_name, chosen_text, amount2, current2]
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

func _build_drinks_controls(parent: VBoxContainer) -> void:
	_drink_type_label = Label.new()
	_drink_type_label.text = "跑腿伙计：选择饮料"
	_drink_type_label.add_theme_font_size_override("font_size", 12)
	parent.add_child(_drink_type_label)

	_drink_type_option = OptionButton.new()
	_drink_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drink_type_option.custom_minimum_size = Vector2.ZERO if is_embedded_in_right_panel() else Vector2(380, 0)
	_drink_type_option.item_selected.connect(_on_drink_type_selected)
	parent.add_child(_drink_type_option)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	_drinks_selection_label = Label.new()
	_drinks_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drinks_selection_label.add_theme_font_size_override("font_size", 12)
	_drinks_selection_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82, 1))
	row.add_child(_drinks_selection_label)

	_drinks_undo_btn = Button.new()
	_drinks_undo_btn.text = "撤销"
	_drinks_undo_btn.pressed.connect(_on_drinks_undo_pressed)
	row.add_child(_drinks_undo_btn)

	_drinks_clear_btn = Button.new()
	_drinks_clear_btn.text = "清空"
	_drinks_clear_btn.pressed.connect(_on_drinks_clear_pressed)
	row.add_child(_drinks_clear_btn)

	_drinks_error_label = Label.new()
	_drinks_error_label.add_theme_font_size_override("font_size", 12)
	_drinks_error_label.add_theme_color_override("font_color", Color(1, 0.45, 0.45, 1))
	_drinks_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drinks_error_label.visible = false
	parent.add_child(_drinks_error_label)

	_rebuild_drink_type_options()

func _build_food_controls(parent: VBoxContainer) -> void:
	_food_type_label = Label.new()
	_food_type_label.text = "见习厨师：选择食物"
	_food_type_label.add_theme_font_size_override("font_size", 12)
	parent.add_child(_food_type_label)

	_food_type_option = OptionButton.new()
	_food_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_food_type_option.custom_minimum_size = Vector2.ZERO if is_embedded_in_right_panel() else Vector2(380, 0)
	_food_type_option.item_selected.connect(_on_food_type_selected)
	parent.add_child(_food_type_option)

	_rebuild_food_type_options()

func _rebuild_food_type_options() -> void:
	_selected_food_type = ""
	_available_food_types.clear()
	if _food_type_option == null:
		return
	_food_type_option.clear()
	_available_food_types = _get_food_options_for_employee(_selected_employee_type)
	for t in _available_food_types:
		_food_type_option.add_item(_get_product_display_name(t))
		var idx := _food_type_option.get_item_count() - 1
		_food_type_option.set_item_metadata(idx, t)
	if _food_type_option.get_item_count() > 0:
		_food_type_option.select(0)
		_apply_selected_food_type(0)

func _get_food_options_for_employee(employee_type: String) -> Array[String]:
	var emp_id := str(employee_type)
	if emp_id.is_empty():
		return []
	if not EmployeeRegistryClass.is_loaded():
		return []
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val == null or not (def_val is EmployeeDef):
		return []
	var def: EmployeeDef = def_val
	var info: Dictionary = def.get_production_info()
	var opts_val = info.get("food_options", null)
	if not (opts_val is Array):
		return []

	var out: Array[String] = []
	var opts: Array = opts_val
	for v in opts:
		var pid := str(v)
		if pid.is_empty():
			continue
		if out.has(pid):
			continue
		out.append(pid)
	out.sort()
	return out

func _apply_selected_food_type(index: int) -> void:
	if _food_type_option == null:
		return
	if index < 0 or index >= _food_type_option.get_item_count():
		return
	var meta = _food_type_option.get_item_metadata(index)
	_selected_food_type = str(meta)

func _on_food_type_selected(index: int) -> void:
	_apply_selected_food_type(index)
	_update_confirm_state()
	_update_info()

func _update_food_controls_visibility() -> void:
	if _production_type != "food":
		return
	var has_choice := not _available_food_types.is_empty()
	if _food_type_label != null:
		_food_type_label.visible = has_choice
	if _food_type_option != null:
		_food_type_option.visible = has_choice

func _rebuild_drink_type_options() -> void:
	_selected_drink_type = ""
	if _drink_type_option == null:
		return
	_drink_type_option.clear()
	for t in _available_drink_types:
		_drink_type_option.add_item(_get_product_display_name(t))
		var idx := _drink_type_option.get_item_count() - 1
		_drink_type_option.set_item_metadata(idx, t)
	if _drink_type_option.get_item_count() > 0:
		_drink_type_option.select(0)
		_apply_selected_drink_type(0)

func _apply_selected_drink_type(index: int) -> void:
	if _drink_type_option == null:
		return
	if index < 0 or index >= _drink_type_option.get_item_count():
		return
	var meta = _drink_type_option.get_item_metadata(index)
	_selected_drink_type = str(meta)

func _on_drink_type_selected(index: int) -> void:
	_apply_selected_drink_type(index)
	_update_confirm_state()
	_update_info()

func _on_drinks_clear_pressed() -> void:
	drinks_clear_requested.emit()

func _on_drinks_undo_pressed() -> void:
	drinks_undo_requested.emit()

func _update_drinks_controls_visibility() -> void:
	if _production_type != "drinks":
		return
	var is_errand := _selected_employee_type == "errand_boy"
	if _drink_type_label != null:
		_drink_type_label.visible = is_errand
	if _drink_type_option != null:
		_drink_type_option.visible = is_errand
	if _drinks_selection_label != null:
		_drinks_selection_label.visible = not is_errand
	if _drinks_undo_btn != null:
		_drinks_undo_btn.visible = not is_errand
	if _drinks_clear_btn != null:
		_drinks_clear_btn.visible = not is_errand
	if _drinks_error_label != null:
		_drinks_error_label.visible = (not is_errand) and (not _drinks_error_label.text.is_empty())

func _update_drinks_selection_label() -> void:
	if _drinks_selection_label == null:
		return
	_drinks_selection_label.text = "进货点: %d（点击地图选择）" % _drinks_selected_sources_count
	if _drinks_undo_btn != null:
		_drinks_undo_btn.disabled = _drinks_selected_sources_count <= 0
	if _drinks_clear_btn != null:
		_drinks_clear_btn.disabled = _drinks_selected_sources_count <= 0

func _get_product_display_name(product_id: String) -> String:
	var pid := str(product_id)
	if pid.is_empty():
		return ""
	if not ProductRegistryClass.is_loaded():
		return pid
	var def_val = ProductRegistryClass.get_def(pid)
	if def_val != null and (def_val is ProductDef):
		var def: ProductDef = def_val
		if not def.name.is_empty():
			return def.name
	return pid
