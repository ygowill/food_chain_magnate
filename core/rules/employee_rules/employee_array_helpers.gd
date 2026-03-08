extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func require_string_array_field(container: Dictionary, key: String, container_label: String) -> Array[String]:
	assert(container.has(key), "%s 缺少 %s" % [container_label, key])
	assert(container[key] is Array, "%s.%s 类型错误（期望 Array）" % [container_label, key])
	var arr: Array = container[key]

	var out: Array[String] = []
	for v in arr:
		assert(v is String, "%s.%s 元素类型错误（期望 String）" % [container_label, key])
		var s: String = v
		assert(not s.is_empty(), "%s.%s 不应包含空字符串" % [container_label, key])
		out.append(s)
	return out

static func lookup_employee_def(employee_id: String, prefix: String = "") -> Result:
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return Result.failure("%s未知员工定义: %s" % [prefix, employee_id])
	if not (def_val is EmployeeDef):
		return Result.failure("%s员工定义类型错误（期望 EmployeeDef）: %s" % [prefix, employee_id])
	return Result.success(def_val)

static func require_employee_def(employee_id: String) -> EmployeeDef:
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	assert(def_val != null, "未知员工: %s" % employee_id)
	assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
	return def_val as EmployeeDef

