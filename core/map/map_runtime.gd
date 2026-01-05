# 地图运行时工具（Fail Fast）
# 负责：将 MapBaker 的 baked 数据写入 GameState.map，并提供 RoadGraph 缓存与常用查询。
class_name MapRuntime
extends RefCounted

const MapBakerClass = preload("res://core/map/map_baker.gd")
const RoadGraphClass = preload("res://core/map/road_graph.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"
const _EXTERNAL_TILE_PLACEMENTS_KEY := "external_tile_placements"
const _MAP_ORIGIN_KEY := "map_origin"

static func apply_baked_map(state, baked_data: Dictionary) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not (baked_data is Dictionary):
		return Result.failure("baked_data 类型错误（期望 Dictionary）")

	if not baked_data.has("cells") or not (baked_data["cells"] is Array):
		return Result.failure("baked_data.cells 缺失或类型错误（期望 Array）")
	var cells: Array = baked_data["cells"]
	if cells.is_empty():
		return Result.failure("baked_data.cells 不能为空")

	if not baked_data.has("grid_size") or not (baked_data["grid_size"] is Vector2i):
		return Result.failure("baked_data.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = baked_data["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("baked_data.grid_size 非法: %s" % str(grid_size))
	if cells.size() != grid_size.y:
		return Result.failure("baked_data.cells 行数与 grid_size.y 不匹配: %d != %d" % [cells.size(), grid_size.y])
	for y in range(grid_size.y):
		var row_val = cells[y]
		if not (row_val is Array):
			return Result.failure("baked_data.cells[%d] 类型错误（期望 Array）" % y)
		var row: Array = row_val
		if row.size() != grid_size.x:
			return Result.failure("baked_data.cells[%d] 长度与 grid_size.x 不匹配: %d != %d" % [y, row.size(), grid_size.x])
		for x in range(grid_size.x):
			if not (row[x] is Dictionary):
				return Result.failure("baked_data.cells[%d][%d] 类型错误（期望 Dictionary）" % [y, x])

	if not baked_data.has("tile_placements") or not (baked_data["tile_placements"] is Array):
		return Result.failure("baked_data.tile_placements 缺失或类型错误（期望 Array）")
	var tile_placements: Array = baked_data["tile_placements"]
	for i in range(tile_placements.size()):
		var tp_val = tile_placements[i]
		if not (tp_val is Dictionary):
			return Result.failure("baked_data.tile_placements[%d] 类型错误（期望 Dictionary）" % i)
		var tp: Dictionary = tp_val
		for k in ["tile_id", "board_pos", "rotation"]:
			if not tp.has(k):
				return Result.failure("baked_data.tile_placements[%d] 缺少字段: %s" % [i, k])
		if not (tp["tile_id"] is String) or str(tp["tile_id"]).is_empty():
			return Result.failure("baked_data.tile_placements[%d].tile_id 类型错误或为空（期望非空 String）" % i)
		if not (tp["board_pos"] is Vector2i):
			return Result.failure("baked_data.tile_placements[%d].board_pos 类型错误（期望 Vector2i）" % i)
		if not (tp["rotation"] is int):
			return Result.failure("baked_data.tile_placements[%d].rotation 类型错误（期望 int）" % i)

	if not baked_data.has("houses") or not (baked_data["houses"] is Dictionary):
		return Result.failure("baked_data.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = baked_data["houses"]

	if not baked_data.has("restaurants") or not (baked_data["restaurants"] is Dictionary):
		return Result.failure("baked_data.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = baked_data["restaurants"]

	if not baked_data.has("drink_sources") or not (baked_data["drink_sources"] is Array):
		return Result.failure("baked_data.drink_sources 缺失或类型错误（期望 Array）")
	var drink_sources: Array = baked_data["drink_sources"]

	if not baked_data.has("boundary_index") or not (baked_data["boundary_index"] is Dictionary):
		return Result.failure("baked_data.boundary_index 缺失或类型错误（期望 Dictionary）")
	var boundary_index: Dictionary = baked_data["boundary_index"]

	if not baked_data.has("next_house_number"):
		return Result.failure("baked_data.next_house_number 缺失")
	var next_house_read := _parse_non_negative_int(baked_data["next_house_number"], "baked_data.next_house_number")
	if not next_house_read.ok:
		return next_house_read
	var next_house_number: int = int(next_house_read.value)
	if next_house_number <= 0:
		return Result.failure("baked_data.next_house_number 必须 > 0")

	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return Result.failure("MapUtils.TILE_SIZE 非法: %d" % tile_size)
	if grid_size.x % tile_size != 0 or grid_size.y % tile_size != 0:
		return Result.failure("grid_size 必须可被 TILE_SIZE 整除: %s (tile=%d)" % [str(grid_size), tile_size])
	var tile_grid_size := Vector2i(grid_size.x / tile_size, grid_size.y / tile_size)

	state.map["cells"] = cells
	state.map["grid_size"] = grid_size
	state.map["tile_grid_size"] = tile_grid_size
	state.map["tile_placements"] = tile_placements
	state.map["houses"] = houses
	state.map["restaurants"] = restaurants
	state.map["drink_sources"] = drink_sources
	state.map["boundary_index"] = boundary_index
	state.map["next_house_number"] = next_house_number
	state.map["next_restaurant_id"] = 1
	state.map[_MAP_ORIGIN_KEY] = Vector2i.ZERO
	state.map["marketing_placements"] = {}
	state.map[_EXTERNAL_CELLS_KEY] = {}
	state.map[_EXTERNAL_TILE_PLACEMENTS_KEY] = []

	# RoadGraph 是运行时派生缓存，必须失效
	invalidate_road_graph(state)

	return Result.success()

static func get_road_graph(state) -> RefCounted:
	assert(state != null, "MapRuntime.get_road_graph: state 为空")
	if state._road_graph == null:
		assert(state.map is Dictionary, "MapRuntime.get_road_graph: state.map 类型错误（期望 Dictionary）")
		assert(state.map.has("cells") and (state.map["cells"] is Array), "MapRuntime.get_road_graph: state.map.cells 缺失或类型错误（期望 Array）")
		assert(state.map.has("grid_size") and (state.map["grid_size"] is Vector2i), "MapRuntime.get_road_graph: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
		var cells: Array = state.map["cells"]
		assert(not cells.is_empty(), "MapRuntime.get_road_graph: state.map.cells 不能为空")
		var grid_size: Vector2i = state.map["grid_size"]
		assert(state.map.has("boundary_index") and (state.map["boundary_index"] is Dictionary), "MapRuntime.get_road_graph: state.map.boundary_index 缺失或类型错误（期望 Dictionary）")
		var boundary_index: Dictionary = state.map["boundary_index"]
		var external_cells: Dictionary = {}
		if state.map.has(_EXTERNAL_CELLS_KEY):
			assert(state.map[_EXTERNAL_CELLS_KEY] is Dictionary, "MapRuntime.get_road_graph: state.map.external_cells 类型错误（期望 Dictionary）")
			external_cells = state.map[_EXTERNAL_CELLS_KEY]
		var origin := get_map_origin(state)
		state._road_graph = RoadGraphClass.build_from_cells_with_external(cells, grid_size, origin, external_cells, boundary_index)
	return state._road_graph

static func invalidate_road_graph(state) -> void:
	assert(state != null, "MapRuntime.invalidate_road_graph: state 为空")
	state._road_graph = null

static func get_map_origin(state) -> Vector2i:
	assert(state != null, "MapRuntime.get_map_origin: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_map_origin: state.map 类型错误（期望 Dictionary）")
	if state.map.has(_MAP_ORIGIN_KEY) and (state.map[_MAP_ORIGIN_KEY] is Vector2i):
		return state.map[_MAP_ORIGIN_KEY]
	return Vector2i.ZERO

static func set_map_origin(state, origin: Vector2i) -> void:
	assert(state != null, "MapRuntime.set_map_origin: state 为空")
	assert(state.map is Dictionary, "MapRuntime.set_map_origin: state.map 类型错误（期望 Dictionary）")
	state.map[_MAP_ORIGIN_KEY] = origin

static func world_to_index(state, world_pos: Vector2i) -> Vector2i:
	return world_pos + get_map_origin(state)

static func index_to_world(state, index_pos: Vector2i) -> Vector2i:
	return index_pos - get_map_origin(state)

static func get_world_min(state) -> Vector2i:
	assert(state != null, "MapRuntime.get_world_min: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_world_min: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("grid_size") and (state.map["grid_size"] is Vector2i), "MapRuntime.get_world_min: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var origin := get_map_origin(state)
	return -origin

static func get_world_max(state) -> Vector2i:
	assert(state != null, "MapRuntime.get_world_max: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_world_max: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("grid_size") and (state.map["grid_size"] is Vector2i), "MapRuntime.get_world_max: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	var origin := get_map_origin(state)
	return Vector2i(grid_size.x - origin.x - 1, grid_size.y - origin.y - 1)

static func is_world_pos_in_grid(state, world_pos: Vector2i) -> bool:
	assert(state != null, "MapRuntime.is_world_pos_in_grid: state 为空")
	assert(state.map is Dictionary, "MapRuntime.is_world_pos_in_grid: state.map 类型错误（期望 Dictionary）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return false
	var grid_size: Vector2i = state.map["grid_size"]
	var idx := world_to_index(state, world_pos)
	return idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y

static func is_on_map_edge(state, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if not is_world_pos_in_grid(state, world_pos):
		return false
	var minp := get_world_min(state)
	var maxp := get_world_max(state)
	return world_pos.x == minp.x or world_pos.y == minp.y or world_pos.x == maxp.x or world_pos.y == maxp.y

static func get_cell(state, pos: Vector2i) -> Dictionary:
	assert(state != null, "MapRuntime.get_cell: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_cell: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("grid_size") and (state.map["grid_size"] is Vector2i), "MapRuntime.get_cell: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	assert(grid_size.x > 0 and grid_size.y > 0, "MapRuntime.get_cell: state.map.grid_size 非法: %s" % str(grid_size))
	var idx := world_to_index(state, pos)
	assert(idx.x >= 0 and idx.x < grid_size.x and idx.y >= 0 and idx.y < grid_size.y, "MapRuntime.get_cell: pos 越界: %s (grid=%s origin=%s)" % [str(pos), str(grid_size), str(get_map_origin(state))])

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
	if is_world_pos_in_grid(state, pos):
		return true
	if state.map.has(_EXTERNAL_CELLS_KEY) and (state.map[_EXTERNAL_CELLS_KEY] is Dictionary):
		var external_cells: Dictionary = state.map[_EXTERNAL_CELLS_KEY]
		return external_cells.has(_pos_key(pos))
	return false

static func get_cell_any(state, pos: Vector2i) -> Dictionary:
	assert(state != null, "MapRuntime.get_cell_any: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_cell_any: state.map 类型错误（期望 Dictionary）")
	if is_world_pos_in_grid(state, pos):
		return get_cell(state, pos)
	assert(state.map.has(_EXTERNAL_CELLS_KEY) and (state.map[_EXTERNAL_CELLS_KEY] is Dictionary), "MapRuntime.get_cell_any: state.map.external_cells 缺失或类型错误（期望 Dictionary）")
	var external_cells: Dictionary = state.map[_EXTERNAL_CELLS_KEY]
	var key := _pos_key(pos)
	assert(external_cells.has(key), "MapRuntime.get_cell_any: external_cells 不存在 pos: %s" % str(pos))
	var cell_val = external_cells[key]
	assert(cell_val is Dictionary, "MapRuntime.get_cell_any: external_cells[%s] 类型错误（期望 Dictionary）" % key)
	return cell_val

static func _pos_key(pos: Vector2i) -> String:
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

static func add_map_tile(
	state,
	tile_def: TileDef,
	piece_registry: Dictionary,
	board_pos: Vector2i,
	rotation: int
) -> Result:
	if state == null:
		return Result.failure("MapRuntime.add_map_tile: state 为空")
	if tile_def == null:
		return Result.failure("MapRuntime.add_map_tile: tile_def 为空")
	if not (state.map is Dictionary):
		return Result.failure("MapRuntime.add_map_tile: state.map 类型错误（期望 Dictionary）")
	if not (piece_registry is Dictionary):
		return Result.failure("MapRuntime.add_map_tile: piece_registry 类型错误（期望 Dictionary）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MapRuntime.add_map_tile: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MapRuntime.add_map_tile: state.map.cells 缺失或类型错误（期望 Array）")
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("MapRuntime.add_map_tile: state.map.houses 缺失或类型错误（期望 Dictionary）")
	if not state.map.has("drink_sources") or not (state.map["drink_sources"] is Array):
		return Result.failure("MapRuntime.add_map_tile: state.map.drink_sources 缺失或类型错误（期望 Array）")
	if not state.map.has("next_house_number"):
		return Result.failure("MapRuntime.add_map_tile: state.map.next_house_number 缺失")
	if not state.map.has(_EXTERNAL_TILE_PLACEMENTS_KEY) or not (state.map[_EXTERNAL_TILE_PLACEMENTS_KEY] is Array):
		return Result.failure("MapRuntime.add_map_tile: state.map.external_tile_placements 缺失或类型错误（期望 Array）")

	var tile_size := int(MapUtils.TILE_SIZE)
	var tile_world_min := board_pos * tile_size
	var tile_world_max := tile_world_min + Vector2i(tile_size - 1, tile_size - 1)

	var current_min := get_world_min(state)
	var current_max := get_world_max(state)
	var desired_min := Vector2i(min(current_min.x, tile_world_min.x), min(current_min.y, tile_world_min.y))
	var desired_max := Vector2i(max(current_max.x, tile_world_max.x), max(current_max.y, tile_world_max.y))

	var ensure := ensure_world_rect(state, desired_min, desired_max)
	if not ensure.ok:
		return ensure

	var grid_size: Vector2i = state.map["grid_size"]
	var origin := get_map_origin(state)
	var houses: Dictionary = state.map["houses"]
	var drink_sources: Array = state.map["drink_sources"]
	var cells: Array = state.map["cells"]

	var bake := MapBakerClass.bake_tile_into_cells(
		cells, grid_size, origin, tile_def, board_pos, rotation, piece_registry, houses, drink_sources
	)
	if not bake.ok:
		return bake

	state.map["cells"] = cells
	state.map["houses"] = houses
	state.map["drink_sources"] = drink_sources

	assert(bake.value is Dictionary and bake.value.has("max_house_number"), "MapRuntime.add_map_tile: bake.value 缺少 max_house_number")
	var max_house_number: int = int(bake.value["max_house_number"])
	var next_house_number: int = int(state.map["next_house_number"])
	state.map["next_house_number"] = max(next_house_number, max_house_number + 1)

	var placements: Array = state.map[_EXTERNAL_TILE_PLACEMENTS_KEY]
	placements.append({
		"tile_id": str(tile_def.id),
		"board_pos": board_pos,
		"rotation": rotation,
	})
	state.map[_EXTERNAL_TILE_PLACEMENTS_KEY] = placements

	invalidate_road_graph(state)
	return Result.success()

static func ensure_world_rect(state, desired_min: Vector2i, desired_max: Vector2i) -> Result:
	if state == null:
		return Result.failure("MapRuntime.ensure_world_rect: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("MapRuntime.ensure_world_rect: state.map 类型错误（期望 Dictionary）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MapRuntime.ensure_world_rect: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MapRuntime.ensure_world_rect: state.map.cells 缺失或类型错误（期望 Array）")

	var old_grid: Vector2i = state.map["grid_size"]
	var old_origin := get_map_origin(state)
	var old_cells: Array = state.map["cells"]

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
		assert(row_val is Array, "MapRuntime.ensure_world_rect: old_cells[%d] 类型错误（期望 Array）" % y)
		var row: Array = row_val
		assert(row.size() == old_grid.x, "MapRuntime.ensure_world_rect: old_cells[%d] 长度不匹配" % y)
		for x in range(old_grid.x):
			new_cells[y + shift.y][x + shift.x] = row[x]

	state.map["cells"] = new_cells
	state.map["grid_size"] = new_grid
	state.map["tile_grid_size"] = Vector2i(new_grid.x / tile_size, new_grid.y / tile_size)
	state.map["boundary_index"] = _build_boundary_index(state.map["tile_grid_size"])
	set_map_origin(state, new_origin)

	invalidate_road_graph(state)
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

static func get_house(state, house_id: String) -> Dictionary:
	assert(state != null, "MapRuntime.get_house: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_house: state.map 类型错误（期望 Dictionary）")
	assert(not house_id.is_empty(), "MapRuntime.get_house: house_id 不能为空")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MapRuntime.get_house: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	assert(houses.has(house_id), "MapRuntime.get_house: house_id 不存在: %s" % house_id)
	var h_val = houses[house_id]
	assert(h_val is Dictionary, "MapRuntime.get_house: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	return h_val

static func get_restaurant(state, restaurant_id: String) -> Dictionary:
	assert(state != null, "MapRuntime.get_restaurant: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_restaurant: state.map 类型错误（期望 Dictionary）")
	assert(not restaurant_id.is_empty(), "MapRuntime.get_restaurant: restaurant_id 不能为空")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "MapRuntime.get_restaurant: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	assert(restaurants.has(restaurant_id), "MapRuntime.get_restaurant: restaurant_id 不存在: %s" % restaurant_id)
	var r_val = restaurants[restaurant_id]
	assert(r_val is Dictionary, "MapRuntime.get_restaurant: restaurants[%s] 类型错误（期望 Dictionary）" % restaurant_id)
	return r_val

static func get_player_restaurants(state, player_id: int) -> Array[String]:
	assert(state != null, "MapRuntime.get_player_restaurants: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_player_restaurants: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "MapRuntime.get_player_restaurants: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	var result: Array[String] = []
	for rest_id in restaurants:
		assert(rest_id is String, "MapRuntime.get_player_restaurants: restaurants key 类型错误（期望 String）")
		var rid: String = str(rest_id)
		var rest_val = restaurants[rest_id]
		assert(rest_val is Dictionary, "MapRuntime.get_player_restaurants: restaurants[%s] 类型错误（期望 Dictionary）" % rid)
		var rest: Dictionary = rest_val
		assert(rest.has("owner") and (rest["owner"] is int), "MapRuntime.get_player_restaurants: restaurants[%s].owner 缺失或类型错误（期望 int）" % rid)
		if int(rest["owner"]) == player_id:
			result.append(rid)
	result.sort()
	return result

static func get_sorted_house_ids(state) -> Array[String]:
	assert(state != null, "MapRuntime.get_sorted_house_ids: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_sorted_house_ids: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MapRuntime.get_sorted_house_ids: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	return HouseNumberManagerClass.get_sorted_house_ids(houses)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 不能为负数: %d" % [path, int(r.value)])
	return r
