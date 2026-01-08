# 道路图
# 提供最短路径、连通性、街区划分等功能
class_name RoadGraph
extends RefCounted

const Builder = preload("res://core/map/road_graph/builder.gd")
const Blocks = preload("res://core/map/road_graph/blocks.gd")
const Pathfinding = preload("res://core/map/road_graph/pathfinding.gd")
const RangeQuery = preload("res://core/map/road_graph/range_query.gd")

# === 图数据 ===
# 节点: (x, y, segment_index) 表示位置 + 该位置内的段索引
# 边: 节点之间的连接

var _nodes: Dictionary = {}  # node_key -> { pos, segment_index, segment }
var _edges: Dictionary = {}  # node_key -> [{ to, weight, crosses_boundary }]
var _grid_size: Vector2i = Vector2i.ZERO
var _map_origin: Vector2i = Vector2i.ZERO
var _boundary_index: Dictionary = {}

# 街区区域 (用于 mailbox 营销)
var _block_regions: Dictionary = {}  # region_id -> [Vector2i]
var _cell_to_block: Dictionary = {}  # Vector2i -> region_id

# === 构建图 ===

static func build_from_cells(cells: Array, grid_size: Vector2i, boundary_index: Dictionary = {}) -> RoadGraph:
	return build_from_cells_with_external(cells, grid_size, Vector2i.ZERO, {}, boundary_index)

static func build_from_cells_with_external(
	cells: Array,
	grid_size: Vector2i,
	map_origin: Vector2i,
	external_cells: Dictionary,
	boundary_index: Dictionary = {}
) -> RoadGraph:
	var graph := RoadGraph.new()
	graph._grid_size = grid_size
	graph._map_origin = map_origin
	graph._boundary_index = boundary_index

	Builder.populate_nodes_and_edges(graph, cells, external_cells)
	Blocks.calculate_block_regions(graph, cells)

	return graph

# === 最短路径 ===

# 查找最短路径
# 规则距离定义（对齐 docs/design.md）：
# - distance：跨越板块边界次数（primary）
# - steps：道路步数（secondary，用于在 distance 相同时稳定选路）
# 返回: { distance, boundary_crossings, steps, path }
func find_shortest_path(from_pos: Vector2i, to_pos: Vector2i) -> Result:
	return Pathfinding.find_shortest_path(self, from_pos, to_pos)

# === 连通性检查 ===

# 检查两个位置是否连通
func are_positions_connected(pos1: Vector2i, pos2: Vector2i) -> bool:
	return Pathfinding.are_positions_connected(self, pos1, pos2)

# 计算距离 (如果不连通返回 -1)
func get_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	return Pathfinding.get_distance(self, pos1, pos2)

# 计算道路步数 (如果不连通返回 -1)
func get_step_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	return Pathfinding.get_step_distance(self, pos1, pos2)

# 获取边界跨越次数 (如果不连通返回 -1)
func get_boundary_crossings(pos1: Vector2i, pos2: Vector2i) -> int:
	return Pathfinding.get_boundary_crossings(self, pos1, pos2)

# === 邻接检查 ===

# 获取从指定位置可直接到达的所有位置
func get_reachable_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return Pathfinding.get_reachable_neighbors(self, pos)

# 检查位置是否有道路
func has_road_at(pos: Vector2i) -> bool:
	return Pathfinding.has_road_at(self, pos)

# === 范围查询 ===

# 获取指定距离内的所有道路格子
func get_cells_within_distance(from_pos: Vector2i, max_distance: int) -> Array[Vector2i]:
	return RangeQuery.get_cells_within_distance(self, from_pos, max_distance)

# === 街区计算 ===

func get_block_cells(pos: Vector2i) -> Array[Vector2i]:
	return Blocks.get_block_cells(self, pos)

func get_block_id(pos: Vector2i) -> int:
	return Blocks.get_block_id(self, pos)

func are_in_same_block(pos1: Vector2i, pos2: Vector2i) -> bool:
	return Blocks.are_in_same_block(self, pos1, pos2)

# === 查询方法 ===

# 获取节点数量
func get_node_count() -> int:
	return _nodes.size()

# 获取边数量
func get_edge_count() -> int:
	var count := 0
	for edges in _edges.values():
		count += edges.size()
	return count

# 获取街区数量
func get_block_count() -> int:
	return _block_regions.size()

# === 调试 ===

func dump() -> String:
	var output := "=== RoadGraph ===\n"
	output += "Grid size: %s\n" % str(_grid_size)
	output += "Nodes: %d\n" % get_node_count()
	output += "Edges: %d\n" % get_edge_count()
	output += "Block regions: %d\n" % get_block_count()
	return output

func dump_connectivity_matrix(sample_points: Array[Vector2i]) -> String:
	var output := "Connectivity Matrix:\n"
	output += "     "
	for p in sample_points:
		output += "%2d,%2d " % [p.x, p.y]
	output += "\n"

	for p1 in sample_points:
		output += "%2d,%2d " % [p1.x, p1.y]
		for p2 in sample_points:
			var dist := get_distance(p1, p2)
			if dist >= 0:
				output += " %3d  " % dist
			else:
				output += "  -   "
		output += "\n"

	return output
