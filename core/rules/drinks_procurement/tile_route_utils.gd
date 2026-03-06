# 饮料采购：飞艇板块路线辅助
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func get_tile_size(state: GameState, prefix_label: String = "") -> Result:
	var grid_size_read := MapStateAccessClass.require_grid_size(state, prefix_label)
	if not grid_size_read.ok:
		return grid_size_read
	var tile_grid_size_read := MapStateAccessClass.require_tile_grid_size(state, prefix_label)
	if not tile_grid_size_read.ok:
		return tile_grid_size_read
	var grid_size: Vector2i = grid_size_read.value
	var tile_grid_size: Vector2i = tile_grid_size_read.value
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

static func world_to_tile_pos(state: GameState, world_pos: Vector2i, prefix_label: String = "") -> Result:
	var tile_size_read := get_tile_size(state, prefix_label)
	if not tile_size_read.ok:
		return tile_size_read
	var tile_size: int = int(tile_size_read.value)
	var bx := _floor_div(world_pos.x, tile_size)
	var by := _floor_div(world_pos.y, tile_size)
	return Result.success(Vector2i(bx, by))

static func get_tile_bounds(state: GameState, prefix_label: String = "") -> Result:
	var tile_size_read := get_tile_size(state, prefix_label)
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

static func get_tile_positions_set_result(state: GameState, prefix_label: String = "") -> Result:
	var map_read := MapStateAccessClass.require_map(state, prefix_label)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value
	var out := {}

	var placements_read := _read_optional_placements(map, "tile_placements", prefix_label)
	if not placements_read.ok:
		return placements_read
	_append_tile_positions(out, placements_read.value)

	var external_read := _read_optional_placements(map, "external_tile_placements", prefix_label)
	if not external_read.ok:
		return external_read
	_append_tile_positions(out, external_read.value)

	return Result.success(out)

static func get_tile_positions_set(state: GameState) -> Dictionary:
	var read := get_tile_positions_set_result(state)
	if not read.ok:
		return {}
	return read.value

static func _read_optional_placements(map: Dictionary, field_name: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not map.has(field_name):
		return Result.success([])
	if not (map[field_name] is Array):
		return Result.failure("%sstate.map.%s 类型错误（期望 Array）" % [prefix, field_name])
	return Result.success(map[field_name])

static func _append_tile_positions(out: Dictionary, placements: Array) -> void:
	for p_val in placements:
		if not (p_val is Dictionary):
			continue
		var placement: Dictionary = p_val
		var board_pos = placement.get("board_pos", null)
		if board_pos is Vector2i:
			out[Vector2i(board_pos)] = true

static func _floor_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(floor(float(a) / float(b)))
