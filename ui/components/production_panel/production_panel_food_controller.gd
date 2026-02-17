# ProductionPanel：食物生产 UI/选择逻辑（拆分自 production_panel.gd）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const FoodTypeItemClass = preload("res://ui/components/production_panel/production_panel_food_type_item.gd")

var _panel = null

func setup(panel) -> void:
	_panel = panel

func build_food_controls(parent: VBoxContainer) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	p._food_type_label = Label.new()
	p._food_type_label.text = "见习厨师：选择食物"
	p._food_type_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_hint_dark(p._food_type_label)
	parent.add_child(p._food_type_label)

	p._food_type_container = HFlowContainer.new()
	p._food_type_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._food_type_container.add_theme_constant_override("h_separation", 10)
	p._food_type_container.add_theme_constant_override("v_separation", 10)
	parent.add_child(p._food_type_container)

	rebuild_food_type_options()

func rebuild_food_type_options() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	var prev_selected := str(p._selected_food_type)
	p._selected_food_type = ""
	if p._available_food_types is Array:
		p._available_food_types.clear()
	p._food_type_items.clear()
	if p._food_type_container == null:
		return

	UiRebuildHelpersClass.free_children(p._food_type_container)
	p._available_food_types = _get_food_options_for_employee(str(p._selected_employee_type))
	p._ensure_skin()
	for t in p._available_food_types:
		var item := FoodTypeItemClass.new()
		item.product_id = str(t)
		item.display_name = p._get_product_display_name(str(t))
		item.icon_texture = p._get_product_icon_texture(str(t))
		item.pressed.connect(_on_food_type_item_pressed)
		p._food_type_container.add_child(item)
		p._food_type_items[str(t)] = item

	var desired := ""
	if not prev_selected.is_empty() and p._food_type_items.has(prev_selected):
		desired = prev_selected
	elif not p._available_food_types.is_empty():
		desired = str(p._available_food_types[0])
	if not desired.is_empty():
		select_food_type(desired, false)

func update_food_controls_visibility() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if str(p._production_type) != "food":
		return
	var has_choice = not p._available_food_types.is_empty()
	if p._food_type_label != null:
		p._food_type_label.visible = has_choice
	if p._food_type_container != null:
		p._food_type_container.visible = has_choice

func select_food_type(product_id: String, update_ui: bool = true) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	var pid := str(product_id).strip_edges()
	p._selected_food_type = pid if (not pid.is_empty() and p._food_type_items.has(pid)) else ""
	for k in p._food_type_items.keys():
		var item_val = p._food_type_items.get(k, null)
		if item_val != null and is_instance_valid(item_val) and item_val.has_method("set_selected"):
			item_val.call("set_selected", str(k) == p._selected_food_type)

	if update_ui:
		p._update_confirm_state()
		p._update_info()

func _on_food_type_item_pressed(product_id: String) -> void:
	select_food_type(product_id, true)

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
