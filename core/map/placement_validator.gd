# 放置验证器（Fail Fast）
# 提供统一的建筑物放置验证 API（缺字段/类型错直接 assert；规则不满足返回 Result.failure）
class_name PlacementValidator
extends RefCounted

const Placement = preload("res://core/map/placement_validator/placement.gd")
const RestaurantPlacement = preload("res://core/map/placement_validator/restaurant_placement.gd")
const GardenAttachment = preload("res://core/map/placement_validator/garden_attachment.gd")
const RoadUtils = preload("res://core/map/placement_validator/road_utils.gd")

static func validate_placement(
	map_ctx: Dictionary,
	piece_id: String,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	context: Dictionary = {}
) -> Result:
	return Placement.validate_placement(map_ctx, piece_id, world_anchor, rotation, piece_registry, context)

static func validate_restaurant_placement(
	map_ctx: Dictionary,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	_player_id: int,
	is_initial_placement: bool,
	context: Dictionary = {}
) -> Result:
	return RestaurantPlacement.validate_restaurant_placement(map_ctx, world_anchor, rotation, piece_registry, _player_id, is_initial_placement, context)

static func validate_house_placement(
	map_ctx: Dictionary,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	_player_id: int,
	context: Dictionary = {}
) -> Result:
	return Placement.validate_placement(map_ctx, "house", world_anchor, rotation, piece_registry, context)

static func validate_garden_attachment(
	map_ctx: Dictionary,
	house_id: String,
	garden_direction: String,
	_piece_registry: Dictionary,
	_context: Dictionary = {}
) -> Result:
	return GardenAttachment.validate_garden_attachment(map_ctx, house_id, garden_direction, _piece_registry, _context)

static func get_valid_placements(
	map_ctx: Dictionary,
	piece_id: String,
	piece_registry: Dictionary,
	context: Dictionary = {}
) -> Array[Dictionary]:
	return Placement.get_valid_placements(map_ctx, piece_id, piece_registry, context)

static func is_adjacent_to_road(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return RoadUtils.is_adjacent_to_road(cells, pos, grid_size)

static func get_adjacent_road_cells(cells: Array, positions: Array[Vector2i], grid_size: Vector2i) -> Array[Vector2i]:
	return RoadUtils.get_adjacent_road_cells(cells, positions, grid_size)
