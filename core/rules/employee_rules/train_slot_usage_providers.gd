extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CountsClass = preload("res://core/rules/employee_rules/counts.gd")

const TRAIN_USAGE_TAG := "use:train"

static func get_train_providers_for_working(state: GameState, player_id: int) -> Array[Dictionary]:
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
