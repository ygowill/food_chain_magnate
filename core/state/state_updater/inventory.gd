extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

# === 库存操作 ===

static func _require_player_inventory(state: GameState, player_id: int, caller: String) -> Result:
	var player_read := PlayerStateAccessClass.require_player(state, player_id, caller)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % player_id, caller)
	if not inventory_read.ok:
		return inventory_read
	return Result.success({
		"player": player,
		"inventory": inventory_read.value,
	})

# 添加库存
static func add_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> Result:
	if food_type.is_empty():
		return Result.failure("food_type 不能为空")

	if amount < 0:
		return Result.failure("库存数量不能为负: %d" % amount)

	var ctx_read := _require_player_inventory(state, player_id, "add_inventory")
	if not ctx_read.ok:
		return ctx_read
	var ctx: Dictionary = ctx_read.value
	var player: Dictionary = ctx["player"]
	var inventory: Dictionary = ctx["inventory"]
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
	if food_type.is_empty():
		return Result.failure("food_type 不能为空")
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	var ctx_read := _require_player_inventory(state, player_id, "remove_inventory")
	if not ctx_read.ok:
		return ctx_read
	var ctx: Dictionary = ctx_read.value
	var player: Dictionary = ctx["player"]
	var inventory: Dictionary = ctx["inventory"]
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
	assert(not food_type.is_empty(), "has_inventory: food_type 不能为空")
	assert(amount >= 0, "has_inventory: amount 不能为负: %d" % amount)

	var player_read := PlayerStateAccessClass.require_player(state, player_id, "has_inventory")
	assert(player_read.ok, player_read.error)
	var player: Dictionary = player_read.value
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % player_id, "has_inventory")
	assert(inventory_read.ok, inventory_read.error)
	var inventory: Dictionary = inventory_read.value
	if not inventory.has(food_type):
		return 0 >= amount
	assert(inventory[food_type] is int, "has_inventory: inventory[%s] 类型错误（期望 int）" % food_type)
	return int(inventory[food_type]) >= amount
