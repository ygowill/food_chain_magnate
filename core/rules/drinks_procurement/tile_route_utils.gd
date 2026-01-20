# 饮料采购：飞艇板块路线辅助
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")

static func get_tile_size(state: GameState) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 缺失或类型错误")
	var map: Dictionary = state.map
	if not map.has("grid_size") or not (map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size 缺失或类型错误")
	if not map.has("tile_grid_size") or not (map["tile_grid_size"] is Vector2i):
		return Result.failure("state.map.tile_grid_size 缺失或类型错误")
	var grid_size: Vector2i = map["grid_size"]
	var tile_grid_size: Vector2i = map["tile_grid_size"]
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("state.map.tile_grid_size 非法: %s" % str(tile_grid_size))
	if grid_size.x % tile_grid_size.x != 0 or grid_size.y % tile_grid_size.y != 0:
		return Result.failure("grid_size 与 tile_grid_size 不可整除: grid=%s tile=%s" % [str(grid_size), str(tile_grid_size)])
	var tile_size_x := grid_size.x / tile_grid_size.x
	var tile_size_y := grid_size.y / tile_grid_size.y
	if tile_size_x != tile_size_y:
		return Result.failure("grid_size 与 tile_grid_size 不匹配（非正方形板块）: grid=%s tile=%s" % [str(grid_size), str(tile_grid_size)])
	if tile_size_x <= 0:
		return Result.failure("tile_size 非法: %d" % tile_size_x)
	return Result.success(tile_size_x)

static func world_to_tile_pos(state: GameState, world_pos: Vector2i) -> Result:
	var tile_size_read := get_tile_size(state)
	if not tile_size_read.ok:
		return tile_size_read
	var tile_size: int = int(tile_size_read.value)
	var bx := _floor_div(world_pos.x, tile_size)
	var by := _floor_div(world_pos.y, tile_size)
	return Result.success(Vector2i(bx, by))

static func get_tile_bounds(state: GameState) -> Result:
	var tile_size_read := get_tile_size(state)
	if not tile_size_read.ok:
		return tile_size_read
	var tile_size: int = int(tile_size_read.value)
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var min_tile := Vector2i(_floor_div(minp.x, tile_size), _floor_div(minp.y, tile_size))
	var max_tile := Vector2i(_floor_div(maxp.x, tile_size), _floor_div(maxp.y, tile_size))
	return Result.success({
		"tile_size": tile_size,
		"min": min_tile,
		"max": max_tile
	})

static func get_tile_positions_set(state: GameState) -> Dictionary:
	var out := {}
	if state == null or not (state.map is Dictionary):
		return out
	var map: Dictionary = state.map
	var placements_val = map.get("tile_placements", null)
	if placements_val is Array:
		var placements: Array = placements_val
		for p_val in placements:
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var bp = p.get("board_pos", null)
			if bp is Vector2i:
				out[Vector2i(bp)] = true
	var ext_val = map.get("external_tile_placements", null)
	if ext_val is Array:
		var ext: Array = ext_val
		for p_val2 in ext:
			if not (p_val2 is Dictionary):
				continue
			var p2: Dictionary = p_val2
			var bp2 = p2.get("board_pos", null)
			if bp2 is Vector2i:
				out[Vector2i(bp2)] = true
	return out

static func _floor_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(floor(float(a) / float(b)))
