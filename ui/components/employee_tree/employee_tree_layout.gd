# 员工升级路线树：Layered + Lanes 布局
# - X：layer（entry_level 为 0，其它按最长路径推导）
# - Y：按职责 role 固定“车道”(lane)，同色员工尽量同一水平线（允许列内留空）
# - lane 内：多轨道(track)防重叠；同 role 的 1->1 链尽量保持同 track（直线更清晰）
class_name EmployeeTreeLayout
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")

# 你确认的顺序（从上到下）：
# - special / new_shop（new_shop 优先并入 special 的空位；否则落在 special 下方 track）
# - manager
# - price
# - recruit / train（颜色相同，但为避免路线图布局混淆，分到两条 lane）
# - marketing
# - procure_drink
# - produce_food
const ROLE_TO_LANE_GROUP := {
	"special": 0,
	"new_shop": 0,
	"manager": 1,
	"price": 2,
	"recruit_train": 3, # 兼容旧数据：未细分时仍落在 recruit 车道
	"recruit": 3,
	"train": 4,
	"marketing": 5,
	"procure_drink": 6,
	"produce_food": 7,
}

const ROLE_SUB_PRIORITY_IN_GROUP_0 := {
	"special": 0,
	"new_shop": 1,
}

static func layout(
	node_ids: Array[String],
	edges_out: Dictionary,
	entry_ids: Array[String],
	role_by_id: Dictionary,
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

	# Keep `iterations` for backwards compatibility (previous barycenter layout); currently unused.
	# (GDScript doesn't support discard assignment like `_ = iterations`.)

	var roles: Dictionary = _normalize_roles(ids, role_by_id)
	var positions: Dictionary = _assign_positions_lanes(ids, roles, layer_by_id, layers, edges_out, edges_in, node_size, layer_spacing, node_spacing_y)
	var bounds: Rect2 = _compute_bounds(ids, positions, node_size, padding)
	var shifted_positions: Dictionary = _shift_positions(ids, positions, bounds.position)

	return {
		"positions": shifted_positions,
		"bounds": Rect2(Vector2.ZERO, bounds.size),
		"layers": layers,
		"layer_by_id": layer_by_id,
	}

static func _normalize_roles(node_ids: Array[String], role_by_id: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in node_ids:
		if id.is_empty():
			continue
		var r := ""
		var v = role_by_id.get(id, null)
		if v is String:
			r = str(v)
		if r.is_empty():
			# 兜底：未知 role 归到 special（保证可显示）
			r = "special"
		out[id] = r
	return out

static func _assign_positions_lanes(
	node_ids: Array[String],
	role_by_id: Dictionary,
	layer_by_id: Dictionary,
	layers: Array,
	edges_out: Dictionary,
	edges_in: Dictionary,
	node_size: Vector2,
	layer_spacing: float,
	node_spacing_y: float
) -> Dictionary:
	var out: Dictionary = {}
	if node_ids.is_empty():
		return out

	var group_by_id: Dictionary = {}
	var ids_by_group: Dictionary = {}
	for id in node_ids:
		var role: String = str(role_by_id.get(id, "special"))
		var gi := int(ROLE_TO_LANE_GROUP.get(role, 0))
		group_by_id[id] = gi
		if not ids_by_group.has(gi):
			ids_by_group[gi] = []
		var arr: Array = ids_by_group[gi]
		arr.append(id)
		ids_by_group[gi] = arr

	var track_by_id: Dictionary = {}
	var track_count_by_group: Dictionary = {}
	var group_count: int = int(ROLE_TO_LANE_GROUP.values().max()) + 1
	for gi2 in range(group_count):
		var group_ids_val = ids_by_group.get(gi2, [])
		var group_ids: Array = group_ids_val if group_ids_val is Array else []
		if group_ids.is_empty():
			track_count_by_group[gi2] = 0
			continue
		var entities := _build_group_entities(group_ids, role_by_id, layer_by_id, edges_out, edges_in, gi2)
		var tracks_used_by_layer: Dictionary = {} # layer_index -> {track: true}
		var max_track := -1
		for e_val in entities:
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			var ids_val = e.get("ids", [])
			var e_ids: Array = ids_val if ids_val is Array else []
			if e_ids.is_empty():
				continue
			var layers_val = e.get("layers", [])
			var e_layers: Array = layers_val if layers_val is Array else []

			var track := 0
			var safety := 0
			while safety < 256:
				safety += 1
				if _entity_fits_track(e_layers, track, tracks_used_by_layer):
					_mark_entity_track(e_layers, track, tracks_used_by_layer)
					max_track = maxi(max_track, track)
					for nid_val in e_ids:
						var nid := str(nid_val)
						if nid.is_empty():
							continue
						track_by_id[nid] = track
					break
				track += 1
		track_count_by_group[gi2] = maxi(0, max_track + 1)

	var base_y_by_group: Array[float] = []
	base_y_by_group.resize(group_count)

	var lane_gap := float(node_spacing_y) * 2.0
	var y_cursor := 0.0
	for gi3 in range(group_count):
		base_y_by_group[gi3] = y_cursor
		var tc := int(track_count_by_group.get(gi3, 0))
		if tc <= 0:
			continue
		var lane_height := float(tc) * float(node_size.y) + float(maxi(0, tc - 1)) * float(node_spacing_y)
		y_cursor += lane_height

		# 仅在后续仍有内容时添加间距
		var has_later := false
		for gi4 in range(gi3 + 1, group_count):
			if int(track_count_by_group.get(gi4, 0)) > 0:
				has_later = true
				break
		if has_later:
			y_cursor += lane_gap

	for id2 in node_ids:
		var li := int(layer_by_id.get(id2, 0))
		var x := float(li) * float(layer_spacing)
		var gi5 := int(group_by_id.get(id2, 0))
		var base_y := float(base_y_by_group[gi5])
		var track2 := int(track_by_id.get(id2, 0))
		var y := base_y + float(track2) * (float(node_size.y) + float(node_spacing_y))
		out[id2] = Vector2(x, y)

	return out

static func _build_group_entities(
	group_ids: Array,
	role_by_id: Dictionary,
	layer_by_id: Dictionary,
	edges_out: Dictionary,
	edges_in: Dictionary,
	group_index: int
) -> Array:
	var out: Array = []
	var used: Dictionary = {}

	var roles_in_group: Array[String] = []
	for id_val in group_ids:
		var id := str(id_val)
		if id.is_empty():
			continue
		var role := str(role_by_id.get(id, "special"))
		if roles_in_group.has(role):
			continue
		roles_in_group.append(role)

	# group 0：special 在上，new_shop 可并入空位
	roles_in_group.sort_custom(func(a, b) -> bool:
		var pa := int(ROLE_SUB_PRIORITY_IN_GROUP_0.get(str(a), 0)) if group_index == 0 else 0
		var pb := int(ROLE_SUB_PRIORITY_IN_GROUP_0.get(str(b), 0)) if group_index == 0 else 0
		if pa == pb:
			return str(a) < str(b)
		return pa < pb
	)

	for role in roles_in_group:
		var ids_in_role: Array[String] = []
		for id2_val in group_ids:
			var id2 := str(id2_val)
			if id2.is_empty():
				continue
			if str(role_by_id.get(id2, "")) == role:
				ids_in_role.append(id2)
		if ids_in_role.is_empty():
			continue

		var chains := _extract_role_chains(ids_in_role, role_by_id, layer_by_id, edges_out, edges_in)
		for ch_val in chains:
			if not (ch_val is Array):
				continue
			var ch: Array = ch_val
			if ch.size() < 2:
				continue
			var layers_used: Array[int] = []
			var seen_layers: Dictionary = {}
			for nid_val in ch:
				var nid := str(nid_val)
				if nid.is_empty():
					continue
				used[nid] = true
				var li := int(layer_by_id.get(nid, 0))
				if not seen_layers.has(li):
					seen_layers[li] = true
					layers_used.append(li)
			layers_used.sort()
			out.append({
				"ids": ch.duplicate(),
				"layers": layers_used,
				"role": role,
				"is_chain": true,
			})

	for id3_val in group_ids:
		var id3 := str(id3_val)
		if id3.is_empty():
			continue
		if used.has(id3):
			continue
		var role3 := str(role_by_id.get(id3, "special"))
		out.append({
			"ids": [id3],
			"layers": [int(layer_by_id.get(id3, 0))],
			"role": role3,
			"is_chain": false,
		})

	out.sort_custom(func(a, b) -> bool:
		if not (a is Dictionary) or not (b is Dictionary):
			return false
		var da: Dictionary = a
		var db: Dictionary = b
		var ra := str(da.get("role", ""))
		var rb := str(db.get("role", ""))
		var pa := int(ROLE_SUB_PRIORITY_IN_GROUP_0.get(ra, 0)) if group_index == 0 else 0
		var pb := int(ROLE_SUB_PRIORITY_IN_GROUP_0.get(rb, 0)) if group_index == 0 else 0
		if pa != pb:
			return pa < pb

		var ca := bool(da.get("is_chain", false))
		var cb := bool(db.get("is_chain", false))
		if ca != cb:
			return ca and not cb

		var a_ids: Array = da.get("ids", [])
		var b_ids: Array = db.get("ids", [])
		if a_ids.size() != b_ids.size():
			return a_ids.size() > b_ids.size()

		var la: Array = da.get("layers", [])
		var lb: Array = db.get("layers", [])
		var mina := int(la[0]) if la.size() > 0 else 0
		var minb := int(lb[0]) if lb.size() > 0 else 0
		if mina != minb:
			return mina < minb

		return str(a_ids[0]) < str(b_ids[0])
	)

	return out

static func _extract_role_chains(
	ids_in_role: Array[String],
	role_by_id: Dictionary,
	layer_by_id: Dictionary,
	edges_out: Dictionary,
	edges_in: Dictionary
) -> Array:
	# 基于“同 role 的 1->1 链”抽取：尽量在同一 track，视觉上更直。
	var in_deg: Dictionary = {}
	var out_next: Dictionary = {} # id -> next_id (仅在 outdeg==1 时提供)
	var out_deg: Dictionary = {}

	var role := ""
	if not ids_in_role.is_empty():
		role = str(role_by_id.get(ids_in_role[0], ""))

	var id_set: Dictionary = {}
	for id in ids_in_role:
		id_set[id] = true

	for id2 in ids_in_role:
		var outs_val = edges_out.get(id2, [])
		var outs: Array = outs_val if outs_val is Array else []
		var nexts: Array[String] = []
		for v_val in outs:
			var v := str(v_val)
			if v.is_empty():
				continue
			if not id_set.has(v):
				continue
			if str(role_by_id.get(v, "")) != role:
				continue
			nexts.append(v)
		out_deg[id2] = nexts.size()
		if nexts.size() == 1:
			out_next[id2] = nexts[0]

	for id3 in ids_in_role:
		var indeg := 0
		var ins_val = edges_in.get(id3, [])
		var ins: Array = ins_val if ins_val is Array else []
		for u_val in ins:
			var u := str(u_val)
			if u.is_empty():
				continue
			if not id_set.has(u):
				continue
			if str(role_by_id.get(u, "")) != role:
				continue
			indeg += 1
		in_deg[id3] = indeg

	var starts: Array[String] = []
	for id4 in ids_in_role:
		if int(out_deg.get(id4, 0)) != 1:
			continue
		var indeg2 := int(in_deg.get(id4, 0))
		# Allow merge nodes (in_deg>1) as chain starts to keep post-merge paths horizontal.
		if indeg2 != 1:
			starts.append(id4)
			continue
		# indeg==1：若父节点不是 1->1，则从这里开始一条新链（避免分叉后的链被拧弯）
		var pred := ""
		var ins2_val = edges_in.get(id4, [])
		var ins2: Array = ins2_val if ins2_val is Array else []
		for u2_val in ins2:
			var u2 := str(u2_val)
			if u2.is_empty():
				continue
			if not id_set.has(u2):
				continue
			if str(role_by_id.get(u2, "")) != role:
				continue
			pred = u2
			break
		if pred.is_empty():
			starts.append(id4)
			continue
		if int(out_deg.get(pred, 0)) != 1:
			starts.append(id4)

	# 同一 role 内：按 layer 从左到右抽取（更稳定）
	starts.sort_custom(func(a, b) -> bool:
		var la := int(layer_by_id.get(str(a), 0))
		var lb := int(layer_by_id.get(str(b), 0))
		if la == lb:
			return str(a) < str(b)
		return la < lb
	)

	var chains: Array = []
	var visited: Dictionary = {}
	for s_val in starts:
		var s := str(s_val)
		if s.is_empty():
			continue
		if visited.has(s):
			continue
		var chain: Array[String] = [s]
		var current := s
		var safety := 0
		while safety < 256:
			safety += 1
			if int(out_deg.get(current, 0)) != 1:
				break
			var nxt := str(out_next.get(current, ""))
			if nxt.is_empty():
				break
			if int(in_deg.get(nxt, 0)) != 1:
				break
			if chain.has(nxt):
				break
			chain.append(nxt)
			current = nxt
		if chain.size() >= 2:
			chains.append(chain)
			for id5 in chain:
				visited[id5] = true

	# 长链优先（更值得对齐）
	chains.sort_custom(func(a, b) -> bool:
		var aa: Array = a if a is Array else []
		var bb: Array = b if b is Array else []
		if aa.size() != bb.size():
			return aa.size() > bb.size()
		return str(aa[0]) < str(bb[0])
	)
	return chains

static func _entity_fits_track(layers: Array, track: int, used_by_layer: Dictionary) -> bool:
	for li_val in layers:
		var li := int(li_val)
		var used_val = used_by_layer.get(li, null)
		if used_val is Dictionary:
			var used: Dictionary = used_val
			if used.has(track):
				return false
	return true

static func _mark_entity_track(layers: Array, track: int, used_by_layer: Dictionary) -> void:
	for li_val in layers:
		var li := int(li_val)
		var used_val = used_by_layer.get(li, null)
		var used: Dictionary = {}
		if used_val is Dictionary:
			used = used_val
		used[track] = true
		used_by_layer[li] = used

static func _assign_layers(node_ids: Array[String], edges_out: Dictionary, entry_ids: Array[String]) -> Dictionary:
	var layer_by_id: Dictionary = {}

	# Layer 0：entry_level
	for id in entry_ids:
		var eid := str(id)
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
			var v := str(v_val)
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
		var src := str(src_val)
		if src.is_empty():
			continue
		var arr_val = edges_out.get(src_val, [])
		var arr: Array = arr_val if arr_val is Array else []
		for dst_val in arr:
			var dst := str(dst_val)
			if dst.is_empty():
				continue
			if not edges_in.has(dst):
				edges_in[dst] = []
			var a: Array = edges_in[dst]
			a.append(src)
			edges_in[dst] = a
	return edges_in

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
