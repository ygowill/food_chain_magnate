extends RefCounted

const RoadGraphClass = preload("res://core/map/road_graph.gd")
const Coords = preload("res://core/map/map_runtime/coords.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"

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
		var origin := Coords.get_map_origin(state)
		state._road_graph = RoadGraphClass.build_from_cells_with_external(cells, grid_size, origin, external_cells, boundary_index)
	return state._road_graph

static func invalidate_road_graph(state) -> void:
	assert(state != null, "MapRuntime.invalidate_road_graph: state 为空")
	state._road_graph = null

