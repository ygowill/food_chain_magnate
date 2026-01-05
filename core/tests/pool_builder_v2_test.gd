# 模块系统 V2：Pools 推导（路线B）回归测试
class_name PoolBuilderV2Test
extends RefCounted

const GameConfigClass = preload("res://core/data/game_config.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const PoolBuilderClass = preload("res://core/modules/v2/pool_builder.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	# 2 人局：one_x=1
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(2, seed_val)
	if not init2.ok:
		return Result.failure("2p 初始化失败: %s" % init2.error)
	var state2 := engine2.get_state()
	if state2 == null:
		return Result.failure("2p state 为空")
	if not (state2.rules is Dictionary):
		return Result.failure("2p state.rules 类型错误（期望 Dictionary）")
	if not state2.rules.has("one_x_employee_copies") or not (state2.rules["one_x_employee_copies"] is int):
		return Result.failure("2p state.rules.one_x_employee_copies 缺失或类型错误（期望 int）")
	if int(state2.rules["one_x_employee_copies"]) != 1:
		return Result.failure("2p one_x_employee_copies 应为 1，实际: %d" % int(state2.rules["one_x_employee_copies"]))
	if int(state2.employee_pool.get("recruiter", 0)) != 12:
		return Result.failure("2p recruiter 池数量应为 12，实际: %d" % int(state2.employee_pool.get("recruiter", 0)))
	if int(state2.employee_pool.get("cfo", 0)) != 1:
		return Result.failure("2p cfo(one_x) 池数量应为 1，实际: %d" % int(state2.employee_pool.get("cfo", 0)))
	if state2.employee_pool.has("ceo"):
		return Result.failure("ceo 不应进入 employee_pool")
	if not state2.milestone_pool.has("first_hire_3"):
		return Result.failure("milestone_pool 应包含 first_hire_3")
	if state2.milestone_pool.size() != 18:
		return Result.failure("milestone_pool 数量应为 18，实际: %d" % state2.milestone_pool.size())

	# 4 人局：当前数据未必有 4p 地图，因此用 PoolBuilder 直接验证 one_x=2
	var cfg_read := GameConfigClass.load_default()
	if not cfg_read.ok:
		return Result.failure("加载 GameConfig 失败: %s" % cfg_read.error)
	var cfg = cfg_read.value
	if cfg == null:
		return Result.failure("GameConfig 为空")
	var map4: Dictionary = cfg.rule_one_x_employee_copies_by_player_count
	if not map4.has("4") or not (map4.get("4", null) is int):
		return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count[\"4\"] 缺失或类型错误（期望 int）")
	if int(map4.get("4", -1)) != 2:
		return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count[\"4\"] 应为 2，实际: %d" % int(map4.get("4", -1)))

	var employees: Dictionary = {}
	for emp_id in EmployeeRegistryClass.get_all_ids():
		var def = EmployeeRegistryClass.get_def(emp_id)
		if def == null:
			return Result.failure("EmployeeRegistry 缺少员工定义: %s" % emp_id)
		employees[emp_id] = def

	var pool4_read := PoolBuilderClass.build_employee_pool(4, {"one_x_employee_copies": 2}, employees)
	if not pool4_read.ok:
		return Result.failure("PoolBuilder.build_employee_pool(4) 失败: %s" % pool4_read.error)
	var pool4: Dictionary = pool4_read.value
	if int(pool4.get("cfo", 0)) != 2:
		return Result.failure("4p cfo(one_x) 池数量应为 2，实际: %d" % int(pool4.get("cfo", 0)))

	# MilestoneDef.pool 必需（缺失应失败）
	var bad := MilestoneDefClass.from_dict({
		"id": "bad_ms",
		"name": "Bad Milestone",
		"trigger": {"event": "Dummy", "filter": {}},
		"effects": [{"type": "dummy"}],
		"exclusive_type": "dummy",
		"expires_at": null
	})
	if bad.ok:
		return Result.failure("MilestoneDef 缺少 pool 字段时应失败")

	return Result.success()
