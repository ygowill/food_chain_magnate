# 饮料采购：路线校验（Fail Fast）
extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")

static func validate_route(
	state: GameState,
	restaurants: Dictionary,
	restaurant_id: String,
	entrance_pos: Vector2i,
	route: Array[Vector2i],
	range_type: String,
	range_value: int
) -> Result:
	if route.is_empty():
		return Result.failure("route 不能为空")

	if range_type == "air":
		return validate_air_route(state, restaurants, restaurant_id, entrance_pos, route, range_value)
	return validate_road_route(state, restaurants, restaurant_id, entrance_pos, route, range_value)

static func validate_air_route(
	state: GameState,
	restaurants: Dictionary,
	restaurant_id: String,
	entrance_pos: Vector2i,
	route: Array[Vector2i],
	max_steps: int
) -> Result:
	if not restaurants.has(restaurant_id):
		return Result.failure("餐厅不存在: %s" % restaurant_id)
	var tile_bounds_read := TileRouteUtilsClass.get_tile_bounds(state)
	if not tile_bounds_read.ok:
		return tile_bounds_read
	var tile_bounds: Dictionary = tile_bounds_read.value
	var min_tile: Vector2i = tile_bounds.get("min", Vector2i.ZERO)
	var max_tile: Vector2i = tile_bounds.get("max", Vector2i.ZERO)
	var tiles_set := TileRouteUtilsClass.get_tile_positions_set(state)

	var entrance_tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
	if not entrance_tile_read.ok:
		return entrance_tile_read
	var entrance_tile: Vector2i = entrance_tile_read.value
	if route[0] != entrance_tile:
		return Result.failure("飞艇路线必须从餐厅所在板块出发")

	var visited := {}
	for i in range(route.size()):
		var pos: Vector2i = route[i]
		if not tiles_set.is_empty():
			if not tiles_set.has(pos):
				return Result.failure("route 板块不存在: %s" % str(pos))
		else:
			if pos.x < min_tile.x or pos.x > max_tile.x or pos.y < min_tile.y or pos.y > max_tile.y:
				return Result.failure("route 越界: %s" % str(pos))
		if i > 0:
			var prev: Vector2i = route[i - 1]
			if not MapUtils.are_adjacent(prev, pos):
				return Result.failure("飞艇路线必须按四向相邻板块移动: %s -> %s" % [str(prev), str(pos)])
		if i >= 2 and route[i] == route[i - 2]:
			return Result.failure("不允许U型转弯")
		if visited.has(pos):
			return Result.failure("不允许重复板块: %s" % str(pos))
		visited[pos] = true

	if route.size() > max_steps:
		return Result.failure("超出飞艇范围: tiles=%d > %d" % [route.size(), max_steps])

	return Result.success()

static func validate_road_route(
	state: GameState,
	restaurants: Dictionary,
	restaurant_id: String,
	entrance_pos: Vector2i,
	route: Array[Vector2i],
	max_distance: int
) -> Result:
	if not restaurants.has(restaurant_id):
		return Result.failure("餐厅不存在: %s" % restaurant_id)

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	var start_candidates_result := RangeUtilsClass.get_adjacent_road_cells(state, entrance_pos)
	if not start_candidates_result.ok:
		return start_candidates_result
	var start_candidates: Array[Vector2i] = start_candidates_result.value
	if start_candidates.is_empty():
		return Result.failure("餐厅入口未邻接道路")
	if not start_candidates.has(route[0]):
		return Result.failure("卡车路线必须从餐厅入口邻接道路出发")

	for i in range(route.size()):
		var pos: Vector2i = route[i]
		if not CoordsClass.is_world_pos_in_grid(state, pos):
			return Result.failure("route 越界: %s" % str(pos))
		if not CellsClass.has_road_at(state, pos):
			return Result.failure("卡车路线必须沿道路移动: %s" % str(pos))
		if i > 0:
			var prev: Vector2i = route[i - 1]
			var neighbors: Array[Vector2i] = road_graph.get_reachable_neighbors(prev)
			if not neighbors.has(pos):
				return Result.failure("卡车路线不连通: %s -> %s" % [str(prev), str(pos)])
		if i >= 2 and route[i] == route[i - 2]:
			return Result.failure("不允许U型转弯")

	var boundary_crossings := 0
	for i in range(1, route.size()):
		if MapUtils.crosses_tile_boundary(route[i - 1], route[i]):
			boundary_crossings += 1
	if boundary_crossings > max_distance:
		return Result.failure("超出卡车范围: %d > %d" % [boundary_crossings, max_distance])

	return Result.success()
