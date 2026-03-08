extends RefCounted

const EconomyRulesClass = preload("res://core/rules/economy_rules.gd")
const EffectIdsSegmentInvokerClass = preload("res://core/rules/effect_ids_segment_invoker.gd")
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

		var employee_read := EconomyRulesClass.require_employee_def(emp_id, "PaydaySalaryDiscount: ")
		if not employee_read.ok:
			return employee_read
		var def: EmployeeDef = employee_read.value

		var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
			effect_registry,
			def.effect_ids,
			EFFECT_SEG_PAYDAY_SALARY_DISCOUNT,
			[state, player_id, ctx, emp_id],
			"PaydaySalaryDiscount",
			"EmployeeDef[%s].effect_ids" % emp_id
		)
		if not inv.ok:
			return inv
		warnings.append_array(inv.warnings)

	var cap_val = ctx.get("salary_discount_recruit_capacity", null)
	if not (cap_val is int):
		return Result.failure("PaydaySalaryDiscount: ctx.salary_discount_recruit_capacity 类型错误（期望 int）")
	return Result.success(int(cap_val)).with_warnings(warnings)
