# 距离/范围工具（对外入口）
# 负责：road/air range 判断、道路邻接格计算等可复用逻辑。
#
# NOTE: RangeUtils 的实现拆分到两个文件中，避免单文件过大：
# - `core/utils/range_utils_road.gd`：道路范围（RoadGraph 距离、邻接道路格）
# - `core/utils/range_utils_air.gd`：空中范围（Manhattan 距离）
class_name RangeUtils
extends RefCounted

const Road := preload("res://core/utils/range_utils_road.gd")
const Air := preload("res://core/utils/range_utils_air.gd")

static func get_adjacent_road_cells(state: GameState, anchor: Vector2i) -> Result:
	return Road.get_adjacent_road_cells(state, anchor)

static func get_adjacent_road_cells_for_positions(state: GameState, positions: Array) -> Result:
	return Road.get_adjacent_road_cells_for_positions(state, positions)

static func is_within_road_range_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i],
	max_distance: int
) -> Result:
	return Road.is_within_road_range_to_any_road_cells(
		state,
		actor,
		restaurant_ids,
		target_road_cells,
		max_distance
	)

static func get_min_road_distance_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i]
) -> Result:
	return Road.get_min_road_distance_to_any_road_cells(state, actor, restaurant_ids, target_road_cells)

static func is_within_air_range_to_any_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_cells: Array[Vector2i],
	max_steps: int
) -> Result:
	return Air.is_within_air_range_to_any_cells(state, actor, restaurant_ids, target_cells, max_steps)

static func is_within_road_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_distance: int
) -> Result:
	return Road.is_within_road_range(state, actor, restaurant_ids, target_pos, max_distance)

static func is_within_air_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_steps: int
) -> Result:
	return Air.is_within_air_range(state, actor, restaurant_ids, target_pos, max_steps)
