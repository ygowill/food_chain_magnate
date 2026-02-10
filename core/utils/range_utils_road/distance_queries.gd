extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const AdjacentCellsClass = preload("res://core/utils/range_utils_road/adjacent_cells.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const RangeOriginRegistryClass = preload("res://core/rules/range_origin_registry.gd")

static func is_within_road_range_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i],
	max_distance: int
) -> Result:
	if restaurant_ids == null:
		return Result.failure("restaurant_ids 为空")
	if max_distance < 0:
		return Result.failure("max_distance 必须 >= 0")
	if target_road_cells == null:
		return Result.failure("target_road_cells 为空")
	if target_road_cells.is_empty():
		return Result.success(false)

	var min_r: Result = get_min_road_distance_to_any_road_cells(state, actor, restaurant_ids, target_road_cells)
	if not min_r.ok:
		return min_r
	var min_d: int = int(min_r.value)
	return Result.success(min_d >= 0 and min_d <= max_distance)

static func get_min_road_distance_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i]
) -> Result:
	if restaurant_ids == null:
		return Result.failure("restaurant_ids 为空")
	if target_road_cells == null:
		return Result.failure("target_road_cells 为空")
	if target_road_cells.is_empty():
		return Result.success(-1)

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var targets: Array[Vector2i] = []
	var target_set := {}
	for i in range(target_road_cells.size()):
		var v = target_road_cells[i]
		if not (v is Vector2i):
			return Result.failure("target_road_cells[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if target_set.has(p):
			continue
		target_set[p] = true
		if not CellsClass.has_cell_any(state, p):
			continue
		if not CellsClass.has_road_at_any(state, p):
			continue
		targets.append(p)
	if targets.is_empty():
		return Result.success(-1)

	var best := -1
	var start_road_set := {}

	# 起点：餐厅入口（免下车生效时四角都视为入口）
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			return Result.failure("餐厅不存在: %s" % rest_id)
		var rest: Dictionary = restaurants[rest_id]
		if not rest.has("owner") or not (rest["owner"] is int):
			return Result.failure("餐厅 %s 缺少 owner 或类型错误" % rest_id)
		if int(rest["owner"]) != actor:
			return Result.failure("餐厅 %s 不属于玩家 %d" % [rest_id, actor])
		if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
			return Result.failure("餐厅 %s 缺少 entrance_pos 或类型错误" % rest_id)
		var entrance_points_read := StructuresClass.get_restaurant_entrance_points(state, rest_id, rest)
		if not entrance_points_read.ok:
			return entrance_points_read
		var entrance_points: Array[Vector2i] = entrance_points_read.value

		for ep in entrance_points:
			var start_cells_result: Result = AdjacentCellsClass.get_adjacent_road_cells(state, ep)
			if not start_cells_result.ok:
				return start_cells_result
			var start_road_cells_one: Array[Vector2i] = start_cells_result.value
			for s2 in start_road_cells_one:
				start_road_set[s2] = true

	# 模块可扩展起点（例如 coffee_shop）
	var extra_read := RangeOriginRegistryClass.get_extra_origin_positions(state, actor, restaurant_ids, "road")
	if not extra_read.ok:
		return extra_read
	var extra: Array[Vector2i] = extra_read.value
	for origin in extra:
		var start_cells_result2: Result = AdjacentCellsClass.get_adjacent_road_cells(state, origin)
		if not start_cells_result2.ok:
			return start_cells_result2
		var start_road_cells_one2: Array[Vector2i] = start_cells_result2.value
		for s3 in start_road_cells_one2:
			start_road_set[s3] = true

	var start_road_cells: Array[Vector2i] = []
	for k in start_road_set.keys():
		if k is Vector2i:
			start_road_cells.append(k)
	if start_road_cells.is_empty():
		return Result.failure("没有可用于计算距离的起点（餐厅/模块起点未邻接道路）")

	for s in start_road_cells:
		for t in targets:
			var d: int = int(road_graph.get_distance(s, t))
			if d < 0:
				continue
			if best < 0 or d < best:
				best = d
				if best == 0:
					return Result.success(0)

	return Result.success(best)

static func is_within_road_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_distance: int
) -> Result:
	if max_distance < 0:
		return Result.failure("max_distance 必须 >= 0")

	var target_cells_result: Result = AdjacentCellsClass.get_adjacent_road_cells(state, target_pos)
	if not target_cells_result.ok:
		return target_cells_result
	var target_road_cells: Array[Vector2i] = target_cells_result.value
	if target_road_cells.is_empty():
		return Result.success(false)
	return is_within_road_range_to_any_road_cells(state, actor, restaurant_ids, target_road_cells, max_distance)
