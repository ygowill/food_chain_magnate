extends RefCounted

static func try_get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> Result:
	if state == null:
		return Result.failure("immediate_train_pending: state 为空")
	if employee_type.is_empty():
		return Result.failure("immediate_train_pending: employee_type 不能为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return Result.success(0)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	if pending_all.has(str(player_id)):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return Result.success(0)
	var per_val = pending_all[player_id]
	if not (per_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return Result.success(0)
	var v = per_player[employee_type]
	if not (v is int):
		return Result.failure("round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	if int(v) < 0:
		return Result.failure("round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
	return Result.success(int(v))

static func get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> int:
	if state == null:
		return 0
	var read := try_get_immediate_train_pending_count(state, player_id, employee_type)
	if not read.ok:
		return 0
	return int(read.value)

static func try_get_immediate_train_pending_total(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("immediate_train_pending: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return Result.success(0)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	if pending_all.has(str(player_id)):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return Result.success(0)
	var per_val = pending_all[player_id]
	if not (per_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	var total := 0
	for k in per_player.keys():
		if not (k is String):
			return Result.failure("round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
		var emp_id: String = str(k)
		if emp_id.is_empty():
			return Result.failure("round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
		var v = per_player[k]
		if not (v is int):
			return Result.failure("round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
		if int(v) < 0:
			return Result.failure("round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, emp_id, int(v)])
		total += int(v)
	return Result.success(total)

static func get_immediate_train_pending_total(state: GameState, player_id: int) -> int:
	if state == null:
		return 0
	var read := try_get_immediate_train_pending_total(state, player_id)
	if not read.ok:
		return 0
	return int(read.value)

static func try_has_any_immediate_train_pending(state: GameState) -> Result:
	if state == null:
		return Result.failure("immediate_train_pending: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return Result.success(false)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val

	for pid in pending_all.keys():
		if pid is String:
			return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(pid))
		if not (pid is int):
			return Result.failure("round_state.immediate_train_pending key 类型错误（期望 int）")
		var per_val = pending_all.get(pid, null)
		if not (per_val is Dictionary):
			return Result.failure("round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % int(pid))
		var per_player: Dictionary = per_val
		for emp_id in per_player.keys():
			if not (emp_id is String):
				return Result.failure("round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % int(pid))
			var emp_key: String = str(emp_id)
			if emp_key.is_empty():
				return Result.failure("round_state.immediate_train_pending[%d] 不应包含空字符串 key" % int(pid))
			var v = per_player[emp_id]
			if not (v is int):
				return Result.failure("round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [int(pid), emp_key])
			if int(v) < 0:
				return Result.failure("round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [int(pid), emp_key, int(v)])
			if int(v) > 0:
				return Result.success(true)
	return Result.success(false)

static func has_any_immediate_train_pending(state: GameState) -> bool:
	if state == null:
		return false
	var read := try_has_any_immediate_train_pending(state)
	if not read.ok:
		return false
	return bool(read.value)

static func try_add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> Result:
	if state == null:
		return Result.failure("immediate_train_pending: state 为空")
	if employee_type.is_empty():
		return Result.failure("immediate_train_pending: employee_type 不能为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	var pending_all: Dictionary = {}
	if pending_val != null:
		if not (pending_val is Dictionary):
			return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		pending_all = pending_val

	if pending_all.has(str(player_id)):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	var per_val = pending_all.get(player_id, null)
	var per_player: Dictionary = {}
	if per_val != null:
		if not (per_val is Dictionary):
			return Result.failure("round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
		per_player = per_val

	var current := 0
	if per_player.has(employee_type):
		var v = per_player[employee_type]
		if not (v is int):
			return Result.failure("round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
		if int(v) < 0:
			return Result.failure("round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
		current = int(v)
	per_player[employee_type] = current + 1
	pending_all[player_id] = per_player
	state.round_state["immediate_train_pending"] = pending_all
	return Result.success(current + 1)

static func add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> void:
	if state == null:
		return
	var r := try_add_immediate_train_pending(state, player_id, employee_type)
	if not r.ok:
		return

static func try_consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> Result:
	if state == null:
		return Result.failure("immediate_train_pending: state 为空")
	if employee_type.is_empty():
		return Result.failure("immediate_train_pending: employee_type 不能为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return Result.success(false)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	if pending_all.has(str(player_id)):
		return Result.failure("round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return Result.success(false)
	var per_val = pending_all[player_id]
	if not (per_val is Dictionary):
		return Result.failure("round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return Result.success(false)
	var current_val = per_player[employee_type]
	if not (current_val is int):
		return Result.failure("round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	var current: int = int(current_val)
	if current <= 0:
		return Result.failure("round_state.immediate_train_pending[%d].%s 必须 > 0，实际: %d" % [player_id, employee_type, current])

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

	return Result.success(true)

static func consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> bool:
	if state == null:
		return false
	var read := try_consume_immediate_train_pending(state, player_id, employee_type)
	if not read.ok:
		return false
	return bool(read.value)

