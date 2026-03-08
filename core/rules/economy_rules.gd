# 经济规则 helper
# 目标：收敛 Payday 等经济域里重复的 token 资格判定。
class_name EconomyRules
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")

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
