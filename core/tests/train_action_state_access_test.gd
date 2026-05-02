# train 动作状态访问回归测试
class_name TrainActionStateAccessTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const TrainCompanyValidationClass = preload("res://gameplay/actions/train/train_company_validation.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_missing_reserve_employees_fails_fast(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_invalid_reserve_employees_type_fails_fast(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_valid_reserve_employees_still_allows_train(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_explicit_trainer_staff_id_consumes_selected_trainer(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_explicit_trainer_staff_id_uses_working_multiplier_instances(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_implicit_trainer_staff_id_maps_multiplier_instances_to_physical_staff(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_same_role_color_fails_fast_on_unknown_target_employee()
	if not r.ok:
		return r
	return Result.success({"cases": 7})

static func _make_train_ready_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return init
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.turn_order = [0, 1]
	state.current_player_index = 0

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	return Result.success(engine)

static func _test_missing_reserve_employees_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val)
	if not engine_r.ok:
		return Result.failure("初始化失败: %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	state.players[0].erase("reserve_employees")
	var train := engine.execute_command(Command.create("train", 0, {
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if train.ok:
		return Result.failure("缺失 reserve_employees 时 train 应失败")
	var err := str(train.error)
	if err.find("train: player.reserve_employees") < 0:
		return Result.failure("错误信息应包含 reserve_employees 路径，实际: %s" % err)
	return Result.success()

static func _test_invalid_reserve_employees_type_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val)
	if not engine_r.ok:
		return Result.failure("初始化失败(case2): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	state.players[0]["reserve_employees"] = "bad"
	var train := engine.execute_command(Command.create("train", 0, {
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if train.ok:
		return Result.failure("reserve_employees 类型错误时 train 应失败")
	var err := str(train.error)
	if err.find("train: player.reserve_employees") < 0:
		return Result.failure("错误信息应包含 reserve_employees 路径，实际: %s" % err)
	return Result.success()

static func _test_valid_reserve_employees_still_allows_train(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val)
	if not engine_r.ok:
		return Result.failure("初始化失败(case3): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	var take_trainee := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("取出 marketing_trainee 失败: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee.ok:
		return Result.failure("添加 marketing_trainee 到 reserve 失败: %s" % add_trainee.error)
	var trainee_staff_id := int(Dictionary(add_trainee.value).get("staff_id", -1))
	if trainee_staff_id <= 0:
		return Result.failure("添加 marketing_trainee 应返回有效 staff_id，实际: %s" % str(add_trainee.value))
	var train := engine.execute_command(Command.create("train", 0, {
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train.ok:
		return Result.failure("合法 reserve_employees 下 train 不应失败: %s" % train.error)
	state = engine.get_state()
	if not Array(state.players[0].get("reserve_employees", [])).has("campaign_manager"):
		return Result.failure("训练后 campaign_manager 应进入 reserve_employees")
	var reserve_staff_ids: Array = Array(state.players[0].get("reserve_staff_ids", []))
	if reserve_staff_ids.find(trainee_staff_id) < 0:
		return Result.failure("训练后应保留原 trainee staff_id=%d，实际 reserve_staff_ids=%s" % [trainee_staff_id, str(reserve_staff_ids)])
	var registry: Dictionary = Dictionary(state.players[0].get("staff_registry", {}))
	if not registry.has(trainee_staff_id):
		return Result.failure("训练后 staff_registry 应保留原 trainee staff_id=%d" % trainee_staff_id)
	var record: Dictionary = Dictionary(registry.get(trainee_staff_id, {}))
	if str(record.get("employee_type", "")) != "campaign_manager":
		return Result.failure("训练后原 staff_id=%d 的 employee_type 应变为 campaign_manager，实际: %s" % [trainee_staff_id, str(record)])
	var train_counts: Dictionary = Dictionary(state.round_state.get("staff_train_event_counts", {}))
	if int(train_counts.get(trainee_staff_id, 0)) != 1:
		return Result.failure("训练后 staff_train_event_counts[%d] 应为 1，实际: %s" % [trainee_staff_id, str(train_counts)])
	return Result.success()

static func _test_explicit_trainer_staff_id_consumes_selected_trainer(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val + 91)
	if not engine_r.ok:
		return Result.failure("初始化失败(case4): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()

	var take_trainer2 := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer2.ok:
		return Result.failure("添加第二个 trainer 前取出失败: %s" % take_trainer2.error)
	var add_trainer2 := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer2.ok:
		return Result.failure("添加第二个 trainer 失败: %s" % add_trainer2.error)

	var trainer_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "trainer", ["employees"])
	if not trainer_ids_read.ok:
		return Result.failure("读取 trainer staff_ids 失败: %s" % trainer_ids_read.error)
	var trainer_ids: Array = trainer_ids_read.value
	if trainer_ids.size() < 2:
		return Result.failure("需要 2 个 trainer staff_id，实际: %s" % str(trainer_ids))
	var first_trainer_staff_id := int(trainer_ids[0])
	var second_trainer_staff_id := int(trainer_ids[1])

	var take_trainee := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("取出 marketing_trainee 失败: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee.ok:
		return Result.failure("添加 marketing_trainee 到 reserve 失败: %s" % add_trainee.error)
	var trainee_staff_id := int(Dictionary(add_trainee.value).get("staff_id", -1))
	if trainee_staff_id <= 0:
		return Result.failure("marketing_trainee staff_id 无效: %s" % str(add_trainee.value))

	var train := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": second_trainer_staff_id,
		"source_staff_id": trainee_staff_id,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train.ok:
		return Result.failure("显式 trainer/source staff 下 train 不应失败: %s" % train.error)

	state = engine.get_state()
	var second_used_read := StaffStateClass.get_staff_track_used(state, second_trainer_staff_id, "train")
	if not second_used_read.ok:
		return Result.failure("读取第二个 trainer usage 失败: %s" % second_used_read.error)
	var first_used_read := StaffStateClass.get_staff_track_used(state, first_trainer_staff_id, "train")
	if not first_used_read.ok:
		return Result.failure("读取第一个 trainer usage 失败: %s" % first_used_read.error)
	if int(second_used_read.value) != 1 or int(first_used_read.value) != 0:
		return Result.failure("显式 trainer_staff_id 应只消耗第二个 trainer，实际 first=%s second=%s" % [str(first_used_read.value), str(second_used_read.value)])
	return Result.success()

static func _test_explicit_trainer_staff_id_uses_working_multiplier_instances(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val + 137)
	if not engine_r.ok:
		return Result.failure("初始化失败(case multiplier): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	state.round_state["working_employee_multipliers"] = {
		0: {"trainer": 2}
	}

	var trainer_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "trainer", ["employees"])
	if not trainer_ids_read.ok:
		return Result.failure("读取 trainer staff_ids 失败(multiplier): %s" % trainer_ids_read.error)
	var trainer_ids: Array = trainer_ids_read.value
	if trainer_ids.size() != 1:
		return Result.failure("需要 1 个物理 trainer staff_id，实际: %s" % str(trainer_ids))
	var trainer_staff_id := int(trainer_ids[0])

	var take_trainees := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 2)
	if not take_trainees.ok:
		return Result.failure("取出 2 个 marketing_trainee 失败: %s" % take_trainees.error)
	var add_trainee1 := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee1.ok:
		return Result.failure("添加第一个 marketing_trainee 到 reserve 失败: %s" % add_trainee1.error)
	var add_trainee2 := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee2.ok:
		return Result.failure("添加第二个 marketing_trainee 到 reserve 失败: %s" % add_trainee2.error)
	var trainee_staff_id1 := int(Dictionary(add_trainee1.value).get("staff_id", -1))
	var trainee_staff_id2 := int(Dictionary(add_trainee2.value).get("staff_id", -1))
	if trainee_staff_id1 <= 0 or trainee_staff_id2 <= 0 or trainee_staff_id1 == trainee_staff_id2:
		return Result.failure("marketing_trainee staff_id 应为两个不同有效值，实际: %s / %s" % [str(add_trainee1.value), str(add_trainee2.value)])

	var initial_trainer_read := EmployeeRulesClass.try_resolve_trainer_for_working(state, 0, trainer_staff_id)
	if not initial_trainer_read.ok:
		return Result.failure("工作乘数下应能解析 trainer staff_id: %s" % initial_trainer_read.error)
	var initial_trainer: Dictionary = initial_trainer_read.value
	if int(initial_trainer.get("remaining", 0)) != 2 or int(initial_trainer.get("max_step_remaining", 0)) != 1:
		return Result.failure("工作乘数下 trainer 应有总剩余 2、单实例剩余 1，实际: %s" % str(initial_trainer))

	var train1 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_id,
		"source_staff_id": trainee_staff_id1,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train1.ok:
		return Result.failure("工作乘数下第一次显式 trainer train 不应失败: %s" % train1.error)

	state = engine.get_state()
	var after_first_trainer_read := EmployeeRulesClass.try_resolve_trainer_for_working(state, 0, trainer_staff_id)
	if not after_first_trainer_read.ok:
		return Result.failure("工作乘数下第一次 train 后同一 trainer 应仍有第二个虚拟实例可用: %s" % after_first_trainer_read.error)
	var after_first_trainer: Dictionary = after_first_trainer_read.value
	if int(after_first_trainer.get("remaining", 0)) != 1 or int(after_first_trainer.get("max_step_remaining", 0)) != 1:
		return Result.failure("第一次 train 后 trainer 应剩余 1 个虚拟实例，实际: %s" % str(after_first_trainer))

	var blocked := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_id,
		"source_staff_id": trainee_staff_id1,
		"from_employee": "campaign_manager",
		"to_employee": "brand_manager",
	}))
	if blocked.ok:
		return Result.failure("无 multi_trainer_on_one 时，工作乘数虚拟实例不应允许同一员工继续连升")

	state = engine.get_state()
	var train2 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_id,
		"source_staff_id": trainee_staff_id2,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train2.ok:
		return Result.failure("同一物理 trainer 的第二个工作乘数虚拟实例应可培训另一名员工: %s" % train2.error)

	state = engine.get_state()
	var trainer_used_read := StaffStateClass.get_staff_track_used(state, trainer_staff_id, "train")
	if not trainer_used_read.ok:
		return Result.failure("读取工作乘数 trainer usage 失败: %s" % trainer_used_read.error)
	if int(trainer_used_read.value) != 2:
		return Result.failure("工作乘数下物理 trainer staff usage 应累计 2，实际: %s" % str(trainer_used_read.value))
	return Result.success()

static func _test_implicit_trainer_staff_id_maps_multiplier_instances_to_physical_staff(player_count: int, seed_val: int) -> Result:
	var engine_r := _make_train_ready_engine(player_count, seed_val + 151)
	if not engine_r.ok:
		return Result.failure("初始化失败(case implicit multiplier): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()

	var take_trainer2 := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer2.ok:
		return Result.failure("添加第二个 trainer 前取出失败(implicit multiplier): %s" % take_trainer2.error)
	var add_trainer2 := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer2.ok:
		return Result.failure("添加第二个 trainer 失败(implicit multiplier): %s" % add_trainer2.error)
	state.round_state["working_employee_multipliers"] = {
		0: {"trainer": 2}
	}

	var trainer_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "trainer", ["employees"])
	if not trainer_ids_read.ok:
		return Result.failure("读取 trainer staff_ids 失败(implicit multiplier): %s" % trainer_ids_read.error)
	var trainer_ids: Array = trainer_ids_read.value
	trainer_ids.sort()
	if trainer_ids.size() < 2:
		return Result.failure("需要 2 个物理 trainer staff_id，实际: %s" % str(trainer_ids))
	var first_trainer_staff_id := int(trainer_ids[0])
	var second_trainer_staff_id := int(trainer_ids[1])

	var take_trainees := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 2)
	if not take_trainees.ok:
		return Result.failure("取出 2 个 marketing_trainee 失败(implicit multiplier): %s" % take_trainees.error)
	var add_trainee1 := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee1.ok:
		return Result.failure("添加第一个 marketing_trainee 到 reserve 失败(implicit multiplier): %s" % add_trainee1.error)
	var add_trainee2 := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee2.ok:
		return Result.failure("添加第二个 marketing_trainee 到 reserve 失败(implicit multiplier): %s" % add_trainee2.error)
	var trainee_staff_id1 := int(Dictionary(add_trainee1.value).get("staff_id", -1))
	var trainee_staff_id2 := int(Dictionary(add_trainee2.value).get("staff_id", -1))
	if trainee_staff_id1 <= 0 or trainee_staff_id2 <= 0:
		return Result.failure("marketing_trainee staff_id 应有效(implicit multiplier)，实际: %s / %s" % [str(add_trainee1.value), str(add_trainee2.value)])

	var train1 := engine.execute_command(Command.create("train", 0, {
		"source_staff_id": trainee_staff_id1,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train1.ok:
		return Result.failure("工作乘数下第一次隐式 trainer train 不应失败: %s" % train1.error)
	var train2 := engine.execute_command(Command.create("train", 0, {
		"source_staff_id": trainee_staff_id2,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not train2.ok:
		return Result.failure("工作乘数下第二次隐式 trainer train 不应失败: %s" % train2.error)

	state = engine.get_state()
	var first_used_read := StaffStateClass.get_staff_track_used(state, first_trainer_staff_id, "train")
	if not first_used_read.ok:
		return Result.failure("读取第一个 trainer usage 失败(implicit multiplier): %s" % first_used_read.error)
	var second_used_read := StaffStateClass.get_staff_track_used(state, second_trainer_staff_id, "train")
	if not second_used_read.ok:
		return Result.failure("读取第二个 trainer usage 失败(implicit multiplier): %s" % second_used_read.error)
	if int(first_used_read.value) != 2 or int(second_used_read.value) != 0:
		return Result.failure("隐式分配应将前两个虚拟实例映射回第一个物理 trainer，实际 first=%s second=%s" % [str(first_used_read.value), str(second_used_read.value)])
	return Result.success()

static func _test_same_role_color_fails_fast_on_unknown_target_employee() -> Result:
	var result := TrainCompanyValidationClass._is_same_role_color("marketing_trainee", "ghost_employee")
	if result.ok:
		return Result.failure("未知 to_employee 时应失败")
	var err := str(result.error)
	if err.find("未知员工定义: ghost_employee") < 0:
		return Result.failure("错误信息应包含 ghost_employee，实际: %s" % err)
	return Result.success()
