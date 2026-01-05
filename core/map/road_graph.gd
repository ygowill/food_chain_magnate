# 道路图
# 提供最短路径、连通性、街区划分等功能
class_name RoadGraph
extends RefCounted

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

static func build_from_cells(cells: Array, grid_size: Vector2i,
							 boundary_index: Dictionary = {}) -> RoadGraph:
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

	# 创建节点
	for y in grid_size.y:
		for x in grid_size.x:
			var pos := Vector2i(x - map_origin.x, y - map_origin.y)
			var cell: Dictionary = cells[y][x]
			var segments: Array = cell.get("road_segments", [])

			for seg_idx in segments.size():
				var node_key := _make_node_key(pos, seg_idx)
				graph._nodes[node_key] = {
					"pos": pos,
					"segment_index": seg_idx,
					"segment": segments[seg_idx]
				}
				graph._edges[node_key] = []

	# 创建节点（外部格子）
	var external_positions: Array[Vector2i] = []
	for k in external_cells.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2:
			continue
		if not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		external_positions.append(Vector2i(int(parts[0]), int(parts[1])))
	external_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	for pos in external_positions:
		var cell_val = external_cells.get("%d,%d" % [pos.x, pos.y], null)
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		var segments: Array = cell.get("road_segments", [])
		for seg_idx in segments.size():
			var node_key := _make_node_key(pos, seg_idx)
			graph._nodes[node_key] = {
				"pos": pos,
				"segment_index": seg_idx,
				"segment": segments[seg_idx]
			}
			graph._edges[node_key] = []

	# 创建边
	graph._build_edges_with_external(cells, external_cells)

	# 计算街区
	graph._calculate_block_regions(cells)

	return graph

# 创建节点键
static func _make_node_key(pos: Vector2i, segment_index: int) -> String:
	return "%d,%d:%d" % [pos.x, pos.y, segment_index]

# 从节点键解析位置和段索引
static func _parse_node_key(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	var pos_parts := parts[0].split(",")
	if pos_parts.size() != 2:
		return {}
	return {
		"pos": Vector2i(int(pos_parts[0]), int(pos_parts[1])),
		"segment_index": int(parts[1])
	}

# 构建边
func _build_edges_with_external(cells: Array, external_cells: Dictionary) -> void:
	var node_keys: Array = _nodes.keys()
	node_keys.sort()
	for node_key_val in node_keys:
		var node_key: String = str(node_key_val)
		var node_data: Dictionary = _nodes[node_key]
		var pos: Vector2i = node_data.pos
		var segment: Dictionary = node_data.segment
		var dirs: Array = segment.get("dirs", [])

		# 遍历该段连接的方向
		for dir in dirs:
			var neighbor_pos := MapUtils.get_neighbor_pos(pos, dir)
			if not _has_cell_any(neighbor_pos, external_cells):
				continue

			var opposite_dir := MapUtils.get_opposite_dir(dir)
			var neighbor_cell := _get_cell_any(neighbor_pos, cells, external_cells)
			if neighbor_cell.is_empty():
				continue
			var neighbor_segments: Array = neighbor_cell.get("road_segments", [])

			# 找到邻居中可以连接的段
			for n_seg_idx in neighbor_segments.size():
				var n_segment: Dictionary = neighbor_segments[n_seg_idx]
				var n_dirs: Array = n_segment.get("dirs", [])

				if opposite_dir in n_dirs:
					var neighbor_key := _make_node_key(neighbor_pos, n_seg_idx)
					var crosses := MapUtils.crosses_tile_boundary(pos, neighbor_pos)

					_edges[node_key].append({
						"to": neighbor_key,
						"weight": 1,
						"crosses_boundary": crosses
					})
					break  # 只连接第一个匹配的段

func _has_cell_any(pos: Vector2i, external_cells: Dictionary) -> bool:
	var idx := pos + _map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < _grid_size.x and idx.y < _grid_size.y:
		return true
	return external_cells.has("%d,%d" % [pos.x, pos.y])

func _get_cell_any(pos: Vector2i, cells: Array, external_cells: Dictionary) -> Dictionary:
	var idx := pos + _map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < _grid_size.x and idx.y < _grid_size.y:
		var row_val = cells[idx.y]
		if not (row_val is Array):
			return {}
		var row: Array = row_val
		var cell_val = row[idx.x]
		return cell_val if cell_val is Dictionary else {}
	var key := "%d,%d" % [pos.x, pos.y]
	var cell_val = external_cells.get(key, null)
	return cell_val if cell_val is Dictionary else {}

# === 最短路径 ===

# 查找最短路径
# 规则距离定义（对齐 docs/design.md）：
# - distance：跨越板块边界次数（primary）
# - steps：道路步数（secondary，用于在 distance 相同时稳定选路）
# 返回: { distance, boundary_crossings, steps, path }
func find_shortest_path(from_pos: Vector2i, to_pos: Vector2i) -> Result:
	var start_nodes := _get_nodes_at_pos(from_pos)
	var end_nodes := _get_nodes_at_pos(to_pos)

	if start_nodes.is_empty():
		return Result.failure("起点没有道路: %s" % str(from_pos))
	if end_nodes.is_empty():
		return Result.failure("终点没有道路: %s" % str(to_pos))

	# 多源 Dijkstra（按 (boundary_crossings, steps) 的字典序最短）
	var best_result: Dictionary = {}
	var best_crossings := INF
	var best_steps := INF

	for start_node in start_nodes:
		var result := _dijkstra(start_node, end_nodes)
		if result.ok:
			var crossings: int = result.value.distance
			var steps: int = result.value.get("steps", INF)
			if crossings < best_crossings or (crossings == best_crossings and steps < best_steps):
				best_crossings = crossings
				best_steps = steps
				best_result = result.value

	if best_result.is_empty():
		return Result.failure("找不到路径")

	return Result.success(best_result)

# Dijkstra 算法实现（按 (boundary_crossings, steps) 的字典序）
func _dijkstra(start_node: String, end_nodes: Array) -> Result:
	var dist := {}  # node -> { crossings, steps }
	var prev := {}  # node -> previous node
	var pq := []    # 优先队列

	dist[start_node] = {"crossings": 0, "steps": 0}
	pq.append({"node": start_node, "crossings": 0, "steps": 0})

	while not pq.is_empty():
		# 取出距离最小的节点
		pq.sort_custom(func(a, b):
			if a.crossings != b.crossings:
				return a.crossings < b.crossings
			return a.steps < b.steps
		)
		var current = pq.pop_front()
		var current_node: String = current.node

		# 检查是否到达终点
		if current_node in end_nodes:
			var path := _reconstruct_path(prev, current_node)
			return Result.success({
				"distance": current.crossings,
				"boundary_crossings": current.crossings,
				"steps": current.steps,
				"path": path
			})

		# 跳过已处理的更长路径
		var current_best = dist.get(current_node, {"crossings": INF, "steps": INF})
		if current.crossings > current_best.crossings:
			continue
		if current.crossings == current_best.crossings and current.steps > current_best.steps:
			continue

		# 遍历邻居
		for edge in _edges.get(current_node, []):
			var neighbor: String = edge.to
			var new_steps: int = current.steps + edge.weight
			var new_crossings: int = current.crossings
			if edge.crosses_boundary:
				new_crossings += 1

			var neighbor_best = dist.get(neighbor, {"crossings": INF, "steps": INF})
			if new_crossings < neighbor_best.crossings or \
				(new_crossings == neighbor_best.crossings and new_steps < neighbor_best.steps):
				dist[neighbor] = {"crossings": new_crossings, "steps": new_steps}
				prev[neighbor] = current_node
				pq.append({
					"node": neighbor,
					"crossings": new_crossings,
					"steps": new_steps
				})

	return Result.failure("找不到路径")

# 重建路径
func _reconstruct_path(prev: Dictionary, end_node: String) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := end_node

	while current != "":
		var parsed := _parse_node_key(current)
		if not parsed.is_empty():
			path.push_front(parsed.pos)
		current = prev.get(current, "")

	return path

# 获取指定位置的所有节点
func _get_nodes_at_pos(pos: Vector2i) -> Array:
	var nodes := []
	var seg_idx := 0
	while true:
		var key := _make_node_key(pos, seg_idx)
		if _nodes.has(key):
			nodes.append(key)
			seg_idx += 1
		else:
			break
	return nodes

# === 连通性检查 ===

# 检查两个位置是否连通
func are_positions_connected(pos1: Vector2i, pos2: Vector2i) -> bool:
	var result := find_shortest_path(pos1, pos2)
	return result.ok

# 计算距离 (如果不连通返回 -1)
func get_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(pos1, pos2)
	if result.ok:
		return result.value.distance
	return -1

# 计算道路步数 (如果不连通返回 -1)
func get_step_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(pos1, pos2)
	if result.ok:
		return result.value.get("steps", -1)
	return -1

# 获取边界跨越次数 (如果不连通返回 -1)
func get_boundary_crossings(pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(pos1, pos2)
	if result.ok:
		return result.value.boundary_crossings
	return -1

# === 邻接检查 ===

# 获取从指定位置可直接到达的所有位置
func get_reachable_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var nodes := _get_nodes_at_pos(pos)

	for node_key in nodes:
		for edge in _edges.get(node_key, []):
			var parsed := _parse_node_key(edge.to)
			if not parsed.is_empty():
				var neighbor_pos: Vector2i = parsed.pos
				if not neighbors.has(neighbor_pos):
					neighbors.append(neighbor_pos)

	return neighbors

# 检查位置是否有道路
func has_road_at(pos: Vector2i) -> bool:
	return not _get_nodes_at_pos(pos).is_empty()

# === 街区计算 ===

# 计算街区区域 (用于 mailbox 营销)
func _calculate_block_regions(cells: Array) -> void:
	var visited := {}
	var region_id := 0

	for y in _grid_size.y:
		for x in _grid_size.x:
			var pos := Vector2i(x - _map_origin.x, y - _map_origin.y)
			if visited.has(pos):
				continue

			var cell: Dictionary = cells[y][x]
			var has_road = not cell.get("road_segments", []).is_empty()
			var is_blocked := bool(cell.get("blocked", false))

			if has_road or is_blocked:
				visited[pos] = -1
				_cell_to_block[pos] = -1
			else:
				# 洪水填充非道路区域
				var region_cells := _flood_fill_block(cells, pos, visited)
				_block_regions[region_id] = region_cells
				for cell_pos in region_cells:
					_cell_to_block[cell_pos] = region_id
				region_id += 1

# 洪水填充
func _flood_fill_block(cells: Array, start: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var region: Array[Vector2i] = []
	var queue := [start]

	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()

		if visited.has(pos):
			continue
		var idx := pos + _map_origin
		if idx.x < 0 or idx.y < 0 or idx.x >= _grid_size.x or idx.y >= _grid_size.y:
			continue

		var cell: Dictionary = cells[idx.y][idx.x]
		var has_road = not cell.get("road_segments", []).is_empty()
		var is_blocked := bool(cell.get("blocked", false))

		if has_road or is_blocked:
			visited[pos] = -1
			continue

		visited[pos] = true
		region.append(pos)

		# 检查四个方向的邻居
		for dir in MapUtils.DIRECTIONS:
			queue.append(MapUtils.get_neighbor_pos(pos, dir))

	return region

# 获取指定位置所在街区的所有格子
func get_block_cells(pos: Vector2i) -> Array[Vector2i]:
	var block_id: int = _cell_to_block.get(pos, -1)
	if block_id == -1:
		return []
	return _block_regions.get(block_id, [])

# 获取指定位置的街区 ID
func get_block_id(pos: Vector2i) -> int:
	return _cell_to_block.get(pos, -1)

# 检查两个位置是否在同一街区
func are_in_same_block(pos1: Vector2i, pos2: Vector2i) -> bool:
	var block1 := get_block_id(pos1)
	var block2 := get_block_id(pos2)
	return block1 != -1 and block1 == block2

# === 范围查询 ===

# 获取指定距离内的所有道路格子
func get_cells_within_distance(from_pos: Vector2i, max_distance: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start_nodes := _get_nodes_at_pos(from_pos)

	if start_nodes.is_empty():
		return result

	var visited := {}
	var queue := []

	# 初始化起点
	for node in start_nodes:
		queue.append({"node": node, "distance": 0})
		visited[node] = true

	while not queue.is_empty():
		var current = queue.pop_front()
		var current_node: String = current.node
		var current_dist: int = current.distance

		# 添加到结果
		var parsed := _parse_node_key(current_node)
		if not parsed.is_empty():
			var pos: Vector2i = parsed.pos
			if not result.has(pos):
				result.append(pos)

		# 如果还可以继续
		if current_dist < max_distance:
			for edge in _edges.get(current_node, []):
				var neighbor: String = edge.to
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append({
						"node": neighbor,
						"distance": current_dist + edge.weight
					})

	return result

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
