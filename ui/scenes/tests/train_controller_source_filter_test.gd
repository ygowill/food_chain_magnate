class_name TrainControllerSourceFilterTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/panel/working/train_controller.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const Support = preload("res://core/tests/milestone_system/milestone_system_test_support.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(seed_val: int = 12345) -> Result:
	var r_without_trainer := _test_unselected_trainer_keeps_recruited_source_visible(seed_val)
	if not r_without_trainer.ok:
		return r_without_trainer

	var r_recruit_then_train := _test_recruited_employee_visible_after_recruit_then_train(seed_val)
	if not r_recruit_then_train.ok:
		return r_recruit_then_train

	var r_without_milestone := _test_newly_trained_employee_filtered_without_milestone(seed_val)
	if not r_without_milestone.ok:
		return r_without_milestone

	var r_with_milestone := _test_chain_train_source_kept_with_milestone(seed_val)
	if not r_with_milestone.ok:
		return r_with_milestone

	return Result.success({"cases": 4})

static func _test_unselected_trainer_keeps_recruited_source_visible(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val + 17)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		engine.dispose()
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		engine.dispose()
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		engine.dispose()
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		engine.dispose()
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var controller = ControllerClass.new(null, Callable(), Callable(), Callable())
	var source_items: Array = controller._build_trainable_source_items_from_staff(state, 0)
	var unfiltered: Array = controller._filter_source_items_for_trainer(state, 0, -1, source_items)
	if not _has_source_employee_type(unfiltered, "marketing_trainee"):
		engine.dispose()
		return Result.failure("未选择培训员时，待命/刚招聘员工仍应显示在培训来源中: %s" % str(unfiltered))

	engine.dispose()
	return Result.success(unfiltered)

static func _test_recruited_employee_visible_after_recruit_then_train(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val + 29)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		engine.dispose()
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		engine.dispose()
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var recruit := engine.execute_command(Command.create("recruit", 0, {
		"employee_type": "marketing_trainee",
	}))
	if not recruit.ok:
		engine.dispose()
		return Result.failure("recruit(marketing_trainee) 失败: %s" % recruit.error)

	state = engine.get_state()
	if state.sub_phase != DefsClass.SUB_PHASE_TRAIN:
		engine.dispose()
		return Result.failure("招聘后应进入 Train 子阶段，实际: %s" % str(state.sub_phase))

	var controller = ControllerClass.new(null, Callable(), Callable(), Callable())
	var source_items: Array = controller._build_trainable_source_items_from_staff(state, 0)
	if not _has_source_employee_type(source_items, "marketing_trainee"):
		engine.dispose()
		return Result.failure("刚招聘的 marketing_trainee 应出现在培训来源中: %s" % str(source_items))

	var trainer_staff_id := _read_first_trainer_staff_id(state, 0)
	if trainer_staff_id <= 0:
		engine.dispose()
		return Result.failure("未找到可用 trainer_staff_id")
	var filtered: Array = controller._filter_source_items_for_trainer(state, 0, trainer_staff_id, source_items)
	if not _has_source_employee_type(filtered, "marketing_trainee"):
		engine.dispose()
		return Result.failure("选中培训员后，刚招聘的 marketing_trainee 仍应保留在培训来源中: %s" % str(filtered))

	engine.dispose()
	return Result.success(filtered)

static func _test_newly_trained_employee_filtered_without_milestone(seed_val: int) -> Result:
	var setup_r := _build_chain_train_state(seed_val, false)
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = setup_r.value
	var engine: GameEngine = setup.get("engine", null)
	var state: GameState = setup.get("state", null)
	if engine == null or state == null:
		return Result.failure("测试构建结果无效")

	var controller = ControllerClass.new(null, Callable(), Callable(), Callable())
	var source_items: Array = controller._build_trainable_source_items_from_staff(state, 0)
	if not _has_source_employee_type(source_items, "campaign_manager"):
		engine.dispose()
		return Result.failure("首轮培训后，来源列表中应包含 campaign_manager 以复现 UI 过滤场景")

	var trainer_staff_id := _read_first_trainer_staff_id(state, 0)
	if trainer_staff_id <= 0:
		engine.dispose()
		return Result.failure("未找到可用 trainer_staff_id")
	var filtered: Array = controller._filter_source_items_for_trainer(state, 0, trainer_staff_id, source_items)
	if _has_source_employee_type(filtered, "campaign_manager"):
		engine.dispose()
		return Result.failure("默认规则下，已在本子阶段培训过的 campaign_manager 不应继续出现在培训来源中: %s" % str(filtered))

	engine.dispose()
	return Result.success(filtered)

static func _test_chain_train_source_kept_with_milestone(seed_val: int) -> Result:
	var setup_r := _build_chain_train_state(seed_val, true)
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = setup_r.value
	var engine: GameEngine = setup.get("engine", null)
	var state: GameState = setup.get("state", null)
	if engine == null or state == null:
		return Result.failure("测试构建结果无效")

	var controller = ControllerClass.new(null, Callable(), Callable(), Callable())
	var source_items: Array = controller._build_trainable_source_items_from_staff(state, 0)
	var trainer_staff_id := _read_first_trainer_staff_id(state, 0)
	if trainer_staff_id <= 0:
		engine.dispose()
		return Result.failure("未找到可用 trainer_staff_id")
	var filtered: Array = controller._filter_source_items_for_trainer(state, 0, trainer_staff_id, source_items)
	if not _has_source_employee_type(filtered, "campaign_manager"):
		engine.dispose()
		return Result.failure("multi_trainer_on_one 生效时，campaign_manager 应保留在培训来源中: %s" % str(filtered))

	engine.dispose()
	return Result.success(filtered)

static func _build_chain_train_state(seed_val: int, allow_chain_train: bool) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	if allow_chain_train:
		state.players[0]["multi_trainer_on_one"] = true

	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			engine.dispose()
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			engine.dispose()
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		engine.dispose()
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		engine.dispose()
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager"
	}))
	if not t1.ok:
		engine.dispose()
		return Result.failure("首轮培训失败: %s" % t1.error)

	return Result.success({
		"engine": engine,
		"state": engine.get_state(),
	})

static func _read_first_trainer_staff_id(state: GameState, player_id: int) -> int:
	var trainers := EmployeeRulesClass.get_trainers_for_working(state, player_id)
	for trainer_val in trainers:
		if not (trainer_val is Dictionary):
			continue
		var trainer: Dictionary = trainer_val
		if int(trainer.get("remaining", 0)) <= 0:
			continue
		return int(trainer.get("staff_id", -1))
	if trainers.is_empty():
		return -1
	var first_val = trainers[0]
	if not (first_val is Dictionary):
		return -1
	return int(Dictionary(first_val).get("staff_id", -1))

static func _has_source_employee_type(source_items: Array, employee_type: String) -> bool:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return false
	for item_val in source_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("employee_type", "")).strip_edges() == emp_id:
			return true
	return false
