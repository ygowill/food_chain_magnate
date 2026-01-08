# 地图运行时工具（Fail Fast）
# 负责：将 MapBaker 的 baked 数据写入 GameState.map，并提供 RoadGraph 缓存与常用查询。
class_name MapRuntime
extends RefCounted

const MapBakerClass = preload("res://core/map/map_baker.gd")
const RoadGraphClass = preload("res://core/map/road_graph.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")
const BakedMap = preload("res://core/map/map_runtime/baked_map.gd")
const RoadGraphCache = preload("res://core/map/map_runtime/road_graph_cache.gd")
const Coords = preload("res://core/map/map_runtime/coords.gd")
const Cells = preload("res://core/map/map_runtime/cells.gd")
const TileEdit = preload("res://core/map/map_runtime/tile_edit.gd")
const Structures = preload("res://core/map/map_runtime/structures.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"
const _EXTERNAL_TILE_PLACEMENTS_KEY := "external_tile_placements"
const _MAP_ORIGIN_KEY := "map_origin"

static func apply_baked_map(state, baked_data: Dictionary) -> Result:
	return BakedMap.apply_baked_map(state, baked_data)

static func get_road_graph(state) -> RefCounted:
	return RoadGraphCache.get_road_graph(state)

static func invalidate_road_graph(state) -> void:
	RoadGraphCache.invalidate_road_graph(state)

static func get_map_origin(state) -> Vector2i:
	return Coords.get_map_origin(state)

static func set_map_origin(state, origin: Vector2i) -> void:
	Coords.set_map_origin(state, origin)

static func world_to_index(state, world_pos: Vector2i) -> Vector2i:
	return Coords.world_to_index(state, world_pos)

static func index_to_world(state, index_pos: Vector2i) -> Vector2i:
	return Coords.index_to_world(state, index_pos)

static func get_world_min(state) -> Vector2i:
	return Coords.get_world_min(state)

static func get_world_max(state) -> Vector2i:
	return Coords.get_world_max(state)

static func is_world_pos_in_grid(state, world_pos: Vector2i) -> bool:
	return Coords.is_world_pos_in_grid(state, world_pos)

static func is_on_map_edge(state, world_pos: Vector2i) -> bool:
	return Coords.is_on_map_edge(state, world_pos)

static func get_cell(state, pos: Vector2i) -> Dictionary:
	return Cells.get_cell(state, pos)

static func has_cell_any(state, pos: Vector2i) -> bool:
	return Cells.has_cell_any(state, pos)

static func get_cell_any(state, pos: Vector2i) -> Dictionary:
	return Cells.get_cell_any(state, pos)

static func has_road_at(state, pos: Vector2i) -> bool:
	return Cells.has_road_at(state, pos)

static func has_road_at_any(state, pos: Vector2i) -> bool:
	return Cells.has_road_at_any(state, pos)

static func has_structure_at(state, pos: Vector2i) -> bool:
	return Cells.has_structure_at(state, pos)

static func add_map_tile(
	state,
	tile_def: TileDef,
	piece_registry: Dictionary,
	board_pos: Vector2i,
	rotation: int
) -> Result:
	return TileEdit.add_map_tile(state, tile_def, piece_registry, board_pos, rotation)

static func ensure_world_rect(state, desired_min: Vector2i, desired_max: Vector2i) -> Result:
	return TileEdit.ensure_world_rect(state, desired_min, desired_max)

static func get_house(state, house_id: String) -> Dictionary:
	return Structures.get_house(state, house_id)

static func get_restaurant(state, restaurant_id: String) -> Dictionary:
	return Structures.get_restaurant(state, restaurant_id)

static func get_player_restaurants(state, player_id: int) -> Array[String]:
	return Structures.get_player_restaurants(state, player_id)

static func get_sorted_house_ids(state) -> Array[String]:
	return Structures.get_sorted_house_ids(state)
