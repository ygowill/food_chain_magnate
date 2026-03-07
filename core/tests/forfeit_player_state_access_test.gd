# forfeit_player pending 状态访问回归测试
class_name ForfeitPlayerStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/forfeit_player_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 1})

static func _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation() -> Result:
	var state := GameState.new()
	state.players = [{
		"id": 0,
		"forfeited": false,
		"cash": 0,
		"employees": ["ceo"],
		"reserve_employees": [],
		"busy_marketers": [],
		"inventory": {"burger": 2},
		"milestones": ["m1"],
		"restaurants": [],
	}, {
		"id": 1,
		"forfeited": false,
		"cash": 0,
		"employees": ["ceo"],
		"reserve_employees": [],
		"busy_marketers": [],
		"inventory": {},
		"milestones": [],
		"restaurants": [],
	}]
	state.bank = {
		"total": 0,
		"broke_count": 0,
		"ceo_slots_after_first_break": 1,
		"reserve_added_total": 0,
		"removed_total": 0,
	}
	state.employee_pool = {}
	state.marketing_instances = []
	state.map = {}
	state.round_state = {
		"pending_phase_actions": [],
	}
	var player_before: String = str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("forfeit_player", 0, {}))
	if result.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(result.error)
	if err.find("pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家弃权或资产状态")
	if int((state.bank as Dictionary).get("removed_total", -1)) != 0:
		return Result.failure("失败时不应提前改写 bank.removed_total")
	return Result.success()
