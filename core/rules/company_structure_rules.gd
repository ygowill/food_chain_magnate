# 公司结构规则（Fail Fast）
# 负责：计算公司结构卡槽占用/空位，并在需要时将超出容量的员工移回预备区。
class_name CompanyStructureRules
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func get_empty_slots(player: Dictionary) -> Result:
	var usage_read := _compute_usage(player)
	if not usage_read.ok:
		return usage_read

	var usage: Dictionary = usage_read.value
	var manager_count: int = int(usage.get("manager_count", 0))
	var ceo_slots: int = int(usage.get("ceo_slots", 0))
	var used_slots: int = int(usage.get("used_slots", 0))
	var total_slots: int = int(usage.get("total_slots", 0))
	if manager_count > ceo_slots:
		return Result.failure("CompanyStructureRules.get_empty_slots: 经理数量超过 CEO 卡槽 (%d/%d)" % [manager_count, ceo_slots])
	if used_slots > total_slots:
		return Result.failure("CompanyStructureRules.get_empty_slots: 公司结构已超载 (%d/%d)" % [used_slots, total_slots])
	return Result.success(total_slots - used_slots)

static func enforce_capacity(player: Dictionary) -> Result:
	var employees_read := PlayerStateAccessClass.require_employees(player, "player", "CompanyStructureRules.enforce_capacity")
	if not employees_read.ok:
		return employees_read
	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "CompanyStructureRules.enforce_capacity")
	if not reserve_read.ok:
		return reserve_read
	var company_structure_read := PlayerStateAccessClass.require_company_structure(player, "player", "CompanyStructureRules.enforce_capacity")
	if not company_structure_read.ok:
		return company_structure_read

	var employees_in: Array = employees_read.value
	var reserve_in: Array = reserve_read.value
	var employees: Array = employees_in.duplicate()
	var reserve: Array = reserve_in.duplicate()

	var v1 := _validate_employee_list(employees, "player.employees")
	if not v1.ok:
		return v1
	var v2 := _validate_employee_list(reserve, "player.reserve_employees")
	if not v2.ok:
		return v2
	if not employees.has("ceo"):
		return Result.failure("CompanyStructureRules.enforce_capacity: player.employees 必须包含 CEO")

	var safety := 0
	while true:
		safety += 1
		if safety >= 256:
			return Result.failure("CompanyStructureRules.enforce_capacity: 超出安全循环上限（可能存在无效员工/结构）")

		var usage_read := _compute_usage_with_employees(player, employees)
		if not usage_read.ok:
			return usage_read
		var usage: Dictionary = usage_read.value

		var ceo_slots: int = int(usage.get("ceo_slots", 0))
		var manager_count: int = int(usage.get("manager_count", 0))
		var used_slots: int = int(usage.get("used_slots", 0))
		var total_slots: int = int(usage.get("total_slots", 0))
		if manager_count <= ceo_slots and used_slots <= total_slots:
			break

		var idx_read := _pick_employee_to_reserve(employees, ceo_slots, manager_count)
		if not idx_read.ok:
			return idx_read
		var idx: int = int(idx_read.value)
		if idx < 0:
			return Result.failure("CompanyStructureRules.enforce_capacity: 无法选择可移动的员工（ceo_slots=%d, manager_count=%d, employees=%s）" % [
				ceo_slots,
				manager_count,
				str(employees),
			])

		var emp_id: String = str(employees[idx])
		employees.remove_at(idx)
		reserve.append(emp_id)

	player["employees"] = employees
	player["reserve_employees"] = reserve
	return Result.success()

static func _compute_usage(player: Dictionary) -> Result:
	var employees_read := PlayerStateAccessClass.require_employees(player, "player", "CompanyStructureRules")
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value
	return _compute_usage_with_employees(player, employees)

static func _compute_usage_with_employees(player: Dictionary, employees: Array) -> Result:
	var company_structure_read := PlayerStateAccessClass.require_company_structure(player, "player", "CompanyStructureRules")
	if not company_structure_read.ok:
		return company_structure_read
	var company_structure: Dictionary = company_structure_read.value

	var ceo_slots_read := IntValueParseHelpersClass.parse_non_negative_int_value(
		company_structure.get("ceo_slots", null),
		"player.company_structure.ceo_slots"
	)
	if not ceo_slots_read.ok:
		return Result.failure("CompanyStructureRules: %s" % str(ceo_slots_read.error))
	var ceo_slots: int = int(ceo_slots_read.value)

	var used_slots := 0
	var manager_count := 0
	var manager_slots_total := 0

	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("CompanyStructureRules: employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("CompanyStructureRules: employees[%d] 不应为空字符串" % i)
		if emp_id == "ceo":
			continue

		used_slots += 1
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("CompanyStructureRules: 未知的员工类型: %s" % emp_id)
		var slots := maxi(0, int(def_val.manager_slots))
		if slots > 0:
			manager_count += 1
			manager_slots_total += slots

	var total_slots := ceo_slots + manager_slots_total
	return Result.success({
		"ceo_slots": ceo_slots,
		"used_slots": used_slots,
		"manager_count": manager_count,
		"manager_slots_total": manager_slots_total,
		"total_slots": total_slots,
	})

static func _pick_employee_to_reserve(employees: Array, ceo_slots: int, manager_count: int) -> Result:
	# 1) 先处理“经理数量不能超过 CEO 卡槽”
	if manager_count > ceo_slots:
		for i in range(employees.size() - 1, -1, -1):
			var emp_id: String = str(employees[i])
			if emp_id == "ceo":
				continue
			var def_val = EmployeeRegistryClass.get_def(emp_id)
			if def_val == null:
				return Result.failure("CompanyStructureRules: 未知的员工类型: %s" % emp_id)
			if maxi(0, int(def_val.manager_slots)) > 0:
				return Result.success(i)
		return Result.failure("CompanyStructureRules: 无法选择可移动的经理员工（manager_count=%d, ceo_slots=%d, employees=%s）" % [
			manager_count,
			ceo_slots,
			str(employees),
		])

	# 2) 再处理“总卡槽不足”：优先把非经理移回预备区，避免减少总卡槽。
	for i in range(employees.size() - 1, -1, -1):
		var emp_id2: String = str(employees[i])
		if emp_id2 == "ceo":
			continue
		var def_val2 = EmployeeRegistryClass.get_def(emp_id2)
		if def_val2 == null:
			return Result.failure("CompanyStructureRules: 未知的员工类型: %s" % emp_id2)
		if maxi(0, int(def_val2.manager_slots)) <= 0:
			return Result.success(i)

	# 3) 若全是经理，只能移除经理（会连带减少总卡槽，循环会继续收敛）。
	for i in range(employees.size() - 1, -1, -1):
		var emp_id3: String = str(employees[i])
		if emp_id3 == "ceo":
			continue
		return Result.success(i)

	return Result.failure("CompanyStructureRules: employees 中不存在可移动的员工（仅 CEO？employees=%s）" % str(employees))

static func _validate_employee_list(list: Array, path: String) -> Result:
	for i in range(list.size()):
		var v = list[i]
		if not (v is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		var s := str(v)
		if s.is_empty():
			return Result.failure("%s[%d] 不应为空字符串" % [path, i])
	return Result.success()
