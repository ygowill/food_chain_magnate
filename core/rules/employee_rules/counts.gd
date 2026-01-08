extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")

static func is_entry_level(employee_id: String) -> bool:
	if employee_id.is_empty():
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return false
	if not (def_val is EmployeeDef):
		assert(false, "EmployeeRules.is_entry_level: EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		return false
	var def: EmployeeDef = def_val
	return def.is_entry_level()

static func count_active(player: Dictionary, employee_id: String) -> int:
	assert(not employee_id.is_empty(), "employee_id 不能为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")
		if emp_id == employee_id:
			count += 1
	return count

static func count_active_by_usage_tag(player: Dictionary, usage_tag: String) -> int:
	assert(not usage_tag.is_empty(), "usage_tag 不能为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def = EmployeeRegistryClass.get_def(emp_id)
		assert(def != null, "未知员工: %s" % emp_id)
		if def.has_usage_tag(usage_tag):
			count += 1

	return count

static func count_active_for_working(state: GameState, player: Dictionary, player_id: int, employee_id: String) -> int:
	var base := count_active(player, employee_id)
	var multiplier := WorkingMultiplier.get_working_employee_multiplier(state, player_id, employee_id)
	return base * multiplier

static func count_active_by_usage_tag_for_working(state: GameState, player: Dictionary, player_id: int, usage_tag: String) -> int:
	assert(not usage_tag.is_empty(), "usage_tag 不能为空")
	assert(state != null, "count_active_by_usage_tag_for_working: state 为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def = EmployeeRegistryClass.get_def(emp_id)
		assert(def != null, "未知员工: %s" % emp_id)
		if def.has_usage_tag(usage_tag):
			count += WorkingMultiplier.get_working_employee_multiplier(state, player_id, emp_id)

	return count

