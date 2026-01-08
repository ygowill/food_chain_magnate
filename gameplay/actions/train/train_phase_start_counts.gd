extends RefCounted

static func _require_player_string_array(player: Dictionary, key: String, path: String) -> Result:
	if not player.has(key):
		return Result.failure("%s 缺失" % path)
	var value = player.get(key, null)
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
	return Result.success(arr)

static func _ensure_train_phase_start_counts(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	if not state.round_state.has("train_phase_start_counts"):
		state.round_state["train_phase_start_counts"] = {}
	var all_val = state.round_state.get("train_phase_start_counts", null)
	if not (all_val is Dictionary):
		return Result.failure("train: round_state.train_phase_start_counts 类型错误（期望 Dictionary）")
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.train_phase_start_counts 不应包含字符串玩家 key: %s" % str(player_id))

	if all.has(player_id):
		return Result.success()

	var counts_read := _compute_train_phase_start_counts(state, player_id, reserve)
	if not counts_read.ok:
		return counts_read
	all[player_id] = counts_read.value
	state.round_state["train_phase_start_counts"] = all
	return Result.success()

static func _get_train_phase_start_count(state: GameState, player_id: int, reserve: Array, employee_type: String) -> Result:
	if employee_type.is_empty():
		return Result.failure("train: from_employee 不能为空")
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	var all_val = state.round_state.get("train_phase_start_counts", null)
	if all_val != null:
		if not (all_val is Dictionary):
			return Result.failure("train: round_state.train_phase_start_counts 类型错误（期望 Dictionary）")
		var all: Dictionary = all_val
		assert(not all.has(str(player_id)), "round_state.train_phase_start_counts 不应包含字符串玩家 key: %s" % str(player_id))
		if all.has(player_id):
			var per_val = all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("train: round_state.train_phase_start_counts[%d] 类型错误（期望 Dictionary）" % player_id)
			var per: Dictionary = per_val
			if per.has(employee_type):
				var v = per.get(employee_type, null)
				if not (v is int):
					return Result.failure("train: round_state.train_phase_start_counts[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
				return Result.success(int(v))
			return Result.success(0)

	var counts_read := _compute_train_phase_start_counts(state, player_id, reserve)
	if not counts_read.ok:
		return counts_read
	var counts: Dictionary = counts_read.value
	var v = counts.get(employee_type, 0)
	if not (v is int):
		return Result.failure("train: start_counts.%s 类型错误（期望 int）" % employee_type)
	return Result.success(int(v))

static func _compute_train_phase_start_counts(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	var counts: Dictionary = {}
	# 待命区
	for emp_val in reserve:
		assert(emp_val is String, "train: reserve_employees 元素类型错误（期望 String）")
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("train: reserve_employees 不应包含空字符串")
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

	# 在岗区（FIRST LEMONADE SOLD 需要用到；并用于“本子阶段新获得员工不可连续培训”的一致性）
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("train: player.employees 缺失或类型错误（期望 Array）")
	var employees: Array = player["employees"]
	for emp_val in employees:
		assert(emp_val is String, "train: employees 元素类型错误（期望 String）")
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("train: employees 不应包含空字符串")
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

	# 加上“缺货预支”待培训员工（视为本子阶段开始时就存在的可培训来源）
	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val != null:
		if not (pending_val is Dictionary):
			return Result.failure("train: round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		var pending_all: Dictionary = pending_val
		assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))
		if pending_all.has(player_id):
			var per_val = pending_all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("train: round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
			var per: Dictionary = per_val
			for k in per.keys():
				if not (k is String):
					return Result.failure("train: round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
				var emp_id: String = str(k)
				if emp_id.is_empty():
					return Result.failure("train: round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
				var v = per.get(k, null)
				if not (v is int):
					return Result.failure("train: round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
				if int(v) <= 0:
					continue
				counts[emp_id] = int(counts.get(emp_id, 0)) + int(v)

	return Result.success(counts)
