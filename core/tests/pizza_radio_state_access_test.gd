# pizza radio 状态访问回归测试
class_name PizzaRadioStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/new_milestones/actions/place_pizza_radio_action.gd")
const PENDING_KEY := "new_milestones_pizza_radios_pending"

class _FakePizzaApplyAction:
	extends ActionClass

	func _validate_specific(_state: GameState, _command: Command) -> Result:
		return Result.success({
			"board_number": 1,
			"world_pos": Vector2i(0, 0),
			"rotation": 0,
			"footprint_size": Vector2i.ONE,
			"product": "pizza",
			"duration": 2,
		})

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_validate_specific_reaches_pending_check_with_valid_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	r = _test_apply_changes_writes_radio_placement()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.round_state = {}
	state.map = {
		"marketing_placements": {},
	}
	return state

static func _make_command() -> Command:
	var command := Command.create("place_pizza_radio", 0)
	command.params = {
		"position": [0, 0],
	}
	return command

static func _make_apply_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.marketing_instances = []
	state.round_state = {
		PENDING_KEY: [{"seller": 0}],
	}
	state.map = {
		"marketing_placements": {},
	}
	state.round_number = 4
	return state

static func _test_validate_specific_reaches_pending_check_with_valid_placements() -> Result:
	var action = ActionClass.new()
	var result := action._validate_specific(_make_state(), _make_command())
	if result.ok:
		return Result.failure("缺少 pending 时应失败")
	var err := str(result.error)
	if err.find("当前没有待放置的披萨 radio") < 0:
		return Result.failure("有合法 marketing_placements 时应继续走到 pending 校验，实际: %s" % err)
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

static func _test_apply_changes_writes_radio_placement() -> Result:
	var action = _FakePizzaApplyAction.new()
	var state := _make_apply_state()
	var result := action._apply_changes(state, _make_command())
	if not result.ok:
		return Result.failure("_apply_changes 不应失败: %s" % result.error)
	if state.marketing_instances.size() != 1:
		return Result.failure("marketing_instances 应新增 1 条，实际: %d" % state.marketing_instances.size())
	var placements: Dictionary = state.map["marketing_placements"]
	if not placements.has("1"):
		return Result.failure("marketing_placements 应写入 #1")
	var pending: Array = state.round_state.get(PENDING_KEY, [])
	if not pending.is_empty():
		return Result.failure("成功后应消耗 pending，实际: %s" % str(pending))
	return Result.success()

static func _test_apply_changes_fails_fast_without_partial_mutation() -> Result:
	var action = _FakePizzaApplyAction.new()
	var state := _make_apply_state()
	state.map.erase("marketing_placements")
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	if not state.marketing_instances.is_empty():
		return Result.failure("失败时不应提前写入 marketing_instances")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation() -> Result:
	var action = _FakePizzaApplyAction.new()
	var state := _make_apply_state()
	state.round_state["pending_phase_actions"] = []
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 round_state.pending_phase_actions，实际: %s" % err)
	if not state.marketing_instances.is_empty():
		return Result.failure("失败时不应提前写入 marketing_instances")
	var placements: Dictionary = state.map["marketing_placements"]
	if not placements.is_empty():
		return Result.failure("失败时不应提前写入 marketing_placements")
	var pending: Array = state.round_state.get(PENDING_KEY, [])
	if pending.size() != 1:
		return Result.failure("失败时不应提前消耗 pending，实际: %s" % str(pending))
	return Result.success()
