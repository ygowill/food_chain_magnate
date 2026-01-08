extends RefCounted

const Coords = preload("res://core/map/map_runtime/coords.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"

static func get_cell(state, pos: Vector2i) -> Dictionary:
	assert(state != null, "MapRuntime.get_cell: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_cell: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("grid_size") and (state.map["grid_size"] is Vector2i), "MapRuntime.get_cell: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	assert(grid_size.x > 0 and grid_size.y > 0, "MapRuntime.get_cell: state.map.grid_size 非法: %s" % str(grid_size))
	var idx := Coords.world_to_index(state, pos)
	assert(idx.x >= 0 and idx.x < grid_size.x and idx.y >= 0 and idx.y < grid_size.y, "MapRuntime.get_cell: pos 越界: %s (grid=%s origin=%s)" % [str(pos), str(grid_size), str(Coords.get_map_origin(state))])

	assert(state.map.has("cells") and (state.map["cells"] is Array), "MapRuntime.get_cell: state.map.cells 缺失或类型错误（期望 Array）")
	var cells: Array = state.map["cells"]
	assert(cells.size() == grid_size.y, "MapRuntime.get_cell: state.map.cells 行数不匹配: %d != %d" % [cells.size(), grid_size.y])
	var row_val = cells[idx.y]
	assert(row_val is Array, "MapRuntime.get_cell: state.map.cells[%d] 类型错误（期望 Array）" % idx.y)
	var row: Array = row_val
	assert(row.size() == grid_size.x, "MapRuntime.get_cell: state.map.cells[%d] 长度不匹配: %d != %d" % [idx.y, row.size(), grid_size.x])
	var cell_val = row[idx.x]
	assert(cell_val is Dictionary, "MapRuntime.get_cell: state.map.cells[%d][%d] 类型错误（期望 Dictionary）" % [idx.y, idx.x])
	return cell_val

static func has_cell_any(state, pos: Vector2i) -> bool:
	assert(state != null, "MapRuntime.has_cell_any: state 为空")
	assert(state.map is Dictionary, "MapRuntime.has_cell_any: state.map 类型错误（期望 Dictionary）")
	if Coords.is_world_pos_in_grid(state, pos):
		return true
	if state.map.has(_EXTERNAL_CELLS_KEY) and (state.map[_EXTERNAL_CELLS_KEY] is Dictionary):
		var external_cells: Dictionary = state.map[_EXTERNAL_CELLS_KEY]
		return external_cells.has(pos_key(pos))
	return false

static func get_cell_any(state, pos: Vector2i) -> Dictionary:
	assert(state != null, "MapRuntime.get_cell_any: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_cell_any: state.map 类型错误（期望 Dictionary）")
	if Coords.is_world_pos_in_grid(state, pos):
		return get_cell(state, pos)
	assert(state.map.has(_EXTERNAL_CELLS_KEY) and (state.map[_EXTERNAL_CELLS_KEY] is Dictionary), "MapRuntime.get_cell_any: state.map.external_cells 缺失或类型错误（期望 Dictionary）")
	var external_cells: Dictionary = state.map[_EXTERNAL_CELLS_KEY]
	var key := pos_key(pos)
	assert(external_cells.has(key), "MapRuntime.get_cell_any: external_cells 不存在 pos: %s" % str(pos))
	var cell_val = external_cells[key]
	assert(cell_val is Dictionary, "MapRuntime.get_cell_any: external_cells[%s] 类型错误（期望 Dictionary）" % key)
	return cell_val

static func pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func has_road_at(state, pos: Vector2i) -> bool:
	var cell := get_cell(state, pos)
	assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapRuntime.has_road_at: cell.road_segments 缺失或类型错误: %s" % str(pos))
	var segments: Array = cell["road_segments"]
	return not segments.is_empty()

static func has_road_at_any(state, pos: Vector2i) -> bool:
	if not has_cell_any(state, pos):
		return false
	var cell := get_cell_any(state, pos)
	assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapRuntime.has_road_at_any: cell.road_segments 缺失或类型错误: %s" % str(pos))
	var segments: Array = cell["road_segments"]
	return not segments.is_empty()

static func has_structure_at(state, pos: Vector2i) -> bool:
	var cell := get_cell(state, pos)
	assert(cell.has("structure") and (cell["structure"] is Dictionary), "MapRuntime.has_structure_at: cell.structure 缺失或类型错误: %s" % str(pos))
	var structure: Dictionary = cell["structure"]
	return not structure.is_empty()

