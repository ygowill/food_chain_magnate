# GameEngine：不变量校验
# 负责：集中实现引擎级 invariants 检查（现金/库存/银行/员工守恒等）。
extends RefCounted

static func check_invariants(
	state: GameState,
	initial_total_cash: int,
	initial_employee_totals: Dictionary
) -> Result:
	if state == null:
		return Result.failure("GameState 为空")
	if not (state.players is Array):
		return Result.failure("GameState.players 类型错误（期望 Array）")
	if not (state.bank is Dictionary):
		return Result.failure("GameState.bank 类型错误（期望 Dictionary）")
	if not (state.employee_pool is Dictionary):
		return Result.failure("GameState.employee_pool 类型错误（期望 Dictionary）")

	# 1. 现金非负
	for i in range(state.players.size()):
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("GameState.players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val
		var cash_read := _require_int_field(player, "cash", "GameState.players[%d].cash" % i)
		if not cash_read.ok:
			return cash_read
		var cash: int = int(cash_read.value)
		if cash < 0:
			return Result.failure("玩家 %d 现金为负: $%d" % [i, cash])

	# 2. 库存非负
	for i in range(state.players.size()):
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("GameState.players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val
		var inv_read := _require_dict_field(player, "inventory", "GameState.players[%d].inventory" % i)
		if not inv_read.ok:
			return inv_read
		var inventory: Dictionary = inv_read.value
		for food_type in inventory:
			var v = inventory[food_type]
			if not (v is int):
				return Result.failure("GameState.players[%d].inventory[%s] 类型错误（期望 int）" % [i, str(food_type)])
			var n: int = int(v)
			if n < 0:
				return Result.failure("玩家 %d %s 库存为负: %d" % [
					i, food_type, n
				])

	# 3. 银行非负
	var bank_total_read := _require_int_field(state.bank, "total", "GameState.bank.total")
	if not bank_total_read.ok:
		return bank_total_read
	var bank_total: int = int(bank_total_read.value)

	var bank_broke_count_read := _require_int_field(state.bank, "broke_count", "GameState.bank.broke_count")
	if not bank_broke_count_read.ok:
		return bank_broke_count_read
	var bank_broke_count: int = int(bank_broke_count_read.value)
	if bank_total < 0 and bank_broke_count < 2:
		return Result.failure("银行余额为负: $%d" % bank_total)

	# 3.1 现金守恒（玩家现金 + 银行总额）
	var total_cash_read := compute_total_cash(state)
	if not total_cash_read.ok:
		return total_cash_read
	var total_cash: int = int(total_cash_read.value)

	var reserve_added_total_read := _require_int_field(state.bank, "reserve_added_total", "GameState.bank.reserve_added_total")
	if not reserve_added_total_read.ok:
		return reserve_added_total_read
	var reserve_added_total: int = int(reserve_added_total_read.value)
	if reserve_added_total < 0:
		return Result.failure("GameState.bank.reserve_added_total 不能为负数: %d" % reserve_added_total)

	var removed_total_read := _require_int_field(state.bank, "removed_total", "GameState.bank.removed_total")
	if not removed_total_read.ok:
		return removed_total_read
	var removed_total: int = int(removed_total_read.value)
	if removed_total < 0:
		return Result.failure("GameState.bank.removed_total 不能为负数: %d" % removed_total)

	var expected_total_cash: int = int(initial_total_cash) + reserve_added_total - removed_total
	if total_cash != expected_total_cash:
		return Result.failure("现金守恒失败: 期望 $%d(初始$%d+储备$%d-移除$%d), 实际 $%d" % [
			expected_total_cash, initial_total_cash, reserve_added_total, removed_total, total_cash
		])

	# 4. 员工池非负
	for emp_type in state.employee_pool:
		if not (emp_type is String):
			return Result.failure("GameState.employee_pool key 类型错误（期望 String）")
		var v = state.employee_pool[emp_type]
		if not (v is int):
			return Result.failure("GameState.employee_pool[%s] 类型错误（期望 int）" % str(emp_type))
		var n: int = int(v)
		if n < 0:
			return Result.failure("员工池 %s 为负: %d" % [
				emp_type, n
			])

	# 5. 员工供应池守恒（仅校验初始员工池内存在的类型）
	for emp_type in initial_employee_totals:
		if not (emp_type is String):
			return Result.failure("initial_employee_totals key 类型错误（期望 String）")
		var expected_val = initial_employee_totals[emp_type]
		if not (expected_val is int):
			return Result.failure("initial_employee_totals[%s] 类型错误（期望 int）" % str(emp_type))
		var expected: int = int(expected_val)

		if not state.employee_pool.has(emp_type):
			return Result.failure("GameState.employee_pool 缺少员工类型: %s" % str(emp_type))
		var pool_val = state.employee_pool[emp_type]
		if not (pool_val is int):
			return Result.failure("GameState.employee_pool[%s] 类型错误（期望 int）" % str(emp_type))
		var pool_count: int = int(pool_val)

		var players_count_read := _count_employees_in_players(state, str(emp_type))
		if not players_count_read.ok:
			return players_count_read
		var current: int = pool_count + int(players_count_read.value)
		if current != expected:
			return Result.failure("员工数量守恒失败: %s 期望 %d, 实际 %d" % [emp_type, expected, current])

	return Result.success()

static func compute_total_cash(game_state: GameState) -> Result:
	if game_state == null:
		return Result.failure("GameState 为空")
	if not (game_state.bank is Dictionary):
		return Result.failure("GameState.bank 类型错误（期望 Dictionary）")
	var bank_total_read := _require_int_field(game_state.bank, "total", "GameState.bank.total")
	if not bank_total_read.ok:
		return bank_total_read
	var total: int = int(bank_total_read.value)

	if not (game_state.players is Array):
		return Result.failure("GameState.players 类型错误（期望 Array）")
	for i in range(game_state.players.size()):
		var player_val = game_state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("GameState.players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val
		var cash_read := _require_int_field(player, "cash", "GameState.players[%d].cash" % i)
		if not cash_read.ok:
			return cash_read
		total += int(cash_read.value)

	return Result.success(total)

static func compute_employee_totals(game_state: GameState) -> Result:
	if game_state == null:
		return Result.failure("GameState 为空")
	if not (game_state.employee_pool is Dictionary):
		return Result.failure("GameState.employee_pool 类型错误（期望 Dictionary）")
	var totals: Dictionary = {}
	# 仅基于 employee_pool 中声明的类型做守恒检查，避免对未初始化的员工堆做过早假设。
	for emp_type in game_state.employee_pool:
		if not (emp_type is String):
			return Result.failure("GameState.employee_pool key 类型错误（期望 String）")
		var pool_val = game_state.employee_pool[emp_type]
		if not (pool_val is int):
			return Result.failure("GameState.employee_pool[%s] 类型错误（期望 int）" % str(emp_type))
		var pool_count: int = int(pool_val)

		var count_read := _count_employees_in_players(game_state, str(emp_type))
		if not count_read.ok:
			return count_read
		totals[str(emp_type)] = pool_count + int(count_read.value)

	return Result.success(totals)

static func _count_employees_in_players(game_state: GameState, employee_type: String) -> Result:
	if not (game_state.players is Array):
		return Result.failure("GameState.players 类型错误（期望 Array）")
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	var total := 0
	for i in range(game_state.players.size()):
		var player_val = game_state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("GameState.players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val

		var employees_read := _require_array_field(player, "employees", "GameState.players[%d].employees" % i)
		if not employees_read.ok:
			return employees_read
		var employees: Array = employees_read.value
		var c1 := _count_employee_in_list(employees, employee_type, "GameState.players[%d].employees" % i)
		if not c1.ok:
			return c1
		total += int(c1.value)

		var reserve_read := _require_array_field(player, "reserve_employees", "GameState.players[%d].reserve_employees" % i)
		if not reserve_read.ok:
			return reserve_read
		var reserve: Array = reserve_read.value
		var c2 := _count_employee_in_list(reserve, employee_type, "GameState.players[%d].reserve_employees" % i)
		if not c2.ok:
			return c2
		total += int(c2.value)

		var busy_read := _require_array_field(player, "busy_marketers", "GameState.players[%d].busy_marketers" % i)
		if not busy_read.ok:
			return busy_read
		var busy: Array = busy_read.value
		var c3 := _count_employee_in_list(busy, employee_type, "GameState.players[%d].busy_marketers" % i)
		if not c3.ok:
			return c3
		total += int(c3.value)

	return Result.success(total)

static func _count_employee_in_list(list: Array, employee_type: String, path: String) -> Result:
	if not (list is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var count := 0
	for i in range(list.size()):
		var item = list[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		if str(item) == employee_type:
			count += 1
	return Result.success(count)

static func _require_int_field(dict: Dictionary, key: String, path: String) -> Result:
	if not (dict is Dictionary):
		return Result.failure("%s 的上级对象类型错误（期望 Dictionary）" % path)
	if not dict.has(key):
		return Result.failure("%s 缺失" % path)
	var v = dict[key]
	if not (v is int):
		return Result.failure("%s 类型错误（期望 int）" % path)
	return Result.success(int(v))

static func _require_dict_field(dict: Dictionary, key: String, path: String) -> Result:
	if not (dict is Dictionary):
		return Result.failure("%s 的上级对象类型错误（期望 Dictionary）" % path)
	if not dict.has(key):
		return Result.failure("%s 缺失" % path)
	var v = dict[key]
	if not (v is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	return Result.success(v)

static func _require_array_field(dict: Dictionary, key: String, path: String) -> Result:
	if not (dict is Dictionary):
		return Result.failure("%s 的上级对象类型错误（期望 Dictionary）" % path)
	if not dict.has(key):
		return Result.failure("%s 缺失" % path)
	var v = dict[key]
	if not (v is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	return Result.success(v)
