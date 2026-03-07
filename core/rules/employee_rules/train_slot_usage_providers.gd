extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

const TRAIN_USAGE_TAG := "use:train"

static func try_get_train_providers_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_train_providers_for_working: "
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("%sEmployeeRegistry 未初始化" % prefix)
	var player_read := PlayerStateAccessClass.require_player(state, player_id, prefix)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, prefix)
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	var active_counts := {}
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("%splayer[%d].employees[%d] 类型错误（期望 String）" % [prefix, player_id, i])
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("%splayer[%d].employees[%d] 不应为空字符串" % [prefix, player_id, i])
		active_counts[emp_id] = int(active_counts.get(emp_id, 0)) + 1

	var out: Array[Dictionary] = []
	var seen := {}
	for emp_val in employees:
		var emp_id := str(emp_val)
		if seen.has(emp_id):
			continue
		seen[emp_id] = true

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			continue
		if not (def_val is EmployeeDef):
			return Result.failure("%sEmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % [prefix, emp_id])
		var def: EmployeeDef = def_val
		var cap_per_instance := int(def.train_capacity)
		if cap_per_instance <= 0:
			continue
		if not def.has_usage_tag(TRAIN_USAGE_TAG):
			continue

		var mult_read := WorkingMultiplierClass.try_get_working_employee_multiplier(state, player_id, emp_id)
		if not mult_read.ok:
			return mult_read
		var instances := int(active_counts.get(emp_id, 0)) * int(mult_read.value)
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

	return Result.success(out)

static func get_train_providers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
	var read := try_get_train_providers_for_working(state, player_id)
	if not read.ok:
		return []
	return read.value
