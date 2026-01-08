extends RefCounted

static func build_boundary_index(tile_grid_size: Vector2i) -> Dictionary:
	# 构建板块边界的快速查找索引
	# 用于在路径计算时快速判断是否跨越边界

	var horizontal_boundaries := []  # y 坐标为板块边界
	var vertical_boundaries := []    # x 坐标为板块边界

	for i in range(1, tile_grid_size.y):
		horizontal_boundaries.append(i * TileDef.TILE_SIZE)

	for i in range(1, tile_grid_size.x):
		vertical_boundaries.append(i * TileDef.TILE_SIZE)

	return {
		"horizontal": horizontal_boundaries,
		"vertical": vertical_boundaries,
		"tile_size": TileDef.TILE_SIZE
	}

