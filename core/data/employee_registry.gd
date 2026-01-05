# 员工注册表（Strict Mode）
# 说明：
# - V2：员工定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name EmployeeRegistry
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")

# === 静态缓存 ===
static var _employees: Dictionary = {}  # employee_id -> EmployeeDef
static var _loaded: bool = false

# === 静态方法 ===

static func is_loaded() -> bool:
	return _loaded

static func _ensure_loaded() -> void:
	assert(_loaded, "EmployeeRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func configure_from_catalog(catalog) -> Result:
	if catalog == null:
		return Result.failure("EmployeeRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("EmployeeRegistry.configure_from_catalog: catalog.employees 类型错误（期望 Dictionary）")

	var out: Dictionary = {}
	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("EmployeeRegistry.configure_from_catalog: employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		if emp_id.is_empty():
			return Result.failure("EmployeeRegistry.configure_from_catalog: employees key 不能为空")
		var def_val = catalog.employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("EmployeeRegistry.configure_from_catalog: employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDefClass):
			return Result.failure("EmployeeRegistry.configure_from_catalog: employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val
		if def.id != emp_id:
			return Result.failure("EmployeeRegistry.configure_from_catalog: employees[%s].id 不一致: %s" % [emp_id, def.id])
		out[emp_id] = def

	_employees = out
	_loaded = true
	return Result.success(_employees.size())

# 获取员工定义
# 返回 EmployeeDef 或 null
static func get_def(employee_id: String) -> Variant:
	_ensure_loaded()
	return _employees.get(employee_id, null)

# 检查员工是否需要薪水
static func check_requires_salary(employee_id: String) -> bool:
	var emp = get_def(employee_id)
	assert(emp != null, "未知员工: %s" % employee_id)
	return emp.salary

# 检查员工是否存在
static func has(employee_id: String) -> bool:
	_ensure_loaded()
	return _employees.has(employee_id)

# 获取所有员工 ID
static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for id in _employees.keys():
		ids.append(id)
	ids.sort()
	return ids

# 获取员工数量
static func get_count() -> int:
	_ensure_loaded()
	return _employees.size()

# 重置缓存（用于测试）
static func reset() -> void:
	_employees.clear()
	_loaded = false

# === 调试 ===

static func dump() -> String:
	_ensure_loaded()
	var output := "=== EmployeeRegistry ===\n"
	output += "Total employees: %d\n" % _employees.size()
	output += "\nEmployees:\n"

	var ids := get_all_ids()
	for id in ids:
		var emp = _employees[id]
		output += "  - %s: %s (salary: %s)\n" % [id, emp.name, emp.salary]

	return output
