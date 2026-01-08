extends RefCounted

# 计算街区区域 (用于 mailbox 营销)
static func calculate_block_regions(graph, cells: Array) -> void:
	graph._block_regions.clear()
	graph._cell_to_block.clear()

	var visited := {}
	var region_id := 0

	for y in graph._grid_size.y:
		for x in graph._grid_size.x:
			var pos := Vector2i(x - graph._map_origin.x, y - graph._map_origin.y)
			if visited.has(pos):
				continue

			var cell: Dictionary = cells[y][x]
			var has_road = not cell.get("road_segments", []).is_empty()
			var is_blocked := bool(cell.get("blocked", false))

			if has_road or is_blocked:
				visited[pos] = -1
				graph._cell_to_block[pos] = -1
			else:
				# 洪水填充非道路区域
				var region_cells := _flood_fill_block(graph, cells, pos, visited)
				graph._block_regions[region_id] = region_cells
				for cell_pos in region_cells:
					graph._cell_to_block[cell_pos] = region_id
				region_id += 1

static func _flood_fill_block(graph, cells: Array, start: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var region: Array[Vector2i] = []
	var queue := [start]

	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()

		if visited.has(pos):
			continue
		var idx = pos + graph._map_origin
		if idx.x < 0 or idx.y < 0 or idx.x >= graph._grid_size.x or idx.y >= graph._grid_size.y:
			continue

		var cell: Dictionary = cells[idx.y][idx.x]
		var has_road = not cell.get("road_segments", []).is_empty()
		var is_blocked := bool(cell.get("blocked", false))

		if has_road or is_blocked:
			visited[pos] = -1
			continue

		visited[pos] = true
		region.append(pos)

		# 检查四个方向的邻居
		for dir in MapUtils.DIRECTIONS:
			queue.append(MapUtils.get_neighbor_pos(pos, dir))

	return region

static func get_block_cells(graph, pos: Vector2i) -> Array[Vector2i]:
	var block_id: int = int(graph._cell_to_block.get(pos, -1))
	if block_id == -1:
		return []
	return graph._block_regions.get(block_id, [])

static func get_block_id(graph, pos: Vector2i) -> int:
	return int(graph._cell_to_block.get(pos, -1))

static func are_in_same_block(graph, pos1: Vector2i, pos2: Vector2i) -> bool:
	var block1 := get_block_id(graph, pos1)
	var block2 := get_block_id(graph, pos2)
	return block1 != -1 and block1 == block2
