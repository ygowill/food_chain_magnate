# 初始公司结构测试（M3）
# 验证：玩家初始化时有 CEO，CEO 不需要薪水，招聘额度正确
class_name InitialCompanyTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	# 1) 初始化游戏（模块系统 V2 会装配 EmployeeRegistry）
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()

	# 2) 测试 EmployeeRegistry 加载（CEO）
	var ceo_def = EmployeeRegistryClass.get_def("ceo")
	if ceo_def == null:
		return Result.failure("无法获取 CEO 定义")
	if ceo_def.id != "ceo":
		return Result.failure("CEO 定义 ID 不匹配: %s" % ceo_def.id)
	if ceo_def.salary != false:
		return Result.failure("CEO 应不需要薪水 (salary: false)，实际: %s" % ceo_def.salary)

	# 3) 测试 EmployeeRules.requires_salary
	var ceo_requires_salary := EmployeeRules.requires_salary("ceo")
	if ceo_requires_salary:
		return Result.failure("EmployeeRules.requires_salary('ceo') 应返回 false")

	var recruiter_requires_salary := EmployeeRules.requires_salary("recruiting_girl")
	if recruiter_requires_salary:
		return Result.failure("EmployeeRules.requires_salary('recruiting_girl') 应返回 false（recruiting_girl.salary=false）")

	# 4) 验证每个玩家初始有 CEO
	for i in range(player_count):
		var player := state.get_player(i)
		var employees: Array = player.get("employees", [])
		var employees_staff_ids: Array = player.get("employees_staff_ids", [])
		var staff_registry: Dictionary = player.get("staff_registry", {})

		if employees.size() != 1:
			return Result.failure("玩家 %d 初始员工数量应为 1，实际: %d" % [i, employees.size()])
		if employees_staff_ids.size() != employees.size():
			return Result.failure("玩家 %d employees_staff_ids 应与 employees 等长，实际: %d vs %d" % [i, employees_staff_ids.size(), employees.size()])
		if staff_registry.size() != employees.size():
			return Result.failure("玩家 %d staff_registry 数量应与 employees 一致，实际: %d vs %d" % [i, staff_registry.size(), employees.size()])

		var first_emp = employees[0]
		var emp_id := ""
		if first_emp is String:
			emp_id = first_emp
		elif first_emp is Dictionary:
			emp_id = str(first_emp.get("type", ""))
		else:
			return Result.failure("玩家 %d 员工数据格式无效: %s" % [i, typeof(first_emp)])

		if emp_id != "ceo":
			return Result.failure("玩家 %d 初始员工应为 'ceo'，实际: '%s'" % [i, emp_id])

		var staff_id := int(employees_staff_ids[0])
		if staff_id <= 0:
			return Result.failure("玩家 %d 初始 CEO staff_id 应为正整数，实际: %s" % [i, str(employees_staff_ids)])
		if not staff_registry.has(staff_id):
			return Result.failure("玩家 %d staff_registry 应包含 CEO 的 staff_id=%d" % [i, staff_id])
		var staff_record: Dictionary = staff_registry.get(staff_id, {})
		if str(staff_record.get("employee_type", "")) != "ceo":
			return Result.failure("玩家 %d CEO staff 记录 employee_type 应为 ceo，实际: %s" % [i, str(staff_record)])

	# 5) 验证 count_paid_employees 返回 0（CEO 不计入）
	for i in range(player_count):
		var player := state.get_player(i)
		var paid_count := EmployeeRules.count_paid_employees(player)
		if paid_count != 0:
			return Result.failure("玩家 %d count_paid_employees 应为 0（CEO 无薪），实际: %d" % [i, paid_count])

	# 6) 验证 get_recruit_limit 返回 1（CEO 提供 1 次免费招聘）
	for i in range(player_count):
		var player := state.get_player(i)
		var recruit_limit := EmployeeRules.get_recruit_limit(player)
		if recruit_limit != 1:
			return Result.failure("玩家 %d get_recruit_limit 应为 1（CEO 提供），实际: %d" % [i, recruit_limit])

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"ceo_salary": ceo_def.salary,
		"employee_count": EmployeeRegistryClass.get_count(),
		"next_staff_id": state.next_staff_id,
	})
