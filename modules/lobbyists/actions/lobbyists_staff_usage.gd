extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

const EMPLOYEE_LOBBYIST := "lobbyist"
const USAGE_TAG_LOBBYISTS := "use:lobbyists"
const TRACK_LOBBYISTS := "lobbyists"

static func try_get_lobbyists_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "LobbyistsStaffUsage.try_get_lobbyists_for_working: "
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
		if not def.has_usage_tag(USAGE_TAG_LOBBYISTS):
			continue

		var mult_read := WorkingMultiplierClass.try_get_working_employee_multiplier(state, player_id, employee_type)
		if not mult_read.ok:
			return mult_read
		var capacity := int(mult_read.value)
		if capacity <= 0:
			continue

		var used_read := StaffStateClass.get_staff_track_used(state, staff_id, TRACK_LOBBYISTS)
		if not used_read.ok:
			return used_read
		var used := int(used_read.value)

		out.append({
			"staff_id": staff_id,
			"id": employee_type,
			"employee_type": employee_type,
			"capacity": capacity,
			"used": used,
			"remaining": maxi(0, capacity - used),
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return Result.success(out)

static func resolve_lobbyist_for_working(state: GameState, player_id: int, explicit_staff_id: int = -1) -> Result:
	var providers_read := try_get_lobbyists_for_working(state, player_id)
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
			if int(provider.get("remaining", 0)) <= 0:
				return Result.failure("指定说客本子阶段已用完: staff_id=%d" % explicit_staff_id)
			return Result.success(provider)
		return Result.failure("指定说客不可用: staff_id=%d" % explicit_staff_id)

	for provider_val2 in providers:
		if not (provider_val2 is Dictionary):
			continue
		var provider2: Dictionary = provider_val2
		if int(provider2.get("remaining", 0)) <= 0:
			continue
		return Result.success(provider2)

	if providers.is_empty():
		return Result.failure("需要在岗的说客才能放置道路/公园")
	return Result.failure("本子阶段可用说客次数已用完")

static func increment_lobbyist_usage(state: GameState, staff_id: int) -> Result:
	return StaffStateClass.increment_staff_track_usage(state, staff_id, TRACK_LOBBYISTS, 1)

static func infer_consumed_lobbyist_staff_id(
	old_state: GameState,
	new_state: GameState,
	player_id: int,
	explicit_staff_id: int = -1
) -> int:
	if explicit_staff_id > 0:
		return explicit_staff_id
	if old_state == null or new_state == null:
		return -1
	var ids_read := StaffStateClass.find_staff_ids_by_employee_type(new_state, player_id, EMPLOYEE_LOBBYIST, [StaffStateClass.ZONE_ACTIVE])
	if not ids_read.ok:
		return -1
	for staff_id_val in Array(ids_read.value):
		var staff_id := int(staff_id_val)
		if staff_id <= 0:
			continue
		var old_used_read := StaffStateClass.get_staff_track_used(old_state, staff_id, TRACK_LOBBYISTS)
		var new_used_read := StaffStateClass.get_staff_track_used(new_state, staff_id, TRACK_LOBBYISTS)
		if not old_used_read.ok or not new_used_read.ok:
			continue
		if int(new_used_read.value) > int(old_used_read.value):
			return staff_id
	return -1
