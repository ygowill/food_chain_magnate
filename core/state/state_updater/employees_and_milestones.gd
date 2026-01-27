extends RefCounted

const Collections = preload("res://core/state/state_updater/collections.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

# === 员工操作 ===

static func _get_employee_pool_count(state: GameState, employee_type: String, caller: String) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % caller)
	if not (state.employee_pool is Dictionary):
		return Result.failure("%s: state.employee_pool 类型错误（期望 Dictionary）" % caller)
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	var current := 0
	if state.employee_pool.has(employee_type):
		if not (state.employee_pool[employee_type] is int):
			return Result.failure("%s: employee_pool[%s] 类型错误（期望 int）" % [caller, employee_type])
		current = int(state.employee_pool[employee_type])
	return Result.success(current)

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
	Collections.append_to_array(state.players[player_id], target_key, employee_id)

	return Result.success({"employee_id": employee_id, "location": target_key})

# 从员工池取出员工
static func take_from_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	if count <= 0:
		return Result.failure("count 必须 > 0，实际: %d" % count)
	var available_read := _get_employee_pool_count(state, employee_type, "take_from_pool")
	if not available_read.ok:
		return available_read
	var available: int = int(available_read.value)
	if available < count:
		return Result.failure("员工池不足: %s 需要 %d, 只有 %d" % [employee_type, count, available])

	state.employee_pool[employee_type] = available - count
	return Result.success({"employee_type": employee_type, "taken": count, "remaining": available - count})

# 归还员工到池
static func return_to_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	if count <= 0:
		return Result.failure("count 必须 > 0，实际: %d" % count)
	var current_read := _get_employee_pool_count(state, employee_type, "return_to_pool")
	if not current_read.ok:
		return current_read
	var current: int = int(current_read.value)
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

	Collections.append_to_array(state.players[player_id], "milestones", milestone_id)

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
	var milestones_read := PlayerStateAccessClass.require_milestones(player, "players[%d]" % player_id, "player_has_milestone")
	if not milestones_read.ok:
		assert(false, milestones_read.error)
		return false
	var milestones: Array = milestones_read.value
	return milestones.has(milestone_id)
