class_name RecruitTrainStaffPickerUiTest
extends RefCounted

const RecruitPanelClass = preload("res://ui/components/recruit_panel/recruit_panel.gd")
const TrainPanelClass = preload("res://ui/components/train_panel/train_panel.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

static func run() -> Result:
	var r := await _case_recruit_panel_renders_duplicate_recruiters_as_instances()
	if not r.ok:
		return r
	r = await _case_train_panel_keeps_duplicate_sources_by_staff_key()
	if not r.ok:
		return r
	return Result.success({})

static func _case_recruit_panel_renders_duplicate_recruiters_as_instances() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 RecruitPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 RecruitPanel）")
	var panel := RecruitPanelClass.new()
	var recruiter_picker := EmployeePickerClass.new()
	var target_picker := EmployeePickerClass.new()
	host.add_child(panel)
	panel.add_child(recruiter_picker)
	panel.add_child(target_picker)
	panel.recruiter_container = recruiter_picker
	panel.items_container = target_picker

	panel.set_recruit_count(2, 2)
	panel.set_recruiters([
		{"staff_id": 11, "employee_type": "recruiting_girl", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 12, "employee_type": "recruiting_girl", "capacity": 1, "used": 0, "remaining": 1},
	])
	panel.set_employee_pool({"waitress": 3, "trainer": 2})
	await st.process_frame

	var item_count := recruiter_picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("RecruitPanel 应为重复 recruiter staff 渲染 2 个实例，实际: %d" % item_count)

	_safe_free(panel)
	return Result.success()

static func _case_train_panel_keeps_duplicate_sources_by_staff_key() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")
	var panel := TrainPanelClass.new()
	var source_picker := EmployeePickerClass.new()
	var target_picker := EmployeePickerClass.new()
	host.add_child(panel)
	panel.add_child(source_picker)
	panel.add_child(target_picker)
	panel.trainable_container = source_picker
	panel.path_container = target_picker

	panel.set_train_count(2, 2)
	panel.set_employee_pool({"campaign_manager": 2, "brand_manager": 2})
	panel.set_max_steps_one_employee(1)
	panel.set_trainable_source_items([
		{"staff_id": 21, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
		{"staff_id": 22, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
	], "待命区员工（点击选择）")
	await st.process_frame

	var item_count := source_picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("TrainPanel 应为重复来源 staff 渲染 2 个实例，实际: %d" % item_count)

	if not source_picker.has_method("set_selected") or not source_picker.has_method("get_selected_key"):
		_safe_free(panel)
		return Result.failure("EmployeePicker 缺少实例选择接口")
	source_picker.set_selected("staff:22")
	panel._on_source_selected("marketing_trainee")
	if int(panel._selected_source_staff_id) != 22:
		_safe_free(panel)
		return Result.failure("TrainPanel 选择第二个来源 staff 后应保留 staff_id=22，实际: %s" % str(panel._selected_source_staff_id))

	_safe_free(panel)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()
