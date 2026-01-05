# 不变量校验 Fail Fast 回归测试
# 覆盖：
# - Invariants 不允许缺字段/错误类型被默认值掩盖（例如 cash/inventory/bank.total 等）
# - 员工列表必须为 String 数组（拒绝 Dictionary/其它类型）
class_name InvariantsFailFastTest
extends RefCounted

const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	var base_cash_read := InvariantsClass.compute_total_cash(state)
	if not base_cash_read.ok:
		return Result.failure("无法计算 base_cash: %s" % base_cash_read.error)
	var base_cash: int = int(base_cash_read.value)

	var base_emp_read := InvariantsClass.compute_employee_totals(state)
	if not base_emp_read.ok:
		return Result.failure("无法计算 base_employee_totals: %s" % base_emp_read.error)
	var base_emp: Dictionary = base_emp_read.value

	var r1 := _case_missing_player_cash(state, base_cash, base_emp)
	if not r1.ok:
		return r1
	var r2 := _case_inventory_wrong_type(state, base_cash, base_emp)
	if not r2.ok:
		return r2
	var r3 := _case_missing_bank_total(state)
	if not r3.ok:
		return r3
	var r4 := _case_employee_item_wrong_type(state, base_cash, base_emp)
	if not r4.ok:
		return r4

	return Result.success({"cases": 4})

static func _case_missing_player_cash(state: GameState, base_cash: int, base_emp: Dictionary) -> Result:
	var s := state.duplicate_state()
	assert(s.players.size() > 0, "测试前提不成立：players 为空")
	s.players[0].erase("cash")

	var r: Result = InvariantsClass.check_invariants(s, base_cash, base_emp)
	if r.ok:
		return Result.failure("缺少 cash 时应失败，但返回 ok")
	if str(r.error).find("players[0].cash") < 0:
		return Result.failure("错误信息应包含 players[0].cash，实际: %s" % str(r.error))
	return Result.success()

static func _case_inventory_wrong_type(state: GameState, base_cash: int, base_emp: Dictionary) -> Result:
	var s := state.duplicate_state()
	assert(s.players.size() > 0, "测试前提不成立：players 为空")
	s.players[0]["inventory"] = []

	var r: Result = InvariantsClass.check_invariants(s, base_cash, base_emp)
	if r.ok:
		return Result.failure("inventory 类型错误时应失败，但返回 ok")
	if str(r.error).find("players[0].inventory") < 0:
		return Result.failure("错误信息应包含 players[0].inventory，实际: %s" % str(r.error))
	return Result.success()

static func _case_missing_bank_total(state: GameState) -> Result:
	var s := state.duplicate_state()
	s.bank.erase("total")

	var r: Result = InvariantsClass.compute_total_cash(s)
	if r.ok:
		return Result.failure("bank.total 缺失时 compute_total_cash 应失败，但返回 ok")
	if str(r.error).find("bank.total") < 0:
		return Result.failure("错误信息应包含 bank.total，实际: %s" % str(r.error))
	return Result.success()

static func _case_employee_item_wrong_type(state: GameState, base_cash: int, base_emp: Dictionary) -> Result:
	var s := state.duplicate_state()
	assert(s.players.size() > 0, "测试前提不成立：players 为空")
	s.players[0]["employees"] = [{"type": "ceo"}]

	var r: Result = InvariantsClass.check_invariants(s, base_cash, base_emp)
	if r.ok:
		return Result.failure("employees 元素类型错误时应失败，但返回 ok")
	var err := str(r.error)
	if err.find("employees") < 0 or err.find("类型错误") < 0:
		return Result.failure("错误信息应包含 employees 与 类型错误，实际: %s" % err)
	return Result.success()

