extends RefCounted

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

