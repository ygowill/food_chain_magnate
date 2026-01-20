extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CountsClass = preload("res://core/rules/employee_rules/counts.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const TRAIN_USAGE_TAG := "use:train"
const ROUND_STATE_KEY := "train_slot_usage"
const ROUND_STATE_KEY_INSTANCES := "train_slot_usage_instances"

static func reset_train_slot_usage(state: GameState) -> void:
	# 子阶段级别：与 action_counts 同步重置（避免跨子阶段残留导致误判）
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	state.round_state[ROUND_STATE_KEY] = {}
	state.round_state[ROUND_STATE_KEY_INSTANCES] = {}

static func get_train_slot_usage_round_state_key() -> String:
	return ROUND_STATE_KEY

static func _read_used_slots_total(state: GameState, player_id: int, trainer_id: String) -> int:
	if trainer_id.is_empty():
		return 0
	if state == null or not (state.round_state is Dictionary):
		return 0
	var read := RoundStateCountersClass.get_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, trainer_id)
	assert(read.ok, "train_slot_usage 结构损坏: %s" % read.error)
	return int(read.value)

static func _compute_used_by_instance_from_total(used_total: int, instances: int, cap_per_instance: int) -> Array[int]:
	# 兼容旧版（仅记录 trainer_id 总用量）：将用量尽量集中到少数实例上，得到一个确定的 per-instance 分配。
	var out: Array[int] = []
	if instances <= 0 or cap_per_instance <= 0:
		return out
	var remaining := maxi(0, used_total)
	for _i in range(instances):
		var take := mini(cap_per_instance, remaining)
		out.append(take)
		remaining -= take
	return out

static func _read_used_slots_by_instance(state: GameState, player_id: int, trainer_id: String, instances: int, cap_per_instance: int) -> Result:
	if trainer_id.is_empty():
		return Result.failure("trainer_id 不能为空")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage_instances: state/round_state 无效")
	if instances <= 0:
		return Result.success([])

	var all_val = state.round_state.get(ROUND_STATE_KEY_INSTANCES, null)
	if all_val != null:
		if not (all_val is Dictionary):
			return Result.failure("train_slot_usage_instances 类型错误（期望 Dictionary）")
		var all: Dictionary = all_val
		assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [ROUND_STATE_KEY_INSTANCES, str(player_id)])
		if all.has(player_id):
			var per_val = all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [ROUND_STATE_KEY_INSTANCES, player_id])
			var per: Dictionary = per_val
			if per.has(trainer_id):
				var arr_val = per.get(trainer_id, null)
				if not (arr_val is Array):
					return Result.failure("round_state.%s[%d].%s 类型错误（期望 Array[int]）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id])
				var arr_any: Array = arr_val
				var out: Array[int] = []
				for i in range(instances):
					var v := 0
					if i < arr_any.size():
						var item = arr_any[i]
						if item is int:
							v = int(item)
						elif item is float:
							var f: float = float(item)
							if f == int(f):
								v = int(f)
							else:
								return Result.failure("round_state.%s[%d].%s[%d] 类型错误（期望 int）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i])
						else:
							return Result.failure("round_state.%s[%d].%s[%d] 类型错误（期望 int）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i])
					if v < 0:
						return Result.failure("round_state.%s[%d].%s[%d] 不能为负数: %d" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i, v])
					out.append(v)
				return Result.success(out)

	# fallback：旧版 train_slot_usage（总用量）
	var used_total := _read_used_slots_total(state, player_id, trainer_id)
	var used_by_instance := _compute_used_by_instance_from_total(used_total, instances, cap_per_instance)
	return Result.success(used_by_instance)

static func _write_used_slots_by_instance(state: GameState, player_id: int, trainer_id: String, used_by_instance: Array[int]) -> Result:
	if trainer_id.is_empty():
		return Result.failure("trainer_id 不能为空")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage_instances: state/round_state 无效")

	if not state.round_state.has(ROUND_STATE_KEY_INSTANCES):
		state.round_state[ROUND_STATE_KEY_INSTANCES] = {}
	var all_val = state.round_state.get(ROUND_STATE_KEY_INSTANCES, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % ROUND_STATE_KEY_INSTANCES)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [ROUND_STATE_KEY_INSTANCES, str(player_id)])

	if not all.has(player_id):
		all[player_id] = {}
	var per_val = all.get(player_id, null)
	if not (per_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [ROUND_STATE_KEY_INSTANCES, player_id])
	var per: Dictionary = per_val

	per[trainer_id] = used_by_instance
	all[player_id] = per
	state.round_state[ROUND_STATE_KEY_INSTANCES] = all
	return Result.success()

static func _choose_instance_for_allocation(used_by_instance: Array[int], cap_per_instance: int, slots_needed: int) -> int:
	# 选择一个能承载 slots_needed 的实例；偏向“已用更多”的实例以集中消耗（保留完整实例用于后续多步培训）。
	var best_idx := -1
	var best_used := -1
	for i in range(used_by_instance.size()):
		var used_i := int(used_by_instance[i])
		var remaining := cap_per_instance - used_i
		if remaining < slots_needed:
			continue
		if used_i > best_used:
			best_used = used_i
			best_idx = i
	return best_idx

static func _get_train_providers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	assert(state != null, "get_train_providers_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_train_providers_for_working: player 不存在: %d" % player_id)
	assert(player.has("employees") and (player["employees"] is Array), "get_train_providers_for_working: player.employees 缺失或类型错误（期望 Array）")
	assert(EmployeeRegistryClass.is_loaded(), "get_train_providers_for_working: EmployeeRegistry 未初始化")

	var out: Array[Dictionary] = []
	var seen := {}
	for emp_val in Array(player["employees"]):
		if not (emp_val is String):
			continue
		var emp_id := str(emp_val)
		if emp_id.is_empty():
			continue
		if seen.has(emp_id):
			continue
		seen[emp_id] = true

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			continue
		assert(def_val is EmployeeDef, "get_train_providers_for_working: EmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val
		var cap_per_instance := int(def.train_capacity)
		if cap_per_instance <= 0:
			continue
		if not def.has_usage_tag(TRAIN_USAGE_TAG):
			continue

		var instances := CountsClass.count_active_for_working(state, player, player_id, emp_id)
		if instances <= 0:
			continue
		out.append({
			"id": emp_id,
			"instances": instances,
			"cap_per_instance": cap_per_instance
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := int(a.get("cap_per_instance", 0))
		var cb := int(b.get("cap_per_instance", 0))
		if ca != cb:
			return ca < cb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	return out

static func get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> int:
	# 返回“当前还能对同一张员工卡在一次 Train 动作中提升的最大步数”。
	# - trainer: 1
	# - coach: 2
	# - guru: 3
	# - 若 coach/guru 已被消耗部分 slot，则相应下降。
	if state == null:
		return 0
	if not (state.round_state is Dictionary):
		return 0
	var providers := _get_train_providers_for_working(state, player_id)
	var best := 0
	for p in providers:
		var emp_id: String = str(p.get("id", ""))
		var instances: int = int(p.get("instances", 0))
		var cap_per_instance: int = int(p.get("cap_per_instance", 0))
		if emp_id.is_empty() or instances <= 0 or cap_per_instance <= 0:
			continue
		var used_read := _read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
		if not used_read.ok:
			assert(false, "train_slot_usage_instances 结构损坏: %s" % used_read.error)
			continue
		var used_by_instance: Array[int] = used_read.value
		var max_one := 0
		for u in used_by_instance:
			var remaining := cap_per_instance - int(u)
			if remaining > max_one:
				max_one = remaining
		if max_one > best:
			best = max_one
	return best

static func can_allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	if slots_needed <= 0:
		return Result.failure("can_allocate_train_slots_for_working: slots_needed 必须 > 0")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("can_allocate_train_slots_for_working: state/round_state 无效")

	var providers := _get_train_providers_for_working(state, player_id)
	if providers.is_empty():
		return Result.failure("没有可用的培训员")

	# 指定培训员实例：用于“同一员工必须由同一名培训员继续培训”的规则。
	if not preferred_trainer_id.is_empty():
		for p in providers:
			var emp_id: String = str(p.get("id", ""))
			if emp_id != preferred_trainer_id:
				continue
			var instances: int = int(p.get("instances", 0))
			var cap_per_instance: int = int(p.get("cap_per_instance", 0))
			if instances <= 0 or cap_per_instance <= 0:
				break
			if preferred_instance_idx < 0 or preferred_instance_idx >= instances:
				return Result.failure("培训员实例越界: %s[%d]" % [preferred_trainer_id, preferred_instance_idx])
			if cap_per_instance < slots_needed:
				return Result.failure("培训员容量不足: %s（每实例 %d，需求 %d）" % [preferred_trainer_id, cap_per_instance, slots_needed])
			var used_read := _read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
			if not used_read.ok:
				return used_read
			var used_by_instance: Array[int] = used_read.value
			var remaining := cap_per_instance - int(used_by_instance[preferred_instance_idx])
			if remaining < slots_needed:
				return Result.failure("培训员 slot 不足: %s[%d]（剩余 %d，需求 %d）" % [preferred_trainer_id, preferred_instance_idx, remaining, slots_needed])
			return Result.success({
				"trainer_id": emp_id,
				"instance_idx": preferred_instance_idx,
				"slots": slots_needed,
				"instances": instances,
				"cap_per_instance": cap_per_instance,
			})
		return Result.failure("指定培训员不可用: %s" % preferred_trainer_id)

	# 未指定：选择一个“承载本次培训”的培训员类型/实例（优先消耗 trainer，再到 coach/guru）。
	for p in providers:
		var emp_id: String = str(p.get("id", ""))
		var instances: int = int(p.get("instances", 0))
		var cap_per_instance: int = int(p.get("cap_per_instance", 0))
		if emp_id.is_empty() or instances <= 0 or cap_per_instance <= 0:
			continue
		if cap_per_instance < slots_needed:
			continue

		var used_read := _read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
		if not used_read.ok:
			return used_read
		var used_by_instance: Array[int] = used_read.value

		var idx := _choose_instance_for_allocation(used_by_instance, cap_per_instance, slots_needed)
		if idx < 0:
			continue

		return Result.success({
			"trainer_id": emp_id,
			"instance_idx": idx,
			"slots": slots_needed,
			"instances": instances,
			"cap_per_instance": cap_per_instance,
		})

	return Result.failure("培训员 slot 不足（需要 %d）" % slots_needed)

static func allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	var plan := can_allocate_train_slots_for_working(state, player_id, slots_needed, preferred_trainer_id, preferred_instance_idx)
	if not plan.ok:
		return plan
	var info: Dictionary = plan.value
	var trainer_id: String = str(info.get("trainer_id", ""))
	var instance_idx: int = int(info.get("instance_idx", -1))
	var instances: int = int(info.get("instances", 0))
	var cap_per_instance: int = int(info.get("cap_per_instance", 0))
	if trainer_id.is_empty() or instance_idx < 0:
		return Result.failure("allocate_train_slots_for_working: plan 无效")

	var used_read := _read_used_slots_by_instance(state, player_id, trainer_id, instances, cap_per_instance)
	if not used_read.ok:
		return used_read
	var used_by_instance: Array[int] = used_read.value
	while used_by_instance.size() < instances:
		used_by_instance.append(0)
	if instance_idx >= used_by_instance.size():
		return Result.failure("train_slot_usage_instances: instance_idx 越界: %s[%d]" % [trainer_id, instance_idx])
	used_by_instance[instance_idx] = int(used_by_instance[instance_idx]) + slots_needed
	var write := _write_used_slots_by_instance(state, player_id, trainer_id, used_by_instance)
	if not write.ok:
		return write

	# 同步旧版总计数（用于兼容/调试）
	var inc := RoundStateCountersClass.increment_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, trainer_id, slots_needed)
	if not inc.ok:
		return inc

	return Result.success(info)
