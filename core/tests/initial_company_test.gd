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

	var recruiter_requires_salary := EmployeeRules.requires_salary("recruiter")
	if recruiter_requires_salary:
		return Result.failure("EmployeeRules.requires_salary('recruiter') 应返回 false（recruiter.salary=false）")

	# 4) 验证每个玩家初始有 CEO
	for i in range(player_count):
		var player := state.get_player(i)
		var employees: Array = player.get("employees", [])

		if employees.size() != 1:
			return Result.failure("玩家 %d 初始员工数量应为 1，实际: %d" % [i, employees.size()])

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
		"employee_count": EmployeeRegistryClass.get_count()
	})
