# DinnertimeSettlement：事件/日志辅助
class_name DinnertimeEvents
extends RefCounted

static func append_sold_marketed_demand_events(
	out_events: Array[Dictionary],
	demands: Array,
	house_id: String,
	house: Dictionary,
	winner_owner: int
) -> Result:
	if out_events == null:
		return Result.failure("_append_sold_marketed_demand_events: out_events 为空")
	if demands == null:
		return Result.failure("_append_sold_marketed_demand_events: demands 为空")
	if house_id.is_empty():
		return Result.failure("_append_sold_marketed_demand_events: house_id 不能为空")
	if house == null:
		return Result.failure("_append_sold_marketed_demand_events: house 为空")
	if not house.has("house_number"):
		return Result.failure("_append_sold_marketed_demand_events: house.house_number 缺失")
	var house_number_val = house.get("house_number", null)
	if not (house_number_val is int or house_number_val is float or house_number_val is String):
		return Result.failure("_append_sold_marketed_demand_events: house.house_number 类型错误（期望 int/float/String）")
	var house_number = house_number_val

	for i in range(demands.size()):
		var d_val = demands[i]
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		if not d.has("from_player"):
			continue
		var fp = d.get("from_player", null)
		if not (fp is int):
			continue
		var from_player: int = int(fp)
		if from_player < 0:
			continue
		if from_player == winner_owner:
			continue
		out_events.append({
			"from_player": from_player,
			"sold_by": winner_owner,
			"house_id": house_id,
			"house_number": house_number,
			"demand_index": i,
		})

	return Result.success()
