# 公司结构规则（Fail Fast）
# 负责：计算公司结构卡槽占用/空位，并在需要时将超出容量的员工移回预备区。
class_name CompanyStructureRules
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func get_empty_slots(player: Dictionary) -> int:
	var usage := _compute_usage(player)
	assert(usage.manager_count <= usage.ceo_slots, "CompanyStructureRules.get_empty_slots: 经理数量超过 CEO 卡槽 (%d/%d)" % [usage.manager_count, usage.ceo_slots])
	assert(usage.used_slots <= usage.total_slots, "CompanyStructureRules.get_empty_slots: 公司结构已超载 (%d/%d)" % [usage.used_slots, usage.total_slots])
	return usage.total_slots - usage.used_slots

static func enforce_capacity(player: Dictionary) -> void:
	assert(player.has("employees") and (player["employees"] is Array), "CompanyStructureRules.enforce_capacity: player.employees 缺失或类型错误（期望 Array[String]）")
	assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "CompanyStructureRules.enforce_capacity: player.reserve_employees 缺失或类型错误（期望 Array[String]）")
	assert(player.has("company_structure") and (player["company_structure"] is Dictionary), "CompanyStructureRules.enforce_capacity: player.company_structure 缺失或类型错误（期望 Dictionary）")

	var employees: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]

	_validate_employee_list(employees, "player.employees")
	_validate_employee_list(reserve, "player.reserve_employees")
	assert(employees.has("ceo"), "CompanyStructureRules.enforce_capacity: player.employees 必须包含 CEO")

	var safety := 0
	while true:
		safety += 1
		assert(safety < 256, "CompanyStructureRules.enforce_capacity: 超出安全循环上限（可能存在无效员工/结构）")

		var usage := _compute_usage_with_employees(player, employees)
		if usage.manager_count <= usage.ceo_slots and usage.used_slots <= usage.total_slots:
			break

		var idx := _pick_employee_to_reserve(employees, usage.ceo_slots, usage.manager_count)
		assert(idx >= 0, "CompanyStructureRules.enforce_capacity: 无法选择可移动的员工（ceo_slots=%d, manager_count=%d, employees=%s）" % [usage.ceo_slots, usage.manager_count, str(employees)])
		var emp_id: String = employees[idx]
		employees.remove_at(idx)
		reserve.append(emp_id)

	player["employees"] = employees
	player["reserve_employees"] = reserve

static func _compute_usage(player: Dictionary) -> Dictionary:
	assert(player.has("employees") and (player["employees"] is Array), "CompanyStructureRules: player.employees 缺失或类型错误（期望 Array[String]）")
	var employees: Array = player["employees"]
	return _compute_usage_with_employees(player, employees)

static func _compute_usage_with_employees(player: Dictionary, employees: Array) -> Dictionary:
	assert(player.has("company_structure") and (player["company_structure"] is Dictionary), "CompanyStructureRules: player.company_structure 缺失或类型错误（期望 Dictionary）")
	var company_structure: Dictionary = player["company_structure"]
	assert(company_structure.has("ceo_slots"), "CompanyStructureRules: player.company_structure.ceo_slots 缺失")
	var ceo_slots: int = _require_non_negative_int(company_structure["ceo_slots"], "player.company_structure.ceo_slots")

	var used_slots := 0
	var manager_count := 0
	var manager_slots_total := 0

	for i in range(employees.size()):
		var emp_val = employees[i]
		assert(emp_val is String, "CompanyStructureRules: player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = emp_val
		assert(not emp_id.is_empty(), "CompanyStructureRules: player.employees[%d] 不应为空字符串" % i)
		if emp_id == "ceo":
			continue

		used_slots += 1
		var def = EmployeeRegistryClass.get_def(emp_id)
		assert(def != null, "CompanyStructureRules: 未知的员工类型: %s" % emp_id)
		var slots := maxi(0, int(def.manager_slots))
		if slots > 0:
			manager_count += 1
			manager_slots_total += slots

	var total_slots := ceo_slots + manager_slots_total
	return {
		"ceo_slots": ceo_slots,
		"used_slots": used_slots,
		"manager_count": manager_count,
		"manager_slots_total": manager_slots_total,
		"total_slots": total_slots,
	}

static func _pick_employee_to_reserve(employees: Array, ceo_slots: int, manager_count: int) -> int:
	# 1) 先处理“经理数量不能超过 CEO 卡槽”
	if manager_count > ceo_slots:
		for i in range(employees.size() - 1, -1, -1):
			var emp_id: String = employees[i]
			if emp_id == "ceo":
				continue
			var def = EmployeeRegistryClass.get_def(emp_id)
			assert(def != null, "CompanyStructureRules: 未知的员工类型: %s" % emp_id)
			if maxi(0, int(def.manager_slots)) > 0:
				return i
		return -1

	# 2) 再处理“总卡槽不足”：优先把非经理移回预备区，避免减少总卡槽。
	for i in range(employees.size() - 1, -1, -1):
		var emp_id2: String = employees[i]
		if emp_id2 == "ceo":
			continue
		var def2 = EmployeeRegistryClass.get_def(emp_id2)
		assert(def2 != null, "CompanyStructureRules: 未知的员工类型: %s" % emp_id2)
		if maxi(0, int(def2.manager_slots)) <= 0:
			return i

	# 3) 若全是经理，只能移除经理（会连带减少总卡槽，循环会继续收敛）。
	for i in range(employees.size() - 1, -1, -1):
		var emp_id3: String = employees[i]
		if emp_id3 == "ceo":
			continue
		return i

	return -1

static func _validate_employee_list(list: Array, path: String) -> void:
	for i in range(list.size()):
		var v = list[i]
		assert(v is String, "%s[%d] 类型错误（期望 String）" % [path, i])
		assert(not String(v).is_empty(), "%s[%d] 不应为空字符串" % [path, i])

static func _require_non_negative_int(value, path: String) -> int:
	var v := _require_int(value, path)
	assert(v >= 0, "%s 不能为负数: %d" % [path, v])
	return v

static func _require_int(value, path: String) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		assert(f == floor(f), "%s 必须为整数，实际: %s" % [path, str(value)])
		return int(f)
	assert(false, "%s 类型错误（期望 int）" % path)
	return 0

