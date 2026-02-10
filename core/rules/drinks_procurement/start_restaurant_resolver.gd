# 饮料采购：起点餐厅解析（Fail Fast）
extends RefCounted

const InputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")

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

		# 若提供了 route，则尽量回传“与 route 起点匹配的入口点”（免下车时可能不是 entrance_pos）。
		if not route.is_empty():
			var points_read := StructuresClass.get_restaurant_entrance_points(state, requested_id, rest)
			if not points_read.ok:
				return points_read
			var points: Array[Vector2i] = points_read.value
			if range_type == "air":
				var start_tile: Vector2i = route[0]
				for ep in points:
					var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, ep)
					if not tile_read.ok:
						return tile_read
					var entrance_tile: Vector2i = tile_read.value
					if entrance_tile == start_tile:
						entrance_pos = Vector2i(ep)
						break
			else:
				var start_road: Vector2i = route[0]
				for ep in points:
					var starts_one := RangeUtilsClass.get_adjacent_road_cells(state, ep)
					if not starts_one.ok:
						return starts_one
					var starts: Array[Vector2i] = starts_one.value
					if starts.has(start_road):
						entrance_pos = Vector2i(ep)
						break

		return Result.success({"restaurant_id": requested_id, "entrance_pos": entrance_pos})

	# 若提供了 route，则尝试从 route 起点反推餐厅（避免多餐厅时歧义）
	if not route.is_empty():
		var matches: Array[Dictionary] = []
		if range_type == "air":
			var start_tile: Vector2i = route[0]
			for rest_id in restaurant_ids:
				if not restaurants.has(rest_id):
					continue
				var rest_val = restaurants[rest_id]
				if not (rest_val is Dictionary):
					continue
				var rest: Dictionary = rest_val
				var points_read := StructuresClass.get_restaurant_entrance_points(state, rest_id, rest)
				if not points_read.ok:
					return points_read
				var points: Array[Vector2i] = points_read.value
				for ep in points:
					var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, ep)
					if not tile_read.ok:
						return tile_read
					var entrance_tile: Vector2i = tile_read.value
					if entrance_tile == start_tile:
						matches.append({"restaurant_id": rest_id, "entrance_pos": Vector2i(ep)})
						break
		else:
			var start_road: Vector2i = route[0]
			for rest_id2 in restaurant_ids:
				if not restaurants.has(rest_id2):
					continue
				var rest_val2 = restaurants[rest_id2]
				if not (rest_val2 is Dictionary):
					continue
				var rest2: Dictionary = rest_val2
				var points_read2 := StructuresClass.get_restaurant_entrance_points(state, rest_id2, rest2)
				if not points_read2.ok:
					return points_read2
				var points2: Array[Vector2i] = points_read2.value
				var starts_result := RangeUtilsClass.get_adjacent_road_cells_for_positions(state, points2)
				if not starts_result.ok:
					return starts_result
				var starts_union: Array[Vector2i] = starts_result.value
				if not starts_union.has(start_road):
					continue

				# 选出与 start_road 匹配的入口点（确定性：按 points 顺序取第一个匹配点）。
				var chosen_ep := Vector2i(-1, -1)
				for ep2 in points2:
					var starts_one2 := RangeUtilsClass.get_adjacent_road_cells(state, ep2)
					if not starts_one2.ok:
						return starts_one2
					var starts2: Array[Vector2i] = starts_one2.value
					if starts2.has(start_road):
						chosen_ep = Vector2i(ep2)
						break
				if chosen_ep != Vector2i(-1, -1):
					matches.append({"restaurant_id": rest_id2, "entrance_pos": chosen_ep})
				else:
					# 理论上不会发生：start_road 已在并集中
					matches.append({"restaurant_id": rest_id2, "entrance_pos": Vector2i(points2[0])})

		if matches.size() == 1:
			var match: Dictionary = matches[0]
			var chosen_id: String = str(match.get("restaurant_id", "")).strip_edges()
			var ep_val = match.get("entrance_pos", null)
			if chosen_id.is_empty() or not (ep_val is Vector2i):
				return Result.failure("内部错误: matches[0] 缺失字段")
			return Result.success({"restaurant_id": chosen_id, "entrance_pos": Vector2i(ep_val)})
		if matches.size() > 1:
			var ids: Array[String] = []
			for m_val in matches:
				if m_val is Dictionary:
					ids.append(str((m_val as Dictionary).get("restaurant_id", "")).strip_edges())
			return Result.failure("route 起点匹配到多个餐厅入口，请指定 restaurant_id: %s" % str(ids))
		return Result.failure("route 起点不属于你的任何餐厅入口，请指定 restaurant_id")

	# 未提供 restaurant_id 与 route：由默认选路器挑选一个可行餐厅（确定性：按 id 升序）
	var sorted_ids := restaurant_ids.duplicate()
	sorted_ids.sort()
	var rest_id3: String = sorted_ids[0]
	var rest3: Dictionary = restaurants[rest_id3]
	var entrance_pos_result3 := InputsClass.require_restaurant_entrance_pos(rest3, rest_id3)
	if not entrance_pos_result3.ok:
		return entrance_pos_result3
	var entrance_pos3: Vector2i = entrance_pos_result3.value
	return Result.success({"restaurant_id": rest_id3, "entrance_pos": entrance_pos3})
