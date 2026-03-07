extends RefCounted

const EmployeeArrayHelpers = preload("res://core/rules/employee_rules/employee_array_helpers.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")

static func _get_limit_from_player(
	state: GameState,
	player_id: int,
	player: Dictionary,
	capacity_getter: Callable,
	include_working_multiplier: bool
) -> int:
	var employees := EmployeeArrayHelpers.require_string_array_field(player, "employees", "player")

	var limit := 0
	for emp_id in employees:
		var def := EmployeeArrayHelpers.require_employee_def(emp_id)
		var cap := int(capacity_getter.call(def))
		if cap <= 0:
			continue
		var m := 1
		if include_working_multiplier:
			m = WorkingMultiplier.get_working_employee_multiplier(state, player_id, emp_id)
		limit += cap * m
	return limit

static func _try_get_limit_from_player(
	state: GameState,
	player_id: int,
	player: Dictionary,
	capacity_getter: Callable,
	include_working_multiplier: bool,
	prefix: String
) -> Result:
	if include_working_multiplier and state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("%sEmployeeRegistry 未初始化" % prefix)

	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, prefix)
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	var limit := 0
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("%splayer[%d].employees[%d] 类型错误（期望 String）" % [prefix, player_id, i])
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("%splayer[%d].employees[%d] 不应为空字符串" % [prefix, player_id, i])
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("%s未知员工: %s" % [prefix, emp_id])
		if not (def_val is EmployeeDef):
			return Result.failure("%sEmployeeRegistry[%s] 类型错误（期望 EmployeeDef）" % [prefix, emp_id])
		var def: EmployeeDef = def_val
		var cap := int(capacity_getter.call(def))
		if cap <= 0:
			continue
		var m := 1
		if include_working_multiplier:
			var mult_read := WorkingMultiplier.try_get_working_employee_multiplier(state, player_id, emp_id)
			if not mult_read.ok:
				return mult_read
			m = int(mult_read.value)
		limit += cap * m
	return Result.success(limit)

static func get_recruit_limit(player: Dictionary) -> int:
	# 规则：招聘次数由员工数据驱动（use:recruit + recruit_capacity）。
	return _get_limit_from_player(null, -1, player, func(def: EmployeeDef) -> int: return int(def.recruit_capacity), false)

static func try_get_recruit_limit_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_recruit_limit_for_working: "
	var player_read := PlayerStateAccessClass.require_player(state, player_id, prefix)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return _try_get_limit_from_player(state, player_id, player, func(def: EmployeeDef) -> int: return int(def.recruit_capacity), true, prefix)

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	var read := try_get_recruit_limit_for_working(state, player_id)
	if not read.ok:
		return 0
	return int(read.value)

static func get_train_limit(player: Dictionary) -> int:
	# 规则：训练次数由“培训能力”提供（避免硬编码仅 trainer）。
	return _get_limit_from_player(null, -1, player, func(def: EmployeeDef) -> int: return int(def.train_capacity), false)

static func try_get_train_limit_for_working(state: GameState, player_id: int) -> Result:
	var prefix := "get_train_limit_for_working: "
	var player_read := PlayerStateAccessClass.require_player(state, player_id, prefix)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return _try_get_limit_from_player(state, player_id, player, func(def: EmployeeDef) -> int: return int(def.train_capacity), true, prefix)

static func get_train_limit_for_working(state: GameState, player_id: int) -> int:
	var read := try_get_train_limit_for_working(state, player_id)
	if not read.ok:
		return 0
	return int(read.value)
