extends RefCounted

const RoadGraphCache = preload("res://core/map/map_runtime/road_graph_cache.gd")
const MapParseHelpersClass = preload("res://core/map/parse_helpers.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"
const _EXTERNAL_TILE_PLACEMENTS_KEY := "external_tile_placements"
const _MAP_ORIGIN_KEY := "map_origin"

const _DEFAULT_HOUSE_NUMBER_SUPPLY := [1, 3, 6, 9, 11, 14, 17, 19]
const _DEFAULT_GARDEN_SUPPLY := 8

static func _require_array_field(data: Dictionary, key: String, path: String) -> Result:
	if not data.has(key) or not (data[key] is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array）" % path)
	return Result.success(data[key])

static func _require_dict_field(data: Dictionary, key: String, path: String) -> Result:
	if not data.has(key) or not (data[key] is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	return Result.success(data[key])

static func _require_vec2i_field(data: Dictionary, key: String, path: String) -> Result:
	if not data.has(key) or not (data[key] is Vector2i):
		return Result.failure("%s 缺失或类型错误（期望 Vector2i）" % path)
	return Result.success(data[key])

static func _validate_baked_cells(cells: Array, grid_size: Vector2i) -> Result:
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
	return Result.success()

static func _validate_tile_placements(tile_placements: Array) -> Result:
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
	return Result.success()

static func apply_baked_map(state, baked_data: Dictionary) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not (baked_data is Dictionary):
		return Result.failure("baked_data 类型错误（期望 Dictionary）")

	var cells_read := _require_array_field(baked_data, "cells", "baked_data.cells")
	if not cells_read.ok:
		return cells_read
	var cells: Array = cells_read.value
	if cells.is_empty():
		return Result.failure("baked_data.cells 不能为空")

	var grid_read := _require_vec2i_field(baked_data, "grid_size", "baked_data.grid_size")
	if not grid_read.ok:
		return grid_read
	var grid_size: Vector2i = grid_read.value
	var cells_validate := _validate_baked_cells(cells, grid_size)
	if not cells_validate.ok:
		return cells_validate

	var tile_placements_read := _require_array_field(baked_data, "tile_placements", "baked_data.tile_placements")
	if not tile_placements_read.ok:
		return tile_placements_read
	var tile_placements: Array = tile_placements_read.value
	var placements_validate := _validate_tile_placements(tile_placements)
	if not placements_validate.ok:
		return placements_validate

	var houses_read := _require_dict_field(baked_data, "houses", "baked_data.houses")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value

	var restaurants_read := _require_dict_field(baked_data, "restaurants", "baked_data.restaurants")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var drink_sources_read := _require_array_field(baked_data, "drink_sources", "baked_data.drink_sources")
	if not drink_sources_read.ok:
		return drink_sources_read
	var drink_sources: Array = drink_sources_read.value

	var boundary_index_read := _require_dict_field(baked_data, "boundary_index", "baked_data.boundary_index")
	if not boundary_index_read.ok:
		return boundary_index_read
	var boundary_index: Dictionary = boundary_index_read.value

	if not baked_data.has("next_house_number"):
		return Result.failure("baked_data.next_house_number 缺失")
	var next_house_read := MapParseHelpersClass.parse_non_negative_int(baked_data["next_house_number"], "baked_data.next_house_number")
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
	# external_cells 存储真实的“棋盘外组件”（例如模块额外道路/匝道），不应被 UI 占位格污染。
	state.map[_EXTERNAL_CELLS_KEY] = {}
	state.map[_EXTERNAL_TILE_PLACEMENTS_KEY] = []
	# Piece supplies (rules/UI). Stored in map for deterministic saves/replays.
	if not state.map.has("house_number_supply_remaining"):
		state.map["house_number_supply_remaining"] = _DEFAULT_HOUSE_NUMBER_SUPPLY.duplicate()
	if not state.map.has("garden_supply_remaining"):
		state.map["garden_supply_remaining"] = int(_DEFAULT_GARDEN_SUPPLY)

	# RoadGraph 是运行时派生缓存，必须失效
	RoadGraphCache.invalidate_road_graph(state)

	return Result.success()
