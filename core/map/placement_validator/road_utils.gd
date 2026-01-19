extends RefCounted

# 检查位置是否邻接道路
static func is_adjacent_to_road(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(pos, dir)
		if not MapUtils.is_valid_pos(neighbor, grid_size):
			continue

		var cell_val = cells[neighbor.y][neighbor.x]
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		var rs_val = cell.get("road_segments", null)
		if not (rs_val is Array):
			continue
		var road_segments: Array = rs_val
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
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var rs_val = cell.get("road_segments", null)
			if not (rs_val is Array):
				continue
			var road_segments: Array = rs_val

			if not road_segments.is_empty() and not road_cells.has(neighbor):
				road_cells.append(neighbor)

	return road_cells
