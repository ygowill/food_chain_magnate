class_name RecruitTrainStaffPickerUiTest
extends RefCounted

const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")
const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const TrainControllerClass = preload("res://ui/scenes/game/panel/working/train_controller.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const MULTI_TRAINERS_SAVE_PATH := "res://testdata/saves/manual_cases/employees/multi_trainers.json"

static func run() -> Result:
	var r := await _case_recruit_panel_renders_duplicate_recruiters_as_instances()
	if not r.ok:
		return r
	r = await _case_train_panel_keeps_duplicate_trainers_by_staff_key()
	if not r.ok:
		return r
	r = await _case_train_panel_emits_selection_changed_on_trainer_and_source()
	if not r.ok:
		return r
	r = await _case_train_panel_keeps_duplicate_sources_by_staff_key()
	if not r.ok:
		return r
	r = await _case_single_use_recruiter_and_trainer_hide_usage_markers()
	if not r.ok:
		return r
	r = await _case_multi_use_trainer_keeps_usage_badge_without_tag()
	if not r.ok:
		return r
	r = await _case_train_source_items_hide_quantity_badge()
	if not r.ok:
		return r
	r = await _case_train_panel_shows_targets_after_trainer_and_source_selection()
	if not r.ok:
		return r
	r = await _case_train_panel_applies_cached_items_on_ready()
	if not r.ok:
		return r
	r = await _case_train_controller_show_populates_cached_items_after_ready()
	if not r.ok:
		return r
	r = await _case_multi_trainers_save_real_click_flow_shows_visible_targets()
	if not r.ok:
		return r
	r = await _case_train_panel_scrolls_when_content_is_tall()
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

static func _case_train_panel_emits_selection_changed_on_trainer_and_source() -> Result:
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
	var selection_changed_hits := []
	panel.selection_changed.connect(func() -> void:
		selection_changed_hits.append(true)
	)

	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 0},
	]
	var source_items: Array[Dictionary] = [
		{"staff_id": 21, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
	]

	panel.set_train_count(2, 2)
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命区员工（点击选择）")
	await st.process_frame

	trainer_picker.set_selected("staff:31")
	panel._on_trainer_selected("trainer")
	source_picker.set_selected("staff:21")
	panel._on_source_selected("marketing_trainee")

	if selection_changed_hits.size() != 2:
		_safe_free(panel)
		return Result.failure("TrainPanel 在培训员/来源选择变化时都应发出 selection_changed，实际次数: %d" % selection_changed_hits.size())

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

static func _case_single_use_recruiter_and_trainer_hide_usage_markers() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 Recruit/Train marker UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 Recruit/Train 面板）")

	var recruit_panel = RecruitPanelScene.instantiate()
	host.add_child(recruit_panel)
	await st.process_frame
	recruit_panel.set_recruit_count(1, 1)
	var recruiter_items: Array[Dictionary] = [
		{"staff_id": 11, "employee_type": "recruiting_girl", "capacity": 1, "used": 0, "remaining": 1},
	]
	recruit_panel.set_recruiters(recruiter_items)
	await st.process_frame

	var recruiter_item = recruit_panel.recruiter_container.get_child(0)
	if recruiter_item == null or not is_instance_valid(recruiter_item):
		_safe_free(recruit_panel)
		return Result.failure("RecruitPanel 未渲染 recruiter item")
	if str(recruiter_item.get("badge_text")) != "":
		_safe_free(recruit_panel)
		return Result.failure("单次 recruiter 不应显示 1/1 badge，实际: %s" % str(recruiter_item.get("badge_text")))
	if str(recruiter_item.get("tag_text")) != "":
		_safe_free(recruit_panel)
		return Result.failure("RecruitPanel recruiter 不应显示 可用/已用 tag，实际: %s" % str(recruiter_item.get("tag_text")))

	var train_panel = TrainPanelScene.instantiate()
	host.add_child(train_panel)
	await st.process_frame
	train_panel.set_train_count(1, 1)
	var trainer_items: Array[Dictionary] = [
		{"staff_id": 21, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1},
	]
	train_panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	await st.process_frame

	var trainer_item = train_panel.trainer_container.get_child(0)
	if trainer_item == null or not is_instance_valid(trainer_item):
		_safe_free(recruit_panel)
		_safe_free(train_panel)
		return Result.failure("TrainPanel 未渲染 trainer item")
	if str(trainer_item.get("badge_text")) != "":
		_safe_free(recruit_panel)
		_safe_free(train_panel)
		return Result.failure("单次 trainer 不应显示 1/1 badge，实际: %s" % str(trainer_item.get("badge_text")))
	if str(trainer_item.get("tag_text")) != "":
		_safe_free(recruit_panel)
		_safe_free(train_panel)
		return Result.failure("TrainPanel trainer 不应显示 可用/已用 tag，实际: %s" % str(trainer_item.get("tag_text")))

	_safe_free(recruit_panel)
	_safe_free(train_panel)
	return Result.success()

static func _case_multi_use_trainer_keeps_usage_badge_without_tag() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel badge UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")

	var panel = TrainPanelScene.instantiate()
	host.add_child(panel)
	await st.process_frame

	panel.set_train_count(3, 3)
	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "coach", "capacity": 3, "used": 1, "remaining": 2},
	]
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	await st.process_frame

	var trainer_item = panel.trainer_container.get_child(0)
	if trainer_item == null or not is_instance_valid(trainer_item):
		_safe_free(panel)
		return Result.failure("TrainPanel 未渲染 multi-use trainer item")
	if str(trainer_item.get("badge_text")) != "2/3":
		_safe_free(panel)
		return Result.failure("多次 trainer 应显示 2/3 badge，实际: %s" % str(trainer_item.get("badge_text")))
	if str(trainer_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("多次 trainer 也不应显示 可用/已用 tag，实际: %s" % str(trainer_item.get("tag_text")))

	_safe_free(panel)
	return Result.success()

static func _case_train_source_items_hide_quantity_badge() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel source badge UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")

	var panel = TrainPanelScene.instantiate()
	host.add_child(panel)
	await st.process_frame

	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1},
	]
	var source_items: Array[Dictionary] = [
		{"staff_id": 41, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
		{"staff_id": 42, "employee_type": "campaign_manager", "zone_key": "employees", "requires_same_color": true, "tag_text": "在岗", "badge_count": 1, "enabled": true},
	]

	panel.set_train_count(1, 1)
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命/在岗员工（点击选择）")
	await st.process_frame

	panel.trainer_container.set_selected("staff:31")
	panel._on_trainer_selected("trainer")
	await st.process_frame

	if panel.source_container.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("TrainPanel source 应渲染 2 个 item，实际: %d" % panel.source_container.get_child_count())

	var reserve_item = panel.source_container.get_child(0)
	var active_item = panel.source_container.get_child(1)
	if str(reserve_item.get("badge_text")) != "":
		_safe_free(panel)
		return Result.failure("培训来源待命员工不应显示数量 badge，实际: %s" % str(reserve_item.get("badge_text")))
	if str(active_item.get("badge_text")) != "":
		_safe_free(panel)
		return Result.failure("培训来源在岗员工不应显示数量 badge，实际: %s" % str(active_item.get("badge_text")))
	if str(active_item.get("tag_text")) != "在岗":
		_safe_free(panel)
		return Result.failure("培训来源仍应保留非数量 tag（如 在岗），实际: %s" % str(active_item.get("tag_text")))

	_safe_free(panel)
	return Result.success()

static func _case_train_panel_shows_targets_after_trainer_and_source_selection() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")
	var wrapper := Control.new()
	wrapper.name = "TrainPanelTargetVisibilityWrapper"
	wrapper.custom_minimum_size = Vector2(420, 320)
	wrapper.size = Vector2(420, 320)
	host.add_child(wrapper)

	var panel = TrainPanelScene.instantiate()
	wrapper.add_child(panel)
	panel.set_embedded_in_right_panel(true)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	await st.process_frame

	var trainer_picker = panel.trainer_container
	var source_picker = panel.source_container
	var target_picker = panel.target_container
	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 0},
	]
	var source_items: Array[Dictionary] = []
	for i in range(12):
		source_items.append({
			"staff_id": 21 + i,
			"employee_type": "marketing_trainee",
			"zone_key": "reserve_employees",
			"requires_same_color": false,
			"tag_text": "",
			"badge_count": 1,
			"enabled": true,
		})

	panel.set_train_count(2, 2)
	panel.set_employee_pool({"campaign_manager": 2})
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命区员工（点击选择）")
	var empty_target_items: Array[Dictionary] = []
	panel.set_target_items(empty_target_items, "培训目标")
	await st.process_frame

	if source_picker.get_child_count() < 8:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("测试前置条件失败：source 内容不足以复现目标区被顶到下方，实际: %d" % source_picker.get_child_count())

	trainer_picker.set_selected("staff:31")
	panel._on_trainer_selected("trainer")
	await st.process_frame

	source_picker.set_selected("staff:21")
	panel._on_source_selected("marketing_trainee")
	await st.process_frame

	var main_scroll = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer")
	if main_scroll == null or not (main_scroll is ScrollContainer):
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("TrainPanel 缺少主 ScrollContainer")

	var target_items: Array[Dictionary] = [
		{"employee_type": "campaign_manager", "steps_required": 1, "pool_count": 2, "enabled": true},
	]
	panel.set_target_items(target_items, "培训目标")
	await st.process_frame
	await st.process_frame
	await st.process_frame

	var target_item = target_picker.get_child(0)
	if target_item == null or not is_instance_valid(target_item):
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("选择 trainer/source 后 target 项不应消失")
	if not target_item.has_method("is_enabled"):
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("target 项缺少 is_enabled()")
	if not bool(target_item.is_enabled()):
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("选择 trainer/source 后，现有可达培训目标应变为可点击")

	var sc: ScrollContainer = main_scroll
	if int(sc.get_v_scroll_bar().max_value) <= 0:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("测试前置条件失败：主 ScrollContainer 没有纵向可滚动范围")
	if int(sc.scroll_vertical) <= 0:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("选择 trainer/source 并刷新目标后，应自动滚动到目标区，实际 scroll_vertical=%d" % int(sc.scroll_vertical))

	_safe_free(panel)
	_safe_free(wrapper)
	return Result.success()

static func _case_train_panel_applies_cached_items_on_ready() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")

	var panel = TrainPanelScene.instantiate()
	var trainer_items: Array[Dictionary] = [
		{"staff_id": 31, "employee_type": "trainer", "capacity": 1, "used": 0, "remaining": 1, "instance_idx": 0},
	]
	var source_items: Array[Dictionary] = [
		{"staff_id": 21, "employee_type": "marketing_trainee", "zone_key": "reserve_employees", "requires_same_color": false, "tag_text": "", "badge_count": 1, "enabled": true},
	]
	var target_items: Array[Dictionary] = [
		{"employee_type": "campaign_manager", "steps_required": 1, "pool_count": 2, "enabled": true},
	]

	# 先写缓存数据，再 add_child，模拟 controller.show() 在 panel _ready 之前推送状态。
	panel.set_train_count(2, 2)
	panel.set_employee_pool({"campaign_manager": 2})
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命区员工（点击选择）")
	panel.set_target_items(target_items, "培训目标")

	host.add_child(panel)
	await st.process_frame
	await st.process_frame

	if panel.trainer_container.get_child_count() <= 0:
		_safe_free(panel)
		return Result.failure("TrainPanel 应在 _ready 后把缓存的 trainer_items 渲染出来")
	if panel.source_container.get_child_count() <= 0:
		_safe_free(panel)
		return Result.failure("TrainPanel 应在 _ready 后把缓存的 source_items 渲染出来")
	if panel.target_container.get_child_count() <= 0:
		_safe_free(panel)
		return Result.failure("TrainPanel 应在 _ready 后把缓存的 target_items 渲染出来")

	_safe_free(panel)
	return Result.success()

static func _case_train_controller_show_populates_cached_items_after_ready() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainController UI 测试）")
	var st: SceneTree = tree
	var host_scene := st.current_scene
	if host_scene == null or not is_instance_valid(host_scene):
		return Result.failure("current_scene 为空（无法挂载 TrainController host）")

	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.turn_order = [0, 1]
	state.current_player_index = 0

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		engine.dispose()
		return Result.failure("取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		engine.dispose()
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_source := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_source.ok:
		engine.dispose()
		return Result.failure("取出 marketing_trainee 失败: %s" % take_source.error)
	var add_source := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_source.ok:
		engine.dispose()
		return Result.failure("添加 marketing_trainee 失败: %s" % add_source.error)

	var host := _TrainControllerHost.new()
	host.game_engine = engine
	host_scene.add_child(host)

	var controller = TrainControllerClass.new(host, Callable(), Callable(), Callable())
	controller.show()
	for _i in range(6):
		await st.process_frame

	var panel = controller.train_panel
	if panel == null or not is_instance_valid(panel):
		_safe_free(host)
		engine.dispose()
		return Result.failure("TrainController.show() 后 train_panel 为空")

	if panel.trainer_container.get_child_count() <= 0:
		_safe_free(panel)
		_safe_free(host)
		engine.dispose()
		return Result.failure("TrainController.show() 后 trainer items 应在 _ready 之后被渲染")
	if panel.source_container.get_child_count() <= 0:
		_safe_free(panel)
		_safe_free(host)
		engine.dispose()
		return Result.failure("TrainController.show() 后 source items 应在 _ready 之后被渲染")

	panel.trainer_container.set_selected("staff:%d" % int(Dictionary(add_trainer.value).get("staff_id", -1)))
	panel.trainer_container.employee_selected.emit("trainer")
	for _i in range(4):
		await st.process_frame
	panel.source_container.set_selected("staff:%d" % int(Dictionary(add_source.value).get("staff_id", -1)))
	panel.source_container.employee_selected.emit("marketing_trainee")
	for _i in range(8):
		await st.process_frame

	if panel.target_container.get_child_count() <= 0:
		_safe_free(panel)
		_safe_free(host)
		engine.dispose()
		return Result.failure("TrainController.show() 打开的面板在选择 trainer/source 后应显示 target items")

	_safe_free(panel)
	_safe_free(host)
	engine.dispose()
	return Result.success()

static func _case_multi_trainers_save_real_click_flow_shows_visible_targets() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 multi_trainers 真实链路 UI 测试）")
	var st: SceneTree = tree
	var host_scene := st.current_scene
	if host_scene == null or not is_instance_valid(host_scene):
		return Result.failure("current_scene 为空（无法挂载 game.tscn）")

	if NetClient != null:
		NetClient.shutdown()
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	Globals.reset_game_config()

	var engine := GameEngine.new()
	var load_r: Result = engine.load_from_file(ProjectSettings.globalize_path(MULTI_TRAINERS_SAVE_PATH))
	if not load_r.ok:
		Globals.reset_game_config()
		engine.dispose()
		return Result.failure("载入 multi_trainers 存档失败: %s" % load_r.error)

	Globals.current_game_engine = engine
	Globals.is_game_active = true

	var game = GameScene.instantiate()
	if game == null:
		await _cleanup_game_instance(null)
		engine.dispose()
		return Result.failure("实例化 game.tscn 失败")
	host_scene.add_child(game)
	for _i in range(12):
		await st.process_frame

	if game.game_engine == null:
		await _cleanup_game_instance(game)
		return Result.failure("game.tscn 未复用 multi_trainers 的 GameEngine")

	var panel_controller = game.get("_panel_controller")
	if panel_controller == null:
		await _cleanup_game_instance(game)
		return Result.failure("game.tscn 缺少 _panel_controller")
	panel_controller.on_action_requested("train", {})
	for _i in range(12):
		await st.process_frame

	var working_panels = panel_controller.get("_working_panels")
	if working_panels == null:
		await _cleanup_game_instance(game)
		return Result.failure("_panel_controller 缺少 _working_panels")
	var panel = working_panels.train_panel
	if panel == null or not is_instance_valid(panel):
		await _cleanup_game_instance(game)
		return Result.failure("真实链路打开 train 后 train_panel 为空")
	if panel.trainer_container.get_child_count() <= 0 or panel.source_container.get_child_count() <= 0:
		await _cleanup_game_instance(game)
		return Result.failure("multi_trainers 真实链路打开后应渲染 trainer/source（trainer=%d source=%d）" % [
			panel.trainer_container.get_child_count(),
			panel.source_container.get_child_count(),
		])

	var trainer_card := _find_first_picker_card(panel.trainer_container)
	if trainer_card == null:
		await _cleanup_game_instance(game)
		return Result.failure("未找到真实链路 trainer 可点击卡片")
	await _viewport_click(st, game.get_viewport(), trainer_card.get_global_rect().get_center())
	for _i in range(8):
		await st.process_frame
	if int(panel.get_selected_trainer_staff_id()) <= 0:
		await _cleanup_game_instance(game)
		return Result.failure("真实点击 trainer 后未设置 selected_trainer_staff_id")

	var source_card := _find_first_picker_card(panel.source_container)
	if source_card == null:
		await _cleanup_game_instance(game)
		return Result.failure("未找到真实链路 source 可点击卡片")
	await _viewport_click(st, game.get_viewport(), source_card.get_global_rect().get_center())
	for _i in range(16):
		await st.process_frame

	if int(panel.get_selected_source_staff_id()) <= 0:
		await _cleanup_game_instance(game)
		return Result.failure("真实点击 source 后未设置 selected_source_staff_id")
	if panel.target_container.get_child_count() <= 0:
		await _cleanup_game_instance(game)
		return Result.failure("multi_trainers 真实点击 trainer/source 后应渲染培训目标")

	var target_scroll = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TargetSection/TargetScroll")
	if target_scroll != null:
		await _cleanup_game_instance(game)
		return Result.failure("培训目标区域不应有独立 TargetScroll，应和 trainer/source 一样直接参与主滚动布局")
	var target_item = panel.target_container.get_child(0)
	if target_item == null or not (target_item is Control):
		await _cleanup_game_instance(game)
		return Result.failure("multi_trainers 已生成 target child 但不是 Control")
	var target_visible: bool = panel.content_scroll.get_global_rect().intersects((target_item as Control).get_global_rect())
	if not target_visible:
		await _cleanup_game_instance(game)
		return Result.failure("multi_trainers 培训目标已生成但不在主滚动区域可见范围内")

	await _cleanup_game_instance(game)
	return Result.success()

static func _case_train_panel_scrolls_when_content_is_tall() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 TrainPanel UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 TrainPanel）")

	var wrapper := Control.new()
	wrapper.name = "TrainPanelTallWrapper"
	wrapper.custom_minimum_size = Vector2(420, 320)
	wrapper.size = Vector2(420, 320)
	host.add_child(wrapper)

	var panel = TrainPanelScene.instantiate()
	wrapper.add_child(panel)
	panel.set_embedded_in_right_panel(true)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	await st.process_frame

	var trainer_items: Array[Dictionary] = []
	for i in range(10):
		trainer_items.append({
			"staff_id": 100 + i,
			"employee_type": "trainer",
			"capacity": 1,
			"used": 0,
			"remaining": 1,
			"instance_idx": i,
		})

	var source_items: Array[Dictionary] = []
	for j in range(16):
		source_items.append({
			"staff_id": 200 + j,
			"employee_type": "marketing_trainee",
			"zone_key": "reserve_employees",
			"requires_same_color": false,
			"tag_text": "",
			"badge_count": 1,
			"enabled": true,
		})

	var target_items: Array[Dictionary] = [
		{"employee_type": "campaign_manager", "steps_required": 1, "pool_count": 6, "enabled": true},
	]

	panel.set_train_count(20, 20)
	panel.set_employee_pool({"campaign_manager": 6})
	panel.set_trainer_items(trainer_items, "培训员（点击选择）")
	panel.set_source_items(source_items, "待命区员工（点击选择）")
	panel.set_target_items(target_items, "培训目标")

	await st.process_frame
	await st.process_frame
	await st.process_frame

	var trainer_container = panel.trainer_container
	var source_container = panel.source_container
	if trainer_container == null or source_container == null:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("TrainPanel 缺少 trainer/source 容器")

	if trainer_container.get_child_count() <= 0 or source_container.get_child_count() <= 0:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("测试前置条件失败：TrainPanel 未渲染出足够内容（trainer=%d source=%d）" % [
			trainer_container.get_child_count(),
			source_container.get_child_count(),
		])

	var content_bottom: float = 0.0
	var confirm_bottom: float = float(panel.confirm_btn.position.y + panel.confirm_btn.size.y)
	content_bottom = maxf(content_bottom, confirm_bottom)
	content_bottom = maxf(content_bottom, trainer_container.position.y + trainer_container.size.y)
	content_bottom = maxf(content_bottom, source_container.position.y + source_container.size.y)

	if content_bottom <= wrapper.size.y:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("测试前置条件失败：内容未超过宿主高度（content_bottom=%.1f wrapper_h=%.1f）" % [
			content_bottom,
			wrapper.size.y,
		])

	var main_scroll = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer")
	if main_scroll == null or not (main_scroll is ScrollContainer):
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("TrainPanel 内容过多时应存在主 ScrollContainer 承载全部内容")

	var vertical_max := int((main_scroll as ScrollContainer).get_v_scroll_bar().max_value)
	if vertical_max <= 0:
		_safe_free(panel)
		_safe_free(wrapper)
		return Result.failure("TrainPanel 主 ScrollContainer 在内容过多时应产生纵向滚动，实际 max_value=%d" % vertical_max)

	_safe_free(panel)
	_safe_free(wrapper)
	return Result.success()

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).queue_free()

static func _find_first_picker_card(picker) -> Control:
	if picker == null or not is_instance_valid(picker):
		return null
	if not picker.has_method("get_child_count") or int(picker.get_child_count()) <= 0:
		return null
	var item = picker.get_child(0)
	if item == null or not is_instance_valid(item):
		return null
	for child in item.get_children():
		if child is Control and child.has_signal("card_clicked"):
			return child
	return null

static func _viewport_click(st: SceneTree, viewport: Viewport, global_pos: Vector2) -> void:
	if st == null or viewport == null:
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = global_pos
	press.global_position = global_pos
	viewport.push_input(press, true)
	await st.process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = global_pos
	release.global_position = global_pos
	viewport.push_input(release, true)
	await st.process_frame

static func _cleanup_game_instance(game: Node) -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		for _i in range(8):
			await (tree as SceneTree).process_frame
	if NetClient != null:
		NetClient.shutdown()
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	if tree is SceneTree:
		for _j in range(4):
			await (tree as SceneTree).process_frame

class _TrainControllerHost extends Control:
	var game_engine = null
