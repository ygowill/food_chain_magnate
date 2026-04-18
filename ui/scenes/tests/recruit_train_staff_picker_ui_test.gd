class_name RecruitTrainStaffPickerUiTest
extends RefCounted

const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")

static func run() -> Result:
	var r := await _case_recruit_panel_renders_duplicate_recruiters_as_instances()
	if not r.ok:
		return r
	r = await _case_train_panel_keeps_duplicate_trainers_by_staff_key()
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
	var panel = RecruitPanelScene.instantiate()
	host.add_child(panel)
	await st.process_frame

	var recruiter_picker = panel.recruiter_container
	var recruiters: Array[Dictionary] = [
		{"staff_id": 11, "employee_type": "recruiting_girl", "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 12, "employee_type": "recruiting_girl", "capacity": 1, "used": 0, "remaining": 1},
	]

	panel.set_recruit_count(2, 2)
	panel.set_recruiters(recruiters)
	panel.set_employee_pool({"waitress": 3, "trainer": 2})
	await st.process_frame

	var item_count: int = recruiter_picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("RecruitPanel 应为重复 recruiter staff 渲染 2 个实例，实际: %d" % item_count)

	_safe_free(panel)
	return Result.success()

static func _case_train_panel_keeps_duplicate_trainers_by_staff_key() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")
	var panel = TrainPanelScene.instantiate()
	host.add_child(panel)
	await st.process_frame

	var trainer_picker = panel.trainer_container
	var trainers: Array[Dictionary] = [
		{"staff_id": 11, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 0},
		{"staff_id": 12, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 1},
	]

	panel.set_train_count(3, 3)
	panel.set_trainer_items(trainers, "培训员（点击选择）")
	await st.process_frame

	var item_count: int = trainer_picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("TrainPanel 应为重复 trainer staff 渲染 2 个实例，实际: %d" % item_count)

	trainer_picker.set_selected("staff:12")
	panel._on_trainer_selected("trainer")
	if int(panel.get_selected_trainer_staff_id()) != 12:
		_safe_free(panel)
		return Result.failure("TrainPanel 选择第二个 trainer staff 后应保留 staff_id=12，实际: %s" % str(panel.get_selected_trainer_staff_id()))

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
	var panel = TrainPanelScene.instantiate()
	host.add_child(panel)
	await st.process_frame

	var trainer_picker = panel.trainer_container
	var source_picker = panel.source_container
	var target_picker = panel.target_container
	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 0},
	]
	var source_items: Array[Dictionary] = [
		{"staff_id": 21, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
		{"staff_id": 22, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
	]
	var target_items: Array[Dictionary] = [
		{"employee_type": "campaign_manager", "steps_required": 1, "pool_count": 2, "enabled": true},
	]

	panel.set_train_count(2, 2)
	panel.set_employee_pool({"campaign_manager": 2, "brand_manager": 2})
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命区员工（点击选择）")
	panel.set_target_items(target_items, "培训目标")
	await st.process_frame

	trainer_picker.set_selected("staff:31")
	panel._on_trainer_selected("trainer")

	var item_count: int = source_picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("TrainPanel 应为重复来源 staff 渲染 2 个实例，实际: %d" % item_count)

	if not source_picker.has_method("set_selected") or not source_picker.has_method("get_selected_key"):
		_safe_free(panel)
		return Result.failure("EmployeePicker 缺少实例选择接口")
	source_picker.set_selected("staff:22")
	panel._on_source_selected("marketing_trainee")
	if int(panel.get_selected_source_staff_id()) != 22:
		_safe_free(panel)
		return Result.failure("TrainPanel 选择第二个来源 staff 后应保留 staff_id=22，实际: %s" % str(panel.get_selected_source_staff_id()))

	target_picker.set_selected("campaign_manager")
	panel._on_target_selected("campaign_manager")
	var emitted: Array = []
	panel.train_requested.connect(func(trainer_staff_id: int, source_staff_id: int, from_employee: String, to_employee: String):
		emitted.clear()
		emitted.append_array([trainer_staff_id, source_staff_id, from_employee, to_employee])
	)
	panel._on_confirm_pressed()
	if emitted.size() != 4:
		_safe_free(panel)
		return Result.failure("TrainPanel 确认后应发出 train_requested 信号")
	if int(emitted[0]) != 31 or int(emitted[1]) != 22:
		_safe_free(panel)
		return Result.failure("TrainPanel 确认信号应包含 trainer_staff_id=31/source_staff_id=22，实际: %s" % str(emitted))

	_safe_free(panel)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()
