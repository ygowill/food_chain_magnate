# 模块11：夜班经理（Night Shift Managers）
# - 在岗夜班经理：无薪员工工作两次（CEO 排除，不叠加）
class_name NightShiftManagersV2Test
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_recruit_limit_doubled(seed_val)
	if not r1.ok:
		return r1

	return Result.success()

static func _test_recruit_limit_doubled(seed_val: int) -> Result:
	# 对照组：未启用 night_shift_managers -> limit = ceo(1) + recruiter(1) = 2
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var s0 := e0.get_state()
	_force_player0_ready_for_working(s0)
	_take_to_active(s0, 0, "recruiter")

	var base_limit := EmployeeRulesClass.get_recruit_limit_for_working(s0, 0)
	if base_limit != 2:
		return Result.failure("未启用 night_shift_managers 时招聘上限应为 2，实际: %d" % base_limit)

	# 实验组：启用 night_shift_managers -> limit = ceo(1) + recruiter(1*2) = 3（CEO 排除夜班）
	var e1 := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"night_shift_managers",
	]
	var init1 := e1.initialize(2, seed_val, enabled_modules)
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var s1 := e1.get_state()
	_force_player0_ready_for_working(s1)
	_take_to_active(s1, 0, "night_shift_manager")
	_take_to_active(s1, 0, "recruiter")

	# 触发进入 Working（执行 phase hooks）
	var adv := e1.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("推进到 Working 失败: %s" % adv.error)

	s1 = e1.get_state()
	if s1.phase != "Working":
		return Result.failure("当前应为 Working，实际: %s" % s1.phase)

	var limit := EmployeeRulesClass.get_recruit_limit_for_working(s1, 0)
	if limit != 3:
		return Result.failure("启用 night_shift_managers 时招聘上限应为 3，实际: %d" % limit)

	# 校验 multipliers：recruiter=2，ceo 不应被设置
	var wem_val = s1.round_state.get("working_employee_multipliers", null)
	if not (wem_val is Dictionary):
		return Result.failure("working_employee_multipliers 缺失或类型错误（期望 Dictionary）")
	var wem: Dictionary = wem_val
	if not wem.has(0):
		return Result.failure("working_employee_multipliers 缺少 player 0")
	var per_val = wem.get(0, null)
	if not (per_val is Dictionary):
		return Result.failure("working_employee_multipliers[0] 类型错误（期望 Dictionary）")
	var per: Dictionary = per_val
	if int(per.get("recruiter", 0)) != 2:
		return Result.failure("recruiter multiplier 应为 2，实际: %s" % str(per.get("recruiter", null)))
	if per.has("ceo"):
		return Result.failure("CEO 不参与夜班，working_employee_multipliers 不应包含 ceo")

	return Result.success()

static func _force_player0_ready_for_working(state: GameState) -> void:
	state.phase = "OrderOfBusiness"
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["order_of_business"] = {
		"previous_turn_order": [0, 1],
		"selection_order": [0, 1],
		"picks": [-1, -1],
		"finalized": true
	}
	state.players[0]["company_structure"]["ceo_slots"] = 20

static func _take_to_active(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	state.players[player_id]["employees"].append(employee_id)

