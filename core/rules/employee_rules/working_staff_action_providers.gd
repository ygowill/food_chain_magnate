class_name WorkingStaffActionProviders
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

const TRACK_PRODUCE_FOOD := "produce_food"
const TRACK_PROCURE_DRINKS := "procure_drinks"

static func try_get_food_producers_for_working(state: GameState, player_id: int) -> Result:
	return _try_get_action_providers_for_working(state, player_id, TRACK_PRODUCE_FOOD, "food")

static func get_food_producers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_food_producers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_food_producer(state: GameState, player_id: int, employee_type: String, explicit_staff_id: int = -1) -> Result:
	return _try_resolve_provider_for_working(
		state,
		player_id,
		employee_type,
		explicit_staff_id,
		Callable(WorkingStaffActionProviders, "try_get_food_producers_for_working"),
		"生产"
	)

static func try_get_drinks_procurers_for_working(state: GameState, player_id: int) -> Result:
	return _try_get_action_providers_for_working(state, player_id, TRACK_PROCURE_DRINKS, "drinks")

static func get_drinks_procurers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_drinks_procurers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_drinks_procurer(state: GameState, player_id: int, employee_type: String, explicit_staff_id: int = -1) -> Result:
	return _try_resolve_provider_for_working(
		state,
		player_id,
		employee_type,
		explicit_staff_id,
		Callable(WorkingStaffActionProviders, "try_get_drinks_procurers_for_working"),
		"采购"
	)

static func _try_get_action_providers_for_working(state: GameState, player_id: int, track_id: String, action_kind: String) -> Result:
	var prefix := "get_%s_providers_for_working: " % action_kind
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

	var registry_read := PlayerStateAccessClass.require_staff_registry(player, "player[%d]" % player_id, prefix)
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var out: Array[Dictionary] = []
	for i in range(active_ids.size()):
		var staff_id := int(active_ids[i])
		if staff_id <= 0:
			return Result.failure("%splayer[%d].employees_staff_ids[%d] 必须为正整数" % [prefix, player_id, i])
		if not registry.has(staff_id):
			return Result.failure("%splayer[%d].staff_registry 缺少 staff_id=%d" % [prefix, player_id, staff_id])
		var record_val = registry.get(staff_id, null)
		if not (record_val is Dictionary):
			return Result.failure("%splayer[%d].staff_registry[%d] 类型错误（期望 Dictionary）" % [prefix, player_id, staff_id])
		var record: Dictionary = record_val
		var emp_id := str(record.get("employee_type", "")).strip_edges()
		if emp_id.is_empty():
			return Result.failure("%splayer[%d].staff_registry[%d].employee_type 不能为空" % [prefix, player_id, staff_id])

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("%s未知员工: %s" % [prefix, emp_id])
		if not (def_val is EmployeeDef):
			return Result.failure("%sEmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % [prefix, emp_id])
		var def: EmployeeDef = def_val

		var supports_action := false
		match action_kind:
			"food":
				supports_action = def.can_produce()
			"drinks":
				supports_action = def.can_procure()
			_:
				supports_action = false
		if not supports_action:
			continue

		var mult_read := WorkingMultiplierClass.try_get_working_employee_multiplier(state, player_id, emp_id)
		if not mult_read.ok:
			return mult_read
		var capacity := int(mult_read.value)
		if capacity <= 0:
			continue

		var used_read := StaffStateClass.get_staff_track_used(state, staff_id, track_id)
		if not used_read.ok:
			return used_read
		var used := int(used_read.value)

		out.append({
			"staff_id": staff_id,
			"id": emp_id,
			"employee_type": emp_id,
			"capacity": capacity,
			"used": used,
			"remaining": maxi(0, capacity - used),
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return Result.success(out)

static func _try_resolve_provider_for_working(
	state: GameState,
	player_id: int,
	employee_type: String,
	explicit_staff_id: int,
	getter: Callable,
	verb: String
) -> Result:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return Result.failure("%s员工不能为空" % verb)

	var providers_read: Variant = getter.call(state, player_id)
	if not (providers_read is Result):
		return Result.failure("%s员工解析失败：provider getter 返回值类型错误" % verb)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value

	if explicit_staff_id > 0:
		for provider_val in providers:
			if not (provider_val is Dictionary):
				continue
			var provider: Dictionary = provider_val
			if int(provider.get("staff_id", -1)) != explicit_staff_id:
				continue
			var actual_emp_id := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
			if actual_emp_id != emp_id:
				return Result.failure("staff_id=%d 与 employee_type=%s 不匹配（实际: %s）" % [explicit_staff_id, emp_id, actual_emp_id])
			if int(provider.get("remaining", 0)) <= 0:
				return Result.failure("该员工本子阶段已用完: staff_id=%d" % explicit_staff_id)
			return Result.success(provider)
		return Result.failure("指定%s员工不可用: staff_id=%d" % [verb, explicit_staff_id])

	for provider_val2 in providers:
		if not (provider_val2 is Dictionary):
			continue
		var provider2: Dictionary = provider_val2
		if str(provider2.get("employee_type", provider2.get("id", ""))).strip_edges() != emp_id:
			continue
		if int(provider2.get("remaining", 0)) <= 0:
			continue
		return Result.success(provider2)

	return Result.failure("没有可用的%s员工: %s" % [verb, emp_id])
