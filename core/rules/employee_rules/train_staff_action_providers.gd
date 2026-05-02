extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const TrainSlotUsageStorageClass = preload("res://core/rules/employee_rules/train_slot_usage_storage.gd")
const TrainSlotUsageProvidersClass = preload("res://core/rules/employee_rules/train_slot_usage_providers.gd")

static func _choose_virtual_instance_for_slots(virtual_instances: Array[Dictionary], slots_needed: int) -> int:
	var best_idx := -1
	var best_used := -1
	var slots := maxi(1, slots_needed)
	for item_val in virtual_instances:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var instance_idx := int(item.get("instance_idx", -1))
		var used := int(item.get("used", 0))
		var remaining := int(item.get("remaining", 0))
		if instance_idx < 0 or remaining < slots:
			continue
		if used > best_used:
			best_used = used
			best_idx = instance_idx
	return best_idx

static func try_get_trainers_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_trainers_for_working: "
	if state == null:
		return Result.failure("%sstate 为空" % prefix)

	var sync_read := StaffStateClass.ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read

	var player_read := PlayerStateAccessClass.require_player(state, player_id, prefix)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value

	var active_ids_read := PlayerStateAccessClass.require_employees_staff_ids(player, "player[%d]" % player_id, prefix)
	if not active_ids_read.ok:
		return active_ids_read
	var active_ids: Array = active_ids_read.value

	var registry_read := PlayerStateAccessClass.require_staff_registry(player, "player[%d]" % player_id, prefix)
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var providers_read := TrainSlotUsageProvidersClass.try_get_train_providers_for_working(state, player_id)
	if not providers_read.ok:
		return providers_read
	var grouped: Array = providers_read.value

	var out: Array[Dictionary] = []
	for group_val in grouped:
		if not (group_val is Dictionary):
			continue
		var group: Dictionary = group_val
		var employee_type := str(group.get("id", "")).strip_edges()
		var instances := int(group.get("instances", 0))
		var cap_per_instance := int(group.get("cap_per_instance", 0))
		var multiplier := maxi(1, int(group.get("multiplier", 1)))
		if employee_type.is_empty() or instances <= 0 or cap_per_instance <= 0:
			continue

		var ids: Array[int] = []
		for staff_id_val in active_ids:
			var staff_id := int(staff_id_val)
			if staff_id <= 0 or not registry.has(staff_id):
				continue
			var record_val = registry.get(staff_id, null)
			if not (record_val is Dictionary):
				continue
			var record: Dictionary = record_val
			if str(record.get("employee_type", "")).strip_edges() != employee_type:
				continue
			ids.append(staff_id)
		ids.sort()

		if ids.is_empty():
			continue

		var used_read := TrainSlotUsageStorageClass.read_used_slots_by_instance(state, player_id, employee_type, instances, cap_per_instance)
		if not used_read.ok:
			return used_read
		var used_by_instance: Array[int] = used_read.value

		var count := mini(ids.size(), int(ceil(float(used_by_instance.size()) / float(multiplier))))
		for i in range(count):
			var staff_id := int(ids[i])
			var virtual_instances: Array[Dictionary] = []
			var instance_indices: Array[int] = []
			var used_total := 0
			var remaining_total := 0
			var max_step_remaining := 0
			for offset in range(multiplier):
				var instance_idx := i * multiplier + offset
				if instance_idx >= used_by_instance.size():
					break
				var used := int(used_by_instance[instance_idx])
				var remaining := maxi(0, cap_per_instance - used)
				instance_indices.append(instance_idx)
				virtual_instances.append({
					"instance_idx": instance_idx,
					"used": used,
					"remaining": remaining,
				})
				used_total += used
				remaining_total += remaining
				if remaining > max_step_remaining:
					max_step_remaining = remaining
			if virtual_instances.is_empty():
				continue
			var default_instance_idx := _choose_virtual_instance_for_slots(virtual_instances, 1)
			if default_instance_idx < 0:
				default_instance_idx = int(instance_indices[0])
			out.append({
				"staff_id": staff_id,
				"id": employee_type,
				"employee_type": employee_type,
				"instance_idx": default_instance_idx,
				"instance_indices": instance_indices,
				"virtual_instances": virtual_instances,
				"cap_per_instance": cap_per_instance,
				"multiplier": multiplier,
				"capacity": cap_per_instance * virtual_instances.size(),
				"used": used_total,
				"remaining": remaining_total,
				"max_step_remaining": max_step_remaining,
			})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return Result.success(out)

static func get_trainers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_trainers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_trainer_for_working(state: GameState, player_id: int, trainer_staff_id: int) -> Result:
	if trainer_staff_id <= 0:
		return Result.failure("trainer_staff_id 必须 > 0")
	var providers_read := try_get_trainers_for_working(state, player_id)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value
	for provider_val in providers:
		if not (provider_val is Dictionary):
			continue
		var provider: Dictionary = provider_val
		if int(provider.get("staff_id", -1)) != trainer_staff_id:
			continue
		if int(provider.get("remaining", 0)) <= 0:
			return Result.failure("培训员已用完: staff_id=%d" % trainer_staff_id)
		return Result.success(provider.duplicate(true))
	return Result.failure("指定培训员不可用: staff_id=%d" % trainer_staff_id)
