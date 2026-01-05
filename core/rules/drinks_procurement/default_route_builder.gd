# 饮料采购：默认选路（Fail Fast / 确定性）
extends RefCounted

const InputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

static func build_default_route(
	state: GameState,
	restaurant_ids: Array[String],
	restaurants: Dictionary,
	drink_sources: Array,
	range_type: String,
	range_value: int
) -> Result:
	var sorted_ids := restaurant_ids.duplicate()
	sorted_ids.sort()

	# 选择“存在可拾取来源”的最先餐厅（确定性：按 id 升序）
	for rest_id in sorted_ids:
		var rest: Dictionary = restaurants[rest_id]
		var entrance_pos_result := InputsClass.require_restaurant_entrance_pos(rest, rest_id)
		if not entrance_pos_result.ok:
			return entrance_pos_result
		var entrance_pos: Vector2i = entrance_pos_result.value
		var route_result := build_default_route_for_restaurant(state, entrance_pos, drink_sources, range_type, range_value)
		if route_result.ok:
			return Result.success({
				"restaurant_id": rest_id,
				"entrance_pos": entrance_pos,
				"route": route_result.value
			})

	return Result.failure("范围内没有可采购的饮料源")

static func build_default_route_for_restaurant(
	state: GameState,
	entrance_pos: Vector2i,
	drink_sources: Array,
	range_type: String,
	range_value: int
) -> Result:
	if range_type == "air":
		return build_default_air_route(entrance_pos, drink_sources, range_value)
	return build_default_road_route(state, entrance_pos, drink_sources, range_value)

static func build_default_air_route(
	entrance_pos: Vector2i,
	drink_sources: Array,
	range_value: int
) -> Result:
	var best_source: Vector2i = Vector2i(-1, -1)
	var best_dist := INF

	for source in drink_sources:
		var src: Vector2i = source["world_pos"]
		var d: int = abs(src.x - entrance_pos.x) + abs(src.y - entrance_pos.y)
		if d > range_value:
			continue
		if d < best_dist or (d == best_dist and (src.y < best_source.y or (src.y == best_source.y and src.x < best_source.x))):
			best_dist = d
			best_source = src

	if best_dist == INF:
		return Result.failure("飞艇范围内没有可采购的饮料源")

	# 默认路径：先走 x 再走 y（确定性）
	var route: Array[Vector2i] = [entrance_pos]
	var x := entrance_pos.x
	var y := entrance_pos.y
	while x != best_source.x:
		x += 1 if best_source.x > x else -1
		route.append(Vector2i(x, y))
	while y != best_source.y:
		y += 1 if best_source.y > y else -1
		route.append(Vector2i(x, y))

	return Result.success(route)

static func build_default_road_route(
	state: GameState,
	entrance_pos: Vector2i,
	drink_sources: Array,
	range_value: int
) -> Result:
	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	var start_candidates_result := RangeUtilsClass.get_adjacent_road_cells(state, entrance_pos)
	if not start_candidates_result.ok:
		return start_candidates_result
	var start_candidates: Array[Vector2i] = start_candidates_result.value
	if start_candidates.is_empty():
		return Result.failure("餐厅入口未邻接道路")

	var best_path: Array[Vector2i] = []
	var best_dist := INF
	var best_steps := INF
	var best_src: Vector2i = Vector2i(2147483647, 2147483647)

	var cache: Dictionary = {}

	for source in drink_sources:
		var src: Vector2i = source["world_pos"]
		var end_candidates_result := RangeUtilsClass.get_adjacent_road_cells(state, src)
		if not end_candidates_result.ok:
			return end_candidates_result
		var end_candidates: Array[Vector2i] = end_candidates_result.value
		if end_candidates.is_empty():
			continue

		for from_cell in start_candidates:
			for to_cell in end_candidates:
				var sp := _get_shortest_path_cached(road_graph, from_cell, to_cell, cache)
				if sp.is_empty():
					continue
				if not sp.has("distance") or not sp.has("steps") or not sp.has("path"):
					return Result.failure("shortest_path 返回缺字段: %s" % str(sp))
				if not (sp["distance"] is int):
					return Result.failure("shortest_path.distance 类型错误: %s" % str(sp))
				if not (sp["steps"] is int):
					return Result.failure("shortest_path.steps 类型错误: %s" % str(sp))
				if not (sp["path"] is Array):
					return Result.failure("shortest_path.path 类型错误: %s" % str(sp))
				var d: int = sp["distance"]
				var steps: int = sp["steps"]
				var path: Array = sp["path"]
				if d > range_value:
					continue
				if d < best_dist or \
					(d == best_dist and steps < best_steps) or \
					(d == best_dist and steps == best_steps and (src.y < best_src.y or (src.y == best_src.y and src.x < best_src.x))):
					best_dist = d
					best_steps = steps
					best_src = src
					best_path = path

	if best_path.is_empty():
		return Result.failure("卡车范围内没有可采购的饮料源")

	return Result.success(best_path)

static func _get_shortest_path_cached(road_graph, from_cell: Vector2i, to_cell: Vector2i, cache: Dictionary) -> Dictionary:
	var key := "%d,%d|%d,%d" % [from_cell.x, from_cell.y, to_cell.x, to_cell.y]
	if cache.has(key):
		return cache[key]
	var result = road_graph.find_shortest_path(from_cell, to_cell)
	if not result.ok:
		cache[key] = {}
		return {}
	cache[key] = result.value
	return cache[key]
