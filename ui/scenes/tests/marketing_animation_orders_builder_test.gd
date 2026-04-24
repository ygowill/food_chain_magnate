# 营销动画订单构建回归测试
class_name MarketingAnimationOrdersBuilderTest
extends RefCounted

const BuilderClass = preload("res://ui/scenes/game/marketing/orders_builder.gd")

static func run() -> Result:
	var timeline_r := _case_builds_orders_from_timeline()
	if not timeline_r.ok:
		return timeline_r
	var fallback_r := _case_builds_orders_from_processed_fallback()
	if not fallback_r.ok:
		return fallback_r
	return Result.success({"cases": 2})

static func _case_builds_orders_from_timeline() -> Result:
	var data := {
		"rounds": 1,
		"processed": [],
		"expired": [],
		"timeline_events": [
			{
				"kind": "campaign_start",
				"round_index": 0,
				"board_number": 7,
				"type": "radio",
				"owner": 0,
				"product": "burger",
				"products": ["burger"],
				"world_pos": [4, 5],
				"footprint_size": [1, 1],
				"affected_houses": ["house_1"],
				"demand_amount": 1,
			},
			{
				"kind": "house_demand",
				"round_index": 0,
				"board_number": 7,
				"type": "radio",
				"owner": 0,
				"product": "burger",
				"house_id": "house_1",
				"house_number": 3,
				"amount_requested": 1,
				"amount_added": 1,
				"demand_before": 0,
				"demand_after": 1,
				"cap": 3,
			},
			{
				"kind": "duration_tick",
				"board_number": 7,
				"type": "radio",
				"owner": 0,
				"product": "burger",
				"world_pos": [4, 5],
				"footprint_size": [1, 1],
				"duration_before": 2,
				"duration_after": 1,
				"expired": false,
			},
		],
	}
	var orders := BuilderClass.build_orders_from_settlement(data)
	if orders.size() != 1:
		return Result.failure("timeline 应构建 1 个订单，实际: %d" % orders.size())
	var order: Dictionary = orders[0]
	if int(order.get("board_number", 0)) != 7:
		return Result.failure("board_number 错误: %s" % str(order.get("board_number", null)))
	if str(order.get("type", "")) != "radio":
		return Result.failure("type 错误: %s" % str(order.get("type", null)))
	var house_events_val = order.get("house_events", null)
	if not (house_events_val is Array):
		return Result.failure("house_events 类型错误（期望 Array）")
	var house_events: Array = house_events_val
	if house_events.size() != 1:
		return Result.failure("house_events 数量错误: %d" % house_events.size())
	var house_evt: Dictionary = house_events[0]
	if str(house_evt.get("house_id", "")) != "house_1":
		return Result.failure("house_id 错误: %s" % str(house_evt.get("house_id", null)))
	if int(order.get("duration_before", 0)) != 2 or int(order.get("duration_after", 0)) != 1:
		return Result.failure("duration 未合并到订单: %s" % str(order))
	return Result.success()

static func _case_builds_orders_from_processed_fallback() -> Result:
	var data := {
		"rounds": 1,
		"processed": [
			{
				"board_number": 3,
				"type": "billboard",
				"owner": 0,
				"product": "pizza",
				"world_pos": Vector2i(1, 2),
				"affected_houses": ["house_2", "house_3"],
				"demands_added": 1,
				"duration_before": 1,
				"duration_after": 0,
				"expired": true,
			},
		],
		"expired": [],
	}
	var orders := BuilderClass.build_orders_from_settlement(data)
	if orders.size() != 1:
		return Result.failure("processed fallback 应构建 1 个订单，实际: %d" % orders.size())
	var order: Dictionary = orders[0]
	if not bool(order.get("expired", false)):
		return Result.failure("processed fallback 应保留 expired=true")
	var house_events_val = order.get("house_events", null)
	if not (house_events_val is Array):
		return Result.failure("processed fallback house_events 类型错误")
	var house_events: Array = house_events_val
	if house_events.size() != 2:
		return Result.failure("processed fallback 应为 affected_houses 构建 house_events，实际: %d" % house_events.size())
	return Result.success()
