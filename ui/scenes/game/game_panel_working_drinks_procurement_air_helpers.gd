# Game scene：Working/Drinks Procurement（air procure）帮助函数
# 拆分自：`game_panel_working_drinks_procurement_controller.gd`
extends RefCounted

const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")

static func collect_air_sources_in_tiles(state: GameState, tiles: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var sources_val = state.map.get("drink_sources", null)
	if not (sources_val is Array):
		return out
	var tile_set := {}
	for t in tiles:
		tile_set[t] = true
	var sources: Array = sources_val
	for s_val in sources:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp = s.get("world_pos", null)
		if wp is Vector2i:
			var tile_pos: Vector2i = MapUtils.world_to_tile(Vector2i(wp)).board_pos
			if tile_set.has(tile_pos):
				out.append(Vector2i(wp))
	return out

static func build_air_tile_display_route(tiles: Array[Vector2i], tile_size_cells: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := tile_size_cells if tile_size_cells > 0 else int(MapUtils.TILE_SIZE)
	for t in tiles:
		out.append(get_tile_center_world_pos(t, size))
	return out

static func get_tile_center_world_pos(tile_pos: Vector2i, tile_size_cells: int = -1) -> Vector2i:
	var size := tile_size_cells if tile_size_cells > 0 else int(MapUtils.TILE_SIZE)
	return tile_pos * size + Vector2i(size / 2, size / 2)

static func get_air_tile_size_cells(state: GameState) -> int:
	var size := int(MapUtils.TILE_SIZE)
	if state == null:
		return size
	var read := TileRouteUtilsClass.get_tile_size(state)
	if read.ok:
		size = int(read.value)
	return size

static func get_air_tile_bounds(state: GameState, tile_positions_set: Dictionary) -> Dictionary:
	var bounds: Dictionary = {}
	if state == null:
		return bounds
	if not tile_positions_set.is_empty():
		return bounds
	var read := TileRouteUtilsClass.get_tile_bounds(state)
	if read.ok and (read.value is Dictionary):
		bounds = read.value
	return bounds

static func is_air_tile_valid(tile_pos: Vector2i, tile_positions_set: Dictionary, bounds: Dictionary) -> bool:
	if not tile_positions_set.is_empty():
		return tile_positions_set.has(tile_pos)
	if bounds.is_empty():
		return true
	var min_tile = bounds.get("min", null)
	var max_tile = bounds.get("max", null)
	if min_tile is Vector2i and max_tile is Vector2i:
		return tile_pos.x >= min_tile.x and tile_pos.y >= min_tile.y and tile_pos.x <= max_tile.x and tile_pos.y <= max_tile.y
	return true

static func get_air_procure_max_tiles(state: GameState, emp_def: EmployeeDef) -> int:
	if emp_def == null:
		return 0
	var max_tiles := int(emp_def.range_value)
	if state == null:
		return max_tiles
	var bonus_read := DrinksProcurementClass._get_distance_range_bonus_from_milestones(
		state, state.get_current_player_id(), str(emp_def.id)
	)
	if bonus_read.ok:
		max_tiles += int(bonus_read.value)
	return max_tiles

static func get_air_procure_start_tiles(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return out
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return out
	var restaurants: Dictionary = restaurants_val

	var seen := {}
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			continue
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var ep = rest.get("entrance_pos", null)
		if not (ep is Vector2i):
			continue
		var entrance_pos: Vector2i = Vector2i(ep)

		var tile_pos := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
		if tile_read.ok:
			tile_pos = tile_read.value
		else:
			tile_pos = MapUtils.world_to_tile(entrance_pos).board_pos

		if seen.has(tile_pos):
			continue
		seen[tile_pos] = true
		out.append(tile_pos)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return out

static func get_air_procure_legal_tiles(state: GameState, emp_def: EmployeeDef, selected_tiles: Array[Vector2i], entrance_tile: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null or emp_def == null:
		return out
	var max_tiles := get_air_procure_max_tiles(state, emp_def)
	if max_tiles <= 0:
		return out

	var tile_positions_set := TileRouteUtilsClass.get_tile_positions_set(state)
	var bounds := get_air_tile_bounds(state, tile_positions_set)

	if selected_tiles.is_empty():
		for start_tile in get_air_procure_start_tiles(state):
			if is_air_tile_valid(start_tile, tile_positions_set, bounds):
				out.append(start_tile)
		return out

	if selected_tiles.size() >= max_tiles:
		return out

	var last_tile: Vector2i = selected_tiles[selected_tiles.size() - 1]
	for offset_val in MapUtils.DIR_OFFSETS.values():
		if not (offset_val is Vector2i):
			continue
		var offset: Vector2i = offset_val
		var candidate: Vector2i = last_tile + offset
		if selected_tiles.has(candidate):
			continue
		if not is_air_tile_valid(candidate, tile_positions_set, bounds):
			continue
		out.append(candidate)

	return out

static func build_air_procure_overlay_options(state: GameState, emp_def: EmployeeDef, selected_tiles: Array[Vector2i], entrance_tile: Vector2i) -> Dictionary:
	return {
		"tile_mode": true,
		"tile_size_cells": get_air_tile_size_cells(state),
		"selected_tiles": selected_tiles.duplicate(),
		"legal_tiles": get_air_procure_legal_tiles(state, emp_def, selected_tiles, entrance_tile)
	}

static func resolve_air_procure_restaurant_and_entrance_from_start_tile(state: GameState, start_tile: Vector2i) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if start_tile == Vector2i(-1, -1):
		return Result.failure("未选择起点板块")

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = restaurants_val

	var matches: Array[String] = []
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			continue
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var ep = rest.get("entrance_pos", null)
		if not (ep is Vector2i):
			continue
		var entrance_pos: Vector2i = Vector2i(ep)

		var entrance_tile := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
		if tile_read.ok:
			entrance_tile = tile_read.value
		else:
			entrance_tile = MapUtils.world_to_tile(entrance_pos).board_pos

		if entrance_tile == start_tile:
			matches.append(str(rest_id))

	if matches.is_empty():
		return Result.failure("第一格必须选择餐厅所在板块")

	matches.sort()
	var chosen_id: String = matches[0]
	var chosen: Dictionary = restaurants.get(chosen_id, {})
	var ep2 = chosen.get("entrance_pos", null)
	if not (ep2 is Vector2i):
		return Result.failure("无法解析餐厅入口位置: %s" % chosen_id)

	return Result.success({
		"restaurant_id": chosen_id,
		"entrance_pos": Vector2i(ep2),
	})
