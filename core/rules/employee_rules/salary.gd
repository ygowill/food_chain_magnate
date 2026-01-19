extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeArrayHelpers = preload("res://core/rules/employee_rules/employee_array_helpers.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func _milestone_def_has_effect_type(ms_def: MilestoneDefClass, effect_type: String) -> bool:
	for e_i in range(ms_def.effects.size()):
		var eff_val = ms_def.effects[e_i]
		assert(eff_val is Dictionary, "EmployeeRules.requires_salary: effects[%d] 类型错误（期望 Dictionary）" % e_i)
		var eff: Dictionary = eff_val
		assert(eff.has("type") and (eff["type"] is String), "EmployeeRules.requires_salary: effects[%d].type 缺失或类型错误（期望 String）" % e_i)
		if str(eff["type"]) == effect_type:
			return true
	return false

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
		var milestones := EmployeeArrayHelpers.require_string_array_field(player, "milestones", "player")
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and (def_val is EmployeeDef) and is_marketing_employee_def(def_val):
			for mid in milestones:
				var ms_def_val = MilestoneRegistryClass.get_def(mid)
				assert(ms_def_val != null, "EmployeeRules.requires_salary: 未知里程碑定义: %s" % mid)
				assert(ms_def_val is MilestoneDefClass, "EmployeeRules.requires_salary: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
				var ms_def: MilestoneDefClass = ms_def_val
				if _milestone_def_has_effect_type(ms_def, "marketing_no_salary"):
					return false

	return true

static func is_marketing_employee_def(def: EmployeeDef) -> bool:
	for t in def.usage_tags:
		var s: String = str(t)
		if s.begins_with("use:marketing:"):
			return true
	return false

static func count_paid_employees(player: Dictionary) -> int:
	var count := 0
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees := EmployeeArrayHelpers.require_string_array_field(player, key, "player")
		for emp_id in employees:
			if requires_salary(emp_id, player):
				count += 1
	return count
