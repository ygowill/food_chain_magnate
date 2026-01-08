extends RefCounted

const RoadGraphCache = preload("res://core/map/map_runtime/road_graph_cache.gd")

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
	RoadGraphCache.invalidate_road_graph(state)

	return Result.success()

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

