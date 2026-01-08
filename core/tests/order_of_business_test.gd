# 决定顺序（Order of Business）smoke test（M3）
class_name OrderOfBusinessTest
extends RefCounted

static func run(player_count: int = 3, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 固定上一回合顺序，避免依赖 shuffle 的细节
	var state := engine.get_state()
	state.turn_order = [0, 1, 2]
	state.current_player_index = 0
	# 避免首轮 Restructuring/OrderOfBusiness 自动跳过：让离开 Setup 后进入 round=2
	state.round_number = 1

	# Setup -> Restructuring（回合 1）
	var adv1 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv1.ok:
		return Result.failure("推进到 Restructuring 失败: %s" % adv1.error)

	if engine.get_state().phase != "Restructuring":
		return Result.failure("期望进入 Restructuring，实际: %s" % engine.get_state().phase)

	# 构造不同的空余卡槽数：
	# - P0: CEO + 3 名在岗员工，占满卡槽 => 0 空位
	# - P1: CEO + 1 名经理（executive_vp，提供 10 个经理卡槽） => 空位最大
	# - P2: 仅 CEO => 3 空位
	state = engine.get_state()
	# 说明：这里直接改写 employees 用于构造局面，需要同步 employee_pool，
	# 保证“员工供应池守恒”不变量不被测试用例破坏。
	for pid in range(player_count):
		var old_emps: Array = state.players[pid].get("employees", [])
		for emp in old_emps:
			if state.employee_pool.has(emp):
				state.employee_pool[emp] = int(state.employee_pool.get(emp, 0)) + 1

	var new_emps := {
		0: ["ceo", "recruiter", "trainer", "burger_cook"],
		1: ["ceo", "executive_vp"],
		2: ["ceo"]
	}
	for pid in new_emps:
		var list: Array = new_emps[pid]
		state.players[pid]["employees"] = list
		for emp in list:
			if state.employee_pool.has(emp):
				state.employee_pool[emp] = int(state.employee_pool.get(emp, 0)) - 1

	# Restructuring -> OrderOfBusiness：应计算 selection_order，并初始化 picks
	var safety2 := 0
	while engine.get_state().phase == "Restructuring":
		safety2 += 1
		if safety2 > player_count + 5:
			return Result.failure("提交 Restructuring 超出安全上限")
		var actor := engine.get_state().get_current_player_id()
		var submit := engine.execute_command(Command.create("submit_restructuring", actor, {}))
		if not submit.ok:
			return Result.failure("提交重组失败: %s" % submit.error)

	state = engine.get_state()
	if state.phase != "OrderOfBusiness":
		return Result.failure("期望进入 OrderOfBusiness，实际: %s" % state.phase)

	var expected := [1, 2, 0]
	if state.selection_order != expected:
		return Result.failure("selection_order 不匹配: %s != %s" % [str(state.selection_order), str(expected)])

	# 选择顺序：按选择顺序依次选最靠前的空位（确定性）
	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > player_count + 2:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		var oob: Dictionary = state.round_state.get("order_of_business", {})
		if bool(oob.get("finalized", false)):
			break
		var picks: Array = oob.get("picks", [])
		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("picks 未包含空位")

		var actor := state.get_current_player_id()
		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	if engine.get_state().turn_order != expected:
		return Result.failure("turn_order 不匹配: %s != %s" % [str(engine.get_state().turn_order), str(expected)])

	# OrderOfBusiness 完成后应自动进入 Working
	state = engine.get_state()
	if state.phase != "Working":
		return Result.failure("OrderOfBusiness 完成后应自动进入 Working，实际: %s" % state.phase)
	if state.get_current_player_id() != 1:
		return Result.failure("Working 首位玩家应为 1，实际: %d" % state.get_current_player_id())

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"selection_order": expected
	})
