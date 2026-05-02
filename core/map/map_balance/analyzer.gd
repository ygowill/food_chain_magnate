class_name MapBalanceAnalyzer
extends RefCounted

const RoadGraphClass = preload("res://core/map/road_graph.gd")
const ThresholdsClass = preload("res://core/map/map_balance/thresholds.gd")
const ScorerClass = preload("res://core/map/map_balance/scorer.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"
const _MAP_ORIGIN_KEY := "map_origin"

static func analyze_state(state, player_count: int = 0) -> Result:
	if state == null:
		return Result.failure("MapBalanceAnalyzer.analyze_state: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("MapBalanceAnalyzer.analyze_state: state.map 类型错误（期望 Dictionary）")
	return analyze_map_data(state.map, player_count)

static func analyze_map_data(map_data: Dictionary, player_count: int = 0) -> Result:
	var input_read := _read_map_input(map_data)
	if not input_read.ok:
		return input_read
	var input: Dictionary = input_read.value

	var graph = RoadGraphClass.build_from_cells_with_external(
		input["cells"],
		input["grid_size"],
		input["map_origin"],
		input["external_cells"],
		input["boundary_index"],
		input["road_graph_options"]
	)

	var houses_read := _collect_starting_houses(map_data)
	if not houses_read.ok:
		return houses_read
	var starting_houses: Array[Dictionary] = houses_read.value

	var drink_sources_read := _collect_drink_sources(map_data)
	if not drink_sources_read.ok:
		return drink_sources_read
	var drink_sources: Array[Dictionary] = drink_sources_read.value

	var neighborhoods_bundle := _build_neighborhoods(input, graph)
	var road_bundle := _build_road_systems(graph)

	_assign_houses_to_neighborhoods(neighborhoods_bundle, graph, starting_houses)
	_assign_houses_to_road_systems(road_bundle, starting_houses)
	_assign_drinks_to_road_systems(road_bundle, drink_sources)

	var analysis := _build_analysis(
		map_data,
		player_count,
		input,
		starting_houses,
		drink_sources,
		neighborhoods_bundle["items"],
		road_bundle["items"]
	)

	if player_count > 0:
		var thresholds_read := ThresholdsClass.for_player_count(player_count)
		if thresholds_read.ok:
			var thresholds: Dictionary = thresholds_read.value
			analysis["thresholds"] = thresholds
			analysis["evaluation"] = ScorerClass.evaluate(analysis, thresholds)
		else:
			analysis["threshold_error"] = thresholds_read.error

	return Result.success(analysis)

static func _read_map_input(map_data: Dictionary) -> Result:
	if not (map_data is Dictionary):
		return Result.failure("MapBalanceAnalyzer: map_data 类型错误（期望 Dictionary）")

	var cells_val = map_data.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("MapBalanceAnalyzer: map_data.cells 缺失或类型错误（期望 Array）")
	var cells: Array = cells_val
	if cells.is_empty():
		return Result.failure("MapBalanceAnalyzer: map_data.cells 不能为空")

	var grid_val = map_data.get("grid_size", null)
	if not (grid_val is Vector2i):
		return Result.failure("MapBalanceAnalyzer: map_data.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = grid_val
	var cells_check := _validate_cells(cells, grid_size)
	if not cells_check.ok:
		return cells_check

	var map_origin := Vector2i.ZERO
	var origin_val = map_data.get(_MAP_ORIGIN_KEY, null)
	if origin_val != null:
		if not (origin_val is Vector2i):
			return Result.failure("MapBalanceAnalyzer: map_data.map_origin 类型错误（期望 Vector2i）")
		map_origin = origin_val

	var external_cells: Dictionary = {}
	var external_val = map_data.get(_EXTERNAL_CELLS_KEY, null)
	if external_val != null:
		if not (external_val is Dictionary):
			return Result.failure("MapBalanceAnalyzer: map_data.external_cells 类型错误（期望 Dictionary）")
		external_cells = external_val

	var boundary_index: Dictionary = {}
	var boundary_val = map_data.get("boundary_index", null)
	if boundary_val is Dictionary:
		boundary_index = boundary_val

	var options: Dictionary = {}
	if _read_boolish(map_data.get("road_graph_connect_parallel_lanes", false)):
		options["connect_parallel_lanes"] = true

	return Result.success({
		"cells": cells,
		"grid_size": grid_size,
		"map_origin": map_origin,
		"external_cells": external_cells,
		"boundary_index": boundary_index,
		"road_graph_options": options,
	})

static func _validate_cells(cells: Array, grid_size: Vector2i) -> Result:
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("MapBalanceAnalyzer: grid_size 非法: %s" % str(grid_size))
	if cells.size() != grid_size.y:
		return Result.failure("MapBalanceAnalyzer: cells 行数与 grid_size.y 不匹配")
	for y in range(grid_size.y):
		var row_val = cells[y]
		if not (row_val is Array):
			return Result.failure("MapBalanceAnalyzer: cells[%d] 类型错误（期望 Array）" % y)
		var row: Array = row_val
		if row.size() != grid_size.x:
			return Result.failure("MapBalanceAnalyzer: cells[%d] 长度与 grid_size.x 不匹配" % y)
		for x in range(grid_size.x):
			if not (row[x] is Dictionary):
				return Result.failure("MapBalanceAnalyzer: cells[%d][%d] 类型错误（期望 Dictionary）" % [y, x])
	return Result.success()

static func _collect_starting_houses(map_data: Dictionary) -> Result:
	var houses_val = map_data.get("houses", null)
	if not (houses_val is Dictionary):
		return Result.failure("MapBalanceAnalyzer: map_data.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = houses_val
	var keys := houses.keys()
	keys.sort()

	var out: Array[Dictionary] = []
	for key_val in keys:
		var house_val = houses[key_val]
		if not (house_val is Dictionary):
			return Result.failure("MapBalanceAnalyzer: houses[%s] 类型错误（期望 Dictionary）" % str(key_val))
		var house: Dictionary = house_val
		if not _is_starting_house(house):
			continue

		var cells_read := _read_vec2i_array_or_anchor(house, "cells", "anchor_pos", "houses[%s]" % str(key_val))
		if not cells_read.ok:
			return cells_read

		out.append({
			"house_id": str(house.get("house_id", str(key_val))),
			"house_number": int(house.get("house_number", 0)),
			"cells": cells_read.value,
			"anchor_pos": house.get("anchor_pos", null),
		})
	return Result.success(out)

static func _collect_drink_sources(map_data: Dictionary) -> Result:
	var sources_val = map_data.get("drink_sources", null)
	if not (sources_val is Array):
		return Result.failure("MapBalanceAnalyzer: map_data.drink_sources 缺失或类型错误（期望 Array）")
	var sources: Array = sources_val
	var out: Array[Dictionary] = []
	for i in range(sources.size()):
		var source_val = sources[i]
		if not (source_val is Dictionary):
			return Result.failure("MapBalanceAnalyzer: drink_sources[%d] 类型错误（期望 Dictionary）" % i)
		var source: Dictionary = source_val
		var pos_val = _to_vec2i(source.get("world_pos", null))
		if not (pos_val is Vector2i):
			return Result.failure("MapBalanceAnalyzer: drink_sources[%d].world_pos 缺失或类型错误" % i)
		var type_val = source.get("type", null)
		if not (type_val is String) or str(type_val).strip_edges().is_empty():
			return Result.failure("MapBalanceAnalyzer: drink_sources[%d].type 缺失或类型错误" % i)
		out.append({
			"index": i,
			"world_pos": pos_val,
			"type": str(type_val).strip_edges(),
			"tile_id": str(source.get("tile_id", "")),
		})
	return Result.success(out)

static func _is_starting_house(house: Dictionary) -> bool:
	if not house.has("printed"):
		return true
	var printed_val = house.get("printed", null)
	if printed_val is bool:
		return bool(printed_val)
	return true

static func _read_vec2i_array_or_anchor(data: Dictionary, cells_key: String, anchor_key: String, path: String) -> Result:
	var cells_val = data.get(cells_key, null)
	if cells_val is Array:
		var parsed: Array[Vector2i] = []
		var arr: Array = cells_val
		for i in range(arr.size()):
			var pos_val = _to_vec2i(arr[i])
			if not (pos_val is Vector2i):
				return Result.failure("MapBalanceAnalyzer: %s.%s[%d] 类型错误（期望 Vector2i）" % [path, cells_key, i])
			parsed.append(pos_val)
		return Result.success(parsed)

	var anchor_val = _to_vec2i(data.get(anchor_key, null))
	if anchor_val is Vector2i:
		return Result.success([anchor_val])
	return Result.failure("MapBalanceAnalyzer: %s 缺少 %s 或 %s" % [path, cells_key, anchor_key])

static func _build_neighborhoods(input: Dictionary, graph) -> Dictionary:
	var items: Array[Dictionary] = []
	var by_id: Dictionary = {}
	var ids: Array = graph._block_regions.keys()
	ids.sort()
	for id_val in ids:
		var region_id := int(id_val)
		var cells_val = graph._block_regions[id_val]
		var region_cells: Array = cells_val if cells_val is Array else []
		var empty_spaces := 0
		for pos_val in region_cells:
			if pos_val is Vector2i and _is_empty_buildable_cell(input, pos_val):
				empty_spaces += 1
		var stat := {
			"id": region_id,
			"total_spaces": region_cells.size(),
			"empty_spaces": empty_spaces,
			"starting_house_ids": [],
			"starting_house_count": 0,
		}
		items.append(stat)
		by_id[region_id] = stat
	return {
		"items": items,
		"by_id": by_id,
	}

static func _build_road_systems(graph) -> Dictionary:
	var adjacency := _build_undirected_adjacency(graph)
	var node_keys: Array = graph._nodes.keys()
	node_keys.sort()

	var visited: Dictionary = {}
	var component_ids_by_pos: Dictionary = {}
	var items: Array[Dictionary] = []
	var by_id: Dictionary = {}

	for node_key_val in node_keys:
		var node_key := str(node_key_val)
		if visited.has(node_key):
			continue
		var component_id := items.size()
		var queue: Array[String] = [node_key]
		var component_nodes: Array[String] = []
		var position_set: Dictionary = {}
		visited[node_key] = true

		while not queue.is_empty():
			var current: String = str(queue.pop_front())
			component_nodes.append(current)
			var node_data: Dictionary = graph._nodes[current]
			var pos: Vector2i = node_data.get("pos", Vector2i.ZERO)
			position_set[pos] = true

			var neighbors: Array = adjacency.get(current, [])
			for next_val in neighbors:
				var next_key := str(next_val)
				if visited.has(next_key):
					continue
				visited[next_key] = true
				queue.append(next_key)

		var positions: Array[Vector2i] = []
		for pos_key in position_set.keys():
			if pos_key is Vector2i:
				positions.append(pos_key)
				var existing: Array = component_ids_by_pos.get(pos_key, [])
				existing.append(component_id)
				component_ids_by_pos[pos_key] = existing
		_sort_positions(positions)

		var stat := {
			"id": component_id,
			"node_count": component_nodes.size(),
			"road_cell_count": positions.size(),
			# route_count 当前以道路节点数近似；后续可替换为更贴近 BGH 定义的路线计数。
			"route_count": component_nodes.size(),
			"positions": positions,
			"starting_house_ids": [],
			"starting_house_count": 0,
			"drink_source_indexes": [],
			"drink_location_count": 0,
		}
		items.append(stat)
		by_id[component_id] = stat

	return {
		"items": items,
		"by_id": by_id,
		"component_ids_by_pos": component_ids_by_pos,
	}

static func _build_undirected_adjacency(graph) -> Dictionary:
	var adjacency: Dictionary = {}
	for key_val in graph._nodes.keys():
		adjacency[str(key_val)] = []
	for from_val in graph._edges.keys():
		var from_key := str(from_val)
		var edges: Array = graph._edges.get(from_key, [])
		for edge_val in edges:
			if not (edge_val is Dictionary):
				continue
			var edge: Dictionary = edge_val
			var to_key := str(edge.get("to", ""))
			if to_key.is_empty() or not adjacency.has(to_key):
				continue
			_append_unique(adjacency[from_key], to_key)
			_append_unique(adjacency[to_key], from_key)
	return adjacency

static func _assign_houses_to_neighborhoods(bundle: Dictionary, graph, houses: Array[Dictionary]) -> void:
	var by_id: Dictionary = bundle.get("by_id", {})
	for house in houses:
		var block_ids := _block_ids_for_positions(graph, house.get("cells", []))
		for block_id in block_ids:
			if not by_id.has(block_id):
				continue
			var stat: Dictionary = by_id[block_id]
			var ids: Array = stat.get("starting_house_ids", [])
			_append_unique(ids, str(house.get("house_id", "")))
			stat["starting_house_ids"] = ids
			stat["starting_house_count"] = ids.size()
			by_id[block_id] = stat

static func _assign_houses_to_road_systems(bundle: Dictionary, houses: Array[Dictionary]) -> void:
	var by_id: Dictionary = bundle.get("by_id", {})
	var component_ids_by_pos: Dictionary = bundle.get("component_ids_by_pos", {})
	for house in houses:
		var component_ids := _road_component_ids_touching_positions(component_ids_by_pos, house.get("cells", []))
		for component_id in component_ids:
			if not by_id.has(component_id):
				continue
			var stat: Dictionary = by_id[component_id]
			var ids: Array = stat.get("starting_house_ids", [])
			_append_unique(ids, str(house.get("house_id", "")))
			stat["starting_house_ids"] = ids
			stat["starting_house_count"] = ids.size()
			by_id[component_id] = stat

static func _assign_drinks_to_road_systems(bundle: Dictionary, drink_sources: Array[Dictionary]) -> void:
	var by_id: Dictionary = bundle.get("by_id", {})
	var component_ids_by_pos: Dictionary = bundle.get("component_ids_by_pos", {})
	for source in drink_sources:
		var pos_val = source.get("world_pos", null)
		if not (pos_val is Vector2i):
			continue
		var component_ids := _road_component_ids_touching_positions(component_ids_by_pos, [pos_val])
		for component_id in component_ids:
			if not by_id.has(component_id):
				continue
			var stat: Dictionary = by_id[component_id]
			var ids: Array = stat.get("drink_source_indexes", [])
			_append_unique(ids, int(source.get("index", -1)))
			stat["drink_source_indexes"] = ids
			stat["drink_location_count"] = ids.size()
			by_id[component_id] = stat

static func _build_analysis(
	map_data: Dictionary,
	player_count: int,
	input: Dictionary,
	starting_houses: Array[Dictionary],
	drink_sources: Array[Dictionary],
	neighborhoods: Array[Dictionary],
	road_systems: Array[Dictionary]
) -> Dictionary:
	var drink_counts := _count_drinks_by_type(drink_sources)
	var max_houses_in_neighborhood := _max_int_field(neighborhoods, "starting_house_count")
	var max_houses_on_road_system := _max_int_field(road_systems, "starting_house_count")
	var max_drinks_on_road_system := _max_int_field(road_systems, "drink_location_count")
	var largest_neighborhood_total := _max_int_field(neighborhoods, "total_spaces")
	var largest_neighborhood_empty := _max_int_field(neighborhoods, "empty_spaces")
	var largest_road_route := _max_int_field(road_systems, "route_count")
	var total_houses := starting_houses.size()

	var tile_placements_val = map_data.get("tile_placements", [])
	var tile_count: int = tile_placements_val.size() if tile_placements_val is Array else 0

	return {
		"player_count": player_count,
		"grid_size": input.get("grid_size", Vector2i.ZERO),
		"tile_count": tile_count,
		"total_starting_houses": total_houses,
		"total_drink_locations": drink_sources.size(),
		"drink_counts_by_type": drink_counts,
		"neighborhood_count": neighborhoods.size(),
		"road_system_count": road_systems.size(),
		"max_starting_houses_in_neighborhood": max_houses_in_neighborhood,
		"max_starting_houses_in_neighborhood_ratio": _ratio(max_houses_in_neighborhood, total_houses),
		"max_starting_houses_on_road_system": max_houses_on_road_system,
		"max_starting_houses_on_road_system_ratio": _ratio(max_houses_on_road_system, total_houses),
		"max_drink_locations_on_road_system": max_drinks_on_road_system,
		"largest_neighborhood_total_spaces": largest_neighborhood_total,
		"largest_neighborhood_empty_spaces": largest_neighborhood_empty,
		"largest_road_system_route_count": largest_road_route,
		"starting_houses": starting_houses,
		"drink_sources": drink_sources,
		"neighborhoods": neighborhoods,
		"road_systems": road_systems,
	}

static func _block_ids_for_positions(graph, positions_val) -> Array[int]:
	var out_set: Dictionary = {}
	var positions: Array = positions_val if positions_val is Array else []
	for pos_val in positions:
		if not (pos_val is Vector2i):
			continue
		var block_id := int(graph.get_block_id(pos_val))
		if block_id >= 0:
			out_set[block_id] = true
	var out: Array[int] = []
	for id_val in out_set.keys():
		out.append(int(id_val))
	out.sort()
	return out

static func _road_component_ids_touching_positions(component_ids_by_pos: Dictionary, positions_val) -> Array[int]:
	var out_set: Dictionary = {}
	var positions: Array = positions_val if positions_val is Array else []
	for pos_val in positions:
		if not (pos_val is Vector2i):
			continue
		_add_component_ids_at_pos(out_set, component_ids_by_pos, pos_val)
		for dir in MapUtils.DIRECTIONS:
			_add_component_ids_at_pos(out_set, component_ids_by_pos, MapUtils.get_neighbor_pos(pos_val, dir))
	var out: Array[int] = []
	for id_val in out_set.keys():
		out.append(int(id_val))
	out.sort()
	return out

static func _add_component_ids_at_pos(out_set: Dictionary, component_ids_by_pos: Dictionary, pos: Vector2i) -> void:
	var ids_val = component_ids_by_pos.get(pos, null)
	if not (ids_val is Array):
		return
	var ids: Array = ids_val
	for id_val in ids:
		out_set[int(id_val)] = true

static func _is_empty_buildable_cell(input: Dictionary, world_pos: Vector2i) -> bool:
	var cell := _get_cell(input, world_pos)
	if cell.is_empty():
		return false
	if bool(cell.get("blocked", false)):
		return false
	var roads_val = cell.get("road_segments", [])
	if roads_val is Array and not roads_val.is_empty():
		return false
	var structure_val = cell.get("structure", null)
	if structure_val is Dictionary and not structure_val.is_empty():
		return false
	var drink_val = cell.get("drink_source", null)
	if drink_val is Dictionary and not drink_val.is_empty():
		return false
	return true

static func _get_cell(input: Dictionary, world_pos: Vector2i) -> Dictionary:
	var cells: Array = input.get("cells", [])
	var grid_size: Vector2i = input.get("grid_size", Vector2i.ZERO)
	var origin: Vector2i = input.get("map_origin", Vector2i.ZERO)
	var idx := world_pos + origin
	if idx.x < 0 or idx.y < 0 or idx.x >= grid_size.x or idx.y >= grid_size.y:
		return {}
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return {}
	var row: Array = row_val
	var cell_val = row[idx.x]
	return cell_val if cell_val is Dictionary else {}

static func _count_drinks_by_type(drink_sources: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for source in drink_sources:
		var drink_type := str(source.get("type", ""))
		if drink_type.is_empty():
			continue
		counts[drink_type] = int(counts.get(drink_type, 0)) + 1
	return counts

static func _max_int_field(items: Array[Dictionary], field: String) -> int:
	var out := 0
	for item in items:
		out = maxi(out, int(item.get(field, 0)))
	return out

static func _ratio(part: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(part) / float(total)

static func _append_unique(arr: Array, value) -> void:
	if not arr.has(value):
		arr.append(value)

static func _sort_positions(positions: Array[Vector2i]) -> void:
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

static func _to_vec2i(value):
	if value is Vector2i:
		return value
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2 and _is_intish(arr[0]) and _is_intish(arr[1]):
			return Vector2i(int(arr[0]), int(arr[1]))
	return null

static func _is_intish(value) -> bool:
	if value is int:
		return true
	if value is float:
		var f := float(value)
		return f == floor(f)
	return false

static func _read_boolish(value) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) != 0
	if value is float:
		var f := float(value)
		if f == floor(f):
			return int(f) != 0
	return false
