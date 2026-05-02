extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

const ROUND_STATE_KEY := "train_employee_locks"

# 记录 Train 子阶段内“同一名员工只能由同一名培训员(具体实例)继续培训”的锁。
# 通过 staff_id 绑定具体员工实例；缺货预支等无实体来源则使用临时 token。
# - round_state.train_employee_locks[player_id][employee_type] = Array[token]
# - token 表示“一张员工卡的身份”，培训后会随着职位升级从 from_employee 移动到 to_employee。
# - token 的锁字段：
#   - trainer_id: String（空字符串表示未锁定）
#   - instance_idx: int（0..instances-1；trainer_id 为空时该值无意义）

static func reset_train_employee_locks(state: GameState) -> void:
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	state.round_state[ROUND_STATE_KEY] = {}

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

static func _append_token(tokens_by_employee: Dictionary, employee_id: String, staff_id: int) -> Result:
	if employee_id.is_empty():
		return Result.failure("train_locks: employee_id 不能为空")
	if not tokens_by_employee.has(employee_id):
		tokens_by_employee[employee_id] = []
	var tokens_val = tokens_by_employee.get(employee_id, null)
	if not (tokens_val is Array):
		return Result.failure("train_locks: tokens_by_employee.%s 类型错误（期望 Array）" % employee_id)
	var tokens: Array = tokens_val
	tokens.append({
		"staff_id": staff_id,
		"trainer_id": "",
		"instance_idx": 0,
	})
	tokens_by_employee[employee_id] = tokens
	return Result.success()

static func _append_staff_zone_tokens(tokens_by_employee: Dictionary, player: Dictionary, staff_zone_key: String, zone_label: String) -> Result:
	if not player.has(staff_zone_key):
		return Result.failure("train_locks: player.%s 缺失" % staff_zone_key)
	var ids_val = player.get(staff_zone_key, null)
	if not (ids_val is Array):
		return Result.failure("train_locks: player.%s 类型错误（期望 Array[int]）" % staff_zone_key)
	var ids: Array = ids_val
	var registry_val = player.get("staff_registry", null)
	if not (registry_val is Dictionary):
		return Result.failure("train_locks: player.staff_registry 缺失或类型错误（期望 Dictionary）")
	var registry: Dictionary = registry_val
	for i in range(ids.size()):
		var staff_id := int(ids[i])
		if staff_id <= 0:
			return Result.failure("train_locks: player.%s[%d] 必须为正整数，实际: %s" % [staff_zone_key, i, str(ids[i])])
		if not registry.has(staff_id):
			return Result.failure("train_locks: %s staff_id 不存在: %d" % [zone_label, staff_id])
		var record_val = registry.get(staff_id, null)
		if not (record_val is Dictionary):
			return Result.failure("train_locks: staff_registry[%d] 类型错误（期望 Dictionary）" % staff_id)
		var record: Dictionary = record_val
		var emp_id := str(record.get("employee_type", "")).strip_edges()
		if emp_id.is_empty():
			return Result.failure("train_locks: staff_registry[%d].employee_type 不能为空" % staff_id)
		var add := _append_token(tokens_by_employee, emp_id, staff_id)
		if not add.ok:
			return add
	return Result.success()

static func _compute_initial_token_counts(state: GameState, player_id: int, reserve: Array) -> Result:
	var tokens_read := _compute_initial_tokens_by_employee(state, player_id, reserve)
	if not tokens_read.ok:
		return tokens_read
	var tokens_by_employee: Dictionary = tokens_read.value
	var counts: Dictionary = {}
	for k in tokens_by_employee.keys():
		if not (k is String):
			return Result.failure("train_locks: tokens_by_employee key 类型错误（期望 String）")
		var emp_id: String = str(k)
		var tokens_val = tokens_by_employee.get(k, null)
		if not (tokens_val is Array):
			return Result.failure("train_locks: tokens_by_employee.%s 类型错误（期望 Array）" % emp_id)
		counts[emp_id] = (tokens_val as Array).size()
	return Result.success(counts)

static func _compute_initial_tokens_by_employee(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null:
		return Result.failure("train_locks: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train_locks: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train_locks: player_id 越界: %d" % player_id)

	for i in range(reserve.size()):
		if not (reserve[i] is String):
			return Result.failure("train_locks: reserve_employees 元素类型错误（期望 String）")
		if str(reserve[i]).is_empty():
			return Result.failure("train_locks: reserve_employees 不应包含空字符串")

	var tokens_by_employee: Dictionary = {}

	# 缺货预支：视为本子阶段开始时就存在的“可培训来源 token”。
	# 先校验 pending 结构，保持原有 fail-fast 错误优先级。
	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val != null:
		if not (pending_val is Dictionary):
			return Result.failure("train_locks: round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		var pending_all: Dictionary = pending_val
		if pending_all.has(str(player_id)):
			return Result.failure("train_locks: round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))
		if pending_all.has(player_id):
			var per_val = pending_all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("train_locks: round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
			var per: Dictionary = per_val
			for k in per.keys():
				if not (k is String):
					return Result.failure("train_locks: round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
				var emp_id: String = str(k)
				if emp_id.is_empty():
					return Result.failure("train_locks: round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
				var v = per.get(k, null)
				if not (v is int):
					return Result.failure("train_locks: round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
				if int(v) <= 0:
					continue
				for _i in range(int(v)):
					var pending_staff_id := -1
					var add_pending := _append_token(tokens_by_employee, emp_id, pending_staff_id)
					if not add_pending.ok:
						return add_pending

	var sync_read := StaffStateClass.ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train_locks: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	# 待命区
	var reserve_tokens := _append_staff_zone_tokens(tokens_by_employee, player, "reserve_staff_ids", "reserve")
	if not reserve_tokens.ok:
		return reserve_tokens

	# 在岗区（用于 FIRST LEMONADE SOLD 的“在岗培训”，以及统一 token 计数口径）
	var active_read := _require_player_string_array(player, "employees", "train_locks: player.employees")
	if not active_read.ok:
		return active_read
	var active_tokens := _append_staff_zone_tokens(tokens_by_employee, player, "employees_staff_ids", "employees")
	if not active_tokens.ok:
		return active_tokens

	return Result.success(tokens_by_employee)

static func _build_tokens_from_counts(counts: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in counts.keys():
		if not (k is String):
			continue
		var emp_id: String = str(k)
		if emp_id.is_empty():
			continue
		var count := int(counts.get(k, 0))
		if count <= 0:
			continue
		var tokens: Array = []
		for _i in range(count):
			tokens.append({"staff_id": 0, "trainer_id": "", "instance_idx": 0})
		out[emp_id] = tokens
	return out

static func _fail_on_string_player_key(all: Dictionary, player_id: int) -> Result:
	if all.has(str(player_id)):
		return Result.failure("round_state.%s 不应包含字符串玩家 key: %s" % [ROUND_STATE_KEY, str(player_id)])
	return Result.success()

static func _read_player_locks(state: GameState, player_id: int) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_locks: state/round_state 无效")

	var all_val = state.round_state.get(ROUND_STATE_KEY, null)
	if all_val == null:
		return Result.success(null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % ROUND_STATE_KEY)
	var all: Dictionary = all_val
	var key_check := _fail_on_string_player_key(all, player_id)
	if not key_check.ok:
		return key_check
	if not all.has(player_id):
		return Result.success(null)
	var per_val = all.get(player_id, null)
	if not (per_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [ROUND_STATE_KEY, player_id])
	return Result.success(per_val)

static func _ensure_player_locks(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_locks: state/round_state 无效")

	if not state.round_state.has(ROUND_STATE_KEY):
		state.round_state[ROUND_STATE_KEY] = {}
	var all_val = state.round_state.get(ROUND_STATE_KEY, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % ROUND_STATE_KEY)
	var all: Dictionary = all_val
	var key_check := _fail_on_string_player_key(all, player_id)
	if not key_check.ok:
		return key_check

	if all.has(player_id):
		return Result.success(all[player_id])

	var tokens_read := _compute_initial_tokens_by_employee(state, player_id, reserve)
	if not tokens_read.ok:
		return tokens_read
	var per: Dictionary = tokens_read.value
	all[player_id] = per
	state.round_state[ROUND_STATE_KEY] = all
	return Result.success(per)

static func plan_training(
	state: GameState,
	player_id: int,
	from_employee: String,
	steps_needed: int,
	multi_trainer_on_one: bool,
	reserve: Array,
	init_if_missing: bool,
	to_employee: String = "",
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1,
	preferred_source_staff_id: int = -1
) -> Result:
	if from_employee.is_empty():
		return Result.failure("train_locks: from_employee 不能为空")
	if steps_needed <= 0:
		return Result.failure("train_locks: steps_needed 必须 > 0")

	var locks_read: Result
	if init_if_missing:
		locks_read = _ensure_player_locks(state, player_id, reserve)
	else:
		locks_read = _read_player_locks(state, player_id)
		if not locks_read.ok:
			return locks_read
		if locks_read.value == null:
			var tokens_read := _compute_initial_tokens_by_employee(state, player_id, reserve)
			if not tokens_read.ok:
				return tokens_read
			locks_read = Result.success(tokens_read.value)

	if not locks_read.ok:
		return locks_read
	if locks_read.value == null:
		return Result.failure("train_locks: locks 读取失败")
	var locks: Dictionary = locks_read.value

	var target_tokens_check := _validate_target_tokens_container(locks, to_employee)
	if not target_tokens_check.ok:
		return target_tokens_check

	var tokens_val = locks.get(from_employee, null)
	if not (tokens_val is Array):
		return Result.failure("train_locks: 未找到可用于培训的员工 token: %s" % from_employee)
	var tokens: Array = tokens_val
	if tokens.is_empty():
		return Result.failure("train_locks: 未找到可用于培训的员工 token: %s" % from_employee)

	var best_plan: Dictionary = {}
	var best_cap := 0
	var best_trainer_id := ""
	var best_instance_idx := 0
	var best_token_idx := -1
	var saw_source_token := false

	for i in range(tokens.size()):
		var token_val = tokens[i]
		if not (token_val is Dictionary):
			return Result.failure("train_locks: token 类型错误（期望 Dictionary）: %s[%d]" % [from_employee, i])
		var token: Dictionary = token_val
		var token_staff_id := int(token.get("staff_id", 0))
		if preferred_source_staff_id > 0:
			if token_staff_id != preferred_source_staff_id:
				continue
			saw_source_token = true
		var locked_trainer_id: String = str(token.get("trainer_id", ""))
		var locked_instance_idx: int = int(token.get("instance_idx", 0))

		var token_preferred_trainer_id := ""
		var token_preferred_instance_idx := -1
		if not preferred_trainer_id.is_empty():
			if not multi_trainer_on_one and not locked_trainer_id.is_empty():
				if locked_trainer_id != preferred_trainer_id or locked_instance_idx != preferred_instance_idx:
					continue
			token_preferred_trainer_id = preferred_trainer_id
			token_preferred_instance_idx = preferred_instance_idx
		elif not multi_trainer_on_one and not locked_trainer_id.is_empty():
			token_preferred_trainer_id = locked_trainer_id
			token_preferred_instance_idx = locked_instance_idx

		var can := EmployeeRulesClass.can_allocate_train_slots_for_working(
			state, player_id, steps_needed, token_preferred_trainer_id, token_preferred_instance_idx
		)
		if not can.ok:
			continue
		var info: Dictionary = can.value
		var trainer_id: String = str(info.get("trainer_id", ""))
		var instance_idx: int = int(info.get("instance_idx", 0))
		var cap_per_instance: int = int(info.get("cap_per_instance", 0))

		# 选择最“小”的培训员容量优先（trainer < coach < guru），以减少占用高阶培训员的灵活性。
		var better := false
		if best_token_idx < 0:
			better = true
		elif cap_per_instance < best_cap:
			better = true
		elif cap_per_instance == best_cap:
			if not preferred_trainer_id.is_empty() and i < best_token_idx:
				better = true
			elif not preferred_trainer_id.is_empty():
				better = false
			elif trainer_id < best_trainer_id:
				better = true
			elif trainer_id == best_trainer_id:
				if instance_idx < best_instance_idx:
					better = true
				elif instance_idx == best_instance_idx and i < best_token_idx:
					better = true

		if better:
			best_cap = cap_per_instance
			best_trainer_id = trainer_id
			best_instance_idx = instance_idx
			best_token_idx = i
			best_plan = {
				"token_index": i,
				"source_staff_id": token_staff_id,
				"trainer_id": trainer_id,
				"instance_idx": instance_idx,
				"slots": steps_needed,
			}

	if not best_plan.is_empty():
		return Result.success(best_plan)

	if preferred_source_staff_id > 0 and not saw_source_token:
		return Result.failure("本回合没有可继续培训的员工: staff_id=%d" % preferred_source_staff_id)

	# 若存在培训员容量但因“锁”被禁止（需要里程碑），给出更明确的提示。
	if not multi_trainer_on_one:
		var unlocked_can := EmployeeRulesClass.can_allocate_train_slots_for_working(state, player_id, steps_needed)
		if unlocked_can.ok:
			return Result.failure("本子阶段同一名员工不能更换培训员继续培训（需要里程碑允许）: %s" % from_employee)

	return Result.failure("培训员 slot 不足（需要 %d）" % steps_needed)

static func _validate_target_tokens_container(locks: Dictionary, to_employee: String) -> Result:
	if to_employee.is_empty():
		return Result.success()
	var to_tokens_val = locks.get(to_employee, null)
	if to_tokens_val == null:
		return Result.success()
	if not (to_tokens_val is Array):
		return Result.failure("train_locks: to_employee tokens 类型错误（期望 Array）: %s" % to_employee)
	return Result.success()

static func apply_move_token_and_lock(
	state: GameState,
	player_id: int,
	from_employee: String,
	to_employee: String,
	plan: Dictionary,
	multi_trainer_on_one: bool,
	reserve: Array,
	target_staff_id: int = -1
) -> Result:
	if from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("train_locks: from/to_employee 不能为空")
	if not (plan is Dictionary):
		return Result.failure("train_locks: plan 类型错误（期望 Dictionary）")

	var locks_read := _ensure_player_locks(state, player_id, reserve)
	if not locks_read.ok:
		return locks_read
	var locks: Dictionary = locks_read.value

	var from_tokens_val = locks.get(from_employee, null)
	if not (from_tokens_val is Array):
		return Result.failure("train_locks: from_employee tokens 缺失: %s" % from_employee)
	var from_tokens: Array = from_tokens_val

	var token_index: int = int(plan.get("token_index", -1))
	if token_index < 0 or token_index >= from_tokens.size():
		return Result.failure("train_locks: token_index 越界: %s[%d]" % [from_employee, token_index])
	var token_val = from_tokens[token_index]
	if not (token_val is Dictionary):
		return Result.failure("train_locks: token 类型错误（期望 Dictionary）: %s[%d]" % [from_employee, token_index])
	var token: Dictionary = token_val

	var trainer_id: String = str(plan.get("trainer_id", ""))
	var instance_idx: int = int(plan.get("instance_idx", 0))

	if not multi_trainer_on_one:
		token["trainer_id"] = trainer_id
		token["instance_idx"] = instance_idx
	if target_staff_id > 0:
		token["staff_id"] = target_staff_id
	elif not token.has("staff_id"):
		token["staff_id"] = 0

	from_tokens.remove_at(token_index)
	locks[from_employee] = from_tokens

	var to_tokens_val = locks.get(to_employee, null)
	var to_tokens: Array = []
	if to_tokens_val != null:
		if not (to_tokens_val is Array):
			return Result.failure("train_locks: to_employee tokens 类型错误（期望 Array）: %s" % to_employee)
		to_tokens = to_tokens_val
	to_tokens.append(token)
	locks[to_employee] = to_tokens

	# 写回
	var all_val = state.round_state.get(ROUND_STATE_KEY, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % ROUND_STATE_KEY)
	var all: Dictionary = all_val
	var key_check := _fail_on_string_player_key(all, player_id)
	if not key_check.ok:
		return key_check
	all[player_id] = locks
	state.round_state[ROUND_STATE_KEY] = all

	return Result.success()
