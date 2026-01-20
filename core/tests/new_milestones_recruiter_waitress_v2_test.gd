# 模块3：全新里程碑
# 覆盖：
# - FIRST RECRUITING GIRL USED：使用 recruiting_girl 的 recruit -> 获得 executive_vice_president，且其永久免薪
# - FIRST WAITRESS USED：薪水变为每人 $3（仅对获得者）
class_name NewMilestonesRecruiterWaitressV2Test
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 993311) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"new_milestones",
	]

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)

	# recruiting_girl 在岗，执行 2 次招聘：第二次必然用到 recruiting_girl 的容量 -> 触发里程碑
	state.phase = "Working"
	state.sub_phase = "Recruit"
	var take := StateUpdaterClass.take_from_pool(state, "recruiting_girl", 1)
	if not take.ok:
		return Result.failure("从员工池取出 recruiting_girl 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "recruiting_girl", false)
	if not add.ok:
		return Result.failure("添加 recruiting_girl 失败: %s" % add.error)

	var r1 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "waitress"}))
	if not r1.ok:
		return Result.failure("recruit(1) 失败: %s" % r1.error)
	var r2 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "kitchen_trainee"}))
	if not r2.ok:
		return Result.failure("recruit(2) 失败: %s" % r2.error)

	state = engine.get_state()
	if not Array(state.players[0].get("milestones", [])).has("first_recruiting_girl_used"):
		return Result.failure("玩家0 应获得里程碑 first_recruiting_girl_used")
	if not Array(state.players[0].get("reserve_employees", [])).has("executive_vice_president"):
		return Result.failure("应获得 executive_vice_president 到 reserve_employees")
	if EmployeeRulesClass.requires_salary("executive_vice_president", state.players[0]):
		return Result.failure("executive_vice_president 应永久免薪（EmployeeRules.requires_salary 应为 false）")

	# 直接触发 first_waitress_used（waitress 的 UseEmployee 在本项目来自晚餐结算；此处用事件模拟）
	var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": 0, "id": "waitress"})
	if not ms.ok:
		return Result.failure("触发里程碑失败(UseEmployee/waitress): %s" % ms.error)
	state = engine.get_state()
	if int(state.players[0].get("salary_cost_override", -1)) != 3:
		return Result.failure("salary_cost_override 应为 3")

	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0
