# BankStateAccess 回归测试
class_name BankStateAccessTest
extends RefCounted

const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_require_and_adjust_total()
	if not r.ok:
		return r
	r = _test_apply_reserve_injection()
	if not r.ok:
		return r
	r = _test_removed_total_and_break_metadata()
	if not r.ok:
		return r
	r = _test_negative_injection_fails_fast()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.bank = {
		"total": 10,
		"broke_count": 0,
		"ceo_slots_after_first_break": -1,
		"reserve_added_total": 0,
		"removed_total": 0,
	}
	return state

static func _test_require_and_adjust_total() -> Result:
	var state := _make_state()
	var total_read := BankStateAccessClass.require_total(state, "BankStateAccessTest")
	if not total_read.ok:
		return Result.failure("require_total 失败: %s" % total_read.error)
	if int(total_read.value) != 10:
		return Result.failure("bank.total 应为 10，实际: %s" % str(total_read.value))
	var adjust := BankStateAccessClass.add_to_total(state, -3, "BankStateAccessTest")
	if not adjust.ok:
		return Result.failure("add_to_total 失败: %s" % adjust.error)
	if int(state.bank.get("total", -999)) != 7:
		return Result.failure("bank.total 应变为 7，实际: %s" % str(state.bank.get("total", null)))
	return Result.success()

static func _test_apply_reserve_injection() -> Result:
	var state := _make_state()
	var inject := BankStateAccessClass.apply_reserve_injection(state, 25, "BankStateAccessTest")
	if not inject.ok:
		return Result.failure("apply_reserve_injection 失败: %s" % inject.error)
	if int(state.bank.get("total", -999)) != 35:
		return Result.failure("注资后 bank.total 应为 35，实际: %s" % str(state.bank.get("total", null)))
	if int(state.bank.get("reserve_added_total", -999)) != 25:
		return Result.failure("注资后 reserve_added_total 应为 25，实际: %s" % str(state.bank.get("reserve_added_total", null)))
	return Result.success()

static func _test_removed_total_and_break_metadata() -> Result:
	var state := _make_state()
	var removed := BankStateAccessClass.add_removed_total(state, 12, "BankStateAccessTest")
	if not removed.ok:
		return Result.failure("add_removed_total 失败: %s" % removed.error)
	var broke := BankStateAccessClass.set_broke_count(state, 1, "BankStateAccessTest")
	if not broke.ok:
		return Result.failure("set_broke_count 失败: %s" % broke.error)
	var slots := BankStateAccessClass.set_ceo_slots_after_first_break(state, 4, "BankStateAccessTest")
	if not slots.ok:
		return Result.failure("set_ceo_slots_after_first_break 失败: %s" % slots.error)
	if int(state.bank.get("removed_total", -999)) != 12:
		return Result.failure("removed_total 应为 12，实际: %s" % str(state.bank.get("removed_total", null)))
	if int(state.bank.get("broke_count", -999)) != 1:
		return Result.failure("broke_count 应为 1，实际: %s" % str(state.bank.get("broke_count", null)))
	if int(state.bank.get("ceo_slots_after_first_break", -999)) != 4:
		return Result.failure("ceo_slots_after_first_break 应为 4，实际: %s" % str(state.bank.get("ceo_slots_after_first_break", null)))
	return Result.success()

static func _test_negative_injection_fails_fast() -> Result:
	var state := _make_state()
	var inject := BankStateAccessClass.apply_reserve_injection(state, -1, "BankStateAccessTest")
	if inject.ok:
		return Result.failure("负数注资应失败，但返回 ok")
	if str(inject.error).find("不能为负数") < 0:
		return Result.failure("错误信息应包含 不能为负数，实际: %s" % str(inject.error))
	return Result.success()

