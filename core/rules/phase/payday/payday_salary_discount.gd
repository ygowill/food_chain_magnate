extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const EFFECT_SEG_PAYDAY_SALARY_DISCOUNT := ":payday:salary_discount:"

static func get_salary_discount_recruit_capacity(
	state: GameState,
	player_id: int,
	player: Dictionary,
	effect_registry
) -> Result:
	if state == null:
		return Result.failure("PaydaySalaryDiscount: state 为空")
	var employees_read := PlayerStateAccessClass.require_employees(player, "player", "PaydaySalaryDiscount")
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	if effect_registry == null:
		return Result.failure("PaydaySalaryDiscount: EffectRegistry 未设置")

	var warnings: Array[String] = []
	var ctx := {"salary_discount_recruit_capacity": 0}

	# Q3：折扣仅由“在岗员工”提供（reserve 不计入）
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("PaydaySalaryDiscount: employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("PaydaySalaryDiscount: employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("PaydaySalaryDiscount: 未知员工定义: %s" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("PaydaySalaryDiscount: 员工定义类型错误（期望 EmployeeDef）: %s" % emp_id)
		var def: EmployeeDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_PAYDAY_SALARY_DISCOUNT) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx, emp_id])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var cap_val = ctx.get("salary_discount_recruit_capacity", null)
	if not (cap_val is int):
		return Result.failure("PaydaySalaryDiscount: ctx.salary_discount_recruit_capacity 类型错误（期望 int）")
	return Result.success(int(cap_val)).with_warnings(warnings)
