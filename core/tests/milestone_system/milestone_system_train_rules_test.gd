# MilestoneSystemTest module: training_rules (split from milestone_system_test.gd)
extends RefCounted

const Support = preload("res://core/tests/milestone_system/milestone_system_test_support.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const PaydaySettlementClass = preload("res://modules/base_rules/rules/phase/payday_settlement.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(seed_val: int) -> Result:
	var r := _run_all(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 9})

static func _run_all(seed_val: int) -> Result:
	var r_chain_train_restricted_without_milestone := _test_chain_train_restricted_without_milestone(seed_val)
	if not r_chain_train_restricted_without_milestone.ok:
		return r_chain_train_restricted_without_milestone

	var r_chain_train_allowed_with_milestone := _test_chain_train_allowed_with_milestone(seed_val)
	if not r_chain_train_allowed_with_milestone.ok:
		return r_chain_train_allowed_with_milestone

	var r_multi_step_train_disallowed_without_coach_or_guru := _test_multi_step_train_disallowed_without_coach_or_guru(seed_val)
	if not r_multi_step_train_disallowed_without_coach_or_guru.ok:
		return r_multi_step_train_disallowed_without_coach_or_guru

	var r_multi_step_train_allowed_with_coach := _test_multi_step_train_allowed_with_coach(seed_val)
	if not r_multi_step_train_allowed_with_coach.ok:
		return r_multi_step_train_allowed_with_coach

	var r_multi_step_train_allowed_with_guru := _test_multi_step_train_allowed_with_guru(seed_val)
	if not r_multi_step_train_allowed_with_guru.ok:
		return r_multi_step_train_allowed_with_guru

	var r_guru_can_continue_training_after_two_step := _test_guru_can_continue_training_after_two_step(seed_val)
	if not r_guru_can_continue_training_after_two_step.ok:
		return r_guru_can_continue_training_after_two_step

	var r_switch_trainer_disallowed_without_milestone := _test_switch_trainer_disallowed_without_milestone(seed_val)
	if not r_switch_trainer_disallowed_without_milestone.ok:
		return r_switch_trainer_disallowed_without_milestone

	var r_switch_between_two_coaches_disallowed_without_milestone := _test_switch_between_two_coaches_disallowed_without_milestone(seed_val)
	if not r_switch_between_two_coaches_disallowed_without_milestone.ok:
		return r_switch_between_two_coaches_disallowed_without_milestone

	var r_duplicate_target_source_staff_lock := _test_duplicate_target_source_staff_lock_disallows_new_card_switch(seed_val)
	if not r_duplicate_target_source_staff_lock.ok:
		return r_duplicate_target_source_staff_lock

	return Result.success()

static func _test_chain_train_restricted_without_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# 2 名 trainer => 2 次培训
	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	# 待命 marketing_trainee（可链式培训的测试来源）
	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "campaign_manager"}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)

	# 默认：不能继续培训本子阶段新培训得到的员工（campaign_manager）
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "campaign_manager", "to_employee": "brand_manager"}))
	if t2.ok:
		return Result.failure("默认规则下不应允许链式培训（campaign_manager -> brand_manager）")

	return Result.success()

static func _test_duplicate_target_source_staff_lock_disallows_new_card_switch(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	var trainer_staff_ids: Array[int] = []
	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
		trainer_staff_ids.append(int(Dictionary(add_trainer.value).get("staff_id", -1)))
	if trainer_staff_ids.size() != 2 or trainer_staff_ids[0] <= 0 or trainer_staff_ids[1] <= 0:
		return Result.failure("测试前置条件失败：trainer staff_ids 无效: %s" % str(trainer_staff_ids))

	var take_existing_campaign := StateUpdaterClass.take_from_pool(state, "campaign_manager", 1)
	if not take_existing_campaign.ok:
		return Result.failure("从员工池取出既有 campaign_manager 失败: %s" % take_existing_campaign.error)
	var add_existing_campaign := StateUpdaterClass.add_employee(state, 0, "campaign_manager", true)
	if not add_existing_campaign.ok:
		return Result.failure("添加既有 campaign_manager 到待命区失败: %s" % add_existing_campaign.error)
	var existing_campaign_staff_id := int(Dictionary(add_existing_campaign.value).get("staff_id", -1))
	if existing_campaign_staff_id <= 0:
		return Result.failure("既有 campaign_manager staff_id 无效: %s" % str(add_existing_campaign.value))

	var take_trainee := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_trainee.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_trainee.error)
	var trainee_staff_id := int(Dictionary(add_trainee.value).get("staff_id", -1))
	if trainee_staff_id <= 0:
		return Result.failure("marketing_trainee staff_id 无效: %s" % str(add_trainee.value))

	var t1 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_ids[0],
		"source_staff_id": trainee_staff_id,
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)

	var t2 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_ids[1],
		"source_staff_id": trainee_staff_id,
		"from_employee": "campaign_manager",
		"to_employee": "brand_manager",
	}))
	if t2.ok:
		return Result.failure("默认规则下不应允许用第二名 trainer 继续培训刚训练出的同一 staff_id")

	var t3 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": trainer_staff_ids[1],
		"source_staff_id": existing_campaign_staff_id,
		"from_employee": "campaign_manager",
		"to_employee": "brand_manager",
	}))
	if not t3.ok:
		return Result.failure("同类型但本子阶段开始时已存在的 campaign_manager 应仍可被第二名 trainer 培训，实际: %s" % t3.error)

	state = engine.get_state()
	var trained_type_read := StaffStateClass.get_staff_employee_type(state, 0, existing_campaign_staff_id)
	if not trained_type_read.ok:
		return Result.failure("读取既有 campaign_manager staff 类型失败: %s" % trained_type_read.error)
	if str(trained_type_read.value) != "brand_manager":
		return Result.failure("既有 campaign_manager 应被训练为 brand_manager，实际: %s" % str(trained_type_read.value))
	var new_type_read := StaffStateClass.get_staff_employee_type(state, 0, trainee_staff_id)
	if not new_type_read.ok:
		return Result.failure("读取刚训练出的 campaign_manager staff 类型失败: %s" % new_type_read.error)
	if str(new_type_read.value) != "campaign_manager":
		return Result.failure("刚训练出的 staff_id 不应被第二名 trainer 继续升级，实际: %s" % str(new_type_read.value))

	return Result.success()

static func _test_chain_train_allowed_with_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.players[0]["multi_trainer_on_one"] = true

	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "campaign_manager"}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "campaign_manager", "to_employee": "brand_manager"}))
	if not t2.ok:
		return Result.failure("multi_trainer_on_one=true 时应允许链式培训，实际: %s" % t2.error)

	return Result.success()

static func _test_multi_step_train_disallowed_without_coach_or_guru(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# 2 名 trainer => 2 次培训，但单次最多 1 步（不能拼成 2 步培训同一人）
	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	# 2 步目标：marketing_trainee -> campaign_manager -> brand_manager
	var t := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "brand_manager"}))
	if t.ok:
		return Result.failure("无 coach/guru 时不应允许 2 步培训（marketing_trainee -> brand_manager）")

	return Result.success()

static func _test_multi_step_train_allowed_with_coach(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# coach => 2 次培训，可对同一人 2 步
	var take_coach := StateUpdaterClass.take_from_pool(state, "coach", 1)
	if not take_coach.ok:
		return Result.failure("从员工池取出 coach 失败: %s" % take_coach.error)
	var add_coach := StateUpdaterClass.add_employee(state, 0, "coach", false)
	if not add_coach.ok:
		return Result.failure("添加 coach 失败: %s" % add_coach.error)

	# 防止自动跳过 Train 子阶段：保证 train_limit > 本次消耗（使 train 仍为 initiatable action）
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var t := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "brand_manager"}))
	if not t.ok:
		return Result.failure("coach 应允许 2 步培训（marketing_trainee -> brand_manager），实际: %s" % t.error)

	state = engine.get_state()
	var used := EmployeeRulesClass.get_action_count(state, 0, "train")
	if used != 2:
		return Result.failure("2 步培训后 train used 应为 2，实际: %d" % used)

	return Result.success()

static func _test_multi_step_train_allowed_with_guru(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# guru => 3 次培训，可对同一人 3 步
	var take_guru := StateUpdaterClass.take_from_pool(state, "guru", 1)
	if not take_guru.ok:
		return Result.failure("从员工池取出 guru 失败: %s" % take_guru.error)
	var add_guru := StateUpdaterClass.add_employee(state, 0, "guru", false)
	if not add_guru.ok:
		return Result.failure("添加 guru 失败: %s" % add_guru.error)

	# 防止自动跳过 Train 子阶段：保证 train_limit > 本次消耗（使 train 仍为 initiatable action）
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 management_trainee 到待命区失败: %s" % add_from.error)

	# 3 步目标：management_trainee -> junior_vice_president -> vice_president -> senior_vice_president
	var t := engine.execute_command(Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "senior_vice_president"}))
	if not t.ok:
		return Result.failure("guru 应允许 3 步培训（management_trainee -> senior_vice_president），实际: %s" % t.error)

	state = engine.get_state()
	var used := EmployeeRulesClass.get_action_count(state, 0, "train")
	if used != 3:
		return Result.failure("3 步培训后 train used 应为 3，实际: %d" % used)

	return Result.success()

static func _test_guru_can_continue_training_after_two_step(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# guru => 3 次培训：先 2 步，再允许继续 1 步（同一名 guru 仍有剩余 slot）
	var take_guru := StateUpdaterClass.take_from_pool(state, "guru", 1)
	if not take_guru.ok:
		return Result.failure("从员工池取出 guru 失败: %s" % take_guru.error)
	var add_guru := StateUpdaterClass.add_employee(state, 0, "guru", false)
	if not add_guru.ok:
		return Result.failure("添加 guru 失败: %s" % add_guru.error)

	# 防止自动跳过 Train 子阶段：保证 train_limit > 本轮累计消耗
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 management_trainee 到待命区失败: %s" % add_from.error)

	# 2 步：management_trainee -> junior_vice_president -> vice_president
	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "vice_president"}))
	if not t1.ok:
		return Result.failure("guru 2 步培训应成功（management_trainee -> vice_president），实际: %s" % t1.error)

	# 再 1 步：vice_president -> senior_vice_president（仍应允许）
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "vice_president", "to_employee": "senior_vice_president"}))
	if not t2.ok:
		return Result.failure("guru 应允许继续 1 步培训（vice_president -> senior_vice_president），实际: %s" % t2.error)

	state = engine.get_state()
	var used := EmployeeRulesClass.get_action_count(state, 0, "train")
	if used != 3:
		return Result.failure("累计培训 3 步后 train used 应为 3，实际: %d" % used)

	return Result.success()

static func _test_switch_trainer_disallowed_without_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# 1 trainer + 1 coach：总训练次数足够，但同一名员工不应允许“先 trainer 再 coach”继续培训（无里程碑）。
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_coach := StateUpdaterClass.take_from_pool(state, "coach", 1)
	if not take_coach.ok:
		return Result.failure("从员工池取出 coach 失败: %s" % take_coach.error)
	var add_coach := StateUpdaterClass.add_employee(state, 0, "coach", false)
	if not add_coach.ok:
		return Result.failure("添加 coach 失败: %s" % add_coach.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 marketing_trainee 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "campaign_manager"}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)

	# coach 仍有剩余，但不应允许换培训员继续培训 campaign_manager
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "campaign_manager", "to_employee": "brand_manager"}))
	if t2.ok:
		return Result.failure("默认规则下不应允许更换培训员继续培训（campaign_manager -> brand_manager）")

	return Result.success()

static func _test_switch_between_two_coaches_disallowed_without_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# 2 名 coach：先用 1 名 coach 完成 2 步培训后，不应允许“换另一名 coach”继续培训同一员工（无里程碑）。
	for _i in range(2):
		var take_coach := StateUpdaterClass.take_from_pool(state, "coach", 1)
		if not take_coach.ok:
			return Result.failure("从员工池取出 coach 失败: %s" % take_coach.error)
		var add_coach := StateUpdaterClass.add_employee(state, 0, "coach", false)
		if not add_coach.ok:
			return Result.failure("添加 coach 失败: %s" % add_coach.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 management_trainee 到待命区失败: %s" % add_from.error)

	# 2 步：management_trainee -> junior_vice_president -> vice_president
	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "vice_president"}))
	if not t1.ok:
		return Result.failure("coach 2 步培训应成功（management_trainee -> vice_president），实际: %s" % t1.error)

	# 第二名 coach 仍有剩余，但不应允许继续培训 vice_president
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "vice_president", "to_employee": "senior_vice_president"}))
	if t2.ok:
		return Result.failure("默认规则下不应允许在两名 coach 间切换继续培训（vice_president -> senior_vice_president）")

	return Result.success()
