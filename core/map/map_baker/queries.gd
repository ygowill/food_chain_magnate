extends RefCounted

# 获取指定世界坐标的格子
static func get_cell(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	assert(MapUtils.is_valid_pos(pos, grid_size), "MapBaker.get_cell: pos 越界: %s (grid=%s)" % [str(pos), str(grid_size)])
	var cell_val = cells[pos.y][pos.x]
	assert(cell_val is Dictionary, "MapBaker.get_cell: cells[%d][%d] 类型错误（期望 Dictionary）" % [pos.y, pos.x])
	return cell_val

# 获取指定位置的道路段
static func get_road_segments_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Array:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapBaker.get_road_segments_at: cell.road_segments 缺失或类型错误: %s" % str(pos))
	return cell["road_segments"]

# 检查位置是否有道路
static func has_road_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return not get_road_segments_at(cells, pos, grid_size).is_empty()

# 检查位置是否有建筑
static func has_structure_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("structure") and (cell["structure"] is Dictionary), "MapBaker.has_structure_at: cell.structure 缺失或类型错误: %s" % str(pos))
	var structure: Dictionary = cell["structure"]
	return not structure.is_empty()

# 检查位置是否被阻塞
static func is_blocked_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("blocked") and (cell["blocked"] is bool), "MapBaker.is_blocked_at: cell.blocked 缺失或类型错误: %s" % str(pos))
	return bool(cell["blocked"])

# 获取位置的饮品源
static func get_drink_source_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("drink_source"), "MapBaker.get_drink_source_at: cell.drink_source 缺失: %s" % str(pos))
	var source_val = cell["drink_source"]
	if source_val == null:
		return {}
	assert(source_val is Dictionary, "MapBaker.get_drink_source_at: cell.drink_source 类型错误（期望 Dictionary）: %s" % str(pos))
	return source_val

