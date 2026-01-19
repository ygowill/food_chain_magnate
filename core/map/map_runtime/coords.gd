extends RefCounted

const _MAP_ORIGIN_KEY := "map_origin"

static func get_map_origin(state) -> Vector2i:
	if state == null or not (state.map is Dictionary):
		return Vector2i.ZERO
	var map: Dictionary = state.map
	var v = map.get(_MAP_ORIGIN_KEY, null)
	if v is Vector2i:
		return v
	return Vector2i.ZERO

static func set_map_origin(state, origin: Vector2i) -> void:
	if state == null or not (state.map is Dictionary):
		return
	state.map[_MAP_ORIGIN_KEY] = origin

static func world_to_index(state, world_pos: Vector2i) -> Vector2i:
	return world_pos + get_map_origin(state)

static func index_to_world(state, index_pos: Vector2i) -> Vector2i:
	return index_pos - get_map_origin(state)

static func get_world_min(state) -> Vector2i:
	if state == null or not (state.map is Dictionary):
		return Vector2i.ZERO
	var origin := get_map_origin(state)
	return -origin

static func get_world_max(state) -> Vector2i:
	if state == null or not (state.map is Dictionary):
		return Vector2i.ZERO
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Vector2i.ZERO
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Vector2i.ZERO
	var origin := get_map_origin(state)
	return Vector2i(grid_size.x - origin.x - 1, grid_size.y - origin.y - 1)

static func is_world_pos_in_grid(state, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
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
