# debug_add_house_demand 状态访问回归测试
class_name DebugAddHouseDemandStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/debug_add_house_demand_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_validate_specific_succeeds_with_valid_house()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_invalid_house_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.map = {
		"houses": {
			"house_1": {
				"has_garden": false,
				"demands": [],
			}
		}
	}
	return state

static func _make_command() -> Command:
	var command := Command.create("debug_add_house_demand", -1)
	command.params = {
		"house_id": "house_1",
		"product": "burger",
		"amount": 1,
		"from_player": 0,
		"board_number": 0,
		"marketing_type": "debug",
	}
	return command

static func _test_validate_specific_succeeds_with_valid_house() -> Result:
	var action = ActionClass.new()
	var result := action._validate_specific(_make_state(), _make_command())
	if not result.ok:
		return Result.failure("_validate_specific 不应失败: %s" % result.error)
	return Result.success()

static func _test_validate_specific_fails_fast_on_missing_houses() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_invalid_house_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["houses"]["house_1"] = []
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("house 类型错误时应失败")
	var err := str(result.error)
	if err.find("houses[house_1]") < 0:
		return Result.failure("错误信息应包含 houses[house_1]，实际: %s" % err)
	return Result.success()
