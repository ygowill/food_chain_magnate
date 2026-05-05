class_name BoardAnalyzer
extends RefCounted

const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const StructureDistanceClass = preload("res://core/map/map_runtime/structure_distance.gd")

static func analyze_state(state: GameState) -> Result:
	if state == null:
		return Result.failure("BoardAnalyzer.analyze_state: state is null")
	var context_read := MapContextBuilderClass.build_context_result(state, "BoardAnalyzer.analyze_state")
	if not context_read.ok:
		return context_read
	var context: Dictionary = context_read.value
	var houses: Dictionary = context.get("houses", {})
	var restaurants: Dictionary = context.get("restaurants", {})
	var grid_size: Vector2i = context.get("grid_size", Vector2i.ZERO)
	var road_graph = RoadGraphCacheClass.get_road_graph(state)

	var house_ids_read := StructuresClass.get_sorted_house_ids(state)
	if not house_ids_read.ok:
		return house_ids_read
	var house_ids: Array[String] = house_ids_read.value
	var restaurant_ids := _sorted_string_keys(restaurants)

	var entrances_read := _build_restaurant_entrance_points(state, restaurants, restaurant_ids)
	if not entrances_read.ok:
		return entrances_read

	var distances_read := _build_restaurant_house_distances(
		state,
		road_graph,
		grid_size,
		houses,
		restaurants,
		house_ids,
		restaurant_ids
	)
	if not distances_read.ok:
		return distances_read

	return Result.success({
		"grid_size": grid_size,
		"house_ids": house_ids.duplicate(),
		"restaurant_ids": restaurant_ids.duplicate(),
		"houses": houses.duplicate(true),
		"restaurants": restaurants.duplicate(true),
		"drink_sources": _copy_array(context.get("drink_sources", [])),
		"marketing_placements": Dictionary(context.get("marketing_placements", {})).duplicate(true),
		"road_graph_available": road_graph != null,
		"restaurant_entrance_points": entrances_read.value,
		"restaurant_house_distances": distances_read.value,
	})

static func _build_restaurant_entrance_points(
	state: GameState,
	restaurants: Dictionary,
	restaurant_ids: Array[String]
) -> Result:
	var out := {}
	for restaurant_id in restaurant_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			return Result.failure("BoardAnalyzer: restaurants[%s] is not Dictionary" % restaurant_id)
		var entrance_read := StructuresClass.get_restaurant_entrance_points(state, restaurant_id, rest_val)
		if not entrance_read.ok:
			return entrance_read
		out[restaurant_id] = _copy_array(entrance_read.value)
	return Result.success(out)

static func _build_restaurant_house_distances(
	state: GameState,
	road_graph,
	grid_size: Vector2i,
	houses: Dictionary,
	restaurants: Dictionary,
	house_ids: Array[String],
	restaurant_ids: Array[String]
) -> Result:
	var out := {}
	if road_graph == null:
		return Result.success(out)
	for restaurant_id in restaurant_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			return Result.failure("BoardAnalyzer: restaurants[%s] is not Dictionary" % restaurant_id)
		var per_house := {}
		for house_id in house_ids:
			var house_val = houses.get(house_id, null)
			if not (house_val is Dictionary):
				return Result.failure("BoardAnalyzer: houses[%s] is not Dictionary" % house_id)
			var dist_read := StructureDistanceClass.get_restaurant_to_house_distance(
				road_graph,
				state,
				grid_size,
				restaurant_id,
				rest_val,
				house_id,
				house_val
			)
			if not dist_read.ok:
				return dist_read
			if dist_read.value is Dictionary and not Dictionary(dist_read.value).is_empty():
				per_house[house_id] = Dictionary(dist_read.value).duplicate(true)
		out[restaurant_id] = per_house
	return Result.success(out)

static func _sorted_string_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		if key is String:
			out.append(str(key))
	out.sort()
	return out

static func _copy_array(value) -> Array:
	if value is Array:
		return Array(value).duplicate(true)
	return []
