# MarketingPanel module marketing type regression test
# Ensures module-defined marketing types (e.g., gourmet_guide) appear in the MarketingPanel selector.
class_name MarketingPanelModuleTypesUiTest
extends RefCounted

const MarketingPanelClass = preload("res://ui/components/marketing_panel/marketing_panel.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

static func run() -> Result:
	var r1 := _case_module_type_visible()
	if not r1.ok:
		return r1
	var r2 := _case_duplicate_marketers_render_multiple_items()
	if not r2.ok:
		return r2
	return Result.success({})

static func _case_module_type_visible() -> Result:
	var panel := MarketingPanelClass.new()
	var container := HFlowContainer.new()
	panel.add_child(container)
	panel.type_container = container

	panel.set_available_marketers([
		{"staff_id": 1, "employee_type": "gourmet_food_critic", "type": "gourmet_guide", "marketing_types": ["gourmet_guide"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
	])
	panel.set_available_boards({"gourmet_guide": [17, 18]})

	if str(panel._selected_type) != "gourmet_guide":
		_safe_free(panel)
		return Result.failure("MarketingPanel should auto-select the only available type gourmet_guide (selected=%s)" % str(panel._selected_type))

	if not panel._type_buttons.has("gourmet_guide"):
		_safe_free(panel)
		return Result.failure("MarketingPanel should include module marketing type gourmet_guide")

	var btn = panel._type_buttons.get("gourmet_guide", null)
	if btn == null or not is_instance_valid(btn):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide button invalid: %s" % str(btn))

	if str(btn.type_id) != "gourmet_guide":
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide type_id mismatch: %s" % str(btn.type_id))

	if not bool(btn.is_available):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide should be available when marketer+boards exist")

	_safe_free(panel)
	return Result.success({})

static func _case_duplicate_marketers_render_multiple_items() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_marketers([
		{"staff_id": 11, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 12, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
	])
	panel.set_available_boards({"billboard": [11, 13]})

	if str(panel._selected_type) != "billboard":
		_safe_free(panel)
		return Result.failure("MarketingPanel should auto-select billboard in duplicate marketer case (selected=%s)" % str(panel._selected_type))

	var item_count := picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("MarketingPanel should render 2 marketer items for duplicate marketers, got: %d" % item_count)
	if int(panel._selected_staff_id) != 11:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应默认选中最小可用 staff_id=11，实际: %s" % str(panel._selected_staff_id))
	if not picker.has_method("set_selected"):
		_safe_free(panel)
		return Result.failure("EmployeePicker 缺少 set_selected")
	picker.set_selected("staff:12")
	panel._on_marketer_selected("marketing_trainee")
	if int(panel._selected_staff_id) != 12:
		_safe_free(panel)
		return Result.failure("MarketingPanel 切换实例后应保留 staff_id=12，实际: %s" % str(panel._selected_staff_id))

	_safe_free(panel)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
