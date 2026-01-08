extends RefCounted

const NodeKeys = preload("res://core/map/road_graph/node_keys.gd")
const Pathfinding = preload("res://core/map/road_graph/pathfinding.gd")

# 获取指定距离内的所有道路格子
static func get_cells_within_distance(graph, from_pos: Vector2i, max_distance: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start_nodes := Pathfinding._get_nodes_at_pos(graph, from_pos)

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
		var parsed := NodeKeys.parse_node_key(current_node)
		if not parsed.is_empty():
			var pos: Vector2i = parsed.pos
			if not result.has(pos):
				result.append(pos)

		# 如果还可以继续
		if current_dist < max_distance:
			for edge in graph._edges.get(current_node, []):
				var neighbor: String = edge.to
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append({
						"node": neighbor,
						"distance": current_dist + edge.weight
					})

	return result

