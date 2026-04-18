# 员工行动额度与回合切换 smoke test（M3）
class_name EmployeeActionTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 推进到 Working / Recruit
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	if engine.get_state().sub_phase != DefsClass.SUB_PHASE_RECRUIT:
		return Result.failure("Working 初始子阶段应为 Recruit，实际: %s" % engine.get_state().sub_phase)

	var first_actor := engine.get_state().get_current_player_id()

	# 1) 无人力资源专员：CEO 仅 1 次招聘
	var r1 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "recruiting_girl"}))
	if not r1.ok:
		return Result.failure("首次招聘失败: %s" % r1.error)

	var r2 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "trainer"}))
	if r2.ok:
		return Result.failure("无招聘员时不应允许第二次招聘（应受 CEO 1 次限制）")

	# 2) 结束一整回合，进入下一回合 Restructuring：只有放入公司结构的员工才算在岗
	var to_restructuring := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_RESTRUCTURING, 50)
	if not to_restructuring.ok:
		return to_restructuring

	# 将 recruiting_girl 放入 CEO 直属槽，视为在岗（本回合公司结构的真值）
	var place := engine.execute_command(Command.create("set_company_structure_direct", first_actor, {
		"slot_index": 0,
		"employee_id": "recruiting_girl"
	}))
	if not place.ok:
		return Result.failure("重组放置 recruiting_girl 失败: %s" % place.error)

	var p := engine.get_state().get_player(first_actor)
	var active: Array = p.get("employees", [])
	var reserve: Array = p.get("reserve_employees", [])
	if not active.has("recruiting_girl"):
		return Result.failure("重组放置后 recruiting_girl 应在岗")
	if reserve.has("recruiting_girl"):
		return Result.failure("重组放置后 recruiting_girl 不应仍在待命区")

	# 3) 推进到下一次 Working / Recruit：人力资源专员应提供额外次数（共 2 次）
	var to_working2 := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 50)
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
		if engine.get_state().phase != DefsClass.PHASE_WORKING:
			return Result.failure("未轮转到目标玩家前不应离开 Working")

	var rr1 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "trainer"}))
	if not rr1.ok:
		return Result.failure("有招聘员时第一次招聘失败: %s" % rr1.error)

	var rr2 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "marketing_trainee"}))
	if not rr2.ok:
		return Result.failure("有招聘员时第二次招聘失败: %s" % rr2.error)

	var rr3 := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "kitchen_trainee"}))
	if rr3.ok:
		return Result.failure("仅 1 名招聘员时不应允许第三次招聘（应为 2 次）")

	var provider_track := _test_recruit_explicit_staff_id_consumes_selected_provider(player_count, seed)
	if not provider_track.ok:
		return provider_track

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"tested_player": first_actor
	})

static func _test_recruit_explicit_staff_id_consumes_selected_provider(player_count: int, seed: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed + 77)
	if not init.ok:
		return Result.failure("explicit recruit staff 初始化失败: %s" % init.error)
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working
	var state := engine.get_state()
	var actor := state.get_current_player_id()

	var take := StateUpdaterClass.take_from_pool(state, "recruiting_girl", 1)
	if not take.ok:
		return Result.failure("explicit recruit staff 取出 recruiting_girl 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "recruiting_girl", false)
	if not add.ok:
		return Result.failure("explicit recruit staff 添加 recruiting_girl 失败: %s" % add.error)
	var staff_id := int(Dictionary(add.value).get("staff_id", -1))
	if staff_id <= 0:
		return Result.failure("explicit recruit staff staff_id 无效: %s" % str(add.value))

	var recruit := engine.execute_command(Command.create("recruit", actor, {
		"employee_type": "waitress",
		"staff_id": staff_id,
	}))
	if not recruit.ok:
		return Result.failure("显式指定招聘员工的 recruit 应成功: %s" % recruit.error)

	state = engine.get_state()
	var staff_usage: Dictionary = Dictionary(state.round_state.get("staff_usage", {}))
	var ceo_staff_id := int(Array(state.get_player(actor).get("employees_staff_ids", []))[0])
	var recruiter_usage: Dictionary = Dictionary(staff_usage.get(staff_id, {}))
	if int(recruiter_usage.get("recruit", 0)) != 1:
		return Result.failure("显式 recruit 后 recruiting_girl staff_usage[%d].recruit 应为 1，实际: %s" % [staff_id, str(staff_usage)])
	if ceo_staff_id != staff_id:
		var ceo_usage: Dictionary = Dictionary(staff_usage.get(ceo_staff_id, {}))
		if int(ceo_usage.get("recruit", 0)) != 0:
			return Result.failure("显式 recruit 后 CEO 不应被记为已使用，实际: %s" % str(staff_usage))
	return Result.success()

static func _complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var player_count := state.players.size()
	var safety := 0
	while state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
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
