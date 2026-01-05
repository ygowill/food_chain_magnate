# 测试辅助：阶段推进工具
# 目标：让 core/tests 中的用例以“真实规则”推进阶段（尤其是 OrderOfBusiness 需要完成选择）。
class_name TestPhaseUtils
extends RefCounted

static func pass_all_players_in_working_sub_phase(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state.phase != "Working" or state.sub_phase.is_empty():
		return Result.failure("当前不在 Working 子阶段，无法 pass_all_players")

	for _i in range(state.players.size()):
		var pid := engine.get_state().get_current_player_id()
		var sk := engine.execute_command(Command.create("skip", pid))
		if not sk.ok:
			return Result.failure("skip 失败: %s" % sk.error)

	return Result.success()

static func complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state.phase != "OrderOfBusiness":
		return Result.success()

	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > state.players.size() + 5:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		if not (state.round_state is Dictionary):
			return Result.failure("OrderOfBusiness 未初始化(round_state)")
		var oob: Dictionary = state.round_state.get("order_of_business", {})
		if not (oob is Dictionary) or oob.is_empty():
			return Result.failure("OrderOfBusiness 未初始化(order_of_business)")

		if bool(oob.get("finalized", false)):
			return Result.success()

		var picks: Array = oob.get("picks", [])
		if picks.size() != state.players.size():
			return Result.failure("OrderOfBusiness picks 长度不匹配")

		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var actor := state.get_current_player_id()
		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	return Result.failure("OrderOfBusiness 状态异常")

static func advance_until_phase(engine: GameEngine, target_phase: String, safety_limit: int = 50) -> Result:
	var safety := 0
	while engine.get_state().phase != target_phase:
		safety += 1
		if safety > safety_limit:
			return Result.failure("推进到 %s 超出安全上限" % target_phase)

		if engine.get_state().phase == "OrderOfBusiness":
			var oob := complete_order_of_business(engine)
			if not oob.ok:
				return oob

		# Working 阶段必须通过子阶段推进离开（advance_phase_action 有门禁）
		if engine.get_state().phase == "Working" and target_phase != "Working":
			var sub_safety := 0
			while engine.get_state().phase == "Working":
				sub_safety += 1
				if sub_safety > 20:
					return Result.failure("Working 子阶段推进超出安全上限")
				var pass_all := pass_all_players_in_working_sub_phase(engine)
				if not pass_all.ok:
					return pass_all
				var sub_adv := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
				if not sub_adv.ok:
					return Result.failure("推进子阶段失败: %s" % sub_adv.error)
			continue

		var adv := engine.execute_command(Command.create_system("advance_phase"))
		if not adv.ok:
			return Result.failure("推进阶段失败: %s" % adv.error)

	return Result.success()
