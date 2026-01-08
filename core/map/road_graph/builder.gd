extends RefCounted

const NodeKeys = preload("res://core/map/road_graph/node_keys.gd")

static func populate_nodes_and_edges(graph, cells: Array, external_cells: Dictionary) -> void:
	graph._nodes.clear()
	graph._edges.clear()

	# 创建节点
	for y in graph._grid_size.y:
		for x in graph._grid_size.x:
			var pos := Vector2i(x - graph._map_origin.x, y - graph._map_origin.y)
			var cell: Dictionary = cells[y][x]
			var segments: Array = cell.get("road_segments", [])

			for seg_idx in segments.size():
				var node_key := NodeKeys.make_node_key(pos, seg_idx)
				graph._nodes[node_key] = {
					"pos": pos,
					"segment_index": seg_idx,
					"segment": segments[seg_idx]
				}
				graph._edges[node_key] = []

	# 创建节点（外部格子）
	var external_positions: Array[Vector2i] = _parse_external_positions(external_cells)
	for pos in external_positions:
		var cell_val = external_cells.get("%d,%d" % [pos.x, pos.y], null)
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		var segments: Array = cell.get("road_segments", [])
		for seg_idx in segments.size():
			var node_key := NodeKeys.make_node_key(pos, seg_idx)
			graph._nodes[node_key] = {
				"pos": pos,
				"segment_index": seg_idx,
				"segment": segments[seg_idx]
			}
			graph._edges[node_key] = []

	_build_edges_with_external(graph, cells, external_cells)

static func _parse_external_positions(external_cells: Dictionary) -> Array[Vector2i]:
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
	return external_positions

static func _build_edges_with_external(graph, cells: Array, external_cells: Dictionary) -> void:
	var node_keys: Array = graph._nodes.keys()
	node_keys.sort()
	for node_key_val in node_keys:
		var node_key: String = str(node_key_val)
		var node_data: Dictionary = graph._nodes[node_key]
		var pos: Vector2i = node_data.pos
		var segment: Dictionary = node_data.segment
		var dirs: Array = segment.get("dirs", [])

		# 遍历该段连接的方向
		for dir in dirs:
			var neighbor_pos := MapUtils.get_neighbor_pos(pos, dir)
			if not _has_cell_any(graph, neighbor_pos, external_cells):
				continue

			var opposite_dir := MapUtils.get_opposite_dir(dir)
			var neighbor_cell := _get_cell_any(graph, neighbor_pos, cells, external_cells)
			if neighbor_cell.is_empty():
				continue
			var neighbor_segments: Array = neighbor_cell.get("road_segments", [])

			# 找到邻居中可以连接的段
			for n_seg_idx in neighbor_segments.size():
				var n_segment: Dictionary = neighbor_segments[n_seg_idx]
				var n_dirs: Array = n_segment.get("dirs", [])

				if opposite_dir in n_dirs:
					var neighbor_key := NodeKeys.make_node_key(neighbor_pos, n_seg_idx)
					var crosses := MapUtils.crosses_tile_boundary(pos, neighbor_pos)

					graph._edges[node_key].append({
						"to": neighbor_key,
						"weight": 1,
						"crosses_boundary": crosses
					})
					break  # 只连接第一个匹配的段

static func _has_cell_any(graph, pos: Vector2i, external_cells: Dictionary) -> bool:
	var idx = pos + graph._map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < graph._grid_size.x and idx.y < graph._grid_size.y:
		return true
	return external_cells.has("%d,%d" % [pos.x, pos.y])

static func _get_cell_any(graph, pos: Vector2i, cells: Array, external_cells: Dictionary) -> Dictionary:
	var idx = pos + graph._map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < graph._grid_size.x and idx.y < graph._grid_size.y:
		var row_val = cells[idx.y]
		if not (row_val is Array):
			return {}
		var row: Array = row_val
		var cell_val = row[idx.x]
		return cell_val if cell_val is Dictionary else {}
	var key := "%d,%d" % [pos.x, pos.y]
	var cell_val = external_cells.get(key, null)
	return cell_val if cell_val is Dictionary else {}
