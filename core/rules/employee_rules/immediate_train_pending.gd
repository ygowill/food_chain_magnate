extends RefCounted

static func get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> int:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return 0
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return 0
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return 0
	var v = per_player[employee_type]
	assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
	return int(v)

static func get_immediate_train_pending_total(state: GameState, player_id: int) -> int:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return 0
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return 0
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	var total := 0
	for k in per_player.keys():
		assert(k is String, "round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
		var emp_id: String = str(k)
		assert(not emp_id.is_empty(), "round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
		var v = per_player[k]
		assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
		assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, emp_id, int(v)])
		total += int(v)
	return total

static func has_any_immediate_train_pending(state: GameState) -> bool:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return false
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val

	for pid in pending_all.keys():
		assert(pid is int, "round_state.immediate_train_pending key 类型错误（期望 int）")
		var per_val = pending_all.get(pid, null)
		assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % int(pid))
		var per_player: Dictionary = per_val
		for emp_id in per_player.keys():
			assert(emp_id is String, "round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % int(pid))
			var emp_key: String = str(emp_id)
			assert(not emp_key.is_empty(), "round_state.immediate_train_pending[%d] 不应包含空字符串 key" % int(pid))
			var v = per_player[emp_id]
			assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [int(pid), emp_key])
			assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [int(pid), emp_key, int(v)])
			if int(v) > 0:
				return true
	return false

static func add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> void:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	var pending_all: Dictionary = {}
	if pending_val != null:
		assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		pending_all = pending_val

	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	var per_val = pending_all.get(player_id, null)
	var per_player: Dictionary = {}
	if per_val != null:
		assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
		per_player = per_val

	var current := 0
	if per_player.has(employee_type):
		var v = per_player[employee_type]
		assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
		assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
		current = int(v)
	per_player[employee_type] = current + 1
	pending_all[player_id] = per_player
	state.round_state["immediate_train_pending"] = pending_all

static func consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> bool:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return false
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return false
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return false
	var current_val = per_player[employee_type]
	assert(current_val is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	var current: int = int(current_val)
	assert(current > 0, "round_state.immediate_train_pending[%d].%s 必须 > 0，实际: %d" % [player_id, employee_type, current])

	current -= 1
	if current <= 0:
		per_player.erase(employee_type)
	else:
		per_player[employee_type] = current

	if per_player.is_empty():
		pending_all.erase(player_id)
	else:
		pending_all[player_id] = per_player

	if pending_all.is_empty():
		state.round_state.erase("immediate_train_pending")
	else:
		state.round_state["immediate_train_pending"] = pending_all

	return true

