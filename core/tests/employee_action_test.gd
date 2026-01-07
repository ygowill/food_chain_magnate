# 员工行动额度与回合切换 smoke test（M3）
class_name EmployeeActionTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 推进到 Working / Recruit
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	if engine.get_state().sub_phase != "Recruit":
		return Result.failure("Working 初始子阶段应为 Recruit，实际: %s" % engine.get_state().sub_phase)

	var first_actor := engine.get_state().get_current_player_id()

	# 1) 无招聘员：CEO 仅 1 次招聘
	var r1 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "recruiter"}))
	if not r1.ok:
		return Result.failure("首次招聘失败: %s" % r1.error)

	var r2 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "trainer"}))
	if r2.ok:
		return Result.failure("无招聘员时不应允许第二次招聘（应受 CEO 1 次限制）")

	# 2) 结束一整回合，进入下一回合 Restructuring：待命员工自动激活
	var to_restructuring := TestPhaseUtilsClass.advance_until_phase(engine, "Restructuring", 50)
	if not to_restructuring.ok:
		return to_restructuring

	var p := engine.get_state().get_player(first_actor)
	var active: Array = p.get("employees", [])
	var reserve: Array = p.get("reserve_employees", [])
	if not active.has("recruiter"):
		return Result.failure("进入 Restructuring 后应自动激活待命员工 recruiter")
	if reserve.has("recruiter"):
		return Result.failure("进入 Restructuring 后 recruiter 不应仍在待命区")

	# 3) 推进到下一次 Working / Recruit：招聘员应提供额外次数（共 2 次）
	var to_working2 := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 50)
	if not to_working2.ok:
		return to_working2

	# 推进到 first_actor 的 Working 回合
	var safety = 0
	while engine.get_state().get_current_player_id() != first_actor:
		safety += 1
		if safety > 20:
			return Result.failure("轮转到目标玩家超出安全上限")
		var end_turn := TestPhaseUtilsClass.end_current_player_working_turn(engine, 50)
		if not end_turn.ok:
			return end_turn
		if engine.get_state().phase != "Working":
			return Result.failure("未轮转到目标玩家前不应离开 Working")

	var rr1 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "trainer"}))
	if not rr1.ok:
		return Result.failure("有招聘员时第一次招聘失败: %s" % rr1.error)

	var rr2 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "marketer"}))
	if not rr2.ok:
		return Result.failure("有招聘员时第二次招聘失败: %s" % rr2.error)

	var rr3 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "kitchen_trainee"}))
	if rr3.ok:
		return Result.failure("仅 1 名招聘员时不应允许第三次招聘（应为 2 次）")

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"tested_player": first_actor
	})

static func _complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var player_count := state.players.size()
	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > player_count + 2:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		var oob: Dictionary = state.round_state.get("order_of_business", {})
		var picks: Array = oob.get("picks", [])
		if picks.size() != player_count:
			return Result.failure("OrderOfBusiness picks 长度不匹配")
		if bool(oob.get("finalized", false)):
			return Result.success()

		var actor := state.get_current_player_id()
		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	return Result.success()
