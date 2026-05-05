class_name DrinkRouteAnalyzer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const RoadGraphClass = preload("res://core/map/road_graph.gd")

const DEFAULT_MAX_CANDIDATES := 4
const _EXTERNAL_CELLS_KEY := "external_cells"

static func generate_routes(
	observation: ObservationState,
	employee_id: String,
	max_candidates: int = DEFAULT_MAX_CANDIDATES
) -> Result:
	if observation == null:
		return Result.failure("DrinkRouteAnalyzer.generate_routes: observation is null")
	if employee_id.is_empty():
		return Result.failure("DrinkRouteAnalyzer.generate_routes: employee_id is empty")
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("DrinkRouteAnalyzer.generate_routes: EmployeeRegistry is not loaded")
	if not EmployeeRegistryClass.has(employee_id):
		return Result.failure("DrinkRouteAnalyzer.generate_routes: unknown employee: %s" % employee_id)
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return Result.failure("DrinkRouteAnalyzer.generate_routes: employee def is invalid: %s" % employee_id)
	var def: EmployeeDef = def_val
	if not def.can_procure() or employee_id == "errand_boy":
		return Result.success([])

	var range_type := str(def.range_type)
	var range_value := int(def.range_value)
	if range_value <= 0:
		return Result.success([])
	if range_type != "air" and range_type != "road":
		return Result.success([])

	var restaurants_val = observation.map_public.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.success([])
	var restaurants: Dictionary = restaurants_val
	var restaurant_ids := _sorted_owned_restaurant_ids(observation, restaurants)
	if restaurant_ids.is_empty():
		return Result.success([])

	var sources := _sorted_drink_sources(observation.map_public)
	if sources.is_empty():
		return Result.success([])

	var candidates: Array[Dictionary] = []
	if range_type == "air":
		candidates = _generate_air_candidates(observation, restaurants, restaurant_ids, sources, employee_id, range_value)
	else:
		candidates = _generate_road_candidates(observation, restaurants, restaurant_ids, sources, employee_id, range_value)

	_sort_route_candidates(candidates)
	if max_candidates > 0 and candidates.size() > max_candidates:
		candidates.resize(max_candidates)
	return Result.success(candidates)

static func _generate_air_candidates(
	observation: ObservationState,
	restaurants: Dictionary,
	restaurant_ids: Array[String],
	sources: Array[Dictionary],
	employee_id: String,
	range_value: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for restaurant_id in restaurant_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var entrance_points := _restaurant_entrance_points_public(observation, restaurant_id, rest_val)
		for source in sources:
			var source_pos: Vector2i = source.get("world_pos", Vector2i.ZERO)
			for entrance_pos in entrance_points:
				var route := _build_air_route(observation.map_public, entrance_pos, source_pos)
				if route.is_empty() or route.size() > range_value:
					continue
				var picked_sources := _picked_sources_for_air_route(observation.map_public, route, sources)
				if picked_sources.is_empty():
					continue
				var selected := _source_positions(picked_sources)
				var signature := "%s|%s|%s" % [employee_id, restaurant_id, str(DrinksProcurementClass.serialize_route(route))]
				if seen.has(signature):
					continue
				seen[signature] = true
				out.append(_build_candidate(employee_id, "air", restaurant_id, route, selected, route.size(), route.size(), picked_sources))
	return out

static func _generate_road_candidates(
	observation: ObservationState,
	restaurants: Dictionary,
	restaurant_ids: Array[String],
	sources: Array[Dictionary],
	employee_id: String,
	range_value: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var graph = _build_road_graph(observation.map_public)
	if graph == null:
		return out
	var seen := {}
	for restaurant_id in restaurant_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var entrance_points := _restaurant_entrance_points_public(observation, restaurant_id, rest_val)
		var start_roads := _adjacent_road_cells_public(observation.map_public, graph, entrance_points)
		if start_roads.is_empty():
			continue
		for source in sources:
			var source_pos: Vector2i = source.get("world_pos", Vector2i.ZERO)
			var target_roads := _adjacent_road_cells_public(observation.map_public, graph, [source_pos])
			if target_roads.is_empty():
				continue
			var best := _best_road_path(graph, start_roads, target_roads)
			if best.is_empty():
				continue
			var distance := int(best.get("distance", 999999))
			if distance > range_value:
				continue
			var route: Array[Vector2i] = best.get("route", [])
			if route.is_empty():
				continue
			var picked_sources := _picked_sources_for_road_route(observation.map_public, graph, route, sources)
			if picked_sources.is_empty():
				continue
			var selected := _source_positions(picked_sources)
			var signature := "%s|%s|%s" % [employee_id, restaurant_id, str(DrinksProcurementClass.serialize_route(route))]
			if seen.has(signature):
				continue
			seen[signature] = true
			out.append(_build_candidate(employee_id, "road", restaurant_id, route, selected, distance, int(best.get("steps", 999999)), picked_sources))
	return out

static func _build_candidate(
	employee_id: String,
	range_type: String,
	restaurant_id: String,
	route: Array[Vector2i],
	selected_sources: Array[Vector2i],
	distance: int,
	steps: int,
	picked_sources: Array[Dictionary]
) -> Dictionary:
	var source_types: Array[String] = []
	for source in picked_sources:
		var type_id := str(source.get("type", ""))
		if not type_id.is_empty() and not source_types.has(type_id):
			source_types.append(type_id)
	source_types.sort()
	return {
		"employee_type": employee_id,
		"range_type": range_type,
		"restaurant_id": restaurant_id,
		"route": route.duplicate(),
		"selected_sources": selected_sources.duplicate(),
		"source_count": selected_sources.size(),
		"source_types": source_types,
		"distance": distance,
		"steps": steps,
		"params": {
			"employee_type": employee_id,
			"restaurant_id": restaurant_id,
			"route": DrinksProcurementClass.serialize_route(route),
			"selected_sources": DrinksProcurementClass.serialize_route(selected_sources),
		},
	}

static func _build_air_route(map_public: Dictionary, from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var from_tile := _world_to_tile_pos(map_public, from_pos)
	var to_tile := _world_to_tile_pos(map_public, to_pos)
	route.append(from_tile)
	var cur := from_tile
	while cur.x != to_tile.x:
		cur = Vector2i(cur.x + (1 if to_tile.x > cur.x else -1), cur.y)
		route.append(cur)
	while cur.y != to_tile.y:
		cur = Vector2i(cur.x, cur.y + (1 if to_tile.y > cur.y else -1))
		route.append(cur)
	return route

static func _best_road_path(graph, start_roads: Array[Vector2i], target_roads: Array[Vector2i]) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 999999
	var best_steps := 999999
	for start_pos in start_roads:
		for target_pos in target_roads:
			var path_read = graph.find_shortest_path(start_pos, target_pos)
			if not path_read.ok:
				continue
			var path_data: Dictionary = path_read.value
			var distance := int(path_data.get("distance", 999999))
			var steps := int(path_data.get("steps", 999999))
			if distance > best_distance or (distance == best_distance and steps >= best_steps):
				continue
			var route_val = path_data.get("path", null)
			if not (route_val is Array):
				continue
			var route: Array[Vector2i] = []
			for pos_val in Array(route_val):
				if pos_val is Vector2i:
					route.append(pos_val)
			if route.is_empty():
				continue
			best_distance = distance
			best_steps = steps
			best = {
				"route": route,
				"distance": distance,
				"steps": steps,
			}
	return best

static func _picked_sources_for_air_route(map_public: Dictionary, route: Array[Vector2i], sources: Array[Dictionary]) -> Array[Dictionary]:
	var route_set := {}
	for pos in route:
		route_set[pos] = true
	var out: Array[Dictionary] = []
	for source in sources:
		var world_pos: Vector2i = source.get("world_pos", Vector2i.ZERO)
		var tile_pos := _world_to_tile_pos(map_public, world_pos)
		if route_set.has(tile_pos):
			out.append(source)
	return out

static func _picked_sources_for_road_route(
	map_public: Dictionary,
	graph,
	route: Array[Vector2i],
	sources: Array[Dictionary]
) -> Array[Dictionary]:
	var route_set := {}
	for pos in route:
		route_set[pos] = true
	var out: Array[Dictionary] = []
	for source in sources:
		var world_pos: Vector2i = source.get("world_pos", Vector2i.ZERO)
		var roads := _adjacent_road_cells_public(map_public, graph, [world_pos])
		for road_pos in roads:
			if route_set.has(road_pos):
				out.append(source)
				break
	return out

static func _source_positions(sources: Array[Dictionary]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for source in sources:
		var pos: Vector2i = source.get("world_pos", Vector2i.ZERO)
		if seen.has(pos):
			continue
		seen[pos] = true
		out.append(pos)
	_sort_positions(out)
	return out

static func _build_road_graph(map_public: Dictionary):
	var cells_val = map_public.get("cells", null)
	if not (cells_val is Array):
		return null
	var grid_size := _read_vector2i(map_public.get("grid_size", Vector2i.ZERO))
	if grid_size.x <= 0 or grid_size.y <= 0:
		return null
	var boundary_index: Dictionary = {}
	var boundary_val = map_public.get("boundary_index", {})
	if boundary_val is Dictionary:
		boundary_index = boundary_val
	var external_cells: Dictionary = {}
	var external_val = map_public.get(_EXTERNAL_CELLS_KEY, {})
	if external_val is Dictionary:
		external_cells = external_val
	var options: Dictionary = {}
	if _read_boolish(map_public.get("road_graph_connect_parallel_lanes", false)):
		options["connect_parallel_lanes"] = true
	return RoadGraphClass.build_from_cells_with_external(
		cells_val,
		grid_size,
		_read_map_origin(map_public),
		external_cells,
		boundary_index,
		options
	)

static func _adjacent_road_cells_public(map_public: Dictionary, graph, anchors: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for anchor in anchors:
		if not _has_cell_any_public(map_public, anchor):
			continue
		if graph.has_road_at(anchor) and not out.has(anchor):
			out.append(anchor)
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(anchor, dir)
			if not _has_cell_any_public(map_public, neighbor):
				continue
			if graph.has_road_at(neighbor) and not out.has(neighbor):
				out.append(neighbor)
	_sort_positions(out)
	return out

static func _restaurant_entrance_points_public(
	observation: ObservationState,
	restaurant_id: String,
	rest: Dictionary
) -> Array[Vector2i]:
	var entrance := _read_vector2i(rest.get("entrance_pos", Vector2i.ZERO))
	var out: Array[Vector2i] = [entrance]
	if not _active_has_employee_tag(observation.own_player, "drivethrough"):
		return out
	var cells_val = rest.get("cells", null)
	if not (cells_val is Array):
		return out
	var cells: Array[Vector2i] = []
	for c_val in Array(cells_val):
		var c := _read_vector2i(c_val)
		cells.append(c)
	if cells.is_empty():
		return out
	var min_pos: Vector2i = cells[0]
	var max_pos: Vector2i = cells[0]
	for cell in cells:
		min_pos.x = mini(min_pos.x, cell.x)
		min_pos.y = mini(min_pos.y, cell.y)
		max_pos.x = maxi(max_pos.x, cell.x)
		max_pos.y = maxi(max_pos.y, cell.y)
	out = [
		Vector2i(min_pos.x, min_pos.y),
		Vector2i(max_pos.x, min_pos.y),
		Vector2i(min_pos.x, max_pos.y),
		Vector2i(max_pos.x, max_pos.y),
	]
	_sort_positions(out)
	return out

static func _active_has_employee_tag(player: Dictionary, tag: String) -> bool:
	if tag.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	var active_val = player.get("employees", [])
	if not (active_val is Array):
		return false
	for employee_val in Array(active_val):
		var employee_id := str(employee_val)
		if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and (def_val as EmployeeDef).has_tag(tag):
			return true
	return false

static func _sorted_owned_restaurant_ids(observation: ObservationState, restaurants: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids_val = observation.own_player.get("restaurants", [])
	if ids_val is Array:
		for id_val in Array(ids_val):
			var restaurant_id := str(id_val)
			if restaurant_id.is_empty() or not restaurants.has(restaurant_id):
				continue
			out.append(restaurant_id)
	if out.is_empty():
		for id_val in restaurants.keys():
			if not (id_val is String):
				continue
			var restaurant_id := str(id_val)
			var rest_val = restaurants.get(restaurant_id, null)
			if rest_val is Dictionary and int(Dictionary(rest_val).get("owner", -1)) == observation.viewer_player_id:
				out.append(restaurant_id)
	out.sort()
	return out

static func _sorted_drink_sources(map_public: Dictionary) -> Array[Dictionary]:
	var sources_val = map_public.get("drink_sources", [])
	var out: Array[Dictionary] = []
	if not (sources_val is Array):
		return out
	for source_val in Array(sources_val):
		if not (source_val is Dictionary):
			continue
		var source: Dictionary = source_val
		var type_id := str(source.get("type", ""))
		if type_id.is_empty():
			continue
		var pos := _read_vector2i(source.get("world_pos", Vector2i.ZERO))
		out.append({
			"world_pos": pos,
			"type": type_id,
			"tile_id": str(source.get("tile_id", "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var type_a := str(a.get("type", ""))
		var type_b := str(b.get("type", ""))
		if type_a != type_b:
			return type_a < type_b
		var pos_a: Vector2i = a.get("world_pos", Vector2i.ZERO)
		var pos_b: Vector2i = b.get("world_pos", Vector2i.ZERO)
		if pos_a.y != pos_b.y:
			return pos_a.y < pos_b.y
		return pos_a.x < pos_b.x
	)
	return out

static func _sort_route_candidates(candidates: Array[Dictionary]) -> void:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var source_a := int(a.get("source_count", 0))
		var source_b := int(b.get("source_count", 0))
		if source_a != source_b:
			return source_a > source_b
		var distance_a := int(a.get("distance", 999999))
		var distance_b := int(b.get("distance", 999999))
		if distance_a != distance_b:
			return distance_a < distance_b
		var steps_a := int(a.get("steps", 999999))
		var steps_b := int(b.get("steps", 999999))
		if steps_a != steps_b:
			return steps_a < steps_b
		return str(a.get("restaurant_id", "")) < str(b.get("restaurant_id", ""))
	)

static func _sort_positions(positions: Array[Vector2i]) -> void:
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

static func _world_to_tile_pos(map_public: Dictionary, world_pos: Vector2i) -> Vector2i:
	var tile_size := _read_tile_size(map_public)
	return Vector2i(_floor_div(world_pos.x, tile_size), _floor_div(world_pos.y, tile_size))

static func _read_tile_size(map_public: Dictionary) -> int:
	var grid_size := _read_vector2i(map_public.get("grid_size", Vector2i.ZERO))
	var tile_grid_size := _read_vector2i(map_public.get("tile_grid_size", Vector2i.ZERO))
	if grid_size.x > 0 and grid_size.y > 0 and tile_grid_size.x > 0 and tile_grid_size.y > 0:
		if grid_size.x % tile_grid_size.x == 0 and grid_size.y % tile_grid_size.y == 0:
			var size_x := grid_size.x / tile_grid_size.x
			var size_y := grid_size.y / tile_grid_size.y
			if size_x == size_y and size_x > 0:
				return int(size_x)
	return MapUtils.TILE_SIZE

static func _has_cell_any_public(map_public: Dictionary, pos: Vector2i) -> bool:
	var grid_size := _read_vector2i(map_public.get("grid_size", Vector2i.ZERO))
	var idx := pos + _read_map_origin(map_public)
	if idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y:
		return true
	var external_val = map_public.get(_EXTERNAL_CELLS_KEY, null)
	return external_val is Dictionary and Dictionary(external_val).has(_pos_key(pos))

static func _read_map_origin(map_public: Dictionary) -> Vector2i:
	return _read_vector2i(map_public.get("map_origin", Vector2i.ZERO))

static func _read_boolish(value) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) != 0
	if value is float:
		var f := float(value)
		return f == floor(f) and int(f) != 0
	return false

static func _read_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Dictionary:
		var dict: Dictionary = value
		return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

static func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func _floor_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(floor(float(a) / float(b)))
