extends RefCounted

const TileBakingClass = preload("res://core/map/map_baker/tile_baking.gd")
const Coords = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCache = preload("res://core/map/map_runtime/road_graph_cache.gd")

const _EXTERNAL_TILE_PLACEMENTS_KEY := "external_tile_placements"

static func _require_state_map_dict(state, prefix: String) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % prefix)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % prefix)
	return Result.success(state.map)

static func _require_map_vec2i(map: Dictionary, key: String, path: String) -> Result:
	if not map.has(key) or not (map[key] is Vector2i):
		return Result.failure("%s 缺失或类型错误（期望 Vector2i）" % path)
	return Result.success(map[key])

static func _require_map_array(map: Dictionary, key: String, path: String) -> Result:
	if not map.has(key) or not (map[key] is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array）" % path)
	return Result.success(map[key])

static func _require_map_dict_field(map: Dictionary, key: String, path: String) -> Result:
	if not map.has(key) or not (map[key] is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	return Result.success(map[key])

static func add_map_tile(
	state,
	tile_def: TileDef,
	piece_registry: Dictionary,
	board_pos: Vector2i,
	rotation: int
) -> Result:
	var prefix := "MapRuntime.add_map_tile"
	if state == null:
		return Result.failure("%s: state 为空" % prefix)
	if tile_def == null:
		return Result.failure("%s: tile_def 为空" % prefix)

	var map_read := _require_state_map_dict(state, prefix)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	if not (piece_registry is Dictionary):
		return Result.failure("%s: piece_registry 类型错误（期望 Dictionary）" % prefix)

	var grid_read := _require_map_vec2i(map, "grid_size", "%s: state.map.grid_size" % prefix)
	if not grid_read.ok:
		return grid_read
	var grid_size: Vector2i = grid_read.value

	var cells_read := _require_map_array(map, "cells", "%s: state.map.cells" % prefix)
	if not cells_read.ok:
		return cells_read
	var cells: Array = cells_read.value

	var houses_read := _require_map_dict_field(map, "houses", "%s: state.map.houses" % prefix)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value

	var drink_sources_read := _require_map_array(map, "drink_sources", "%s: state.map.drink_sources" % prefix)
	if not drink_sources_read.ok:
		return drink_sources_read
	var drink_sources: Array = drink_sources_read.value

	if not map.has("next_house_number"):
		return Result.failure("%s: state.map.next_house_number 缺失" % prefix)

	var ext_read := _require_map_array(map, _EXTERNAL_TILE_PLACEMENTS_KEY, "%s: state.map.external_tile_placements" % prefix)
	if not ext_read.ok:
		return ext_read

	var tile_size := int(MapUtils.TILE_SIZE)
	var tile_world_min := board_pos * tile_size
	var tile_world_max := tile_world_min + Vector2i(tile_size - 1, tile_size - 1)

	var current_min := Coords.get_world_min(state)
	var current_max := Coords.get_world_max(state)
	var desired_min := Vector2i(min(current_min.x, tile_world_min.x), min(current_min.y, tile_world_min.y))
	var desired_max := Vector2i(max(current_max.x, tile_world_max.x), max(current_max.y, tile_world_max.y))

	var ensure := ensure_world_rect(state, desired_min, desired_max)
	if not ensure.ok:
		return ensure

	var origin := Coords.get_map_origin(state)
	# ensure_world_rect 可能会替换 cells/grid_size（扩边时必然如此）；这里必须重新读取。
	var grid_read2 := _require_map_vec2i(map, "grid_size", "%s: state.map.grid_size" % prefix)
	if not grid_read2.ok:
		return grid_read2
	grid_size = grid_read2.value
	var cells_read2 := _require_map_array(map, "cells", "%s: state.map.cells" % prefix)
	if not cells_read2.ok:
		return cells_read2
	cells = cells_read2.value

	var bake := TileBakingClass.bake_tile_into_cells(
		cells, grid_size, origin, tile_def, board_pos, rotation, piece_registry, houses, drink_sources
	)
	if not bake.ok:
		return bake

	state.map["cells"] = cells
	state.map["houses"] = houses
	state.map["drink_sources"] = drink_sources

	if not (bake.value is Dictionary) or not (bake.value as Dictionary).has("max_house_number"):
		return Result.failure("MapRuntime.add_map_tile: bake.value 缺少 max_house_number")
	var max_house_number: int = int((bake.value as Dictionary)["max_house_number"])
	var next_house_number: int = int(state.map["next_house_number"])
	state.map["next_house_number"] = max(next_house_number, max_house_number + 1)

	var placements: Array = state.map[_EXTERNAL_TILE_PLACEMENTS_KEY]
	placements.append({
		"tile_id": str(tile_def.id),
		"board_pos": board_pos,
		"rotation": rotation,
	})
	state.map[_EXTERNAL_TILE_PLACEMENTS_KEY] = placements

	RoadGraphCache.invalidate_road_graph(state)
	return Result.success()

static func ensure_world_rect(state, desired_min: Vector2i, desired_max: Vector2i) -> Result:
	var prefix := "MapRuntime.ensure_world_rect"
	var map_read := _require_state_map_dict(state, prefix)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	var grid_read := _require_map_vec2i(map, "grid_size", "%s: state.map.grid_size" % prefix)
	if not grid_read.ok:
		return grid_read

	var cells_read := _require_map_array(map, "cells", "%s: state.map.cells" % prefix)
	if not cells_read.ok:
		return cells_read

	var old_grid: Vector2i = grid_read.value
	var old_origin := Coords.get_map_origin(state)
	var old_cells: Array = cells_read.value

	var old_min := -old_origin
	var old_max := Vector2i(old_grid.x - old_origin.x - 1, old_grid.y - old_origin.y - 1)

	var new_min := Vector2i(min(old_min.x, desired_min.x), min(old_min.y, desired_min.y))
	var new_max := Vector2i(max(old_max.x, desired_max.x), max(old_max.y, desired_max.y))
	if new_min == old_min and new_max == old_max:
		return Result.success()

	var new_origin := -new_min
	var new_grid := new_max - new_min + Vector2i.ONE
	if new_grid.x <= 0 or new_grid.y <= 0:
		return Result.failure("MapRuntime.ensure_world_rect: new_grid 非法: %s" % str(new_grid))

	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return Result.failure("MapRuntime.ensure_world_rect: TILE_SIZE 非法: %d" % tile_size)
	if new_grid.x % tile_size != 0 or new_grid.y % tile_size != 0:
		return Result.failure("MapRuntime.ensure_world_rect: new_grid 必须可被 TILE_SIZE 整除: %s (tile=%d)" % [str(new_grid), tile_size])

	var shift := new_origin - old_origin
	if shift.x < 0 or shift.y < 0:
		return Result.failure("MapRuntime.ensure_world_rect: 内部错误：shift 不能为负: %s" % str(shift))

	var new_cells := _create_void_cells(new_grid)
	for y in range(old_grid.y):
		var row_val = old_cells[y]
		if not (row_val is Array):
			return Result.failure("MapRuntime.ensure_world_rect: old_cells[%d] 类型错误（期望 Array）" % y)
		var row: Array = row_val
		if row.size() != old_grid.x:
			return Result.failure("MapRuntime.ensure_world_rect: old_cells[%d] 长度不匹配" % y)
		for x in range(old_grid.x):
			new_cells[y + shift.y][x + shift.x] = row[x]

	state.map["cells"] = new_cells
	state.map["grid_size"] = new_grid
	state.map["tile_grid_size"] = Vector2i(new_grid.x / tile_size, new_grid.y / tile_size)
	state.map["boundary_index"] = _build_boundary_index(state.map["tile_grid_size"])
	Coords.set_map_origin(state, new_origin)

	RoadGraphCache.invalidate_road_graph(state)
	return Result.success()

static func _create_void_cells(grid_size: Vector2i) -> Array:
	var cells := []
	for y in grid_size.y:
		var row := []
		for x in grid_size.x:
			row.append(_create_void_cell())
		cells.append(row)
	return cells

static func _create_void_cell() -> Dictionary:
	return {
		"road_segments": [],
		"structure": {},
		"terrain_type": null,
		"drink_source": null,
		"tile_origin": Vector2i(-1, -1),
		"blocked": true
	}

static func _build_boundary_index(tile_grid_size: Vector2i) -> Dictionary:
	var horizontal_boundaries := []
	var vertical_boundaries := []
	for i in range(1, tile_grid_size.y):
		horizontal_boundaries.append(i * MapUtils.TILE_SIZE)
	for i in range(1, tile_grid_size.x):
		vertical_boundaries.append(i * MapUtils.TILE_SIZE)
	return {
		"horizontal": horizontal_boundaries,
		"vertical": vertical_boundaries,
		"tile_size": MapUtils.TILE_SIZE
	}
