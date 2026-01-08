extends RefCounted

const NodeKeys = preload("res://core/map/road_graph/node_keys.gd")

# 查找最短路径
# 规则距离定义（对齐 docs/design.md）：
# - distance：跨越板块边界次数（primary）
# - steps：道路步数（secondary，用于在 distance 相同时稳定选路）
# 返回: { distance, boundary_crossings, steps, path }
static func find_shortest_path(graph, from_pos: Vector2i, to_pos: Vector2i) -> Result:
	var start_nodes := _get_nodes_at_pos(graph, from_pos)
	var end_nodes := _get_nodes_at_pos(graph, to_pos)

	if start_nodes.is_empty():
		return Result.failure("起点没有道路: %s" % str(from_pos))
	if end_nodes.is_empty():
		return Result.failure("终点没有道路: %s" % str(to_pos))

	# 多源 Dijkstra（按 (boundary_crossings, steps) 的字典序最短）
	var best_result: Dictionary = {}
	var best_crossings := INF
	var best_steps := INF

	for start_node in start_nodes:
		var result := _dijkstra(graph, start_node, end_nodes)
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

static func _dijkstra(graph, start_node: String, end_nodes: Array) -> Result:
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
		for edge in graph._edges.get(current_node, []):
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

static func _reconstruct_path(prev: Dictionary, end_node: String) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := end_node

	while current != "":
		var parsed := NodeKeys.parse_node_key(current)
		if not parsed.is_empty():
			path.push_front(parsed.pos)
		current = prev.get(current, "")

	return path

static func _get_nodes_at_pos(graph, pos: Vector2i) -> Array:
	var nodes := []
	var seg_idx := 0
	while true:
		var key := NodeKeys.make_node_key(pos, seg_idx)
		if graph._nodes.has(key):
			nodes.append(key)
			seg_idx += 1
		else:
			break
	return nodes

static func are_positions_connected(graph, pos1: Vector2i, pos2: Vector2i) -> bool:
	var result := find_shortest_path(graph, pos1, pos2)
	return result.ok

static func get_distance(graph, pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(graph, pos1, pos2)
	if result.ok:
		return int(result.value.distance)
	return -1

static func get_step_distance(graph, pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(graph, pos1, pos2)
	if result.ok:
		return int(result.value.get("steps", -1))
	return -1

static func get_boundary_crossings(graph, pos1: Vector2i, pos2: Vector2i) -> int:
	var result := find_shortest_path(graph, pos1, pos2)
	if result.ok:
		return int(result.value.boundary_crossings)
	return -1

static func get_reachable_neighbors(graph, pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var nodes := _get_nodes_at_pos(graph, pos)

	for node_key in nodes:
		for edge in graph._edges.get(node_key, []):
			var parsed := NodeKeys.parse_node_key(edge.to)
			if not parsed.is_empty():
				var neighbor_pos: Vector2i = parsed.pos
				if not neighbors.has(neighbor_pos):
					neighbors.append(neighbor_pos)

	return neighbors

static func has_road_at(graph, pos: Vector2i) -> bool:
	return not _get_nodes_at_pos(graph, pos).is_empty()

