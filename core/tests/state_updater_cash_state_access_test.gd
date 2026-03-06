# state_updater cash 状态访问回归测试
class_name StateUpdaterCashStateAccessTest
extends RefCounted

const CashOps = preload("res://core/state/state_updater/cash.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_get_balance_reads_player_cash_via_helper()
	if not r.ok:
		return r
	r = _test_transfer_cash_updates_players()
	if not r.ok:
		return r
	r = _test_set_player_cash_fails_fast_on_missing_cash()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.bank = {
		"total": 100,
		"broke_count": 0,
		"ceo_slots_after_first_break": -1,
		"reserve_added_total": 0,
		"removed_total": 0,
	}
	state.players = [
		{"cash": 10},
		{"cash": 1},
	]
	return state

static func _test_get_balance_reads_player_cash_via_helper() -> Result:
	var state := _make_state()
	var balance := CashOps.get_balance(state, "player", 0)
	if not balance.ok:
		return Result.failure("get_balance 失败: %s" % balance.error)
	if int(balance.value) != 10:
		return Result.failure("player[0].cash 应为 10，实际: %s" % str(balance.value))
	return Result.success()

static func _test_transfer_cash_updates_players() -> Result:
	var state := _make_state()
	var transfer := CashOps.transfer_cash(state, "player", 0, "player", 1, 4)
	if not transfer.ok:
		return Result.failure("transfer_cash 失败: %s" % transfer.error)
	if int(state.players[0].get("cash", -1)) != 6:
		return Result.failure("转出后 player[0].cash 应为 6，实际: %s" % str(state.players[0]))
	if int(state.players[1].get("cash", -1)) != 5:
		return Result.failure("转入后 player[1].cash 应为 5，实际: %s" % str(state.players[1]))
	return Result.success()

static func _test_set_player_cash_fails_fast_on_missing_cash() -> Result:
	var state := _make_state()
	state.players[0].erase("cash")
	var set_cash := CashOps.set_player_cash(state, 0, 5)
	if set_cash.ok:
		return Result.failure("缺失 cash 时 set_player_cash 应失败")
	var err := str(set_cash.error)
	if err.find("player[0].cash") < 0:
		return Result.failure("错误信息应包含 cash 路径，实际: %s" % err)
	return Result.success()
