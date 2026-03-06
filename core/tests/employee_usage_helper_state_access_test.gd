# employee usage helper 状态访问回归测试
class_name EmployeeUsageHelperStateAccessTest
extends RefCounted

const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_get_active_employee_types_reads_employees(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_get_active_employee_types_tolerates_invalid_employees_field(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_has_active_employee_with_usage_tag_reads_employees(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_has_active_employee_with_usage_tag_tolerates_invalid_employee_entry(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return init
	return Result.success(engine.get_state())

static func _test_get_active_employee_types_reads_employees(player_count: int, seed_val: int) -> Result:
	var state_r := _make_state(player_count, seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败: %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0]["employees"] = ["campaign_manager", "campaign_manager", "marketing_trainee", "trainer"]
	var ids := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(state, 0, "use:marketing:billboard")
	if ids.size() != 2:
		return Result.failure("应只返回两个去重后的 billboard 营销员，实际: %s" % str(ids))
	if ids[0] != "campaign_manager" or ids[1] != "marketing_trainee":
		return Result.failure("billboard 营销员列表不正确: %s" % str(ids))
	return Result.success()

static func _test_get_active_employee_types_tolerates_invalid_employees_field(player_count: int, seed_val: int) -> Result:
	var state_r := _make_state(player_count, seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case2): %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0]["employees"] = "bad"
	var ids := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(state, 0, "use:marketing:billboard")
	if not ids.is_empty():
		return Result.failure("employees 字段损坏时应 fail-soft 返回空数组，实际: %s" % str(ids))
	return Result.success()

static func _test_has_active_employee_with_usage_tag_reads_employees(player_count: int, seed_val: int) -> Result:
	var state_r := _make_state(player_count, seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case3): %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0]["employees"] = ["campaign_manager"]
	if not EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, 0, "campaign_manager", "use:marketing:mailbox"):
		return Result.failure("campaign_manager 应被识别为可用 mailbox 营销员")
	return Result.success()

static func _test_has_active_employee_with_usage_tag_tolerates_invalid_employee_entry(player_count: int, seed_val: int) -> Result:
	var state_r := _make_state(player_count, seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case4): %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0]["employees"] = [123]
	if EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, 0, "campaign_manager", "use:marketing:mailbox"):
		return Result.failure("employees 元素类型损坏时应 fail-soft 返回 false")
	return Result.success()
