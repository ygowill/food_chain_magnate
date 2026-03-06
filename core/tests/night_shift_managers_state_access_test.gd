# night_shift_managers 状态访问回归测试
class_name NightShiftManagersStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/night_shift_managers/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_builds_working_employee_multipliers()
	if not r.ok:
		return r
	r = _test_missing_employees_fails_fast()
	if not r.ok:
		return r
	r = _test_invalid_employee_entry_fails_fast()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"night_shift_managers",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return init
	var state := engine.get_state()
	state.round_state = {}
	state.players[0]["employees"] = ["ceo", "night_shift_manager", "recruiting_girl", "waitress"]
	state.players[1]["employees"] = ["ceo"]
	return Result.success(state)

static func _test_builds_working_employee_multipliers() -> Result:
	var state_r := _make_state(12345)
	if not state_r.ok:
		return Result.failure("初始化失败: %s" % state_r.error)
	var state: GameState = state_r.value
	var entry = EntryClass.new()
	var result := entry._on_working_before_enter(state)
	if not result.ok:
		return Result.failure("_on_working_before_enter 失败: %s" % result.error)
	var all: Dictionary = state.round_state.get("working_employee_multipliers", {})
	var per: Dictionary = all.get(0, {})
	if int(per.get("recruiting_girl", 0)) != 2:
		return Result.failure("recruiting_girl multiplier 应为 2，实际: %s" % str(per))
	if int(per.get("waitress", 0)) != 2:
		return Result.failure("waitress multiplier 应为 2，实际: %s" % str(per))
	if per.has("ceo"):
		return Result.failure("CEO 不应被写入 multiplier，实际: %s" % str(per))
	return Result.success()

static func _test_missing_employees_fails_fast() -> Result:
	var state_r := _make_state(12345)
	if not state_r.ok:
		return Result.failure("初始化失败(case2): %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0].erase("employees")
	var entry = EntryClass.new()
	var result := entry._on_working_before_enter(state)
	if result.ok:
		return Result.failure("缺失 employees 时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	return Result.success()

static func _test_invalid_employee_entry_fails_fast() -> Result:
	var state_r := _make_state(12345)
	if not state_r.ok:
		return Result.failure("初始化失败(case3): %s" % state_r.error)
	var state: GameState = state_r.value
	state.players[0]["employees"] = [123]
	var entry = EntryClass.new()
	var result := entry._on_working_before_enter(state)
	if result.ok:
		return Result.failure("employees 元素类型错误时应失败")
	var err := str(result.error)
	if err.find("players[0].employees[0]") < 0:
		return Result.failure("错误信息应包含 players[0].employees[0]，实际: %s" % err)
	return Result.success()
