extends RefCounted

const StorageClass = preload("res://core/rules/employee_rules/train_slot_usage_storage.gd")
const ProvidersClass = preload("res://core/rules/employee_rules/train_slot_usage_providers.gd")

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

static func try_get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> Result:
	# 返回“当前还能对同一张员工卡在一次 Train 动作中提升的最大步数”。
	# - trainer: 1
	# - coach: 2
	# - guru: 3
	# - 若 coach/guru 已被消耗部分 slot，则相应下降。
	if state == null:
		return Result.failure("train_slot_usage: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage: round_state 类型错误（期望 Dictionary）")
	var providers_read := ProvidersClass.try_get_train_providers_for_working(state, player_id)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value
	var best := 0
	for p in providers:
		var emp_id: String = str(p.get("id", ""))
		var instances: int = int(p.get("instances", 0))
		var cap_per_instance: int = int(p.get("cap_per_instance", 0))
		if emp_id.is_empty() or instances <= 0 or cap_per_instance <= 0:
			continue
		var used_read := StorageClass.read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
		if not used_read.ok:
			return Result.failure("train_slot_usage_instances 结构损坏: %s" % used_read.error)
		var used_by_instance: Array[int] = used_read.value
		var max_one := 0
		for u in used_by_instance:
			var remaining := cap_per_instance - int(u)
			if remaining > max_one:
				max_one = remaining
		if max_one > best:
			best = max_one
	return Result.success(best)

static func get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> int:
	var read := try_get_max_train_steps_for_single_employee_for_working(state, player_id)
	if not read.ok:
		return 0
	return int(read.value)

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

	var providers_read := ProvidersClass.try_get_train_providers_for_working(state, player_id)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value
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
			var used_read := StorageClass.read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
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

		var used_read := StorageClass.read_used_slots_by_instance(state, player_id, emp_id, instances, cap_per_instance)
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

	var used_read := StorageClass.read_used_slots_by_instance(state, player_id, trainer_id, instances, cap_per_instance)
	if not used_read.ok:
		return used_read
	var used_by_instance: Array[int] = used_read.value
	while used_by_instance.size() < instances:
		used_by_instance.append(0)
	if instance_idx >= used_by_instance.size():
		return Result.failure("train_slot_usage_instances: instance_idx 越界: %s[%d]" % [trainer_id, instance_idx])
	used_by_instance[instance_idx] = int(used_by_instance[instance_idx]) + slots_needed
	var write := StorageClass.write_used_slots_by_instance(state, player_id, trainer_id, used_by_instance)
	if not write.ok:
		return write

	# 同步旧版总计数（用于兼容/调试）
	var inc := StorageClass.increment_used_slots_total(state, player_id, trainer_id, slots_needed)
	if not inc.ok:
		return inc

	return Result.success(info)
