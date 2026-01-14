# 员工升级路线树：Layered 布局（MVP）
# - Layer assignment：entry_level 为 0，其它按最长路径推导
# - Node ordering：barycenter 双向迭代，尽量减少连线交叉（Q20）
class_name EmployeeTreeLayout
extends RefCounted

static func layout(
	node_ids: Array[String],
	edges_out: Dictionary,
	entry_ids: Array[String],
	node_size: Vector2,
	layer_spacing: float,
	node_spacing_y: float,
	padding: Vector2 = Vector2(40, 40),
	iterations: int = 6
) -> Dictionary:
	var ids: Array[String] = []
	ids.append_array(node_ids)
	ids.sort()

	var layer_by_id: Dictionary = _assign_layers(ids, edges_out, entry_ids)
	var layers: Array = _build_layers(ids, layer_by_id)
	var edges_in: Dictionary = _build_edges_in(edges_out)

	_order_layers(layers, layer_by_id, edges_out, edges_in, iterations)

	var positions: Dictionary = _assign_positions(layers, node_size, layer_spacing, node_spacing_y)
	positions = _align_unique_chains(layers, layer_by_id, edges_out, edges_in, positions, node_size, node_spacing_y)
	var bounds: Rect2 = _compute_bounds(ids, positions, node_size, padding)
	var shifted_positions: Dictionary = _shift_positions(ids, positions, bounds.position)

	return {
		"positions": shifted_positions,
		"bounds": Rect2(Vector2.ZERO, bounds.size),
		"layers": layers,
		"layer_by_id": layer_by_id,
	}

static func _align_unique_chains(
	layers: Array,
	layer_by_id: Dictionary,
	edges_out: Dictionary,
	edges_in: Dictionary,
	positions: Dictionary,
	node_size: Vector2,
	node_spacing_y: float
) -> Dictionary:
	if layers.is_empty():
		return positions
	if positions.is_empty():
		return positions

	var out_degree: Dictionary = {}
	for id_val in edges_out.keys():
		var id := str(id_val).strip_edges()
		if id.is_empty():
			continue
		var arr_val = edges_out.get(id_val, [])
		var arr: Array = arr_val if arr_val is Array else []
		out_degree[id] = arr.size()

	var in_degree: Dictionary = {}
	for id_val2 in edges_in.keys():
		var id2 := str(id_val2).strip_edges()
		if id2.is_empty():
			continue
		var arr_val2 = edges_in.get(id_val2, [])
		var arr2: Array = arr_val2 if arr_val2 is Array else []
		in_degree[id2] = arr2.size()

	var chains: Array = []
	var visited: Dictionary = {}

	for id3_val in out_degree.keys():
		var start := str(id3_val).strip_edges()
		if start.is_empty():
			continue
		if visited.has(start):
			continue
		var indeg := int(in_degree.get(start, 0))
		var outdeg := int(out_degree.get(start, 0))
		if indeg != 0 or outdeg != 1:
			continue

		var chain: Array[String] = [start]
		var current := start
		var safety := 0
		while safety < 256:
			safety += 1
			var next_val = edges_out.get(current, [])
			var nexts: Array = next_val if next_val is Array else []
			if nexts.size() != 1:
				break
			var nxt := str(nexts[0]).strip_edges()
			if nxt.is_empty():
				break
			if int(in_degree.get(nxt, 0)) != 1:
				break
			if chain.has(nxt):
				break
			chain.append(nxt)
			current = nxt

		if chain.size() >= 4:
			chains.append(chain)
			for c in chain:
				visited[c] = true

	if chains.is_empty():
		return positions

	chains.sort_custom(func(a, b) -> bool:
		var aa: Array = a if a is Array else []
		var bb: Array = b if b is Array else []
		return aa.size() > bb.size()
	)

	var layer_offsets: Dictionary = {}

	for chain_val in chains:
		if not (chain_val is Array):
			continue
		var chain2: Array = chain_val
		if chain2.is_empty():
			continue
		var start2 := str(chain2[0]).strip_edges()
		var start_pos_val = positions.get(start2, null)
		if not (start_pos_val is Vector2):
			continue
		var target_y := float(Vector2(start_pos_val).y)

		var desired_offsets: Dictionary = {}
		var conflict := false

		for node_val in chain2:
			var node := str(node_val).strip_edges()
			if node.is_empty():
				continue
			if not layer_by_id.has(node):
				continue
			var li := int(layer_by_id.get(node, 0))
			var p_val = positions.get(node, null)
			if not (p_val is Vector2):
				continue
			var delta := target_y - float(Vector2(p_val).y)
			if absf(delta) <= 0.001:
				continue

			if layer_offsets.has(li):
				if absf(float(layer_offsets[li]) - delta) > 0.001:
					conflict = true
					break
			if desired_offsets.has(li):
				if absf(float(desired_offsets[li]) - delta) > 0.001:
					conflict = true
					break
			desired_offsets[li] = delta

		if conflict:
			continue

		for li_val in desired_offsets.keys():
			layer_offsets[li_val] = desired_offsets[li_val]

	# 应用 layer offsets：整体平移该层，确保链条节点对齐
	for li_val2 in layer_offsets.keys():
		var li2 := int(li_val2)
		if li2 < 0 or li2 >= layers.size():
			continue
		var delta2 := float(layer_offsets[li_val2])
		if absf(delta2) <= 0.001:
			continue
		var layer_val = layers[li2]
		var layer: Array = layer_val if layer_val is Array else []
		for id4_val in layer:
			var id4 := str(id4_val).strip_edges()
			if id4.is_empty():
				continue
			var p_val2 = positions.get(id4, null)
			if p_val2 is Vector2:
				var p: Vector2 = p_val2
				positions[id4] = Vector2(p.x, p.y + delta2)

	return positions

static func _assign_layers(node_ids: Array[String], edges_out: Dictionary, entry_ids: Array[String]) -> Dictionary:
	var layer_by_id: Dictionary = {}

	# Layer 0：entry_level
	for id in entry_ids:
		var eid := str(id).strip_edges()
		if eid.is_empty():
			continue
		layer_by_id[eid] = 0

	# 迭代松弛：layer(v) = max(layer(v), layer(u)+1)
	var queue: Array[String] = []
	queue.append_array(entry_ids)
	var safety := 0
	while not queue.is_empty() and safety < 100000:
		var u := str(queue.pop_front())
		var u_layer := int(layer_by_id.get(u, 0))
		var next_val = edges_out.get(u, [])
		var nexts: Array = next_val if next_val is Array else []
		for v_val in nexts:
			var v := str(v_val).strip_edges()
			if v.is_empty():
				continue
			var cand := u_layer + 1
			var prev := int(layer_by_id.get(v, -1))
			if prev < cand:
				layer_by_id[v] = cand
				queue.append(v)
		safety += 1

	# 未分配：放到 Layer 0（例如独立节点/特殊员工）
	for id2 in node_ids:
		if not layer_by_id.has(id2):
			layer_by_id[id2] = 0

	return layer_by_id

static func _build_layers(node_ids: Array[String], layer_by_id: Dictionary) -> Array:
	var max_layer := 0
	for k in layer_by_id.keys():
		var id := str(k)
		var l := int(layer_by_id.get(id, 0))
		max_layer = maxi(max_layer, l)

	var layers: Array = []
	for _i in range(max_layer + 1):
		layers.append([])

	for id2 in node_ids:
		var l2 := int(layer_by_id.get(id2, 0))
		if l2 < 0:
			l2 = 0
		while l2 >= layers.size():
			layers.append([])
		layers[l2].append(id2)

	for li in range(layers.size()):
		layers[li].sort()

	return layers

static func _build_edges_in(edges_out: Dictionary) -> Dictionary:
	var edges_in: Dictionary = {}
	for src_val in edges_out.keys():
		var src := str(src_val).strip_edges()
		if src.is_empty():
			continue
		var arr_val = edges_out.get(src_val, [])
		var arr: Array = arr_val if arr_val is Array else []
		for dst_val in arr:
			var dst := str(dst_val).strip_edges()
			if dst.is_empty():
				continue
			if not edges_in.has(dst):
				edges_in[dst] = []
			var a: Array = edges_in[dst]
			a.append(src)
			edges_in[dst] = a
	return edges_in

static func _order_layers(
	layers: Array,
	layer_by_id: Dictionary,
	edges_out: Dictionary,
	edges_in: Dictionary,
	iterations: int
) -> void:
	if layers.size() <= 1:
		return
	var iters := maxi(0, int(iterations))
	if iters <= 0:
		return

	for _iter in range(iters):
		# forward: layer 1..N
		for li in range(1, layers.size()):
			_sort_layer_by_neighbor_barycenter(layers[li], edges_in, layer_by_id, li - 1, layers[li - 1])
		# backward: layer N-1..0
		for li2 in range(layers.size() - 2, -1, -1):
			_sort_layer_by_neighbor_barycenter(layers[li2], edges_out, layer_by_id, li2 + 1, layers[li2 + 1])

static func _sort_layer_by_neighbor_barycenter(
	layer: Array,
	neighbor_map: Dictionary,
	layer_by_id: Dictionary,
	neighbor_layer_index: int,
	neighbor_layer: Array
) -> void:
	if layer.is_empty():
		return

	var neighbor_pos: Dictionary = {}
	for i in range(neighbor_layer.size()):
		neighbor_pos[neighbor_layer[i]] = i

	var bary: Dictionary = {}
	for i2 in range(layer.size()):
		var id := str(layer[i2])
		var arr_val = neighbor_map.get(id, [])
		var arr: Array = arr_val if arr_val is Array else []
		var sum := 0.0
		var cnt := 0
		for n_val in arr:
			var n := str(n_val)
			if int(layer_by_id.get(n, -999)) != neighbor_layer_index:
				continue
			if neighbor_pos.has(n):
				sum += float(neighbor_pos[n])
				cnt += 1
		if cnt > 0:
			bary[id] = sum / float(cnt)
		else:
			# 无邻居：保持原相对顺序
			bary[id] = float(i2)

	layer.sort_custom(func(a, b) -> bool:
		var sa := str(a)
		var sb := str(b)
		var aa := float(bary.get(sa, 0.0))
		var bb := float(bary.get(sb, 0.0))
		if aa == bb:
			return sa < sb
		return aa < bb
	)

static func _assign_positions(
	layers: Array,
	node_size: Vector2,
	layer_spacing: float,
	node_spacing_y: float
) -> Dictionary:
	var positions: Dictionary = {}
	var h := float(node_size.y)

	var max_layer_height := 0.0
	var layer_heights: Array[float] = []
	for layer in layers:
		var n: int = 0
		if layer is Array:
			n = (layer as Array).size()
		var height := float(n) * h + float(maxi(0, n - 1)) * float(node_spacing_y)
		layer_heights.append(height)
		max_layer_height = maxf(max_layer_height, height)

	for li in range(layers.size()):
		var layer2_val = layers[li]
		var layer2: Array = layer2_val if layer2_val is Array else []
		var x := float(li) * float(layer_spacing)
		var start_y := (max_layer_height - layer_heights[li]) * 0.5
		for i in range(layer2.size()):
			var id := str(layer2[i])
			var y := start_y + float(i) * (h + float(node_spacing_y))
			positions[id] = Vector2(x, y)

	return positions

static func _compute_bounds(
	node_ids: Array[String],
	positions: Dictionary,
	node_size: Vector2,
	padding: Vector2
) -> Rect2:
	var minp := Vector2(2147483647.0, 2147483647.0)
	var maxp := Vector2(-2147483648.0, -2147483648.0)

	for id in node_ids:
		var p_val = positions.get(id, null)
		if not (p_val is Vector2):
			continue
		var p: Vector2 = p_val
		minp.x = minf(minp.x, p.x)
		minp.y = minf(minp.y, p.y)
		maxp.x = maxf(maxp.x, p.x + node_size.x)
		maxp.y = maxf(maxp.y, p.y + node_size.y)

	if minp.x > maxp.x:
		minp = Vector2.ZERO
		maxp = Vector2.ZERO

	var size := (maxp - minp) + (padding * 2.0)
	return Rect2(minp - padding, size)

static func _shift_positions(node_ids: Array[String], positions: Dictionary, offset: Vector2) -> Dictionary:
	var out: Dictionary = {}
	for id in node_ids:
		var p_val = positions.get(id, null)
		if p_val is Vector2:
			out[id] = Vector2(p_val) - offset
	return out
