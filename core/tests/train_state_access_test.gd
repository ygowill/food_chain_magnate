# train 状态访问回归测试
class_name TrainStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/train_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const TrainEmployeeUsageClass = preload("res://gameplay/actions/train/train_employee_usage.gd")
const TrainEmployeeLocksClass = preload("res://gameplay/actions/train/train_employee_locks.gd")
const TrainSlotUsageStorageClass = preload("res://core/rules/employee_rules/train_slot_usage_storage.gd")
const RecruitActionClass = preload("res://gameplay/actions/recruit_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_train_events_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_target_locks_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_mandatory_actions_completed_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_recruit_used_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_read_employee_used_before_training_fails_fast_on_invalid_production_counts()
	if not r.ok:
		return r
	r = _test_read_employee_used_before_training_fails_fast_on_invalid_procurement_counts()
	if not r.ok:
		return r
	r = _test_read_employee_used_before_training_fails_fast_on_invalid_marketing_used()
	if not r.ok:
		return r
	r = _test_compute_initial_token_counts_fails_fast_on_invalid_immediate_train_pending_string_player_key()
	if not r.ok:
		return r
	r = _test_read_player_locks_fails_fast_on_invalid_train_employee_locks_string_player_key()
	if not r.ok:
		return r
	r = _test_ensure_player_locks_fails_fast_on_invalid_train_employee_locks_string_player_key()
	if not r.ok:
		return r
	r = _test_read_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_instances_string_player_key()
	if not r.ok:
		return r
	r = _test_write_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_instances_string_player_key()
	if not r.ok:
		return r
	r = _test_read_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_string_player_key()
	if not r.ok:
		return r
	r = _test_validate_fails_fast_on_invalid_train_slot_usage_instances_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_recruit_validate_fails_fast_on_invalid_train_slot_usage_instances_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_read_employee_used_before_training_fails_fast_on_invalid_working_employee_multipliers(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_inferred_use_employee_train_fails_fast_on_invalid_working_employee_multipliers(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_train_can_initiate_fails_closed_on_invalid_working_employee_multipliers(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_train_validate_fails_fast_on_invalid_working_employee_multipliers_limit_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_recruit_can_initiate_fails_closed_on_invalid_working_employee_multipliers(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_recruit_validate_fails_fast_on_invalid_working_employee_multipliers_limit_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_validate_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_recruit_validate_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_recruit_apply_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_train_apply_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 25})

static func _test_apply_changes_fails_fast_on_invalid_train_events_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("train_events 类型错误时应失败")
	var err := str(result.error)
	if err.find("train_events") < 0:
		return Result.failure("错误信息应包含 train_events，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_target_locks_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["train_events"] = []
	state.round_state["train_employee_locks"] = {
		0: {
			"management_trainee": [{
				"trainer_id": "trainer",
				"instance_idx": 0,
			}],
			"new_business_developer": {},
		},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("train_employee_locks 目标桶类型错误时应失败")
	var err := str(result.error)
	if err.find("to_employee tokens") < 0:
		return Result.failure("错误信息应包含 to_employee tokens，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _build_train_state(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	var take_trainee := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_trainee.ok:
		return Result.failure("添加 management_trainee 失败: %s" % add_trainee.error)
	state.round_state["train_events"] = {}
	return Result.success(state)

static func _test_apply_changes_fails_fast_on_invalid_mandatory_actions_completed_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var outcome := Result.success()
	var built := _build_active_price_train_state(player_count, seed_val)
	if not built.ok:
		return built

	var pricing_def_val = EmployeeRegistryClass.get_def("pricing_manager")
	if not (pricing_def_val is EmployeeDef):
		return Result.failure("无法读取 pricing_manager 定义")
	var pricing_def: EmployeeDef = pricing_def_val
	var original_train_to: Array[String] = pricing_def.train_to.duplicate()
	pricing_def.train_to = ["luxury_manager"]

	var state: GameState = built.value
	state.round_state["mandatory_actions_completed"] = {
		"0": ["set_price"],
		0: [],
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "pricing_manager",
		"to_employee": "luxury_manager",
	}))
	if result.ok:
		outcome = Result.failure("mandatory_actions_completed 使用字符串玩家 key 时应失败")
	else:
		var err := str(result.error)
		if err.find("mandatory_actions_completed") < 0 or err.find("字符串玩家 key") < 0:
			outcome = Result.failure("错误信息应包含 mandatory_actions_completed 与 字符串玩家 key，实际: %s" % err)
		elif str(state.players[0]) != player_before:
			outcome = Result.failure("失败时不应提前改写玩家员工状态")
		elif str(state.employee_pool) != pool_before:
			outcome = Result.failure("失败时不应提前改写 employee_pool")
		elif str(state.round_state) != round_state_before:
			outcome = Result.failure("失败时不应提前改写 round_state")

	pricing_def.train_to = original_train_to
	return outcome


static func _test_apply_changes_fails_fast_on_invalid_recruit_used_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var outcome := Result.success()
	var built := _build_active_recruit_train_state(player_count, seed_val)
	if not built.ok:
		return built

	var recruiting_girl_def_val = EmployeeRegistryClass.get_def("recruiting_girl")
	if not (recruiting_girl_def_val is EmployeeDef):
		return Result.failure("无法读取 recruiting_girl 定义")
	var recruiting_girl_def: EmployeeDef = recruiting_girl_def_val
	var original_train_to: Array[String] = recruiting_girl_def.train_to.duplicate()
	recruiting_girl_def.train_to = ["recruiting_manager"]

	var state: GameState = built.value
	state.round_state["recruit_used"] = {
		"0": 2,
		0: 0,
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "recruiting_girl",
		"to_employee": "recruiting_manager",
	}))
	if result.ok:
		outcome = Result.failure("recruit_used 使用字符串玩家 key 时应失败")
	else:
		var err := str(result.error)
		if err.find("recruit_used") < 0:
			outcome = Result.failure("错误信息应包含 recruit_used，实际: %s" % err)
		elif str(state.players[0]) != player_before:
			outcome = Result.failure("失败时不应提前改写玩家员工状态")
		elif str(state.employee_pool) != pool_before:
			outcome = Result.failure("失败时不应提前改写 employee_pool")
		elif str(state.round_state) != round_state_before:
			outcome = Result.failure("失败时不应提前改写 round_state")

	recruiting_girl_def.train_to = original_train_to
	return outcome

static func _build_active_price_train_state(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.players[0]["train_from_active_same_color"] = true

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	var take_pricing := StateUpdaterClass.take_from_pool(state, "pricing_manager", 1)
	if not take_pricing.ok:
		return Result.failure("从员工池取出 pricing_manager 失败: %s" % take_pricing.error)
	var add_pricing := StateUpdaterClass.add_employee(state, 0, "pricing_manager", false)
	if not add_pricing.ok:
		return Result.failure("添加 pricing_manager 失败: %s" % add_pricing.error)
	state.round_state["train_events"] = []
	return Result.success(state)


static func _build_active_recruit_train_state(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.players[0]["train_from_active_same_color"] = true

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	var take_recruiting_girl := StateUpdaterClass.take_from_pool(state, "recruiting_girl", 1)
	if not take_recruiting_girl.ok:
		return Result.failure("从员工池取出 recruiting_girl 失败: %s" % take_recruiting_girl.error)
	var add_recruiting_girl := StateUpdaterClass.add_employee(state, 0, "recruiting_girl", false)
	if not add_recruiting_girl.ok:
		return Result.failure("添加 recruiting_girl 失败: %s" % add_recruiting_girl.error)
	state.round_state["train_events"] = []
	return Result.success(state)

static func _build_recruit_on_credit_validate_state(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var trainee_total := int(state.employee_pool.get("management_trainee", 0))
	var take_all := StateUpdaterClass.take_from_pool(state, "management_trainee", trainee_total)
	if not take_all.ok:
		return Result.failure("清空 management_trainee 堆失败: %s" % take_all.error)
	for _i in range(trainee_total):
		var add_to_p1 := StateUpdaterClass.add_employee(state, 1, "management_trainee", true)
		if not add_to_p1.ok:
			return Result.failure("向 P1 待命区添加 management_trainee 失败: %s" % add_to_p1.error)
	return Result.success(state)

static func _test_read_employee_used_before_training_fails_fast_on_invalid_production_counts() -> Result:
	var state := GameState.new()
	state.round_state = {
		"production_counts": {
			"0": {"pizza_cook": 1},
		},
	}
	var read := TrainEmployeeUsageClass.read_employee_used_before_training(state, 0, "pizza_cook")
	if read.ok:
		return Result.failure("production_counts 使用字符串玩家 key 时应失败")
	var err := str(read.error)
	if err.find("production_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 production_counts 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_read_employee_used_before_training_fails_fast_on_invalid_procurement_counts() -> Result:
	var state := GameState.new()
	state.round_state = {
		"procurement_counts": {
			0: [],
		},
	}
	var read := TrainEmployeeUsageClass.read_employee_used_before_training(state, 0, "cart_operator")
	if read.ok:
		return Result.failure("procurement_counts[player] 类型错误时应失败")
	var err := str(read.error)
	if err.find("procurement_counts") < 0:
		return Result.failure("错误信息应包含 procurement_counts，实际: %s" % err)
	return Result.success()

static func _test_read_employee_used_before_training_fails_fast_on_invalid_marketing_used() -> Result:
	var state := GameState.new()
	state.round_state = {
		"marketing_used": {
			0: {"campaign_manager": "bad"},
		},
	}
	var read := TrainEmployeeUsageClass.read_employee_used_before_training(state, 0, "campaign_manager")
	if read.ok:
		return Result.failure("marketing_used[item] 类型错误时应失败")
	var err := str(read.error)
	if err.find("marketing_used") < 0:
		return Result.failure("错误信息应包含 marketing_used，实际: %s" % err)
	return Result.success()

static func _test_compute_initial_token_counts_fails_fast_on_invalid_immediate_train_pending_string_player_key() -> Result:
	var state := GameState.new()
	state.players = [{
		"employees": ["trainer"],
		"reserve_employees": [],
	}]
	state.round_state = {
		"immediate_train_pending": {
			"0": {"management_trainee": 1},
		},
	}
	var reserve: Array = []
	var result := TrainEmployeeLocksClass._compute_initial_token_counts(state, 0, reserve)
	if result.ok:
		return Result.failure("字符串玩家 key 时 _compute_initial_token_counts 应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_read_player_locks_fails_fast_on_invalid_train_employee_locks_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"train_employee_locks": {
			"0": {},
		},
	}
	var result := TrainEmployeeLocksClass._read_player_locks(state, 0)
	if result.ok:
		return Result.failure("字符串玩家 key 时 _read_player_locks 应失败")
	var err := str(result.error)
	if err.find("train_employee_locks") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_employee_locks 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_ensure_player_locks_fails_fast_on_invalid_train_employee_locks_string_player_key() -> Result:
	var state := GameState.new()
	state.players = [{
		"employees": ["trainer"],
		"reserve_employees": [],
	}]
	state.round_state = {
		"train_employee_locks": {
			"0": {
				"management_trainee": [{"trainer_id": "trainer", "instance_idx": 0}],
			},
		},
	}
	var before := str(state.round_state.get("train_employee_locks", null))
	var reserve: Array = []
	var result := TrainEmployeeLocksClass._ensure_player_locks(state, 0, reserve)
	if result.ok:
		return Result.failure("字符串玩家 key 时 _ensure_player_locks 应失败")
	var err := str(result.error)
	if err.find("train_employee_locks") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_employee_locks 与 字符串玩家 key，实际: %s" % err)
	if str(state.round_state.get("train_employee_locks", null)) != before:
		return Result.failure("失败时不应覆盖已有的 train_employee_locks")
	return Result.success()

static func _test_read_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_instances_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"train_slot_usage_instances": {
			"0": {"trainer": [1]},
		},
	}
	var result := TrainSlotUsageStorageClass.read_used_slots_by_instance(state, 0, "trainer", 1, 1)
	if result.ok:
		return Result.failure("字符串玩家 key 时 read_used_slots_by_instance 应失败")
	var err := str(result.error)
	if err.find("train_slot_usage_instances") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_slot_usage_instances 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_write_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_instances_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"train_slot_usage_instances": {
			"0": {"trainer": [1]},
		},
	}
	var before := str(state.round_state.get("train_slot_usage_instances", null))
	var result := TrainSlotUsageStorageClass.write_used_slots_by_instance(state, 0, "trainer", [1])
	if result.ok:
		return Result.failure("字符串玩家 key 时 write_used_slots_by_instance 应失败")
	var err := str(result.error)
	if err.find("train_slot_usage_instances") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_slot_usage_instances 与 字符串玩家 key，实际: %s" % err)
	if str(state.round_state.get("train_slot_usage_instances", null)) != before:
		return Result.failure("失败时不应覆盖已有的 train_slot_usage_instances")
	return Result.success()

static func _test_read_used_slots_by_instance_fails_fast_on_invalid_train_slot_usage_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"train_slot_usage": {
			"0": {"trainer": 1},
		},
	}
	var result := TrainSlotUsageStorageClass.read_used_slots_by_instance(state, 0, "trainer", 1, 1)
	if result.ok:
		return Result.failure("fallback 读取遇到字符串玩家 key 时应失败")
	var err := str(result.error)
	if err.find("train_slot_usage") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_slot_usage 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_validate_fails_fast_on_invalid_train_slot_usage_instances_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["train_events"] = []
	state.round_state["train_slot_usage_instances"] = {
		"0": {"trainer": [0]},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._validate_specific(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("train_slot_usage_instances 使用字符串玩家 key 时验证应失败")
	var err := str(result.error)
	if err.find("train_slot_usage_instances") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_slot_usage_instances 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_recruit_validate_fails_fast_on_invalid_train_slot_usage_instances_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_recruit_on_credit_validate_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["train_slot_usage_instances"] = {
		"0": {"trainer": [0]},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = RecruitActionClass.new()
	var result := action._validate_specific(state, Command.create("recruit", 0, {
		"employee_type": "management_trainee",
	}))
	if result.ok:
		return Result.failure("recruit 验证遇到非法 train_slot_usage_instances 时应失败")
	var err := str(result.error)
	if err.find("train_slot_usage_instances") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_slot_usage_instances 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_read_employee_used_before_training_fails_fast_on_invalid_working_employee_multipliers(player_count: int, seed_val: int) -> Result:
	var built := _build_active_recruit_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["working_employee_multipliers"] = {
		"0": {"recruiting_girl": 2},
	}
	var read := TrainEmployeeUsageClass.read_employee_used_before_training(state, 0, "recruiting_girl")
	if read.ok:
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时读取应失败")
	var err := str(read.error)
	if err.find("working_employee_multipliers") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 working_employee_multipliers 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_apply_inferred_use_employee_train_fails_fast_on_invalid_working_employee_multipliers(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["train_events"] = []
	state.round_state["working_employee_multipliers"] = {
		"0": {"trainer": 2},
	}
	var before := str(state.round_state)
	var result := TrainEmployeeUsageClass.apply_inferred_use_employee_train(state, 0)
	if result.ok:
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时 apply_inferred_use_employee_train 应失败")
	var err := str(result.error)
	if err.find("working_employee_multipliers") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 working_employee_multipliers 与 字符串玩家 key，实际: %s" % err)
	if str(state.round_state) != before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_train_can_initiate_fails_closed_on_invalid_working_employee_multipliers(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["working_employee_multipliers"] = {
		"0": {"trainer": 2},
	}
	var action = ActionClass.new()
	if action.can_initiate(state, 0):
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时 train can_initiate 应 fail-closed")
	return Result.success()

static func _test_train_validate_fails_fast_on_invalid_working_employee_multipliers_limit_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["working_employee_multipliers"] = {
		"0": {"trainer": 2},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._validate_specific(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时 train 验证应失败")
	var err := str(result.error)
	if err.find("working_employee_multipliers") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 working_employee_multipliers 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_recruit_can_initiate_fails_closed_on_invalid_working_employee_multipliers(player_count: int, seed_val: int) -> Result:
	var built := _build_active_recruit_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["working_employee_multipliers"] = {
		"0": {"recruiting_girl": 2},
	}
	var action = RecruitActionClass.new()
	if action.can_initiate(state, 0):
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时 recruit can_initiate 应 fail-closed")
	return Result.success()

static func _test_recruit_validate_fails_fast_on_invalid_working_employee_multipliers_limit_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_active_recruit_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["working_employee_multipliers"] = {
		"0": {"recruiting_girl": 2},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = RecruitActionClass.new()
	var result := action._validate_specific(state, Command.create("recruit", 0, {
		"employee_type": "management_trainee",
	}))
	if result.ok:
		return Result.failure("working_employee_multipliers 使用字符串玩家 key 时 recruit 验证应失败")
	var err := str(result.error)
	if err.find("working_employee_multipliers") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 working_employee_multipliers 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_validate_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["immediate_train_pending"] = {
		"0": {"management_trainee": 1},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._validate_specific(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("immediate_train_pending 使用字符串玩家 key 时验证应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_recruit_validate_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_recruit_on_credit_validate_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["immediate_train_pending"] = {
		"0": {"management_trainee": 1},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = RecruitActionClass.new()
	var result := action._validate_specific(state, Command.create("recruit", 0, {
		"employee_type": "management_trainee",
	}))
	if result.ok:
		return Result.failure("recruit 验证遇到非法 immediate_train_pending 时应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_recruit_apply_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_recruit_on_credit_validate_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["immediate_train_pending"] = {
		"0": {"management_trainee": 1},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = RecruitActionClass.new()
	var result := action._apply_changes(state, Command.create("recruit", 0, {
		"employee_type": "management_trainee",
	}))
	if result.ok:
		return Result.failure("recruit apply 遇到非法 immediate_train_pending 时应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_train_apply_fails_fast_on_invalid_immediate_train_pending_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.round_state["train_events"] = []
	state.round_state["immediate_train_pending"] = {
		"0": {"management_trainee": 1},
	}
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("train apply 遇到非法 immediate_train_pending 时应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()
