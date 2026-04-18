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

	_safe_free(panel)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()
