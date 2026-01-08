# DinnertimeSettlement：路径/距离计算辅助
class_name DinnertimeDistance
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func get_restaurant_to_house_distance(
	road_graph,
	state: GameState,
	grid_size: Vector2i,
	restaurant_id: String,
	rest: Dictionary,
	house_id: String,
	house: Dictionary
) -> Result:
	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("晚餐结算失败：houses[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % house_id)
	var house_cells_any: Array = house["cells"]
	var house_cells: Array[Vector2i] = []
	for i in range(house_cells_any.size()):
		var v = house_cells_any[i]
		if not (v is Vector2i):
			return Result.failure("晚餐结算失败：houses[%s].cells[%d] 类型错误（期望 Vector2i）" % [house_id, i])
		house_cells.append(v)

	var house_roads := get_structure_adjacent_roads(state, grid_size, house_cells)
	if house_roads.is_empty():
		return Result.success({})

	var entrance_points_read := get_restaurant_entrance_points(state, restaurant_id, rest)
	if not entrance_points_read.ok:
		return entrance_points_read
	var entrance_points_any: Array = entrance_points_read.value
	var entrance_points: Array[Vector2i] = []
	for i in range(entrance_points_any.size()):
		var p = entrance_points_any[i]
		if not (p is Vector2i):
			return Result.failure("晚餐结算失败：restaurants[%s] entrance_points[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		entrance_points.append(p)

	var rest_roads := get_structure_adjacent_roads(state, grid_size, entrance_points)
	if rest_roads.is_empty():
		return Result.success({})

	var best_distance := INF
	var best_steps := INF
	var best_path: Array[Vector2i] = []
	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok:
				continue
			assert(sp.value is Dictionary, "RoadGraph.find_shortest_path: value 类型错误（期望 Dictionary）")
			var sp_val: Dictionary = sp.value
			assert(sp_val.has("distance") and sp_val["distance"] is int, "RoadGraph.find_shortest_path: 缺少/错误 distance（期望 int）")
			assert(sp_val.has("steps") and sp_val["steps"] is int, "RoadGraph.find_shortest_path: 缺少/错误 steps（期望 int）")
			assert(sp_val.has("path") and sp_val["path"] is Array, "RoadGraph.find_shortest_path: 缺少/错误 path（期望 Array）")
			var d: int = int(sp_val["distance"])
			var steps: int = int(sp_val["steps"])
			var path_any: Array = sp_val["path"]
			var path: Array[Vector2i] = []
			for i in range(path_any.size()):
				var p = path_any[i]
				if not (p is Vector2i):
					return Result.failure("RoadGraph.find_shortest_path: path[%d] 类型错误（期望 Vector2i）" % i)
				path.append(p)
			if d < best_distance or (d == best_distance and steps < best_steps):
				best_distance = d
				best_steps = steps
				best_path = path

	if best_distance == INF:
		return Result.success({})
	return Result.success({
		"distance": int(best_distance),
		"steps": int(best_steps),
		"path": best_path,
	})

static func get_restaurant_entrance_points(state: GameState, restaurant_id: String, rest: Dictionary) -> Result:
	if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
		return Result.failure("晚餐结算失败：restaurants[%s].entrance_pos 缺失或类型错误（期望 Vector2i）" % restaurant_id)
	var entrance: Vector2i = rest["entrance_pos"]

	if not rest.has("owner") or not (rest["owner"] is int):
		return Result.failure("晚餐结算失败：restaurants[%s].owner 缺失或类型错误（期望 int）" % restaurant_id)
	var owner: int = int(rest["owner"])
	if owner < 0 or owner >= state.players.size():
		return Result.success([entrance])

	# 免下车：四角都视为入口（本回合）
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	var drive_thru_active := false
	if player.has("drive_thru_active"):
		var v = player["drive_thru_active"]
		if not (v is bool):
			return Result.failure("晚餐结算失败：player[%d].drive_thru_active 类型错误（期望 bool）" % owner)
		drive_thru_active = bool(v)
	if not drive_thru_active:
		return Result.success([entrance])

	if not rest.has("cells") or not (rest["cells"] is Array):
		return Result.failure("晚餐结算失败：restaurants[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % restaurant_id)
	var cells_any: Array = rest["cells"]
	if cells_any.is_empty():
		return Result.success([entrance])
	var cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("晚餐结算失败：restaurants[%s].cells[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		cells.append(c)

	var bounds := MapUtils.get_footprint_bounds(cells)
	assert(bounds.has("min") and bounds["min"] is Vector2i, "MapUtils.get_footprint_bounds: 缺少/错误 min（期望 Vector2i）")
	assert(bounds.has("max") and bounds["max"] is Vector2i, "MapUtils.get_footprint_bounds: 缺少/错误 max（期望 Vector2i）")
	var min_pos: Vector2i = bounds["min"]
	var max_pos: Vector2i = bounds["max"]
	return Result.success([
		Vector2i(min_pos.x, min_pos.y),
		Vector2i(max_pos.x, min_pos.y),
		Vector2i(min_pos.x, max_pos.y),
		Vector2i(max_pos.x, max_pos.y),
	])

static func get_structure_adjacent_roads(state: GameState, grid_size: Vector2i, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		# 若结构自身在道路格上（例如棋盘外道路入口），也应视为入口道路。
		if MapRuntimeClass.has_cell_any(state, cell) and MapRuntimeClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtils.DIRECTIONS:
			var n := MapUtils.get_neighbor_pos(cell, dir)
			if not MapRuntimeClass.has_cell_any(state, n):
				continue
			if MapRuntimeClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(k)
	return result
