# 饮料采购：起点餐厅解析（Fail Fast）
extends RefCounted

const InputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

static func resolve_start_restaurant(
	state: GameState,
	command: Command,
	restaurant_ids: Array[String],
	restaurants: Dictionary,
	range_type: String,
	route: Array[Vector2i]
) -> Result:
	if command.params.has("restaurant_id"):
		var requested_val = command.params["restaurant_id"]
		if not (requested_val is String):
			return Result.failure("restaurant_id 必须为字符串")
		var requested_id: String = requested_val
		if requested_id.is_empty():
			return Result.failure("restaurant_id 不能为空")
		if not restaurants.has(requested_id):
			return Result.failure("餐厅不存在: %s" % requested_id)
		var rest: Dictionary = restaurants[requested_id]
		var owner_check := InputsClass.require_restaurant_owned_by(rest, requested_id, command.actor)
		if not owner_check.ok:
			return owner_check
		var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(rest, requested_id)
		if not entrance_pos_result.ok:
			return entrance_pos_result
		var entrance_pos: Vector2i = entrance_pos_result.value
		return Result.success({"restaurant_id": requested_id, "entrance_pos": entrance_pos})

	# 若提供了 route，则尝试从 route 起点反推餐厅（避免多餐厅时歧义）
	if not route.is_empty():
		var matches: Array[String] = []
		if range_type == "air":
			var start_pos: Vector2i = route[0]
			for rest_id in restaurant_ids:
				var rest: Dictionary = restaurants[rest_id]
				var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(rest, rest_id)
				if not entrance_pos_result.ok:
					return entrance_pos_result
				var entrance_pos: Vector2i = entrance_pos_result.value
				if entrance_pos == start_pos:
					matches.append(rest_id)
		else:
			var start_road: Vector2i = route[0]
			for rest_id in restaurant_ids:
				var rest: Dictionary = restaurants[rest_id]
				var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(rest, rest_id)
				if not entrance_pos_result.ok:
					return entrance_pos_result
				var entrance_pos: Vector2i = entrance_pos_result.value
				var starts_result := RangeUtilsClass.get_adjacent_road_cells(state, entrance_pos)
				if not starts_result.ok:
					return starts_result
				var starts: Array[Vector2i] = starts_result.value
				if starts.has(start_road):
					matches.append(rest_id)

		if matches.size() == 1:
			var chosen_id: String = matches[0]
			var chosen: Dictionary = restaurants[chosen_id]
			var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(chosen, chosen_id)
			if not entrance_pos_result.ok:
				return entrance_pos_result
			var entrance_pos: Vector2i = entrance_pos_result.value
			return Result.success({"restaurant_id": chosen_id, "entrance_pos": entrance_pos})
		if matches.size() > 1:
			return Result.failure("route 起点匹配到多个餐厅入口，请指定 restaurant_id: %s" % str(matches))
		return Result.failure("route 起点不属于你的任何餐厅入口，请指定 restaurant_id")

	# 未提供 restaurant_id 与 route：由默认选路器挑选一个可行餐厅（确定性：按 id 升序）
	var sorted_ids := restaurant_ids.duplicate()
	sorted_ids.sort()
	var rest_id: String = sorted_ids[0]
	var rest: Dictionary = restaurants[rest_id]
	var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(rest, rest_id)
	if not entrance_pos_result.ok:
		return entrance_pos_result
	var entrance_pos: Vector2i = entrance_pos_result.value
	return Result.success({"restaurant_id": rest_id, "entrance_pos": entrance_pos})
