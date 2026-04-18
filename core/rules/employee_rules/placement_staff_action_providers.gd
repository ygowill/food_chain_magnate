class_name PlacementStaffActionProviders
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

const TRACK_HOUSE_GARDEN := "place_house_or_garden"
const TRACK_RESTAURANT := "place_or_move_restaurant"

const ACTION_PLACE_HOUSE := "place_house"
const ACTION_ADD_GARDEN := "add_garden"
const ACTION_PLACE_RESTAURANT := "place_restaurant"
const ACTION_MOVE_RESTAURANT := "move_restaurant"

static func try_get_house_garden_placers_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_house_garden_placers_for_working: "
	return _try_get_active_staff_items_for_working(
		state,
		player_id,
		prefix,
		TRACK_HOUSE_GARDEN,
		Callable(PlacementStaffActionProviders, "_build_house_garden_provider")
	)

static func get_house_garden_placers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_house_garden_placers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_house_garden_placer(
	state: GameState,
	player_id: int,
	action_id: String,
	employee_type: String = "",
	explicit_staff_id: int = -1
) -> Result:
	var capability := _get_house_garden_capability(action_id)
	if capability.is_empty():
		return Result.failure("未知的房屋/花园动作: %s" % action_id)
	return _try_resolve_provider_for_working(
		state,
		player_id,
		employee_type,
		explicit_staff_id,
		capability,
		Callable(PlacementStaffActionProviders, "try_get_house_garden_placers_for_working"),
		"放置房屋/花园员工"
	)

static func try_get_restaurant_placers_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_restaurant_placers_for_working: "
	return _try_get_active_staff_items_for_working(
		state,
		player_id,
		prefix,
		TRACK_RESTAURANT,
		Callable(PlacementStaffActionProviders, "_build_restaurant_provider")
	)

static func get_restaurant_placers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_restaurant_placers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value

static func try_resolve_restaurant_placer(
	state: GameState,
	player_id: int,
	action_id: String,
	employee_type: String = "",
	explicit_staff_id: int = -1
) -> Result:
	var capability := _get_restaurant_capability(action_id)
	if capability.is_empty():
		return Result.failure("未知的餐厅动作: %s" % action_id)
	return _try_resolve_provider_for_working(
		state,
		player_id,
		employee_type,
		explicit_staff_id,
		capability,
		Callable(PlacementStaffActionProviders, "try_get_restaurant_placers_for_working"),
		"餐厅员工"
	)

static func _try_get_active_staff_items_for_working(
	state: GameState,
	player_id: int,
	prefix: String,
	track_id: String,
	builder: Callable
) -> Result:
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
		var employee_type := str(record.get("employee_type", "")).strip_edges()
		if employee_type.is_empty():
			return Result.failure("%splayer[%d].staff_registry[%d].employee_type 不能为空" % [prefix, player_id, staff_id])

		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val == null:
			return Result.failure("%s未知员工: %s" % [prefix, employee_type])
		if not (def_val is EmployeeDef):
			return Result.failure("%sEmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % [prefix, employee_type])
		var def: EmployeeDef = def_val

		var mult_read := WorkingMultiplierClass.try_get_working_employee_multiplier(state, player_id, employee_type)
		if not mult_read.ok:
			return mult_read
		var capacity := int(mult_read.value)
		if capacity <= 0:
			continue

		var used_read := StaffStateClass.get_staff_track_used(state, staff_id, track_id)
		if not used_read.ok:
			return used_read
		var used := int(used_read.value)

		var provider_val = builder.call(staff_id, employee_type, def, capacity, used)
		if not (provider_val is Dictionary):
			return Result.failure("%sprovider builder 返回值类型错误（期望 Dictionary）" % prefix)
		var provider: Dictionary = provider_val
		if provider.is_empty():
			continue
		out.append(provider)

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return Result.success(out)

static func _build_house_garden_provider(staff_id: int, employee_type: String, def: EmployeeDef, capacity: int, used: int) -> Dictionary:
	var can_place_house := def.has_usage_tag("use:place_house")
	var can_add_garden := def.has_usage_tag("use:add_garden")
	if not can_place_house and not can_add_garden:
		return {}
	return {
		"staff_id": staff_id,
		"id": employee_type,
		"employee_type": employee_type,
		"capacity": capacity,
		"used": used,
		"remaining": maxi(0, capacity - used),
		"can_place_house": can_place_house,
		"can_add_garden": can_add_garden,
	}

static func _build_restaurant_provider(staff_id: int, employee_type: String, def: EmployeeDef, capacity: int, used: int) -> Dictionary:
	var can_place_restaurant := def.has_usage_tag("use:place_restaurant")
	var can_move_restaurant := def.has_usage_tag("use:move_restaurant")
	if not can_place_restaurant and not can_move_restaurant:
		return {}
	return {
		"staff_id": staff_id,
		"id": employee_type,
		"employee_type": employee_type,
		"capacity": capacity,
		"used": used,
		"remaining": maxi(0, capacity - used),
		"can_place_restaurant": can_place_restaurant,
		"can_move_restaurant": can_move_restaurant,
	}

static func _get_house_garden_capability(action_id: String) -> String:
	match str(action_id).strip_edges():
		ACTION_PLACE_HOUSE:
			return "can_place_house"
		ACTION_ADD_GARDEN:
			return "can_add_garden"
		_:
			return ""

static func _get_restaurant_capability(action_id: String) -> String:
	match str(action_id).strip_edges():
		ACTION_PLACE_RESTAURANT:
			return "can_place_restaurant"
		ACTION_MOVE_RESTAURANT:
			return "can_move_restaurant"
		_:
			return ""

static func _try_resolve_provider_for_working(
	state: GameState,
	player_id: int,
	employee_type: String,
	explicit_staff_id: int,
	capability_key: String,
	getter: Callable,
	verb: String
) -> Result:
	var providers_read: Variant = getter.call(state, player_id)
	if not (providers_read is Result):
		return Result.failure("%s解析失败：provider getter 返回值类型错误" % verb)
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
			if not bool(provider.get(capability_key, false)):
				return Result.failure("staff_id=%d 不能执行当前动作" % explicit_staff_id)
			var actual_employee_type := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
			if not expected_employee_type.is_empty() and actual_employee_type != expected_employee_type:
				return Result.failure("staff_id=%d 与 employee_type=%s 不匹配（实际: %s）" % [explicit_staff_id, expected_employee_type, actual_employee_type])
			if int(provider.get("remaining", 0)) <= 0:
				return Result.failure("%s已用完: staff_id=%d" % [verb, explicit_staff_id])
			return Result.success(provider)
		return Result.failure("指定%s不可用: staff_id=%d" % [verb, explicit_staff_id])

	var matched_any := false
	var exhausted_any := false
	for provider_val2 in providers:
		if not (provider_val2 is Dictionary):
			continue
		var provider2: Dictionary = provider_val2
		if not bool(provider2.get(capability_key, false)):
			continue
		var actual_employee_type2 := str(provider2.get("employee_type", provider2.get("id", ""))).strip_edges()
		if not expected_employee_type.is_empty() and actual_employee_type2 != expected_employee_type:
			continue
		matched_any = true
		if int(provider2.get("remaining", 0)) <= 0:
			exhausted_any = true
			continue
		return Result.success(provider2)

	if exhausted_any:
		return Result.failure("%s已用完" % verb)
	if matched_any:
		return Result.failure("没有可用的%s" % verb)
	if not expected_employee_type.is_empty():
		return Result.failure("没有可用的%s: %s" % [verb, expected_employee_type])
	return Result.failure("没有可用的%s" % verb)
