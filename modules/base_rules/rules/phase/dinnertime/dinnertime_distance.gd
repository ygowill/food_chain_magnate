# DinnertimeSettlement：路径/距离计算辅助
class_name DinnertimeDistance
extends RefCounted

const StructureDistanceClass = preload("res://core/map/map_runtime/structure_distance.gd")

static func get_restaurant_to_house_distance(
	road_graph,
	state: GameState,
	grid_size: Vector2i,
	restaurant_id: String,
	rest: Dictionary,
	house_id: String,
	house: Dictionary
) -> Result:
	var read := StructureDistanceClass.get_restaurant_to_house_distance(
		road_graph,
		state,
		grid_size,
		restaurant_id,
		rest,
		house_id,
		house
	)
	if not read.ok:
		return Result.failure("晚餐结算失败：%s" % read.error)
	return read

static func get_restaurant_entrance_points(state: GameState, restaurant_id: String, rest: Dictionary) -> Result:
	var read := StructureDistanceClass.get_restaurant_entrance_points(state, restaurant_id, rest)
	if not read.ok:
		return Result.failure("晚餐结算失败：%s" % read.error)
	return read

static func get_structure_adjacent_roads(state: GameState, grid_size: Vector2i, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	return StructureDistanceClass.get_structure_adjacent_roads(state, grid_size, structure_cells)
