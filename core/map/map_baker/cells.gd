extends RefCounted

static func create_empty_cells(grid_size: Vector2i) -> Array:
	var cells := []
	for y in grid_size.y:
		var row := []
		for x in grid_size.x:
			row.append(create_empty_cell())
		cells.append(row)
	return cells

static func create_empty_cell() -> Dictionary:
	return {
		"road_segments": [],     # 道路段数组
		"structure": {},         # 建筑物信息
		"terrain_type": null,    # 地形类型
		"drink_source": null,    # 饮品源
		"tile_origin": Vector2i(-1, -1),  # 所属板块
		"blocked": false         # 是否被阻塞
	}

