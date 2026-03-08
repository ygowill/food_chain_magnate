# 晚餐领域规则 helper
# 目标：收敛晚餐结算中散落的产品/员工/里程碑定义读取，统一失败语义。
class_name DinnertimeRules
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

static func require_product_def(product_id: String, prefix: String = "晚餐结算失败：") -> Result:
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null:
		return Result.failure("%s未知产品定义: %s" % [prefix, product_id])
	if not (def_val is ProductDef):
		return Result.failure("%s产品定义类型错误（期望 ProductDef）: %s" % [prefix, product_id])
	return Result.success(def_val)

static func require_employee_def(employee_id: String, prefix: String = "晚餐结算失败：") -> Result:
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return Result.failure("%s未知员工定义: %s" % [prefix, employee_id])
	if not (def_val is EmployeeDef):
		return Result.failure("%s员工定义类型错误（期望 EmployeeDef）: %s" % [prefix, employee_id])
	return Result.success(def_val)

static func require_milestone_def(milestone_id: String, prefix: String = "晚餐结算失败：") -> Result:
	var def_val = MilestoneRegistryClass.get_def(milestone_id)
	if def_val == null:
		return Result.failure("%s未知里程碑定义: %s" % [prefix, milestone_id])
	if not (def_val is MilestoneDef):
		return Result.failure("%s里程碑定义类型错误（期望 MilestoneDef）: %s" % [prefix, milestone_id])
	return Result.success(def_val)
