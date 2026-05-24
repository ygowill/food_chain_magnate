class_name ProductionProcureStaffPickerUiTest
extends RefCounted

const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")

static func run() -> Result:
	var r := await _case_food_panel_renders_duplicate_staff_instances()
	if not r.ok:
		return r
	r = await _case_drinks_panel_keeps_selected_staff_id()
	if not r.ok:
		return r
	r = await _case_switching_to_drinks_clears_food_staff_cards()
	if not r.ok:
		return r
	r = await _case_production_staff_badge_rules_hide_single_use_and_tags()
	if not r.ok:
		return r
	return Result.success({})

static func _case_food_panel_renders_duplicate_staff_instances() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 ProductionPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ProductionPanel）")

	var panel = ProductionPanelScene.instantiate()
	host.add_child(panel)
	panel.set_production_type("food")
	await st.process_frame

	panel.set_producer_items([
		{"staff_id": 31, "employee_type": "burger_cook", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 32, "employee_type": "burger_cook", "capacity": 1, "used": 0, "remaining": 1},
	])
	await st.process_frame

	var picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("food 面板未创建 employee picker")

	if picker.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("food 面板应渲染 2 个 burger_cook 实例，实际: %d" % picker.get_child_count())

	picker.set_selected("staff:32")
	panel._on_employee_selected("burger_cook")
	if int(panel.get_selected_staff_id()) != 32:
		_safe_free(panel)
		return Result.failure("food 面板选择第二个实例后应保留 staff_id=32，实际: %s" % str(panel.get_selected_staff_id()))

	_safe_free(panel)
	return Result.success()

static func _case_switching_to_drinks_clears_food_staff_cards() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 ProductionPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ProductionPanel）")

	var panel = ProductionPanelScene.instantiate()
	host.add_child(panel)
	panel.set_production_type("food")
	await st.process_frame

	panel.set_producer_items([
		{"staff_id": 51, "employee_type": "kitchen_trainee", "capacity": 1, "used": 0, "remaining": 1},
	])
	await st.process_frame

	var picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("food->drinks 切换前未创建 employee picker")
	if picker.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("food 面板应先渲染 1 个见习厨师，实际: %d" % picker.get_child_count())

	panel.set_production_type("drinks")
	await st.process_frame

	picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("food->drinks 切换后未创建 employee picker")
	if picker.get_child_count() != 0:
		_safe_free(panel)
		return Result.failure("切到 drinks 时不应残留 food 员工卡，实际 child_count=%d" % picker.get_child_count())
	if str(panel.get_selected_employee_type()).strip_edges() != "":
		_safe_free(panel)
		return Result.failure("切到 drinks 且无采购员时 selected employee 应清空，实际: %s" % str(panel.get_selected_employee_type()))

	panel.set_producer_items([])
	await st.process_frame
	picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("drinks 空 provider 刷新后未创建 employee picker")
	if picker.get_child_count() != 0:
		_safe_free(panel)
		return Result.failure("drinks 空 provider 刷新后仍不应显示员工卡，实际 child_count=%d" % picker.get_child_count())

	_safe_free(panel)
	return Result.success()

static func _case_drinks_panel_keeps_selected_staff_id() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 ProductionPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ProductionPanel）")

	var panel = ProductionPanelScene.instantiate()
	host.add_child(panel)
	panel.set_production_type("drinks")
	await st.process_frame

	panel.set_producer_items([
		{"staff_id": 41, "employee_type": "truck_driver", "capacity": 1, "used": 1, "remaining": 0},
		{"staff_id": 42, "employee_type": "truck_driver", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 43, "employee_type": "truck_driver", "capacity": 1, "used": 0, "remaining": 1},
	])
	await st.process_frame

	var picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("drinks 面板未创建 employee picker")

	if int(panel.get_selected_staff_id()) != 42:
		_safe_free(panel)
		return Result.failure("drinks 面板应默认选中剩余次数 > 0 的 staff_id=42，实际: %s" % str(panel.get_selected_staff_id()))

	picker.set_selected("staff:41")
	panel._on_employee_selected("truck_driver")
	if int(panel.get_selected_staff_id()) != 41:
		_safe_free(panel)
		return Result.failure("drinks 面板切换选择后应保留 staff_id=41，实际: %s" % str(panel.get_selected_staff_id()))

	picker.set_selected("staff:42")
	panel._on_employee_selected("truck_driver")
	if int(panel.get_selected_staff_id()) != 42:
		_safe_free(panel)
		return Result.failure("drinks 面板选择第二个实例后应保留 staff_id=42，实际: %s" % str(panel.get_selected_staff_id()))

	if not panel.has_method("refresh_producer_items"):
		_safe_free(panel)
		return Result.failure("ProductionPanel 缺少 refresh_producer_items")
	panel.refresh_producer_items([
		{"staff_id": 41, "employee_type": "truck_driver", "capacity": 1, "used": 1, "remaining": 0},
		{"staff_id": 42, "employee_type": "truck_driver", "capacity": 1, "used": 1, "remaining": 0},
		{"staff_id": 43, "employee_type": "truck_driver", "capacity": 1, "used": 0, "remaining": 1},
	])
	await st.process_frame

	picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("drinks 面板刷新后未创建 employee picker")
	if int(panel.get_selected_staff_id()) != 43:
		_safe_free(panel)
		return Result.failure("第二个同名采购员用完后应自动选中 staff_id=43，实际: %s" % str(panel.get_selected_staff_id()))
	if picker.get_child_count() != 3:
		_safe_free(panel)
		return Result.failure("drinks 面板刷新后应保留 3 个 staff item，实际: %d" % picker.get_child_count())
	var second_item = picker.get_child(1)
	var third_item = picker.get_child(2)
	if second_item == null or not is_instance_valid(second_item) or not second_item.has_method("is_enabled"):
		_safe_free(panel)
		return Result.failure("第二个同名采购员 item 缺少 is_enabled")
	if bool(second_item.call("is_enabled")):
		_safe_free(panel)
		return Result.failure("第二个同名采购员用完后应灰显")
	if third_item == null or not is_instance_valid(third_item) or not third_item.has_method("is_enabled"):
		_safe_free(panel)
		return Result.failure("第三个同名采购员 item 缺少 is_enabled")
	if not bool(third_item.call("is_enabled")):
		_safe_free(panel)
		return Result.failure("第二个同名采购员用完后不应误灰显第三个")

	_safe_free(panel)
	return Result.success()

static func _case_production_staff_badge_rules_hide_single_use_and_tags() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 ProductionPanel badge UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ProductionPanel）")

	var panel = ProductionPanelScene.instantiate()
	host.add_child(panel)
	panel.set_production_type("food")
	await st.process_frame

	panel.set_producer_items([
		{"staff_id": 51, "employee_type": "burger_cook", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 52, "employee_type": "pizza_cook", "capacity": 3, "used": 1, "remaining": 2},
	])
	await st.process_frame

	var picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("food 面板未创建 employee picker")
	if picker.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("food 面板应渲染 2 个 staff item，实际: %d" % picker.get_child_count())

	var single_item = picker.get_child(0)
	var multi_item = picker.get_child(1)
	if str(single_item.get("badge_text")) != "":
		_safe_free(panel)
		return Result.failure("单次 production staff 不应显示 1/1 badge，实际: %s" % str(single_item.get("badge_text")))
	if str(single_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("ProductionPanel 单次 staff 不应显示 可用/已用 tag，实际: %s" % str(single_item.get("tag_text")))
	if str(multi_item.get("badge_text")) != "2/3":
		_safe_free(panel)
		return Result.failure("多次 production staff 应显示 2/3 badge，实际: %s" % str(multi_item.get("badge_text")))
	if str(multi_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("ProductionPanel 多次 staff 不应显示 可用/已用 tag，实际: %s" % str(multi_item.get("tag_text")))

	_safe_free(panel)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()
