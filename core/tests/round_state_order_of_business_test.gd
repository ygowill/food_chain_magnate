# RoundState：order_of_business helper 回归测试
class_name RoundStateOrderOfBusinessTest
extends RefCounted

const RoundStateOrderOfBusinessClass = preload("res://core/utils/round_state_order_of_business.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_require_order_of_business_success()
	if not r.ok:
		return r
	r = _test_require_order_of_business_fails_on_wrong_type()
	if not r.ok:
		return r
	r = _test_require_finalized_fails_on_wrong_type()
	if not r.ok:
		return r
	r = _test_require_previous_turn_order_fails_on_wrong_type()
	if not r.ok:
		return r
	r = _test_require_picks_fails_on_missing_field()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_round_state() -> Dictionary:
	return {
		"order_of_business": {
			"finalized": false,
			"picks": [-1, -1],
			"previous_turn_order": [0, 1],
		}
	}

static func _test_require_order_of_business_success() -> Result:
	var read := RoundStateOrderOfBusinessClass.require_order_of_business(_make_round_state(), "RoundStateOrderOfBusinessTest")
	if not read.ok:
		return Result.failure("require_order_of_business 失败: %s" % read.error)
	if not (read.value is Dictionary):
		return Result.failure("order_of_business 应为 Dictionary")
	return Result.success()

static func _test_require_order_of_business_fails_on_wrong_type() -> Result:
	var round_state := {"order_of_business": []}
	var read := RoundStateOrderOfBusinessClass.require_order_of_business(round_state, "RoundStateOrderOfBusinessTest")
	if read.ok:
		return Result.failure("order_of_business 类型错误时应失败")
	var err := str(read.error)
	if err.find("round_state.order_of_business") < 0:
		return Result.failure("错误信息应包含 round_state.order_of_business，实际: %s" % err)
	return Result.success()

static func _test_require_finalized_fails_on_wrong_type() -> Result:
	var oob := {"finalized": 1}
	var read := RoundStateOrderOfBusinessClass.require_finalized(oob, "RoundStateOrderOfBusinessTest")
	if read.ok:
		return Result.failure("finalized 类型错误时应失败")
	var err := str(read.error)
	if err.find("round_state.order_of_business.finalized") < 0:
		return Result.failure("错误信息应包含 round_state.order_of_business.finalized，实际: %s" % err)
	return Result.success()

static func _test_require_previous_turn_order_fails_on_wrong_type() -> Result:
	var oob := {"previous_turn_order": {}}
	var read := RoundStateOrderOfBusinessClass.require_previous_turn_order(oob, "RoundStateOrderOfBusinessTest")
	if read.ok:
		return Result.failure("previous_turn_order 类型错误时应失败")
	var err := str(read.error)
	if err.find("round_state.order_of_business.previous_turn_order") < 0:
		return Result.failure("错误信息应包含 round_state.order_of_business.previous_turn_order，实际: %s" % err)
	return Result.success()

static func _test_require_picks_fails_on_missing_field() -> Result:
	var read := RoundStateOrderOfBusinessClass.require_picks({}, "RoundStateOrderOfBusinessTest")
	if read.ok:
		return Result.failure("缺失 picks 时应失败")
	var err := str(read.error)
	if err.find("round_state.order_of_business.picks") < 0:
		return Result.failure("错误信息应包含 round_state.order_of_business.picks，实际: %s" % err)
	return Result.success()
