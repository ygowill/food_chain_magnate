# 模块系统 V2：从内容元数据推导 Pools（路线B）
# - employee_pool：来自 EmployeeDef.pool（fixed/one_x/none）
# - milestone_pool：来自 MilestoneDef.pool.enabled
class_name PoolBuilder
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const GameConstantsClass = preload("res://core/engine/game_constants.gd")

static func build_employee_pool(player_count: int, rules: Dictionary, employees: Dictionary) -> Result:
	if player_count < GameConstantsClass.MIN_PLAYERS or player_count > GameConstantsClass.MAX_PLAYERS:
		return Result.failure("PoolBuilder.build_employee_pool: player_count 越界: %d" % player_count)
	if not (rules is Dictionary):
		return Result.failure("PoolBuilder.build_employee_pool: rules 类型错误（期望 Dictionary）")
	if not (employees is Dictionary):
		return Result.failure("PoolBuilder.build_employee_pool: employees 类型错误（期望 Dictionary）")

	if not rules.has("one_x_employee_copies"):
		return Result.failure("PoolBuilder.build_employee_pool: rules 缺少 one_x_employee_copies")
	var copies_read := _parse_non_negative_int(rules.get("one_x_employee_copies", null), "rules.one_x_employee_copies")
	if not copies_read.ok:
		return copies_read
	var one_x_copies: int = int(copies_read.value)

	var pool: Dictionary = {}
	for emp_id_val in employees.keys():
		if not (emp_id_val is String):
			return Result.failure("PoolBuilder.build_employee_pool: employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		if emp_id.is_empty():
			return Result.failure("PoolBuilder.build_employee_pool: employees key 不能为空")

		var def_val = employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("PoolBuilder.build_employee_pool: employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDefClass):
			return Result.failure("PoolBuilder.build_employee_pool: employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val
		if def.id != emp_id:
			return Result.failure("PoolBuilder.build_employee_pool: employees[%s].id 不一致: %s" % [emp_id, def.id])

		match def.pool_type:
			"none":
				continue
			"fixed":
				if def.pool_count <= 0:
					return Result.failure("PoolBuilder.build_employee_pool: %s.pool.count 必须 > 0" % emp_id)
				pool[emp_id] = def.pool_count
			"one_x":
				pool[emp_id] = one_x_copies
			_:
				return Result.failure("PoolBuilder.build_employee_pool: %s.pool.type 不支持: %s" % [emp_id, def.pool_type])

	return Result.success(pool)

static func build_milestone_pool(milestones: Dictionary) -> Result:
	if not (milestones is Dictionary):
		return Result.failure("PoolBuilder.build_milestone_pool: milestones 类型错误（期望 Dictionary）")

	var out: Array[String] = []
	for mid_val in milestones.keys():
		if not (mid_val is String):
			return Result.failure("PoolBuilder.build_milestone_pool: milestones key 类型错误（期望 String）")
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("PoolBuilder.build_milestone_pool: milestones key 不能为空")

		var def_val = milestones.get(mid, null)
		if def_val == null:
			return Result.failure("PoolBuilder.build_milestone_pool: milestones[%s] 为空" % mid)
		if not (def_val is MilestoneDefClass):
			return Result.failure("PoolBuilder.build_milestone_pool: milestones[%s] 类型错误（期望 MilestoneDef）" % mid)
		var def: MilestoneDef = def_val
		if def.id != mid:
			return Result.failure("PoolBuilder.build_milestone_pool: milestones[%s].id 不一致: %s" % [mid, def.id])
		if def.pool_enabled:
			var count := int(def.pool_count)
			if count <= 0:
				return Result.failure("PoolBuilder.build_milestone_pool: %s.pool.count 必须 > 0" % mid)
			for _i in range(count):
				out.append(mid)

	out.sort()
	return Result.success(out)

static func _parse_non_negative_int(value, path: String) -> Result:
	if value is int:
		if int(value) < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		var i: int = int(f)
		if i < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, i])
		return Result.success(i)
	return Result.failure("%s 类型错误（期望整数）" % path)
