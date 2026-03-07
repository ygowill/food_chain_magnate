# StepTimelineBuild cleanup pending 状态访问回归测试
class_name StepTimelineCleanupPendingStateAccessTest
extends RefCounted

const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_read_pending_cleanup_actions_returns_false_when_missing()
	if not r.ok:
		return r
	r = _test_read_pending_cleanup_actions_returns_true_when_cleanup_pending_exists()
	if not r.ok:
		return r
	r = _test_read_pending_cleanup_actions_fails_fast_on_invalid_pending_phase_actions_type()
	if not r.ok:
		return r
	r = _test_read_pending_cleanup_actions_fails_fast_on_invalid_cleanup_pending_type()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.round_state = {}
	return state

static func _test_read_pending_cleanup_actions_returns_false_when_missing() -> Result:
	var state := _make_state()
	var read := StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)
	if not read.ok:
		return Result.failure("缺失 pending 时不应失败: %s" % read.error)
	if bool(read.value):
		return Result.failure("缺失 pending 时应返回 false")
	return Result.success()

static func _test_read_pending_cleanup_actions_returns_true_when_cleanup_pending_exists() -> Result:
	var state := _make_state()
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [{"kind": "fridge_keep", "player_id": 0}],
	}
	var read := StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)
	if not read.ok:
		return Result.failure("合法 cleanup pending 时不应失败: %s" % read.error)
	if not bool(read.value):
		return Result.failure("存在 cleanup pending 时应返回 true")
	return Result.success()

static func _test_read_pending_cleanup_actions_fails_fast_on_invalid_pending_phase_actions_type() -> Result:
	var state := _make_state()
	state.round_state["pending_phase_actions"] = []
	var read := StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)
	if read.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(read.error)
	if err.find("pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions，实际: %s" % err)
	return Result.success()

static func _test_read_pending_cleanup_actions_fails_fast_on_invalid_cleanup_pending_type() -> Result:
	var state := _make_state()
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: {},
	}
	var read := StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)
	if read.ok:
		return Result.failure("pending_phase_actions[Cleanup] 类型错误时应失败")
	var err := str(read.error)
	if err.find("pending_phase_actions[Cleanup]") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions[Cleanup]，实际: %s" % err)
	return Result.success()
