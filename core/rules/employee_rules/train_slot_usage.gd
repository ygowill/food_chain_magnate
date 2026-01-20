extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CountsClass = preload("res://core/rules/employee_rules/counts.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const TRAIN_USAGE_TAG := "use:train"
const ROUND_STATE_KEY := "train_slot_usage"

static func reset_train_slot_usage(state: GameState) -> void:
	# 子阶段级别：与 action_counts 同步重置（避免跨子阶段残留导致误判）
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	state.round_state[ROUND_STATE_KEY] = {}

static func get_train_slot_usage_round_state_key() -> String:
	return ROUND_STATE_KEY

static func _read_used_slots(state: GameState, player_id: int, trainer_id: String) -> int:
	if trainer_id.is_empty():
		return 0
	if state == null or not (state.round_state is Dictionary):
		return 0
	var read := RoundStateCountersClass.get_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, trainer_id)
	assert(read.ok, "train_slot_usage 结构损坏: %s" % read.error)
	return int(read.value)

static func _compute_max_remaining_in_one_instance(instances: int, cap_per_instance: int, used_slots: int) -> int:
	if instances <= 0 or cap_per_instance <= 0:
		return 0
	var total := instances * cap_per_instance
	if used_slots <= 0:
		return cap_per_instance
	if used_slots >= total:
		return 0
	# 将已用 slot 尽量“集中”在少数实例上，保留至少一个完整实例以最大化后续多步培训的可能性。
	if used_slots <= cap_per_instance * (instances - 1):
		return cap_per_instance
	return total - used_slots

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
		var used_slots := _read_used_slots(state, player_id, emp_id)
		var max_one := _compute_max_remaining_in_one_instance(instances, cap_per_instance, used_slots)
		if max_one > best:
			best = max_one
	return best

static func allocate_train_slots_for_working(state: GameState, player_id: int, slots_needed: int) -> Result:
	if slots_needed <= 0:
		return Result.failure("allocate_train_slots_for_working: slots_needed 必须 > 0")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("allocate_train_slots_for_working: state/round_state 无效")

	var providers := _get_train_providers_for_working(state, player_id)
	if providers.is_empty():
		return Result.failure("没有可用的培训员")

	# 选择一个“承载本次培训”的培训员类型，并记录其已用 slot。
	for p in providers:
		var emp_id: String = str(p.get("id", ""))
		var instances: int = int(p.get("instances", 0))
		var cap_per_instance: int = int(p.get("cap_per_instance", 0))
		if emp_id.is_empty() or instances <= 0 or cap_per_instance <= 0:
			continue

		var total := instances * cap_per_instance
		var used_slots := _read_used_slots(state, player_id, emp_id)
		var remaining_total := total - used_slots
		if remaining_total <= 0:
			continue

		if slots_needed == 1:
			# 单步培训：只要该类型还有剩余 slot 即可（优先消耗 trainer，再到 coach/guru）
			var inc := RoundStateCountersClass.increment_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, emp_id, 1)
			if not inc.ok:
				return inc
			return Result.success({"trainer_id": emp_id, "slots": 1})

		# 多步培训：必须能由同一名培训员（同一实例）承担 slots_needed。
		if cap_per_instance < slots_needed:
			continue
		var max_one := _compute_max_remaining_in_one_instance(instances, cap_per_instance, used_slots)
		if max_one < slots_needed:
			continue

		var inc2 := RoundStateCountersClass.increment_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, emp_id, slots_needed)
		if not inc2.ok:
			return inc2
		return Result.success({"trainer_id": emp_id, "slots": slots_needed})

	return Result.failure("培训员 slot 不足（需要 %d）" % slots_needed)

