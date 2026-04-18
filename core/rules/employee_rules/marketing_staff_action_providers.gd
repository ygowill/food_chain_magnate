class_name MarketingStaffActionProviders
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

const TRACK_MARKETING := "initiate_marketing"

static func try_get_marketers_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_marketers_for_working: "
	if state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("%sEmployeeRegistry 未初始化" % prefix)

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

	var busy_ids_read := PlayerStateAccessClass.require_busy_staff_ids(player, "player[%d]" % player_id, prefix)
	if not busy_ids_read.ok:
		return busy_ids_read
	var busy_ids: Array = busy_ids_read.value

	var registry_read := PlayerStateAccessClass.require_staff_registry(player, "player[%d]" % player_id, prefix)
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var current_round_busy_staff_ids := _build_current_round_busy_staff_ids(state, player_id)
	var candidate_ids: Array[int] = []
	var seen := {}
	for staff_id_val in active_ids:
		var staff_id := int(staff_id_val)
		if staff_id <= 0 or seen.has(staff_id):
			continue
		seen[staff_id] = true
		candidate_ids.append(staff_id)
	for staff_id_val2 in busy_ids:
		var staff_id2 := int(staff_id_val2)
		if staff_id2 <= 0 or seen.has(staff_id2):
			continue
		if not current_round_busy_staff_ids.has(staff_id2):
			continue
		seen[staff_id2] = true
		candidate_ids.append(staff_id2)

	var out: Array[Dictionary] = []
	for staff_id in candidate_ids:
		if not registry.has(staff_id):
			return Result.failure("%splayer[%d].staff_registry 缺少 staff_id=%d" % [prefix, player_id, staff_id])
		var record_val = registry.get(staff_id, null)
		if not (record_val is Dictionary):
			return Result.failure("%splayer[%d].staff_registry[%d] 类型错误（期望 Dictionary）" % [prefix, player_id, staff_id])
		var record: Dictionary = record_val
		var employee_type := str(record.get("employee_type", "")).strip_edges()
		if employee_type.is_empty():
			return Result.failure("%splayer[%d].staff_registry[%d].employee_type 不能为空" % [prefix, player_id, staff_id])

		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val == null:
			return Result.failure("%s未知员工: %s" % [prefix, employee_type])
		if not (def_val is EmployeeDef):
			return Result.failure("%sEmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % [prefix, employee_type])
		var def: EmployeeDef = def_val

		var marketing_types := _extract_marketing_types(def)
		if marketing_types.is_empty():
			continue
		var max_duration := int(def.marketing_max_duration)
		if max_duration <= 0:
			continue

		var mult_read := WorkingMultiplierClass.try_get_working_employee_multiplier(state, player_id, employee_type)
		if not mult_read.ok:
			return mult_read
		var capacity := int(mult_read.value)
		if capacity <= 0:
			continue

		var used_read := StaffStateClass.get_staff_track_used(state, staff_id, TRACK_MARKETING)
		if not used_read.ok:
			return used_read
		var used := int(used_read.value)
		var zone_read := StaffStateClass.get_staff_zone(state, player_id, staff_id)
		if not zone_read.ok:
			return zone_read
		var zone_key := str(zone_read.value).strip_edges()

		out.append({
			"staff_id": staff_id,
			"id": employee_type,
			"employee_type": employee_type,
			"marketing_types": marketing_types,
			"max_duration": max_duration,
			"capacity": capacity,
			"used": used,
			"remaining": maxi(0, capacity - used),
			"zone_key": zone_key,
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return Result.success(out)

static func get_marketers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_marketers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_marketer(
	state: GameState,
	player_id: int,
	employee_type: String = "",
	explicit_staff_id: int = -1
) -> Result:
	var providers_read := try_get_marketers_for_working(state, player_id)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value
	var expected_employee_type := str(employee_type).strip_edges()

	if explicit_staff_id > 0:
		for provider_val in providers:
			if not (provider_val is Dictionary):
				continue
			var provider: Dictionary = provider_val
			if int(provider.get("staff_id", -1)) != explicit_staff_id:
				continue
			var actual_employee_type := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
			if not expected_employee_type.is_empty() and actual_employee_type != expected_employee_type:
				return Result.failure("staff_id=%d 与 employee_type=%s 不匹配（实际: %s）" % [explicit_staff_id, expected_employee_type, actual_employee_type])
			if int(provider.get("remaining", 0)) <= 0:
				return Result.failure("该营销员工本子阶段已用完: staff_id=%d" % explicit_staff_id)
			return Result.success(provider)
		return Result.failure("指定营销员工不可用: staff_id=%d" % explicit_staff_id)

	var matched_any := false
	var exhausted_any := false
	for provider_val2 in providers:
		if not (provider_val2 is Dictionary):
			continue
		var provider2: Dictionary = provider_val2
		var actual_employee_type2 := str(provider2.get("employee_type", provider2.get("id", ""))).strip_edges()
		if not expected_employee_type.is_empty() and actual_employee_type2 != expected_employee_type:
			continue
		matched_any = true
		if int(provider2.get("remaining", 0)) <= 0:
			exhausted_any = true
			continue
		return Result.success(provider2)

	if exhausted_any:
		return Result.failure("营销员工本子阶段已用完")
	if matched_any:
		return Result.failure("没有可用的营销员工")
	if not expected_employee_type.is_empty():
		return Result.failure("没有可用的营销员工: %s" % expected_employee_type)
	return Result.failure("没有可用的营销员工")

static func _extract_marketing_types(def: EmployeeDef) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	if def == null or not (def.usage_tags is Array):
		return out
	for tag_val in def.usage_tags:
		var tag := str(tag_val).strip_edges()
		if not tag.begins_with("use:marketing:"):
			continue
		var type_id := tag.substr("use:marketing:".length())
		if type_id.is_empty() or seen.has(type_id):
			continue
		seen[type_id] = true
		out.append(type_id)
	out.sort()
	return out

static func _build_current_round_busy_staff_ids(state: GameState, player_id: int) -> Dictionary:
	var out := {}
	if state == null or not (state.marketing_instances is Array):
		return out
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != player_id:
			continue
		if int(inst.get("created_round", -1)) != int(state.round_number):
			continue
		var staff_id := int(inst.get("staff_id", -1))
		if staff_id > 0:
			out[staff_id] = true
	return out
