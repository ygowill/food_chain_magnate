# mass_marketeers 状态访问回归测试
class_name MassMarketeersStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/mass_marketeers/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_counts_mass_marketeers_from_player_employees()
	if not r.ok:
		return r
	r = _test_missing_employees_fails_fast()
	if not r.ok:
		return r
	r = _test_invalid_employee_entry_fails_fast()
	if not r.ok:
		return r
	r = _test_invalid_existing_marketing_rounds_fails_fast_without_overwrite()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.round_state = {}
	state.players = [
		{"employees": ["mass_marketeer", "mass_marketeer", "trainer"]},
		{"employees": ["mass_marketeer", "burger_cook"]},
	]
	return state

static func _test_counts_mass_marketeers_from_player_employees() -> Result:
	var state := _make_state()
	var entry = EntryClass.new()
	var result := entry._on_marketing_before_primary(state, null)
	if not result.ok:
		return Result.failure("_on_marketing_before_primary 失败: %s" % result.error)
	if int(state.round_state.get("marketing_rounds", -1)) != 4:
		return Result.failure("marketing_rounds 应为 4，实际: %s" % str(state.round_state.get("marketing_rounds", null)))
	return Result.success()

static func _test_missing_employees_fails_fast() -> Result:
	var state := _make_state()
	state.players[0].erase("employees")
	var entry = EntryClass.new()
	var result := entry._on_marketing_before_primary(state, null)
	if result.ok:
		return Result.failure("缺失 employees 时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	return Result.success()

static func _test_invalid_employee_entry_fails_fast() -> Result:
	var state := _make_state()
	state.players[0]["employees"] = [123]
	var entry = EntryClass.new()
	var result := entry._on_marketing_before_primary(state, null)
	if result.ok:
		return Result.failure("employees 元素类型错误时应失败")
	var err := str(result.error)
	if err.find("players[0].employees[0]") < 0:
		return Result.failure("错误信息应包含 players[0].employees[0]，实际: %s" % err)
	return Result.success()

static func _test_invalid_existing_marketing_rounds_fails_fast_without_overwrite() -> Result:
	var state := _make_state()
	state.round_state["marketing_rounds"] = {}
	var before := str(state.round_state)
	var entry = EntryClass.new()
	var result := entry._on_marketing_before_primary(state, null)
	if result.ok:
		return Result.failure("marketing_rounds 类型错误时应失败")
	var err := str(result.error)
	if err.find("marketing_rounds") < 0:
		return Result.failure("错误信息应包含 marketing_rounds，实际: %s" % err)
	if str(state.round_state) != before:
		return Result.failure("失败时不应覆盖已有的 marketing_rounds")
	return Result.success()
