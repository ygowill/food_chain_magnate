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
	var r3 := _case_marketer_badge_rules_hide_single_use_and_tags()
	if not r3.ok:
		return r3
	var r4 := _case_single_multitype_marketer_renders_once_and_filters_types()
	if not r4.ok:
		return r4
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

static func _case_marketer_badge_rules_hide_single_use_and_tags() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_marketers([
		{"staff_id": 21, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 22, "employee_type": "campaign_manager", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 3, "capacity": 3, "used": 1, "remaining": 2},
	])
	panel.set_available_boards({"billboard": [11, 13]})

	if picker.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应渲染 2 个 marketer item，实际: %d" % picker.get_child_count())

	var single_item = picker.get_child(0)
	var multi_item = picker.get_child(1)
	if str(single_item.get("badge_text")) != "":
		_safe_free(panel)
		return Result.failure("单次 marketer 不应显示 1/1 badge，实际: %s" % str(single_item.get("badge_text")))
	if str(single_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("MarketingPanel 单次 marketer 不应显示 可用/已用 tag，实际: %s" % str(single_item.get("tag_text")))
	if str(multi_item.get("badge_text")) != "2/3":
		_safe_free(panel)
		return Result.failure("多次 marketer 应显示 2/3 badge，实际: %s" % str(multi_item.get("badge_text")))
	if str(multi_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("MarketingPanel 多次 marketer 不应显示 可用/已用 tag，实际: %s" % str(multi_item.get("tag_text")))

	_safe_free(panel)
	return Result.success({})

static func _case_single_multitype_marketer_renders_once_and_filters_types() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_boards({"billboard": [11], "mailbox": [21]})
	panel.set_available_marketers([
		{"staff_id": 31, "employee_type": "campaign_manager", "type": "billboard", "marketing_types": ["billboard", "mailbox"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 31, "employee_type": "campaign_manager", "type": "mailbox", "marketing_types": ["billboard", "mailbox"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
	])

	if picker.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("同一 staff 支持多个营销类型时，MarketingPanel 应只渲染 1 个 marketer item，实际: %d" % picker.get_child_count())
	if int(panel._selected_staff_id) != 31:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应先默认选中唯一营销员 staff_id=31，实际: %s" % str(panel._selected_staff_id))
	if str(panel._selected_type) != "":
		_safe_free(panel)
		return Result.failure("唯一营销员有多个可用营销类型时，不应自动选择类型，实际: %s" % str(panel._selected_type))
	if not panel._type_buttons.has("billboard") or not panel._type_buttons.has("mailbox"):
		_safe_free(panel)
		return Result.failure("选中 campaign_manager 后应显示 billboard/mailbox 类型按钮，实际: %s" % str(panel._type_buttons.keys()))

	panel._on_type_selected("billboard")
	if picker.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("选择营销类型后不应重复渲染同一营销员，实际: %d" % picker.get_child_count())
	if int(panel._selected_staff_id) != 31:
		_safe_free(panel)
		return Result.failure("选择营销类型后应保留先选的营销员 staff_id=31，实际: %s" % str(panel._selected_staff_id))

	_safe_free(panel)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
