class_name StrategyBoardAnalyzer
extends RefCounted

const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")

const IDEAL_SERVICE_DISTANCE := 4
const MAX_HEURISTIC_DISTANCE := 8

static func restaurant_placement_value(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	source_state = null,
	action_id: String = "",
	actor_id: int = -1
) -> Dictionary:
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	if source_state is GameState:
		var road_payload := _restaurant_placement_value_from_source(
			source_state,
			observation,
			params,
			income_analysis,
			action_id,
			actor_id
		)
		if not road_payload.is_empty():
			return road_payload
	var houses_val = observation.map_public.get("houses", {}) if observation != null else {}
	if not (houses_val is Dictionary):
		return _empty_restaurant_payload(anchor)
	var houses: Dictionary = houses_val
	var nearest_distance := 2147483647
	var nearby_houses := 0
	var nearby_demand := 0
	var total_demand := 0
	var unserviceable_demand_covered := 0
	var house_value := 0.0
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var house_anchor := _read_vector2i(house.get("anchor_pos", Vector2i.ZERO))
		var distance := absi(anchor.x - house_anchor.x) + absi(anchor.y - house_anchor.y)
		nearest_distance = mini(nearest_distance, distance)
		var demand_count := _house_demand_count(house)
		total_demand += demand_count
		var house_base := maxf(0.0, float(MAX_HEURISTIC_DISTANCE - distance))
		if distance <= IDEAL_SERVICE_DISTANCE:
			nearby_houses += 1
			nearby_demand += demand_count
		house_value += house_base * 0.75
		if demand_count > 0:
			house_value += house_base * float(demand_count) * 2.0
			if observation != null and _min_house_distance_to_owned_restaurant(observation, house_id) < 0:
				unserviceable_demand_covered += demand_count
				house_value += house_base * float(demand_count) * 1.25
	var own_restaurants := int(income_analysis.get("own_restaurants", 0))
	if own_restaurants <= 0 and nearby_houses > 0:
		house_value += 10.0
	if total_demand > 0 and nearby_demand <= 0:
		house_value -= 8.0
	var nearest := nearest_distance if nearest_distance < 2147483647 else -1
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": nearest,
		"nearby_houses": nearby_houses,
		"nearby_demand": nearby_demand,
		"total_public_demand": total_demand,
		"unserviceable_demand_covered": unserviceable_demand_covered,
		"placement_value": house_value,
		"distance_source": "anchor",
	}

static func _restaurant_placement_value_from_source(
	source_state: GameState,
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	action_id: String,
	actor_id: int
) -> Dictionary:
	var player_id := actor_id
	if player_id < 0 and observation != null:
		player_id = int(observation.viewer_player_id)
	if player_id < 0:
		return {}

	var state := source_state.duplicate_state()
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var rotation := int(params.get("rotation", 0))
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, "StrategyBoardAnalyzer.restaurant_placement_value")
	if not map_ctx_read.ok:
		return {}
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := PieceDefClass.create_default_registry()
	var restaurant_id := ""
	var existing_owned_ids := _owned_restaurant_ids(observation, source_state, player_id)

	if action_id == "move_restaurant":
		restaurant_id = str(params.get("restaurant_id", "")).strip_edges()
		if restaurant_id.is_empty():
			return {}
		existing_owned_ids.erase(restaurant_id)
		var move_read := _apply_hypothetical_move(state, map_ctx, piece_registry, player_id, restaurant_id, anchor, rotation)
		if not move_read.ok:
			return {}
	else:
		restaurant_id = _candidate_restaurant_id(state)
		var place_read := _apply_hypothetical_place(state, map_ctx, piece_registry, player_id, restaurant_id, anchor, rotation)
		if not place_read.ok:
			return {}

	RoadGraphCacheClass.invalidate_road_graph(state)
	var analysis_read := BoardAnalyzerClass.analyze_state(state)
	if not analysis_read.ok:
		return {}
	var analysis: Dictionary = analysis_read.value
	if not bool(analysis.get("road_graph_available", false)):
		return {}
	return _restaurant_payload_from_analysis(
		anchor,
		observation,
		income_analysis,
		analysis,
		restaurant_id,
		existing_owned_ids
	)

static func _apply_hypothetical_place(
	state: GameState,
	map_ctx: Dictionary,
	piece_registry: Dictionary,
	player_id: int,
	restaurant_id: String,
	anchor: Vector2i,
	rotation: int
) -> Result:
	var is_initial := str(state.phase) == DefsClass.PHASE_SETUP
	var validate_read := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx,
		anchor,
		rotation,
		piece_registry,
		player_id,
		is_initial,
		{}
	)
	if not validate_read.ok:
		return validate_read
	var payload_read := _read_placement_payload(validate_read.value)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var footprint_cells: Array[Vector2i] = payload["footprint_cells"]
	var entrance_pos: Vector2i = payload["entrance_pos"]
	_write_restaurant_cells(state, restaurant_id, player_id, anchor, rotation, footprint_cells)

	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: state.map.restaurants is not Dictionary")
	var restaurants: Dictionary = restaurants_val
	restaurants[restaurant_id] = {
		"restaurant_id": restaurant_id,
		"owner": player_id,
		"anchor_pos": anchor,
		"entrance_pos": entrance_pos,
		"cells": footprint_cells,
		"rotation": rotation,
	}
	state.map["restaurants"] = restaurants
	_add_player_restaurant_id(state, player_id, restaurant_id)
	return Result.success()

static func _apply_hypothetical_move(
	state: GameState,
	map_ctx: Dictionary,
	piece_registry: Dictionary,
	player_id: int,
	restaurant_id: String,
	anchor: Vector2i,
	rotation: int
) -> Result:
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: state.map.restaurants is not Dictionary")
	var restaurants: Dictionary = restaurants_val
	var rest_val = restaurants.get(restaurant_id, null)
	if not (rest_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: restaurant not found: %s" % restaurant_id)
	var rest: Dictionary = rest_val
	if int(rest.get("owner", -1)) != player_id:
		return Result.failure("StrategyBoardAnalyzer: restaurant owner mismatch: %s" % restaurant_id)
	var old_cells := _read_vector2i_array(rest.get("cells", []))
	if old_cells.is_empty():
		return Result.failure("StrategyBoardAnalyzer: restaurant cells missing: %s" % restaurant_id)

	var validate_read := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx,
		anchor,
		rotation,
		piece_registry,
		player_id,
		false,
		{"ignore_structure_cells": old_cells}
	)
	if not validate_read.ok:
		return validate_read
	var payload_read := _read_placement_payload(validate_read.value)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var new_cells: Array[Vector2i] = payload["footprint_cells"]
	var entrance_pos: Vector2i = payload["entrance_pos"]

	_clear_structure_cells(state, old_cells)
	_write_restaurant_cells(state, restaurant_id, player_id, anchor, rotation, new_cells)
	rest["anchor_pos"] = anchor
	rest["entrance_pos"] = entrance_pos
	rest["cells"] = new_cells
	rest["rotation"] = rotation
	restaurants[restaurant_id] = rest
	state.map["restaurants"] = restaurants
	return Result.success()

static func _read_placement_payload(value) -> Result:
	if not (value is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: placement payload is not Dictionary")
	var payload: Dictionary = value
	var footprint_cells := _read_vector2i_array(payload.get("footprint_cells", []))
	if footprint_cells.is_empty():
		return Result.failure("StrategyBoardAnalyzer: placement footprint_cells is empty")
	var entrance_val = payload.get("entrance_pos", null)
	if not (entrance_val is Vector2i):
		return Result.failure("StrategyBoardAnalyzer: placement entrance_pos missing")
	return Result.success({
		"footprint_cells": footprint_cells,
		"entrance_pos": entrance_val,
	})

static func _restaurant_payload_from_analysis(
	anchor: Vector2i,
	observation: ObservationState,
	income_analysis: Dictionary,
	analysis: Dictionary,
	candidate_restaurant_id: String,
	existing_owned_ids: Array[String]
) -> Dictionary:
	var houses_val = analysis.get("houses", {})
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	var distances_val = analysis.get("restaurant_house_distances", {})
	if not (distances_val is Dictionary):
		return {}
	var distances: Dictionary = distances_val
	if not distances.has(candidate_restaurant_id):
		return {}
	var candidate_distances_val = distances.get(candidate_restaurant_id, {})
	if not (candidate_distances_val is Dictionary):
		return {}
	var candidate_distances: Dictionary = candidate_distances_val

	var nearest_distance := 2147483647
	var nearby_houses := 0
	var nearby_demand := 0
	var total_demand := 0
	var unserviceable_demand_covered := 0
	var house_value := 0.0
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var demand_count := _house_demand_count(house)
		total_demand += demand_count
		var distance := _distance_for_house(candidate_distances, house_id)
		if distance < 0:
			continue
		nearest_distance = mini(nearest_distance, distance)
		var house_base := maxf(0.0, float(MAX_HEURISTIC_DISTANCE - distance))
		if distance <= IDEAL_SERVICE_DISTANCE:
			nearby_houses += 1
			nearby_demand += demand_count
		house_value += house_base * 0.75
		if demand_count > 0:
			house_value += house_base * float(demand_count) * 2.0
			if not _house_has_owned_road_distance(distances, existing_owned_ids, house_id):
				unserviceable_demand_covered += demand_count
				house_value += house_base * float(demand_count) * 1.25
	var own_restaurants := int(income_analysis.get("own_restaurants", 0))
	if own_restaurants <= 0 and nearby_houses > 0:
		house_value += 10.0
	if total_demand > 0 and nearby_demand <= 0:
		house_value -= 8.0
	var nearest := nearest_distance if nearest_distance < 2147483647 else -1
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": nearest,
		"nearby_houses": nearby_houses,
		"nearby_demand": nearby_demand,
		"total_public_demand": total_demand,
		"unserviceable_demand_covered": unserviceable_demand_covered,
		"placement_value": house_value,
		"distance_source": "road_graph",
	}

static func _distance_for_house(per_restaurant_distances: Dictionary, house_id: String) -> int:
	var info_val = per_restaurant_distances.get(house_id, null)
	if not (info_val is Dictionary):
		return -1
	var info: Dictionary = info_val
	if not info.has("distance"):
		return -1
	return int(info.get("distance", -1))

static func _house_has_owned_road_distance(
	distances: Dictionary,
	owned_restaurant_ids: Array[String],
	house_id: String
) -> bool:
	for restaurant_id in owned_restaurant_ids:
		var per_rest_val = distances.get(restaurant_id, null)
		if not (per_rest_val is Dictionary):
			continue
		if _distance_for_house(per_rest_val, house_id) >= 0:
			return true
	return false

static func _empty_restaurant_payload(anchor: Vector2i) -> Dictionary:
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": -1,
		"nearby_houses": 0,
		"nearby_demand": 0,
		"total_public_demand": 0,
		"unserviceable_demand_covered": 0,
		"placement_value": 0.0,
		"distance_source": "anchor",
	}

static func _house_demand_count(house: Dictionary) -> int:
	var demands_val = house.get("demands", [])
	if demands_val is Array:
		return Array(demands_val).size()
	return 0

static func _min_house_distance_to_owned_restaurant(observation: ObservationState, house_id: String) -> int:
	if observation == null or house_id.is_empty():
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var houses: Dictionary = houses_val
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return -1
	var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var own_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var best := 2147483647
	for restaurant_id in own_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var rest_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i.ZERO))
		var distance := absi(house_anchor.x - rest_anchor.x) + absi(house_anchor.y - rest_anchor.y)
		best = mini(best, distance)
	return best if best < 2147483647 else -1

static func _owned_restaurant_ids(observation: ObservationState, state: GameState, player_id: int) -> Array[String]:
	if observation != null:
		return _sorted_unique_strings(observation.own_player.get("restaurants", []))
	if state != null and player_id >= 0 and player_id < state.players.size():
		var player_val = state.players[player_id]
		if player_val is Dictionary:
			return _sorted_unique_strings(Dictionary(player_val).get("restaurants", []))
	return []

static func _candidate_restaurant_id(state: GameState) -> String:
	var restaurants_val = state.map.get("restaurants", {}) if state != null else {}
	var restaurants: Dictionary = restaurants_val if restaurants_val is Dictionary else {}
	var base_id := "__strategy_candidate_restaurant__"
	var candidate_id := base_id
	var index := 1
	while restaurants.has(candidate_id):
		candidate_id = "%s_%d" % [base_id, index]
		index += 1
	return candidate_id

static func _add_player_restaurant_id(state: GameState, player_id: int, restaurant_id: String) -> void:
	if state == null or restaurant_id.is_empty():
		return
	if player_id < 0 or player_id >= state.players.size():
		return
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return
	var player: Dictionary = player_val
	var restaurants: Array = []
	var restaurants_val = player.get("restaurants", [])
	if restaurants_val is Array:
		restaurants = Array(restaurants_val).duplicate()
	if not restaurants.has(restaurant_id):
		restaurants.append(restaurant_id)
	player["restaurants"] = restaurants
	state.players[player_id] = player

static func _write_restaurant_cells(
	state: GameState,
	restaurant_id: String,
	player_id: int,
	anchor: Vector2i,
	rotation: int,
	footprint_cells: Array[Vector2i]
) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var cells_val = state.map.get("cells", [])
	if not (cells_val is Array):
		return
	var cells: Array = cells_val
	for cell_pos in footprint_cells:
		var idx := CoordsClass.world_to_index(state, cell_pos)
		if idx.y < 0 or idx.y >= cells.size():
			continue
		var row_val = cells[idx.y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		if idx.x < 0 or idx.x >= row.size():
			continue
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		cell["structure"] = {
			"piece_id": "restaurant",
			"owner": player_id,
			"anchor_cell": cell_pos == anchor,
			"parent_anchor": anchor,
			"rotation": rotation,
			"restaurant_id": restaurant_id,
			"dynamic": true,
		}
		row[idx.x] = cell
		cells[idx.y] = row
	state.map["cells"] = cells

static func _clear_structure_cells(state: GameState, footprint_cells: Array[Vector2i]) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var cells_val = state.map.get("cells", [])
	if not (cells_val is Array):
		return
	var cells: Array = cells_val
	for cell_pos in footprint_cells:
		var idx := CoordsClass.world_to_index(state, cell_pos)
		if idx.y < 0 or idx.y >= cells.size():
			continue
		var row_val = cells[idx.y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		if idx.x < 0 or idx.x >= row.size():
			continue
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		cell["structure"] = {}
		row[idx.x] = cell
		cells[idx.y] = row
	state.map["cells"] = cells

static func _read_vector2i_array(value) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not (value is Array):
		return out
	for item in Array(value):
		if item is Vector2i:
			out.append(Vector2i(item))
		elif item is Vector2:
			var v2: Vector2 = item
			out.append(Vector2i(int(v2.x), int(v2.y)))
		elif item is Array:
			var arr: Array = item
			if arr.size() >= 2:
				out.append(Vector2i(int(arr[0]), int(arr[1])))
	return out

static func _read_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return Vector2i(value)
	if value is Vector2:
		var v2: Vector2 = value
		return Vector2i(int(v2.x), int(v2.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y"):
			return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	return Vector2i.ZERO

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
