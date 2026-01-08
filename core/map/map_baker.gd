# 地图烘焙器
# 将 TileDef/MapDef 转换为运行时的 map.cells 网格结构
class_name MapBaker
extends RefCounted

const Bake = preload("res://core/map/map_baker/bake.gd")
const Cells = preload("res://core/map/map_baker/cells.gd")
const TileBaking = preload("res://core/map/map_baker/tile_baking.gd")
const BoundaryIndex = preload("res://core/map/map_baker/boundary_index.gd")
const Queries = preload("res://core/map/map_baker/queries.gd")
const Debug = preload("res://core/map/map_baker/debug.gd")

# === 烘焙主入口 ===

# 烘焙地图定义为运行时数据
# map_def: 地图定义
# tile_registry: 板块注册表 { tile_id -> TileDef }
# piece_registry: 建筑件注册表 { piece_id -> PieceDef }
static func bake(map_def: MapDef, tile_registry: Dictionary,
				 piece_registry: Dictionary = {}) -> Result:
	return Bake.bake(map_def, tile_registry, piece_registry)

# === 格子网格创建 ===

static func _create_empty_cells(grid_size: Vector2i) -> Array:
	return Cells.create_empty_cells(grid_size)

static func _create_empty_cell() -> Dictionary:
	return Cells.create_empty_cell()

# === 板块烘焙 ===

static func _bake_tile(cells: Array, tile_def: TileDef, board_pos: Vector2i,
					   rotation: int, piece_registry: Dictionary,
					   houses: Dictionary, drink_sources: Array) -> Result:
	return TileBaking.bake_tile(cells, tile_def, board_pos, rotation, piece_registry, houses, drink_sources)

static func bake_tile_into_cells(
	cells: Array,
	grid_size: Vector2i,
	map_origin: Vector2i,
	tile_def: TileDef,
	board_pos: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	houses: Dictionary,
	drink_sources: Array
) -> Result:
	return TileBaking.bake_tile_into_cells(
		cells,
		grid_size,
		map_origin,
		tile_def,
		board_pos,
		rotation,
		piece_registry,
		houses,
		drink_sources
	)

# === 边界索引构建 ===

static func _build_boundary_index(tile_grid_size: Vector2i) -> Dictionary:
	return BoundaryIndex.build_boundary_index(tile_grid_size)

# === 工具方法 ===

# 获取指定世界坐标的格子
static func get_cell(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	return Queries.get_cell(cells, pos, grid_size)

# 获取指定位置的道路段
static func get_road_segments_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Array:
	return Queries.get_road_segments_at(cells, pos, grid_size)

# 检查位置是否有道路
static func has_road_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return Queries.has_road_at(cells, pos, grid_size)

# 检查位置是否有建筑
static func has_structure_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return Queries.has_structure_at(cells, pos, grid_size)

# 检查位置是否被阻塞
static func is_blocked_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return Queries.is_blocked_at(cells, pos, grid_size)

# 获取位置的饮品源
static func get_drink_source_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	return Queries.get_drink_source_at(cells, pos, grid_size)

# === 调试 ===

static func dump_cells(cells: Array, grid_size: Vector2i) -> String:
	return Debug.dump_cells(cells, grid_size)
