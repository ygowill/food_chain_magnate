extends RefCounted

# 检查位置是否邻接道路
static func is_adjacent_to_road(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(pos, dir)
		if not MapUtils.is_valid_pos(neighbor, grid_size):
			continue

		var cell_val = cells[neighbor.y][neighbor.x]
		assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [neighbor.y, neighbor.x])
		var cell: Dictionary = cell_val
		assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return true

	return false

# 获取邻接的道路格子
static func get_adjacent_road_cells(cells: Array, positions: Array[Vector2i], grid_size: Vector2i) -> Array[Vector2i]:
	var road_cells: Array[Vector2i] = []
	var pos_set := {}
	for pos in positions:
		pos_set[pos] = true

	for pos in positions:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(pos, dir)
			if pos_set.has(neighbor):
				continue
			if not MapUtils.is_valid_pos(neighbor, grid_size):
				continue

			var cell_val = cells[neighbor.y][neighbor.x]
			assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [neighbor.y, neighbor.x])
			var cell: Dictionary = cell_val
			assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = cell["road_segments"]

			if not road_segments.is_empty() and not road_cells.has(neighbor):
				road_cells.append(neighbor)

	return road_cells

