# 招聘缺货预支规则测试（M3 补齐）
# 覆盖：
# - 员工堆为空时允许招聘“预支”，但不产生幽灵员工卡（保持供应池守恒）
# - 必须在紧接的 Train 子阶段完成培训，否则不能离开 Train / Working
class_name RecruitOnCreditRulesTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = "Working"
	state.sub_phase = "Recruit"

	# 准备在岗 trainer（提供培训次数），以允许缺货预支
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	# 清空 recruiter 堆：将所有 recruiter 移到 P1 待命区，保持供应池守恒不变量
	var recruiter_total := int(state.employee_pool.get("recruiter", 0))
	var take_all := StateUpdaterClass.take_from_pool(state, "recruiter", recruiter_total)
	if not take_all.ok:
		return Result.failure("清空 recruiter 堆失败: %s" % take_all.error)
	for _i in range(recruiter_total):
		var add_to_p1 := StateUpdaterClass.add_employee(state, 1, "recruiter", true)
		if not add_to_p1.ok:
			return Result.failure("向 P1 待命区添加 recruiter 失败: %s" % add_to_p1.error)

	if int(state.employee_pool.get("recruiter", 0)) != 0:
		return Result.failure("recruiter 堆应已清空")

	# 1) Recruit 子阶段：允许缺货预支招聘（不加入待命区，只登记待培训）
	var r := engine.execute_command(Command.create("recruit", 0, {"employee_type": "recruiter"}))
	if not r.ok:
		return Result.failure("缺货预支 recruit 失败: %s" % r.error)

	state = engine.get_state()
	var p0 := state.get_player(0)
	if Array(p0.get("reserve_employees", [])).has("recruiter"):
		return Result.failure("缺货预支不应把 recruiter 加入待命区（应仅登记待培训）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return Result.failure("缺货预支后应写入 round_state.immediate_train_pending")
	if not (pending_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	if pending_all.has("0"):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: 0")
	if not pending_all.has(0):
		return Result.failure("缺货预支登记缺失: immediate_train_pending[0]，实际: %s" % str(pending_all))
	var pending_p0_val = pending_all.get(0, null)
	if not (pending_p0_val is Dictionary):
		return Result.failure("immediate_train_pending[0] 类型错误（期望 Dictionary）")
	var pending_p0: Dictionary = pending_p0_val
	if int(pending_p0.get("recruiter", 0)) != 1:
		return Result.failure("缺货预支登记不正确: %s" % str(pending_all))

	# 2) 禁止跳过 Working 阶段
	var adv_phase := engine.execute_command(Command.create_system("advance_phase"))
	if adv_phase.ok:
		return Result.failure("存在缺货预支待培训时不应允许推进主阶段（跳过 Train）")

	# 3) 进入 Train 子阶段
	var pass_all_recruit := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
	if not pass_all_recruit.ok:
		return pass_all_recruit
	var to_train := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if not to_train.ok:
		return Result.failure("推进到 Train 子阶段失败: %s" % to_train.error)
	if engine.get_state().sub_phase != "Train":
		return Result.failure("当前应为 Train，实际: %s" % engine.get_state().sub_phase)

	# 4) 未清账前禁止离开 Train 子阶段
	var pass_all_train := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
	if not pass_all_train.ok:
		return pass_all_train
	var leave_train := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if leave_train.ok:
		return Result.failure("未完成缺货预支培训时不应允许离开 Train 子阶段")

	# 5) Train：用“预支的 recruiter”直接培训为 trainer（不会归还 recruiter 卡）
	var train := engine.execute_command(Command.create("train", 0, {
		"from_employee": "recruiter",
		"to_employee": "trainer",
	}))
	if not train.ok:
		return Result.failure("Train(缺货预支) 执行失败: %s" % train.error)

	state = engine.get_state()
	var pending_all_after: Dictionary = state.round_state.get("immediate_train_pending", {})
	if pending_all_after.has("0"):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: 0")
	var pending_p0_after: Dictionary = {}
	if pending_all_after.has(0):
		var per_val = pending_all_after.get(0, null)
		if not (per_val is Dictionary):
			return Result.failure("immediate_train_pending[0] 类型错误（期望 Dictionary）")
		pending_p0_after = per_val
	if int(pending_p0_after.get("recruiter", 0)) != 0:
		return Result.failure("Train 后缺货预支应清账完毕，实际: %s" % str(pending_all_after))

	# 6) 清账后允许离开 Train
	var pass_all_train2 := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
	if not pass_all_train2.ok:
		return pass_all_train2
	var leave_train2 := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if not leave_train2.ok:
		return Result.failure("清账后离开 Train 失败: %s" % leave_train2.error)
	if engine.get_state().sub_phase != "Marketing":
		return Result.failure("离开 Train 后应进入 Marketing，实际: %s" % engine.get_state().sub_phase)

	return Result.success({
		"seed": seed,
		"recruiter_total": recruiter_total,
	})
