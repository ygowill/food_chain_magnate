extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")

static func get_adjacent_road_cells(state: GameState, anchor: Vector2i) -> Result:
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	# NOTE: RoadGraph 支持 external_cells（地图外道路）；因此这里用 has_cell_any/has_road_at_any，
	# 以保证“贴边/高速”等外部道路在 range/邻接计算中可用。
	if not CellsClass.has_cell_any(state, anchor):
		return Result.failure("anchor 不存在: %s" % str(anchor))

	var cells: Array[Vector2i] = []
	if CellsClass.has_road_at_any(state, anchor):
		cells.append(anchor)

	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(anchor, dir)
		if not CellsClass.has_cell_any(state, neighbor):
			continue
		if CellsClass.has_road_at_any(state, neighbor) and not cells.has(neighbor):
			cells.append(neighbor)

	return Result.success(cells)

static func get_adjacent_road_cells_for_positions(state: GameState, positions: Array) -> Result:
	if positions == null:
		return Result.failure("positions 为空")

	var out: Array[Vector2i] = []
	var seen_pos_set := {}
	var out_set := {}

	for i in range(positions.size()):
		var v = positions[i]
		if not (v is Vector2i):
			return Result.failure("positions[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if seen_pos_set.has(p):
			continue
		seen_pos_set[p] = true

		var read: Result = get_adjacent_road_cells(state, p)
		if not read.ok:
			return read
		var cells: Array[Vector2i] = read.value
		for c in cells:
			if not out_set.has(c):
				out_set[c] = true
				out.append(c)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return Result.success(out)

