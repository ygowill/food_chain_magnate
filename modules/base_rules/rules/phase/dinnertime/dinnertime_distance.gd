# DinnertimeSettlement：路径/距离计算辅助
class_name DinnertimeDistance
extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")

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

	# RoadGraph 的 distance 只统计“道路格 -> 道路格”移动时跨越的板块边界次数。
	# 但规则距离定义是“从餐厅入口到房屋服务边（相邻道路）”，因此：
	# - 若入口格与相邻道路格跨越板块边界，需要额外 +1。
	# - 若房屋格与相邻道路格跨越板块边界，需要额外 +1（终点板块计入）。
	var rest_entry_cost_by_road := _build_structure_to_road_boundary_cost(entrance_points, rest_roads)
	var house_entry_cost_by_road := _build_structure_to_road_boundary_cost(house_cells, house_roads)

	var best_distance := INF
	var best_steps := INF
	var best_path: Array[Vector2i] = []
	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok:
				continue
			if not (sp.value is Dictionary):
				return Result.failure("RoadGraph.find_shortest_path: value 类型错误（期望 Dictionary）")
			var sp_val: Dictionary = sp.value
			if not (sp_val.has("distance") and sp_val["distance"] is int):
				return Result.failure("RoadGraph.find_shortest_path: 缺少/错误 distance（期望 int）")
			if not (sp_val.has("steps") and sp_val["steps"] is int):
				return Result.failure("RoadGraph.find_shortest_path: 缺少/错误 steps（期望 int）")
			if not (sp_val.has("path") and sp_val["path"] is Array):
				return Result.failure("RoadGraph.find_shortest_path: 缺少/错误 path（期望 Array）")
			var d: int = int(sp_val["distance"])
			d += int(rest_entry_cost_by_road.get(s, 0))
			d += int(house_entry_cost_by_road.get(t, 0))
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

static func _build_structure_to_road_boundary_cost(
	structure_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> Dictionary:
	var out := {}
	for r in road_cells:
		var best := INF
		for c in structure_cells:
			if c == r:
				best = 0
				break
			if not MapUtils.are_adjacent(c, r):
				continue
			best = min(best, 1 if MapUtils.crosses_tile_boundary(c, r) else 0)
		if best == INF:
			# 理论上不会发生：road_cells 来源于 structure_cells 的相邻道路枚举。
			best = 0
		out[r] = int(best)
	return out

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
	if not (bounds.has("min") and bounds["min"] is Vector2i):
		return Result.failure("MapUtils.get_footprint_bounds: 缺少/错误 min（期望 Vector2i）")
	if not (bounds.has("max") and bounds["max"] is Vector2i):
		return Result.failure("MapUtils.get_footprint_bounds: 缺少/错误 max（期望 Vector2i）")
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
		if CellsClass.has_cell_any(state, cell) and CellsClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtils.DIRECTIONS:
			var n := MapUtils.get_neighbor_pos(cell, dir)
			if not CellsClass.has_cell_any(state, n):
				continue
			if CellsClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(k)
	return result
