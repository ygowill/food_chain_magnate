# 公司结构校验器
# 校验玩家公司结构是否允许添加员工
# - CEO 卡槽容量检查
# - 唯一员工约束检查
class_name CompanyStructureValidator
extends "res://gameplay/validators/base_validator.gd"

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func validate(state: GameState, player_id: int, params: Dictionary) -> Result:
	var player := state.get_player(player_id)
	if player.is_empty():
		return Result.failure("玩家 %d 不存在" % player_id)

	var employee_id_read := _require_string_param(params, "employee_id")
	if not employee_id_read.ok:
		return employee_id_read
	var employee_id: String = employee_id_read.value

	var to_reserve_read := _require_bool_param(params, "to_reserve")
	if not to_reserve_read.ok:
		return to_reserve_read
	var to_reserve: bool = bool(to_reserve_read.value)

	var employees_read := _require_player_string_array(player, "employees", "player.employees")
	if not employees_read.ok:
		return employees_read
	var reserve_read := _require_player_string_array(player, "reserve_employees", "player.reserve_employees")
	if not reserve_read.ok:
		return reserve_read
	var busy_read := _require_player_string_array(player, "busy_marketers", "player.busy_marketers")
	if not busy_read.ok:
		return busy_read

	# 1) 公司结构卡槽容量检查（仅当要把员工“激活/在岗”时才需要）
	if not to_reserve:
		var ceo_result := _check_ceo_slots(player, employee_id, employees_read.value)
		if not ceo_result.ok:
			return ceo_result

	# 2) 唯一员工约束检查
	var unique_result := _check_unique_constraint(employee_id, employees_read.value, reserve_read.value, busy_read.value)
	if not unique_result.ok:
		return unique_result

	return Result.success()

# === 私有方法 ===

# 严格参数解析（Fail Fast）
static func _require_string_param(params: Dictionary, key: String) -> Result:
	if not params.has(key):
		return Result.failure("缺少参数: %s" % key)
	var value = params[key]
	if not (value is String):
		return Result.failure("%s 必须为字符串" % key)
	var s: String = value
	if s.is_empty():
		return Result.failure("%s 不能为空" % key)
	return Result.success(s)

static func _require_bool_param(params: Dictionary, key: String) -> Result:
	if not params.has(key):
		return Result.failure("缺少参数: %s" % key)
	var value = params[key]
	if not (value is bool):
		return Result.failure("%s 必须为 bool" % key)
	return Result.success(bool(value))

static func _require_player_string_array(player: Dictionary, key: String, path: String) -> Result:
	if not player.has(key):
		return Result.failure("%s 缺失" % path)
	var value = player[key]
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
	return Result.success(arr)

# 检查 CEO 卡槽容量
func _check_ceo_slots(player: Dictionary, _employee_id: String, employees: Array) -> Result:
	if not player.has("company_structure") or not (player["company_structure"] is Dictionary):
		return Result.failure("player.company_structure 缺失或类型错误（期望 Dictionary）")
	var company_structure: Dictionary = player["company_structure"]
	if not company_structure.has("ceo_slots"):
		return Result.failure("player.company_structure.ceo_slots 缺失")
	var ceo_slots_read := _parse_non_negative_int(company_structure["ceo_slots"], "player.company_structure.ceo_slots")
	if not ceo_slots_read.ok:
		return ceo_slots_read
	var ceo_slots: int = int(ceo_slots_read.value)

	# 计算当前公司结构占用（不含 CEO）
	var used_slots := 0
	var manager_count := 0
	var manager_slots_total := 0
	for emp in employees:
		if not (emp is String):
			return Result.failure("player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		used_slots += 1
		var def = EmployeeRegistryClass.get_def(emp_id)
		if def == null:
			return Result.failure("未知的员工类型: %s" % emp_id)
		var slots := maxi(0, int(def.manager_slots))
		if slots > 0:
			manager_count += 1
			manager_slots_total += slots

	# 尝试添加的员工是否为“经理卡槽提供者”
	var employee_id: String = _employee_id
	var add_is_manager := false
	var add_manager_slots := 0
	if not employee_id.is_empty() and employee_id != "ceo":
		var add_def = EmployeeRegistryClass.get_def(employee_id)
		if add_def == null:
			return Result.failure("未知的员工类型: %s" % employee_id)
		add_manager_slots = maxi(0, int(add_def.manager_slots))
		add_is_manager = add_manager_slots > 0

	var new_used := used_slots + 1
	var new_manager_count := manager_count + (1 if add_is_manager else 0)
	var new_manager_slots_total := manager_slots_total + (add_manager_slots if add_is_manager else 0)

	# 经理必须直接向 CEO 汇报，因此经理数量不能超过 CEO 卡槽
	if new_manager_count > ceo_slots:
		return Result.failure("经理数量超过 CEO 卡槽 (%d/%d)" % [new_manager_count, ceo_slots])

	var total_slots := ceo_slots + new_manager_slots_total
	if new_used > total_slots:
		return Result.failure("公司结构卡槽已满 (%d/%d)，无法添加更多激活员工" % [new_used, total_slots])

	return Result.success()

# 检查唯一员工约束
func _check_unique_constraint(employee_id: String, employees: Array, reserve_employees: Array, busy_marketers: Array) -> Result:
	var emp_def = EmployeeRegistryClass.get_def(employee_id)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_id)

	if not emp_def.unique:
		return Result.success()  # 非唯一员工，无需检查

	# 检查玩家是否已拥有该唯一员工
	if _has_employee_in_list(employees, employee_id):
		return Result.failure("%s 是唯一员工，不能重复拥有" % emp_def.name)

	# 也检查预备区（待命员工）
	if _has_employee_in_list(reserve_employees, employee_id):
		return Result.failure("%s 是唯一员工，已在预备区，不能重复招聘" % emp_def.name)

	# 也检查忙碌区（营销员不占卡槽，但仍属于“拥有该员工”）
	if _has_employee_in_list(busy_marketers, employee_id):
		return Result.failure("%s 是唯一员工，处于忙碌区，不能重复拥有" % emp_def.name)

	return Result.success()

func _has_employee_in_list(list: Array, employee_id: String) -> bool:
	for item in list:
		if item is String and item == employee_id:
			return true
	return false

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 不能为负数: %d" % [path, int(r.value)])
	return r
