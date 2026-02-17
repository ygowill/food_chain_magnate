# ProductionPanel：饮料采购 UI/选择逻辑（拆分自 production_panel.gd）
extends RefCounted

const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const FoodTypeItemClass = preload("res://ui/components/production_panel/production_panel_food_type_item.gd")

var _panel = null

func setup(panel) -> void:
	_panel = panel

func build_drinks_controls(parent: VBoxContainer) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	p._drink_type_label = Label.new()
	p._drink_type_label.text = "跑腿伙计：选择饮料"
	p._drink_type_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_hint_dark(p._drink_type_label)
	parent.add_child(p._drink_type_label)

	p._drink_type_container = HFlowContainer.new()
	p._drink_type_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._drink_type_container.add_theme_constant_override("h_separation", 10)
	p._drink_type_container.add_theme_constant_override("v_separation", 10)
	parent.add_child(p._drink_type_container)

	p._drinks_restaurant_label = Label.new()
	p._drinks_restaurant_label.text = "起点餐厅"
	p._drinks_restaurant_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_hint_dark(p._drinks_restaurant_label)
	parent.add_child(p._drinks_restaurant_label)

	p._drinks_restaurant_option = OptionButton.new()
	p._drinks_restaurant_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._drinks_restaurant_option.custom_minimum_size = Vector2.ZERO if p.is_embedded_in_right_panel() else Vector2(380, 0)
	p._drinks_restaurant_option.item_selected.connect(_on_drinks_restaurant_selected)
	parent.add_child(p._drinks_restaurant_option)
	UiStylesClass.apply_option_button_field(p._drinks_restaurant_option)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	p._drinks_selection_label = Label.new()
	p._drinks_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._drinks_selection_label.add_theme_font_size_override("font_size", 12)
	p._drinks_selection_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	row.add_child(p._drinks_selection_label)

	p._drinks_undo_btn = Button.new()
	p._drinks_undo_btn.text = "撤销"
	p._drinks_undo_btn.pressed.connect(_on_drinks_undo_pressed)
	row.add_child(p._drinks_undo_btn)
	UiStylesClass.apply_button_secondary(p._drinks_undo_btn)

	p._drinks_clear_btn = Button.new()
	p._drinks_clear_btn.text = "清空"
	p._drinks_clear_btn.pressed.connect(_on_drinks_clear_pressed)
	row.add_child(p._drinks_clear_btn)
	UiStylesClass.apply_button_secondary(p._drinks_clear_btn)

	p._drinks_error_label = Label.new()
	p._drinks_error_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_error(p._drinks_error_label)
	p._drinks_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p._drinks_error_label.visible = false
	parent.add_child(p._drinks_error_label)

	rebuild_drink_type_options()
	rebuild_drinks_restaurant_options()

func rebuild_drink_type_options() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	var prev_selected := str(p._selected_drink_type)
	p._selected_drink_type = ""
	p._drink_type_items.clear()
	if p._drink_type_container == null:
		return

	UiRebuildHelpersClass.free_children(p._drink_type_container)
	p._ensure_skin()
	for t in p._available_drink_types:
		var item := FoodTypeItemClass.new()
		item.product_id = str(t)
		item.display_name = p._get_product_display_name(str(t))
		item.icon_texture = p._get_product_icon_texture(str(t))
		item.pressed.connect(_on_drink_type_item_pressed)
		p._drink_type_container.add_child(item)
		p._drink_type_items[str(t)] = item

	var desired := ""
	if not prev_selected.is_empty() and p._drink_type_items.has(prev_selected):
		desired = prev_selected
	elif not p._available_drink_types.is_empty():
		desired = str(p._available_drink_types[0])
	if not desired.is_empty():
		select_drink_type(desired, false)

func rebuild_drinks_restaurant_options() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if p._drinks_restaurant_option == null:
		return
	var opts: Array[Dictionary] = []
	for rid in p._drinks_available_restaurants:
		opts.append({
			"id": rid,
			"label": str(p._drinks_restaurant_label_by_id.get(rid, rid)),
		})
	p.set_drinks_procure_restaurants(opts, p._drinks_selected_restaurant_id, p._drinks_restaurant_require_selection)

func update_drinks_controls_visibility() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if str(p._production_type) != "drinks":
		return
	var is_errand := str(p._selected_employee_type) == "errand_boy"
	if p._drink_type_label != null:
		p._drink_type_label.visible = is_errand
	if p._drink_type_container != null:
		p._drink_type_container.visible = is_errand
	if p._drinks_restaurant_label != null:
		p._drinks_restaurant_label.visible = (not is_errand) and bool(p._drinks_restaurant_show_selector)
	if p._drinks_restaurant_option != null:
		p._drinks_restaurant_option.visible = (not is_errand) and bool(p._drinks_restaurant_show_selector)
	if p._drinks_selection_label != null:
		p._drinks_selection_label.visible = not is_errand
	if p._drinks_undo_btn != null:
		p._drinks_undo_btn.visible = not is_errand
	if p._drinks_clear_btn != null:
		p._drinks_clear_btn.visible = not is_errand
	if p._drinks_error_label != null:
		p._drinks_error_label.visible = (not is_errand) and (not str(p._drinks_error_label.text).is_empty())

func update_drinks_selection_label() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if p._drinks_selection_label == null:
		return
	if p._is_air_procure_employee_type(str(p._selected_employee_type)):
		p._drinks_selection_label.text = "板块: %d（从餐厅开始选择）" % int(p._drinks_selected_sources_count)
	else:
		p._drinks_selection_label.text = "进货点: %d（点击地图选择）" % int(p._drinks_selected_sources_count)
	if p._drinks_undo_btn != null:
		if p._is_air_procure_employee_type(str(p._selected_employee_type)):
			p._drinks_undo_btn.disabled = int(p._drinks_selected_sources_count) <= 1
		else:
			p._drinks_undo_btn.disabled = int(p._drinks_selected_sources_count) <= 0
	if p._drinks_clear_btn != null:
		p._drinks_clear_btn.disabled = int(p._drinks_selected_sources_count) <= 0

func select_drink_type(product_id: String, update_ui: bool = true) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	var pid := str(product_id).strip_edges()
	p._selected_drink_type = pid if (not pid.is_empty() and p._drink_type_items.has(pid)) else ""
	for k in p._drink_type_items.keys():
		var item_val = p._drink_type_items.get(k, null)
		if item_val != null and is_instance_valid(item_val) and item_val.has_method("set_selected"):
			item_val.call("set_selected", str(k) == p._selected_drink_type)

	if update_ui:
		p._update_confirm_state()
		p._update_info()

func _on_drink_type_item_pressed(product_id: String) -> void:
	select_drink_type(product_id, true)

func _on_drinks_restaurant_selected(index: int) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if p._suppress_drinks_restaurant_signal:
		return
	if p._drinks_restaurant_option == null:
		return
	if index < 0 or index >= p._drinks_restaurant_option.get_item_count():
		return
	var meta = p._drinks_restaurant_option.get_item_metadata(index)
	p._drinks_selected_restaurant_id = str(meta).strip_edges()
	p.drinks_restaurant_changed.emit(p._drinks_selected_restaurant_id)
	p._update_confirm_state()
	p._update_info()

func _on_drinks_clear_pressed() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	p.drinks_clear_requested.emit()

func _on_drinks_undo_pressed() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	p.drinks_undo_requested.emit()
