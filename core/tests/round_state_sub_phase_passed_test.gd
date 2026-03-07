# RoundState：sub_phase_passed helper 回归测试
class_name RoundStateSubPhasePassedTest
extends RefCounted

const RoundStateSubPhasePassedClass = preload("res://core/utils/round_state_sub_phase_passed.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_reset_flags_initializes_false_values()
	if not r.ok:
		return r
	r = _test_require_sub_phase_passed_fails_on_wrong_type()
	if not r.ok:
		return r
	r = _test_require_all_player_flags_fails_on_missing_player_key()
	if not r.ok:
		return r
	r = _test_set_player_passed_updates_flag()
	if not r.ok:
		return r
	r = _test_get_flags_or_empty_returns_empty_on_invalid_shape()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_round_state() -> Dictionary:
	return {
		"sub_phase_passed": {
			0: false,
			1: false,
		}
	}

static func _test_reset_flags_initializes_false_values() -> Result:
	var round_state := {}
	var reset_r := RoundStateSubPhasePassedClass.reset_flags(round_state, 3, "RoundStateSubPhasePassedTest")
	if not reset_r.ok:
		return Result.failure("reset_flags 失败: %s" % reset_r.error)
	var passed: Dictionary = round_state.get("sub_phase_passed", {})
	for pid in range(3):
		if not passed.has(pid) or bool(passed[pid]):
			return Result.failure("reset_flags 后 sub_phase_passed[%d] 应为 false" % pid)
	return Result.success()

static func _test_require_sub_phase_passed_fails_on_wrong_type() -> Result:
	var read := RoundStateSubPhasePassedClass.require_sub_phase_passed({"sub_phase_passed": []}, "RoundStateSubPhasePassedTest")
	if read.ok:
		return Result.failure("sub_phase_passed 类型错误时应失败")
	var err := str(read.error)
	if err.find("round_state.sub_phase_passed") < 0:
		return Result.failure("错误信息应包含 round_state.sub_phase_passed，实际: %s" % err)
	return Result.success()

static func _test_require_all_player_flags_fails_on_missing_player_key() -> Result:
	var round_state := {"sub_phase_passed": {0: false}}
	var read := RoundStateSubPhasePassedClass.require_all_player_flags(round_state, 2, "RoundStateSubPhasePassedTest")
	if read.ok:
		return Result.failure("缺失玩家 key 时应失败")
	var err := str(read.error)
	if err.find("round_state.sub_phase_passed[1]") < 0:
		return Result.failure("错误信息应包含 round_state.sub_phase_passed[1]，实际: %s" % err)
	return Result.success()

static func _test_set_player_passed_updates_flag() -> Result:
	var round_state := _make_round_state()
	var set_r := RoundStateSubPhasePassedClass.set_player_passed(round_state, 1, true, "RoundStateSubPhasePassedTest")
	if not set_r.ok:
		return Result.failure("set_player_passed 失败: %s" % set_r.error)
	var passed: Dictionary = round_state.get("sub_phase_passed", {})
	if not bool(passed.get(1, false)):
		return Result.failure("sub_phase_passed[1] 应更新为 true")
	return Result.success()

static func _test_get_flags_or_empty_returns_empty_on_invalid_shape() -> Result:
	var passed := RoundStateSubPhasePassedClass.get_flags_or_empty({"sub_phase_passed": []})
	if not passed.is_empty():
		return Result.failure("无效结构时应返回空字典，实际: %s" % str(passed))
	return Result.success()
