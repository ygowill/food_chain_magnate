# 状态更新辅助类
# 提供安全的状态修改方法，支持事务性更新和变更跟踪
class_name StateUpdater
extends RefCounted

# 变更记录
var _changes: Array[Dictionary] = []
var _track_changes: bool = false

# === 现金操作 ===

# 转账：从一方转到另一方
# from_type: "player" | "bank"
# to_type: "player" | "bank"
static func transfer_cash(
	state: GameState,
	from_type: String,
	from_id: int,
	to_type: String,
	to_id: int,
	amount: int
) -> Result:
	if state == null:
		return Result.failure("转账失败：state 为空")
	if not (state.bank is Dictionary):
		return Result.failure("转账失败：state.bank 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("转账失败：state.players 类型错误（期望 Array）")
	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("转账失败：state.bank.broke_count 缺失或类型错误（期望 int）")

	if amount < 0:
		return Result.failure("转账金额不能为负: %d" % amount)

	if amount == 0:
		return Result.success().with_warning("转账金额为0")

	# 检查来源余额
	var from_balance_read := _get_balance(state, from_type, from_id)
	if not from_balance_read.ok:
		return from_balance_read
	var from_balance: int = int(from_balance_read.value)
	var allow_overdraft := false
	if from_type == "bank":
		allow_overdraft = int(state.bank["broke_count"]) >= 2
	if not allow_overdraft and from_balance < amount:
		return Result.failure("余额不足: 需要 $%d, 只有 $%d" % [amount, from_balance])

	# 执行转账
	var debit := _modify_balance(state, from_type, from_id, -amount)
	if not debit.ok:
		return debit
	var credit := _modify_balance(state, to_type, to_id, amount)
	if not credit.ok:
		return credit

	return Result.success({
		"from": {"type": from_type, "id": from_id},
		"to": {"type": to_type, "id": to_id},
		"amount": amount
	})

# 获取余额
static func _get_balance(state: GameState, holder_type: String, holder_id: int) -> Result:
	if state == null:
		return Result.failure("StateUpdater._get_balance: state 为空")
	match holder_type:
		"player":
			if not (state.players is Array):
				return Result.failure("StateUpdater._get_balance: state.players 类型错误（期望 Array）")
			if holder_id < 0 or holder_id >= state.players.size():
				return Result.failure("StateUpdater._get_balance: player_id 越界: %d" % holder_id)
			var player_val = state.players[holder_id]
			if not (player_val is Dictionary):
				return Result.failure("StateUpdater._get_balance: players[%d] 类型错误（期望 Dictionary）" % holder_id)
			var player: Dictionary = player_val
			if not player.has("cash") or not (player["cash"] is int):
				return Result.failure("StateUpdater._get_balance: players[%d].cash 缺失或类型错误（期望 int）" % holder_id)
			return Result.success(int(player["cash"]))
		"bank":
			if not (state.bank is Dictionary):
				return Result.failure("StateUpdater._get_balance: state.bank 类型错误（期望 Dictionary）")
			if holder_id != -1:
				return Result.failure("StateUpdater._get_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			if not state.bank.has("total") or not (state.bank["total"] is int):
				return Result.failure("StateUpdater._get_balance: state.bank.total 缺失或类型错误（期望 int）")
			return Result.success(int(state.bank["total"]))
		_:
			return Result.failure("StateUpdater._get_balance: 未知 holder_type: %s" % holder_type)

# 修改余额
static func _modify_balance(state: GameState, holder_type: String, holder_id: int, delta: int) -> Result:
	if state == null:
		return Result.failure("StateUpdater._modify_balance: state 为空")
	match holder_type:
		"player":
			if not (state.players is Array):
				return Result.failure("StateUpdater._modify_balance: state.players 类型错误（期望 Array）")
			if holder_id < 0 or holder_id >= state.players.size():
				return Result.failure("StateUpdater._modify_balance: player_id 越界: %d" % holder_id)
			var player_val = state.players[holder_id]
			if not (player_val is Dictionary):
				return Result.failure("StateUpdater._modify_balance: players[%d] 类型错误（期望 Dictionary）" % holder_id)
			var player: Dictionary = player_val
			if not player.has("cash") or not (player["cash"] is int):
				return Result.failure("StateUpdater._modify_balance: players[%d].cash 缺失或类型错误（期望 int）" % holder_id)
			player["cash"] = int(player["cash"]) + delta
			state.players[holder_id] = player
			return Result.success()
		"bank":
			if not (state.bank is Dictionary):
				return Result.failure("StateUpdater._modify_balance: state.bank 类型错误（期望 Dictionary）")
			if holder_id != -1:
				return Result.failure("StateUpdater._modify_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			if not state.bank.has("total") or not (state.bank["total"] is int):
				return Result.failure("StateUpdater._modify_balance: state.bank.total 缺失或类型错误（期望 int）")
			state.bank["total"] = int(state.bank["total"]) + delta
			return Result.success()
		_:
			return Result.failure("StateUpdater._modify_balance: 未知 holder_type: %s" % holder_type)

# === 玩家现金便捷方法 ===

# 玩家收入（从银行）
static func player_receive_from_bank(state: GameState, player_id: int, amount: int) -> Result:
	return transfer_cash(state, "bank", -1, "player", player_id, amount)

# 玩家支付（到银行）
static func player_pay_to_bank(state: GameState, player_id: int, amount: int) -> Result:
	return transfer_cash(state, "player", player_id, "bank", -1, amount)

# 玩家间转账
static func player_pay_to_player(state: GameState, from_id: int, to_id: int, amount: int) -> Result:
	return transfer_cash(state, "player", from_id, "player", to_id, amount)

# 直接设置玩家现金（慎用，主要用于初始化）
static func set_player_cash(state: GameState, player_id: int, amount: int) -> Result:
	if state == null:
		return Result.failure("set_player_cash: state 为空")
	if not (state.players is Array):
		return Result.failure("set_player_cash: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)

	if amount < 0:
		return Result.failure("现金不能为负: %d" % amount)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("set_player_cash: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("cash") or not (player["cash"] is int):
		return Result.failure("set_player_cash: players[%d].cash 缺失或类型错误（期望 int）" % player_id)

	state.players[player_id]["cash"] = amount
	return Result.success()

# === 数值操作 ===

# 增加数值
static func increment(dict: Dictionary, key: String, amount: int = 1) -> int:
	assert(dict != null, "StateUpdater.increment: dict 为空")
	assert(not key.is_empty(), "StateUpdater.increment: key 不能为空")
	var current := 0
	if dict.has(key):
		assert(dict[key] is int, "StateUpdater.increment: %s 类型错误（期望 int）" % key)
		current = int(dict[key])
	var new_value := current + amount
	dict[key] = new_value
	return new_value

# 减少数值（不低于0）
static func decrement(dict: Dictionary, key: String, amount: int = 1) -> int:
	assert(dict != null, "StateUpdater.decrement: dict 为空")
	assert(not key.is_empty(), "StateUpdater.decrement: key 不能为空")
	var current := 0
	if dict.has(key):
		assert(dict[key] is int, "StateUpdater.decrement: %s 类型错误（期望 int）" % key)
		current = int(dict[key])
	var new_value = max(0, current - amount)
	dict[key] = new_value
	return new_value

# 设置数值（带范围限制）
static func set_clamped(dict: Dictionary, key: String, value: int, min_val: int = 0, max_val: int = 999999) -> int:
	assert(dict != null, "StateUpdater.set_clamped: dict 为空")
	assert(not key.is_empty(), "StateUpdater.set_clamped: key 不能为空")
	var clamped := clampi(value, min_val, max_val)
	dict[key] = clamped
	return clamped

# === 数组操作 ===

# 添加到数组
static func append_to_array(dict: Dictionary, key: String, item) -> void:
	assert(dict != null, "StateUpdater.append_to_array: dict 为空")
	assert(not key.is_empty(), "StateUpdater.append_to_array: key 不能为空")
	assert(dict.has(key), "StateUpdater.append_to_array: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.append_to_array: %s 类型错误（期望 Array）" % key)
	dict[key].append(item)

# 从数组移除第一个匹配项
static func remove_from_array(dict: Dictionary, key: String, item) -> bool:
	assert(dict != null, "StateUpdater.remove_from_array: dict 为空")
	assert(not key.is_empty(), "StateUpdater.remove_from_array: key 不能为空")
	assert(dict.has(key), "StateUpdater.remove_from_array: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.remove_from_array: %s 类型错误（期望 Array）" % key)
	var arr: Array = dict[key]
	var index := arr.find(item)
	if index >= 0:
		arr.remove_at(index)
		return true
	return false

# 从数组移除指定索引
static func remove_at_index(dict: Dictionary, key: String, index: int) -> bool:
	assert(dict != null, "StateUpdater.remove_at_index: dict 为空")
	assert(not key.is_empty(), "StateUpdater.remove_at_index: key 不能为空")
	assert(dict.has(key), "StateUpdater.remove_at_index: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.remove_at_index: %s 类型错误（期望 Array）" % key)
	var arr: Array = dict[key]
	if index >= 0 and index < arr.size():
		arr.remove_at(index)
		return true
	return false

# === 库存操作 ===

# 添加库存
static func add_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> Result:
	if state == null:
		return Result.failure("add_inventory: state 为空")
	if not (state.players is Array):
		return Result.failure("add_inventory: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)
	if food_type.is_empty():
		return Result.failure("food_type 不能为空")

	if amount < 0:
		return Result.failure("库存数量不能为负: %d" % amount)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("add_inventory: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("inventory") or not (player["inventory"] is Dictionary):
		return Result.failure("add_inventory: players[%d].inventory 缺失或类型错误（期望 Dictionary）" % player_id)
	var inventory: Dictionary = player["inventory"]
	var current := 0
	if inventory.has(food_type):
		assert(inventory[food_type] is int, "add_inventory: inventory[%s] 类型错误（期望 int）" % food_type)
		current = int(inventory[food_type])
	inventory[food_type] = current + amount
	player["inventory"] = inventory
	state.players[player_id] = player

	return Result.success({"food_type": food_type, "new_amount": inventory[food_type]})

# 减少库存
static func remove_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> Result:
	if state == null:
		return Result.failure("remove_inventory: state 为空")
	if not (state.players is Array):
		return Result.failure("remove_inventory: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)
	if food_type.is_empty():
		return Result.failure("food_type 不能为空")
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("remove_inventory: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("inventory") or not (player["inventory"] is Dictionary):
		return Result.failure("remove_inventory: players[%d].inventory 缺失或类型错误（期望 Dictionary）" % player_id)
	var inventory: Dictionary = player["inventory"]
	var current := 0
	if inventory.has(food_type):
		assert(inventory[food_type] is int, "remove_inventory: inventory[%s] 类型错误（期望 int）" % food_type)
		current = int(inventory[food_type])

	if current < amount:
		return Result.failure("库存不足: %s 需要 %d, 只有 %d" % [food_type, amount, current])

	inventory[food_type] = current - amount
	player["inventory"] = inventory
	state.players[player_id] = player

	return Result.success({"food_type": food_type, "new_amount": inventory[food_type]})

# 检查库存是否足够
static func has_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> bool:
	assert(state != null, "has_inventory: state 为空")
	assert(state.players is Array, "has_inventory: state.players 类型错误（期望 Array）")
	assert(player_id >= 0 and player_id < state.players.size(), "has_inventory: player_id 越界: %d" % player_id)
	assert(not food_type.is_empty(), "has_inventory: food_type 不能为空")
	assert(amount >= 0, "has_inventory: amount 不能为负: %d" % amount)

	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "has_inventory: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	assert(player.has("inventory") and (player["inventory"] is Dictionary), "has_inventory: players[%d].inventory 缺失或类型错误（期望 Dictionary）" % player_id)
	var inventory: Dictionary = player["inventory"]
	if not inventory.has(food_type):
		return 0 >= amount
	assert(inventory[food_type] is int, "has_inventory: inventory[%s] 类型错误（期望 int）" % food_type)
	return int(inventory[food_type]) >= amount

# === 员工操作 ===

# 添加员工到玩家
static func add_employee(state: GameState, player_id: int, employee_id: String, to_reserve: bool = false) -> Result:
	if state == null:
		return Result.failure("add_employee: state 为空")
	if not (state.players is Array):
		return Result.failure("add_employee: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)
	if employee_id.is_empty():
		return Result.failure("employee_id 不能为空")

	var target_key := "reserve_employees" if to_reserve else "employees"
	append_to_array(state.players[player_id], target_key, employee_id)

	return Result.success({"employee_id": employee_id, "location": target_key})

# 从员工池取出员工
static func take_from_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	if state == null:
		return Result.failure("take_from_pool: state 为空")
	if not (state.employee_pool is Dictionary):
		return Result.failure("take_from_pool: state.employee_pool 类型错误（期望 Dictionary）")
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	if count <= 0:
		return Result.failure("count 必须 > 0，实际: %d" % count)
	var available := 0
	if state.employee_pool.has(employee_type):
		if not (state.employee_pool[employee_type] is int):
			return Result.failure("take_from_pool: employee_pool[%s] 类型错误（期望 int）" % employee_type)
		available = int(state.employee_pool[employee_type])
	if available < count:
		return Result.failure("员工池不足: %s 需要 %d, 只有 %d" % [employee_type, count, available])

	state.employee_pool[employee_type] = available - count
	return Result.success({"employee_type": employee_type, "taken": count, "remaining": available - count})

# 归还员工到池
static func return_to_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	if state == null:
		return Result.failure("return_to_pool: state 为空")
	if not (state.employee_pool is Dictionary):
		return Result.failure("return_to_pool: state.employee_pool 类型错误（期望 Dictionary）")
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	if count <= 0:
		return Result.failure("count 必须 > 0，实际: %d" % count)
	var current := 0
	if state.employee_pool.has(employee_type):
		if not (state.employee_pool[employee_type] is int):
			return Result.failure("return_to_pool: employee_pool[%s] 类型错误（期望 int）" % employee_type)
		current = int(state.employee_pool[employee_type])
	state.employee_pool[employee_type] = current + count
	return Result.success({"employee_type": employee_type, "returned": count, "total": current + count})

# === 里程碑操作 ===

# 获取里程碑
static func claim_milestone(state: GameState, player_id: int, milestone_id: String) -> Result:
	if state == null:
		return Result.failure("claim_milestone: state 为空")
	if not (state.players is Array):
		return Result.failure("claim_milestone: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("claim_milestone: state.round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)
	if milestone_id.is_empty():
		return Result.failure("milestone_id 不能为空")

	if player_has_milestone(state, player_id, milestone_id):
		return Result.success().with_warning("玩家 %d 已拥有里程碑: %s" % [player_id, milestone_id])

	var index := state.milestone_pool.find(milestone_id)
	if index < 0:
		return Result.failure("里程碑不可用: %s" % milestone_id)

	append_to_array(state.players[player_id], "milestones", milestone_id)

	# 记录到回合状态：允许同回合多名玩家获得；供 Cleanup 阶段统一从 supply 移除
	if not state.round_state.has("milestones_claimed"):
		state.round_state["milestones_claimed"] = {}
	assert(state.round_state["milestones_claimed"] is Dictionary, "claim_milestone: round_state.milestones_claimed 类型错误（期望 Dictionary）")
	var claimed: Dictionary = state.round_state["milestones_claimed"]
	if not claimed.has(milestone_id):
		claimed[milestone_id] = []
	assert(claimed[milestone_id] is Array, "claim_milestone: milestones_claimed[%s] 类型错误（期望 Array）" % milestone_id)
	var list: Array = claimed[milestone_id]
	if not list.has(player_id):
		list.append(player_id)
	claimed[milestone_id] = list
	state.round_state["milestones_claimed"] = claimed

	return Result.success({"milestone_id": milestone_id, "player_id": player_id})

# 检查里程碑是否可用
static func is_milestone_available(state: GameState, milestone_id: String) -> bool:
	return state.milestone_pool.has(milestone_id)

# 检查玩家是否有里程碑
static func player_has_milestone(state: GameState, player_id: int, milestone_id: String) -> bool:
	assert(state != null, "player_has_milestone: state 为空")
	assert(state.players is Array, "player_has_milestone: state.players 类型错误（期望 Array）")
	assert(player_id >= 0 and player_id < state.players.size(), "player_has_milestone: player_id 越界: %d" % player_id)
	assert(not milestone_id.is_empty(), "player_has_milestone: milestone_id 不能为空")
	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "player_has_milestone: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	assert(player.has("milestones") and (player["milestones"] is Array), "player_has_milestone: players[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
	var milestones: Array = player["milestones"]
	return milestones.has(milestone_id)

# === 批量更新 ===

# 批量应用更新
static func apply_batch(state: GameState, updates: Array[Dictionary]) -> Result:
	if state == null:
		return Result.failure("apply_batch: state 为空")
	if not (updates is Array):
		return Result.failure("apply_batch: updates 类型错误（期望 Array）")
	var results: Array[Result] = []

	for i in range(updates.size()):
		var update_val = updates[i]
		if not (update_val is Dictionary):
			return Result.failure("apply_batch: updates[%d] 类型错误（期望 Dictionary）" % i)
		var update: Dictionary = update_val

		if not update.has("op") or not (update["op"] is String):
			return Result.failure("apply_batch: updates[%d].op 缺失或类型错误（期望 String）" % i)
		var op: String = update["op"]
		var result: Result = Result.failure("未初始化")

		match op:
			"transfer_cash":
				if not update.has("from_type") or not (update["from_type"] is String):
					return Result.failure("apply_batch: updates[%d].from_type 缺失或类型错误（期望 String）" % i)
				if not update.has("from_id") or not (update["from_id"] is int):
					return Result.failure("apply_batch: updates[%d].from_id 缺失或类型错误（期望 int）" % i)
				if not update.has("to_type") or not (update["to_type"] is String):
					return Result.failure("apply_batch: updates[%d].to_type 缺失或类型错误（期望 String）" % i)
				if not update.has("to_id") or not (update["to_id"] is int):
					return Result.failure("apply_batch: updates[%d].to_id 缺失或类型错误（期望 int）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = transfer_cash(
					state,
					update["from_type"],
					update["from_id"],
					update["to_type"],
					update["to_id"],
					update["amount"]
				)
			"add_inventory":
				if not update.has("player_id") or not (update["player_id"] is int):
					return Result.failure("apply_batch: updates[%d].player_id 缺失或类型错误（期望 int）" % i)
				if not update.has("food_type") or not (update["food_type"] is String):
					return Result.failure("apply_batch: updates[%d].food_type 缺失或类型错误（期望 String）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = add_inventory(
					state,
					update["player_id"],
					update["food_type"],
					update["amount"]
				)
			"remove_inventory":
				if not update.has("player_id") or not (update["player_id"] is int):
					return Result.failure("apply_batch: updates[%d].player_id 缺失或类型错误（期望 int）" % i)
				if not update.has("food_type") or not (update["food_type"] is String):
					return Result.failure("apply_batch: updates[%d].food_type 缺失或类型错误（期望 String）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = remove_inventory(
					state,
					update["player_id"],
					update["food_type"],
					update["amount"]
				)
			_:
				result = Result.failure("未知操作: %s" % op)

		results.append(result)
		if not result.ok:
			return result  # 遇到错误立即返回

	return Result.success(results)
