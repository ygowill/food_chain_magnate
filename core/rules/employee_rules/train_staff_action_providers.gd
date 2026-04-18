extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const TrainSlotUsageStorageClass = preload("res://core/rules/employee_rules/train_slot_usage_storage.gd")
const TrainSlotUsageProvidersClass = preload("res://core/rules/employee_rules/train_slot_usage_providers.gd")

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

		var count := mini(ids.size(), used_by_instance.size())
		for i in range(count):
			var staff_id := int(ids[i])
			var used := int(used_by_instance[i])
			var remaining := maxi(0, cap_per_instance - used)
			out.append({
				"staff_id": staff_id,
				"id": employee_type,
				"employee_type": employee_type,
				"instance_idx": i,
				"cap_per_instance": cap_per_instance,
				"multiplier": 1,
				"capacity": cap_per_instance,
				"used": used,
				"remaining": remaining,
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
	var providers := get_trainers_for_working(state, player_id)
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
