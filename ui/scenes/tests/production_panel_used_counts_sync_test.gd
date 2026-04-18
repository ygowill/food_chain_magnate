class_name ProductionPanelUsedCountsSyncTest
extends RefCounted

const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")

static func run() -> Result:
	var r := await _case_provider_items_override_legacy_used_cache()
	if not r.ok:
		return r
	return Result.success({})

static func _case_provider_items_override_legacy_used_cache() -> Result:
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
	panel._used_employee_keys_by_mode = {
		"food": {"burger_cook#1": true, "burger_cook#2": true},
		"drinks": {},
	}
	await st.process_frame

	panel.set_producer_items([
		{"staff_id": 11, "employee_type": "burger_cook", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 12, "employee_type": "burger_cook", "capacity": 1, "used": 1, "remaining": 0},
	])
	await st.process_frame

	var picker = panel.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		_safe_free(panel)
		return Result.failure("ProductionPanel 未创建 employee picker")

	if picker.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("ProductionPanel 应为 provider items 渲染 2 个实例，实际: %d" % picker.get_child_count())

	if int(panel.get_selected_staff_id()) != 11:
		_safe_free(panel)
		return Result.failure("ProductionPanel 应默认选中剩余次数 > 0 的 staff_id=11，实际: %s" % str(panel.get_selected_staff_id()))

	if not picker.has_method("set_selected"):
		_safe_free(panel)
		return Result.failure("EmployeePicker 缺少 set_selected")
	picker.set_selected("staff:12")
	panel._on_employee_selected("burger_cook")
	if int(panel.get_selected_staff_id()) != 12:
		_safe_free(panel)
		return Result.failure("ProductionPanel 选择第二个实例后应保留 staff_id=12，实际: %s" % str(panel.get_selected_staff_id()))

	_safe_free(panel)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()
