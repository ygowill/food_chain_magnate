# 经济规则 helper
# 目标：收敛 Payday 等经济域里重复的 token 资格判定。
class_name EconomyRules
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func is_salary_token_eligible_product(product_id: String) -> bool:
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null or not (def_val is ProductDef):
		return false
	var product: ProductDef = def_val
	if product.has_tag("salary_token_ineligible"):
		return false
	if not (product.has_tag("food") or product.has_tag("drink")):
		return false
	return true

static func require_employee_def(employee_id: String, prefix: String = "EconomyRules: ") -> Result:
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return Result.failure("%s未知员工定义: %s" % [prefix, employee_id])
	if not (def_val is EmployeeDef):
		return Result.failure("%s员工定义类型错误（期望 EmployeeDef）: %s" % [prefix, employee_id])
	return Result.success(def_val)
