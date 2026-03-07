# campaign manager second tile 状态访问回归测试
class_name CampaignManagerSecondTileStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd")
const PENDING_KEY := "new_milestones_campaign_manager_pending"

class _FakeSecondTileApplyAction:
	extends ActionClass

	func _validate_specific(_state: GameState, _command: Command) -> Result:
		return Result.success({
			"link_id": "cm-1",
			"type": "mailbox",
			"product": "burger",
			"remaining_duration": 1,
			"board_number": 7,
			"world_pos": Vector2i(0, 0),
			"rotation": 0,
			"footprint_size": Vector2i(2, 2),
		})

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
	r = _test_apply_changes_writes_second_tile()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_pending_type_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{"milestones": []},
		{"milestones": []},
	]
	state.round_state = {}
	state.map = {
		"marketing_placements": {},
	}
	state.turn_order = [0, 1]
	state.current_player_index = 0
	return state

static func _make_command() -> Command:
	var command := Command.create("place_campaign_manager_second_tile", 0)
	command.params = {
		"board_number": 7,
		"position": [0, 0],
	}
	return command

static func _make_apply_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.marketing_instances = []
	state.round_state = {
		PENDING_KEY: {0: {"link_id": "cm-1"}},
	}
	state.map = {
		"marketing_placements": {},
	}
	state.round_number = 5
	return state

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

static func _test_apply_changes_writes_second_tile() -> Result:
	var action = _FakeSecondTileApplyAction.new()
	var state := _make_apply_state()
	var result := action._apply_changes(state, _make_command())
	if not result.ok:
		return Result.failure("_apply_changes 不应失败: %s" % result.error)
	if state.marketing_instances.size() != 1:
		return Result.failure("marketing_instances 应新增 1 条，实际: %d" % state.marketing_instances.size())
	var placements: Dictionary = state.map["marketing_placements"]
	if not placements.has("7"):
		return Result.failure("marketing_placements 应写入 #7")
	var pending: Dictionary = state.round_state.get(PENDING_KEY, {})
	if pending.has(0):
		return Result.failure("成功后应清除 actor pending，实际: %s" % str(pending))
	return Result.success()

static func _test_apply_changes_fails_fast_without_partial_mutation() -> Result:
	var action = _FakeSecondTileApplyAction.new()
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


static func _test_apply_changes_fails_fast_on_invalid_pending_type_without_partial_mutation() -> Result:
	var action = _FakeSecondTileApplyAction.new()
	var state := _make_apply_state()
	state.round_state[PENDING_KEY] = []
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("pending 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.%s" % PENDING_KEY) < 0:
		return Result.failure("错误信息应包含 round_state.%s，实际: %s" % [PENDING_KEY, err])
	if not state.marketing_instances.is_empty():
		return Result.failure("失败时不应提前写入 marketing_instances")
	var placements: Dictionary = state.map["marketing_placements"]
	if not placements.is_empty():
		return Result.failure("失败时不应提前写入 marketing_placements")
	return Result.success()
