extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func requires_salary(employee_id: String, player: Dictionary = {}) -> bool:
	# 从 EmployeeRegistry 读取 salary 字段，并叠加里程碑效果。
	if employee_id.is_empty():
		return false

	var base_requires := EmployeeRegistryClass.check_requires_salary(employee_id)
	if not base_requires:
		return false

	# 持久效果：某些员工永久免薪（由里程碑 effects.type 设置到 player 上）
	var no_salary_val = player.get("no_salary_employee_ids", null)
	if no_salary_val is Array:
		var no_salary: Array = no_salary_val
		if no_salary.has(employee_id):
			return false

	# 里程碑效果：marketing_no_salary -> 营销员不再需要支付薪水（避免硬编码 first_billboard）
	var milestones_val = player.get("milestones", null)
	if milestones_val is Array:
		var milestones: Array = milestones_val
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and is_marketing_employee_def(def_val):
			for i in range(milestones.size()):
				var mid_val = milestones[i]
				assert(mid_val is String, "EmployeeRules.requires_salary: player.milestones[%d] 类型错误（期望 String）" % i)
				var mid: String = str(mid_val)
				assert(not mid.is_empty(), "EmployeeRules.requires_salary: player.milestones 不应包含空字符串")
				var ms_def_val = MilestoneRegistryClass.get_def(mid)
				assert(ms_def_val != null, "EmployeeRules.requires_salary: 未知里程碑定义: %s" % mid)
				assert(ms_def_val is MilestoneDefClass, "EmployeeRules.requires_salary: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
				var ms_def = ms_def_val

				for e_i in range(ms_def.effects.size()):
					var eff_val = ms_def.effects[e_i]
					assert(eff_val is Dictionary, "EmployeeRules.requires_salary: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
					var eff: Dictionary = eff_val
					assert(eff.has("type") and (eff["type"] is String), "EmployeeRules.requires_salary: %s.effects[%d].type 缺失或类型错误（期望 String）" % [mid, e_i])
					if str(eff["type"]) == "marketing_no_salary":
						return false

	return true

static func is_marketing_employee_def(def: EmployeeDef) -> bool:
	for t in def.usage_tags:
		var s: String = str(t)
		if s.begins_with("use:marketing:"):
			return true
	return false

static func count_paid_employees(player: Dictionary) -> int:
	assert(player.has("employees"), "player 缺少 employees")
	assert(player.has("reserve_employees"), "player 缺少 reserve_employees")
	assert(player.has("busy_marketers"), "player 缺少 busy_marketers")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	assert(player["reserve_employees"] is Array, "player.reserve_employees 类型错误（期望 Array）")
	assert(player["busy_marketers"] is Array, "player.busy_marketers 类型错误（期望 Array）")

	var active: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]
	var busy: Array = player["busy_marketers"]

	var count := 0
	for emp in active:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	for emp in reserve:
		assert(emp is String, "player.reserve_employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.reserve_employees 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	for emp in busy:
		assert(emp is String, "player.busy_marketers 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.busy_marketers 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	return count

