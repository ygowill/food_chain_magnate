extends RefCounted

const RoadGraphClass = preload("res://core/map/road_graph.gd")
const Coords = preload("res://core/map/map_runtime/coords.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"

static func get_road_graph(state) -> RefCounted:
	if state == null:
		return null
	if state._road_graph == null:
		if not (state.map is Dictionary):
			return null
		var map: Dictionary = state.map
		var cells_val = map.get("cells", null)
		if not (cells_val is Array):
			return null
		var cells: Array = cells_val
		if cells.is_empty():
			return null
		var grid_size_val = map.get("grid_size", null)
		if not (grid_size_val is Vector2i):
			return null
		var grid_size: Vector2i = grid_size_val
		var boundary_index_val = map.get("boundary_index", null)
		if not (boundary_index_val is Dictionary):
			return null
		var boundary_index: Dictionary = boundary_index_val

		var external_cells: Dictionary = {}
		var external_cells_val = map.get(_EXTERNAL_CELLS_KEY, null)
		if external_cells_val is Dictionary:
			external_cells = external_cells_val
		var origin := Coords.get_map_origin(state)
		state._road_graph = RoadGraphClass.build_from_cells_with_external(cells, grid_size, origin, external_cells, boundary_index)
	return state._road_graph

static func invalidate_road_graph(state) -> void:
	if state == null:
		return
	state._road_graph = null
