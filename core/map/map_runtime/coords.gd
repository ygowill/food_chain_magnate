extends RefCounted

const _MAP_ORIGIN_KEY := "map_origin"

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

