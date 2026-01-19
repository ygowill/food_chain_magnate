# 晚餐需求变体辅助
# 用途：减少多个模块中重复的 “统计 base_required 总量” 等样板。
class_name DinnertimeDemandVariantHelpers
extends RefCounted

static func sum_required_counts(required: Dictionary) -> int:
	if required == null or not (required is Dictionary):
		return 0
	var total := 0
	for k in required.keys():
		total += int(required.get(k, 0))
	return total

static func build_replace_all_variant(module_id: String, product_id: String, total: int, rank: int) -> Dictionary:
	if module_id.is_empty() or product_id.is_empty() or total <= 0:
		return {}
	return {
		"id": "%s:replace_all" % module_id,
		"rank": rank,
		"required": {product_id: total},
	}

