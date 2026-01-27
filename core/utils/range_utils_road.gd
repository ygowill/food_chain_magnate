# RangeUtils：道路距离/范围实现
# 目的：拆分 RangeUtils 的职责，避免单文件过大；本文件作为对外 wrapper。
extends RefCounted

const AdjacentCellsClass = preload("res://core/utils/range_utils_road/adjacent_cells.gd")
const DistanceQueriesClass = preload("res://core/utils/range_utils_road/distance_queries.gd")

static func get_adjacent_road_cells(state: GameState, anchor: Vector2i) -> Result:
	return AdjacentCellsClass.get_adjacent_road_cells(state, anchor)

static func get_adjacent_road_cells_for_positions(state: GameState, positions: Array) -> Result:
	return AdjacentCellsClass.get_adjacent_road_cells_for_positions(state, positions)

static func is_within_road_range_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i],
	max_distance: int
) -> Result:
	return DistanceQueriesClass.is_within_road_range_to_any_road_cells(state, actor, restaurant_ids, target_road_cells, max_distance)

static func get_min_road_distance_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i]
) -> Result:
	return DistanceQueriesClass.get_min_road_distance_to_any_road_cells(state, actor, restaurant_ids, target_road_cells)

static func is_within_road_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_distance: int
) -> Result:
	return DistanceQueriesClass.is_within_road_range(state, actor, restaurant_ids, target_pos, max_distance)
