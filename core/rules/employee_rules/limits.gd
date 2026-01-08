extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")

static func get_recruit_limit(player: Dictionary) -> int:
	# 规则：招聘次数由员工数据驱动（use:recruit + recruit_capacity）。
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.recruit_capacity)
		if cap > 0:
			limit += cap
	return limit

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_recruit_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_recruit_limit_for_working: player 不存在: %d" % player_id)
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.recruit_capacity)
		if cap > 0:
			limit += cap * WorkingMultiplier.get_working_employee_multiplier(state, player_id, emp_id)
	return limit

static func get_train_limit(player: Dictionary) -> int:
	# 规则：训练次数由“培训能力”提供（避免硬编码仅 trainer）。
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.train_capacity)
		if cap > 0:
			limit += cap
	return limit

static func get_train_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_train_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_train_limit_for_working: player 不存在: %d" % player_id)
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.train_capacity)
		if cap > 0:
			limit += cap * WorkingMultiplier.get_working_employee_multiplier(state, player_id, emp_id)
	return limit

