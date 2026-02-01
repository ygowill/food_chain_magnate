extends RefCounted

const NodeKeys = preload("res://core/map/road_graph/node_keys.gd")
const Cells = preload("res://core/map/map_runtime/cells.gd")

static func populate_nodes_and_edges(graph, cells: Array, external_cells: Dictionary, options: Dictionary = {}) -> void:
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
	var external_positions: Array[Vector2i] = Cells.sorted_positions_from_external_cells(external_cells)
	for pos in external_positions:
		var cell_val = external_cells.get(Cells.pos_key(pos), null)
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

	_build_edges_with_external(graph, cells, external_cells, options)

static func _build_edges_with_external(graph, cells: Array, external_cells: Dictionary, options: Dictionary = {}) -> void:
	var connect_parallel := false
	if options is Dictionary:
		var v = options.get("connect_parallel_lanes", null)
		if v is bool:
			connect_parallel = bool(v)
		elif v is int:
			connect_parallel = int(v) != 0
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				connect_parallel = int(f) != 0

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

			if connect_parallel:
				# Parallel adjacent road lanes are connected (e.g. Lobbyists rulebook).
				# - vertical (N-S) lanes connect left/right to other vertical lanes
				# - horizontal (E-W) lanes connect up/down to other horizontal lanes
				var has_ns := ("N" in dirs) and ("S" in dirs)
				var has_ew := ("E" in dirs) and ("W" in dirs)
				if has_ns:
					for side_dir in ["E", "W"]:
						var npos := MapUtils.get_neighbor_pos(pos, side_dir)
						if not _has_cell_any(graph, npos, external_cells):
							continue
						var ncell := _get_cell_any(graph, npos, cells, external_cells)
						if ncell.is_empty():
							continue
						var nsegs: Array = ncell.get("road_segments", [])
						for n_seg_idx2 in nsegs.size():
							var nseg2_val = nsegs[n_seg_idx2]
							if not (nseg2_val is Dictionary):
								continue
							var nseg2: Dictionary = nseg2_val
							var ndirs2: Array = nseg2.get("dirs", [])
							if ("N" in ndirs2) and ("S" in ndirs2):
								var nk := NodeKeys.make_node_key(npos, n_seg_idx2)
								if not _has_edge(graph._edges[node_key], nk):
									var crosses2 := MapUtils.crosses_tile_boundary(pos, npos)
									graph._edges[node_key].append({
										"to": nk,
										"weight": 1,
										"crosses_boundary": crosses2
									})
								break
				if has_ew:
					for side_dir2 in ["N", "S"]:
						var npos2 := MapUtils.get_neighbor_pos(pos, side_dir2)
						if not _has_cell_any(graph, npos2, external_cells):
							continue
						var ncell2 := _get_cell_any(graph, npos2, cells, external_cells)
						if ncell2.is_empty():
							continue
						var nsegs2: Array = ncell2.get("road_segments", [])
						for n_seg_idx3 in nsegs2.size():
							var nseg3_val = nsegs2[n_seg_idx3]
							if not (nseg3_val is Dictionary):
								continue
							var nseg3: Dictionary = nseg3_val
							var ndirs3: Array = nseg3.get("dirs", [])
							if ("E" in ndirs3) and ("W" in ndirs3):
								var nk2 := NodeKeys.make_node_key(npos2, n_seg_idx3)
								if not _has_edge(graph._edges[node_key], nk2):
									var crosses3 := MapUtils.crosses_tile_boundary(pos, npos2)
									graph._edges[node_key].append({
										"to": nk2,
										"weight": 1,
										"crosses_boundary": crosses3
									})
								break

static func _has_edge(edges: Array, to_key: String) -> bool:
	for e_val in edges:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if str(e.get("to", "")) == to_key:
			return true
	return false

static func _has_cell_any(graph, pos: Vector2i, external_cells: Dictionary) -> bool:
	var idx = pos + graph._map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < graph._grid_size.x and idx.y < graph._grid_size.y:
		return true
	return external_cells.has(Cells.pos_key(pos))

static func _get_cell_any(graph, pos: Vector2i, cells: Array, external_cells: Dictionary) -> Dictionary:
	var idx = pos + graph._map_origin
	if idx.x >= 0 and idx.y >= 0 and idx.x < graph._grid_size.x and idx.y < graph._grid_size.y:
		var row_val = cells[idx.y]
		if not (row_val is Array):
			return {}
		var row: Array = row_val
		var cell_val = row[idx.x]
		return cell_val if cell_val is Dictionary else {}
	var key := Cells.pos_key(pos)
	var cell_val = external_cells.get(key, null)
	return cell_val if cell_val is Dictionary else {}
