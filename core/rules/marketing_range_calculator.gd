# 营销范围计算器（M4）
# 目标：将“营销板件 -> 受影响房屋集合”的算法从 PhaseManager 抽离，便于后续模块系统插拔。
class_name MarketingRangeCalculator
extends RefCounted

const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")

func get_affected_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("MarketingRangeCalculator: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("MarketingRangeCalculator: state.map 类型错误（期望 Dictionary）")
	if not (marketing_instance is Dictionary):
		return Result.failure("MarketingRangeCalculator: marketing_instance 类型错误（期望 Dictionary）")

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("MarketingRangeCalculator: marketing_instance.type 缺失或类型错误（期望 String）")
	var marketing_type: String = marketing_instance["type"]
	if marketing_type.is_empty():
		return Result.failure("MarketingRangeCalculator: marketing_instance.type 不能为空")

	if not marketing_instance.has("world_pos") or not (marketing_instance["world_pos"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: marketing_instance.world_pos 缺失或类型错误（期望 Vector2i）")
	var handler := MarketingTypeRegistryClass.get_range_handler(marketing_type)
	if not handler.is_valid():
		return Result.failure("MarketingRangeCalculator: 未知的 marketing type: %s" % marketing_type)
	var r = handler.call(state, marketing_instance)
	if not (r is Result):
		return Result.failure("MarketingRangeCalculator: marketing type handler 必须返回 Result: %s" % marketing_type)
	return r
