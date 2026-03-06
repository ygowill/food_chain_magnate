# new restaurant mailbox 状态访问回归测试
class_name NewRestaurantMailboxStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_validate_specific_reaches_milestone_check_with_valid_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{"milestones": []},
		{"milestones": []},
	]
	state.map = {
		"marketing_placements": {},
	}
	state.turn_order = [0, 1]
	state.current_player_index = 0
	return state

static func _make_command() -> Command:
	var command := Command.create("place_new_restaurant_mailbox", 0)
	command.params = {
		"board_number": 7,
		"product": "burger",
		"position": [0, 0],
	}
	return command

static func _test_validate_specific_reaches_milestone_check_with_valid_placements() -> Result:
	var action = ActionClass.new()
	var result := action._validate_specific(_make_state(), _make_command())
	if result.ok:
		return Result.failure("未获里程碑时应失败")
	var err := str(result.error)
	if err.find("未获得里程碑") < 0:
		return Result.failure("有合法 marketing_placements 时应继续走到里程碑校验，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_missing_marketing_placements() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
