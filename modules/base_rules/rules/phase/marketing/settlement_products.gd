# MarketingSettlement：产品序列 helper（从 settlement_helpers_impl.gd 抽离）
extends RefCounted

static func get_products_in_order(inst: Dictionary) -> Result:
	if inst == null or not (inst is Dictionary):
		return Result.failure("MarketingSettlement: inst 类型错误（期望 Dictionary）")
	if not inst.has("product") or not (inst["product"] is String):
		return Result.failure("MarketingSettlement: inst.product 缺失或类型错误（期望 String）")
	var primary: String = str(inst["product"])
	if primary.is_empty():
		return Result.failure("MarketingSettlement: inst.product 不能为空")

	if not inst.has("products"):
		return Result.success([primary])

	var products_val = inst.get("products", null)
	if products_val == null:
		return Result.success([primary])
	if not (products_val is Array):
		return Result.failure("MarketingSettlement: inst.products 类型错误（期望 Array）")
	var products: Array = products_val
	if products.is_empty():
		return Result.success([primary])

	var out: Array[String] = []
	for i in range(products.size()):
		var v = products[i]
		if not (v is String):
			return Result.failure("MarketingSettlement: inst.products[%d] 类型错误（期望 String）" % i)
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("MarketingSettlement: inst.products[%d] 不能为空" % i)
		out.append(s)

	return Result.success(out)
