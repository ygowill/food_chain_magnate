class_name StructureDistance
extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

static func get_restaurant_to_house_distance(
	road_graph,
	state: GameState,
	grid_size: Vector2i,
	restaurant_id: String,
	rest: Dictionary,
	house_id: String,
	house: Dictionary
) -> Result:
	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("StructureDistance: houses[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % house_id)
	var house_cells_any: Array = house["cells"]
	var house_cells: Array[Vector2i] = []
	for i in range(house_cells_any.size()):
		var v = house_cells_any[i]
		if not (v is Vector2i):
			return Result.failure("StructureDistance: houses[%s].cells[%d] 类型错误（期望 Vector2i）" % [house_id, i])
		house_cells.append(v)

	var house_roads := get_structure_adjacent_roads(state, grid_size, house_cells)
	if house_roads.is_empty():
		return Result.success({})

	var entrance_points_read := get_restaurant_entrance_points(state, restaurant_id, rest)
	if not entrance_points_read.ok:
		return entrance_points_read
	var entrance_points_any: Array = entrance_points_read.value
	var entrance_points: Array[Vector2i] = []
	for i in range(entrance_points_any.size()):
		var p = entrance_points_any[i]
		if not (p is Vector2i):
			return Result.failure("StructureDistance: restaurants[%s] entrance_points[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		entrance_points.append(p)

	var rest_roads := get_structure_adjacent_roads(state, grid_size, entrance_points)
	if rest_roads.is_empty():
		return Result.success({})

	# RoadGraph distance only counts boundaries crossed between road cells.
	# Structure-to-road entry/exit can also cross a tile boundary, so include it.
	var rest_entry_cost_by_road := _build_structure_to_road_boundary_cost(entrance_points, rest_roads)
	var house_entry_cost_by_road := _build_structure_to_road_boundary_cost(house_cells, house_roads)

	var best_distance := INF
	var best_steps := INF
	var best_path: Array[Vector2i] = []
	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok:
				continue
			if not (sp.value is Dictionary):
				return Result.failure("StructureDistance: RoadGraph.find_shortest_path value 类型错误（期望 Dictionary）")
			var sp_val: Dictionary = sp.value
			if not (sp_val.has("distance") and sp_val["distance"] is int):
				return Result.failure("StructureDistance: RoadGraph.find_shortest_path 缺少/错误 distance（期望 int）")
			if not (sp_val.has("steps") and sp_val["steps"] is int):
				return Result.failure("StructureDistance: RoadGraph.find_shortest_path 缺少/错误 steps（期望 int）")
			if not (sp_val.has("path") and sp_val["path"] is Array):
				return Result.failure("StructureDistance: RoadGraph.find_shortest_path 缺少/错误 path（期望 Array）")
			var d: int = int(sp_val["distance"])
			d += int(rest_entry_cost_by_road.get(s, 0))
			d += int(house_entry_cost_by_road.get(t, 0))
			var steps: int = int(sp_val["steps"])
			var path_any: Array = sp_val["path"]
			var path: Array[Vector2i] = []
			for i in range(path_any.size()):
				var p = path_any[i]
				if not (p is Vector2i):
					return Result.failure("StructureDistance: RoadGraph.find_shortest_path path[%d] 类型错误（期望 Vector2i）" % i)
				path.append(p)
			if d < best_distance or (d == best_distance and steps < best_steps):
				best_distance = d
				best_steps = steps
				best_path = path

	if best_distance == INF:
		return Result.success({})
	return Result.success({
		"distance": int(best_distance),
		"steps": int(best_steps),
		"path": best_path,
	})

static func get_restaurant_entrance_points(state: GameState, restaurant_id: String, rest: Dictionary) -> Result:
	return StructuresClass.get_restaurant_entrance_points(state, restaurant_id, rest)

static func get_structure_adjacent_roads(state: GameState, _grid_size: Vector2i, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		# If the structure itself occupies a road cell, treat it as an entry road.
		if CellsClass.has_cell_any(state, cell) and CellsClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtilsClass.DIRECTIONS:
			var n := MapUtilsClass.get_neighbor_pos(cell, dir)
			if not CellsClass.has_cell_any(state, n):
				continue
			if CellsClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(k)
	return result

static func _build_structure_to_road_boundary_cost(
	structure_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> Dictionary:
	var out := {}
	for r in road_cells:
		var best := INF
		for c in structure_cells:
			if c == r:
				best = 0
				break
			if not MapUtilsClass.are_adjacent(c, r):
				continue
			best = min(best, 1 if MapUtilsClass.crosses_tile_boundary(c, r) else 0)
		if best == INF:
			best = 0
		out[r] = int(best)
	return out
