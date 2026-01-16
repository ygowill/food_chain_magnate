extends RefCounted

const MapAccess = preload("res://core/map/placement_validator/map_access.gd")

# === 验证函数 ===

# 验证边界
static func validate_bounds(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	for cell_pos in footprint_cells:
		var idx := MapAccess.world_to_index(map_ctx, cell_pos)
		if not MapUtils.is_valid_pos(idx, grid_size):
			return Result.failure("放置位置超出边界: %s" % str(cell_pos))

	return Result.success()

# 验证格子为空 (没有道路)
static func validate_cells_empty(
	map_ctx: Dictionary,
	piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	if not piece_def.must_be_on_empty:
		return Result.success()

	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	for cell_pos in footprint_cells:
		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)
		assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(cell_pos))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return Result.failure("位置 %s 有道路，无法放置" % str(cell_pos))

	return Result.success()

# 验证没有被阻塞
static func validate_not_blocked(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	for cell_pos in footprint_cells:
		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)
		assert(cell.has("blocked") and (cell["blocked"] is bool), "PlacementValidator: cell.blocked 缺失或类型错误（期望 bool）: %s" % str(cell_pos))
		if bool(cell["blocked"]):
			return Result.failure("位置 %s 被阻塞" % str(cell_pos))

	return Result.success()

# 验证不能覆盖饮品源（饮品进货点）
static func validate_no_drink_source(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")

	# 优先使用 map.drink_sources（规则层使用的“进货点列表”），避免依赖 cells 是否包含 drink_source 字段。
	var drink_source_pos_set := {}
	var sources_val = map_ctx.get("drink_sources", null)
	if sources_val is Array:
		var sources: Array = sources_val
		for i in range(sources.size()):
			var src_val = sources[i]
			if not (src_val is Dictionary):
				continue
			var src: Dictionary = src_val
			var wp_val = src.get("world_pos", null)
			if wp_val is Vector2i:
				drink_source_pos_set[wp_val] = true

	for cell_pos in footprint_cells:
		if not drink_source_pos_set.is_empty() and drink_source_pos_set.has(cell_pos):
			return Result.failure("位置 %s 是饮品进货点，无法放置" % str(cell_pos))

		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)
		var ds = cell.get("drink_source", null)
		if ds == null:
			continue
		if ds is Dictionary and (ds as Dictionary).is_empty():
			continue
		return Result.failure("位置 %s 是饮品进货点，无法放置" % str(cell_pos))

	return Result.success()

# 验证没有建筑重叠
static func validate_no_structure_overlap(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	context: Dictionary
) -> Result:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var ignore_set := {}
	if context.has("ignore_structure_cells"):
		var ignore_cells_val = context["ignore_structure_cells"]
		assert(ignore_cells_val is Array, "PlacementValidator: context.ignore_structure_cells 类型错误（期望 Array[Vector2i]）")
		var ignore_cells: Array = ignore_cells_val
		for v in ignore_cells:
			assert(v is Vector2i, "PlacementValidator: ignore_structure_cells 元素类型错误（期望 Vector2i）")
			ignore_set[v] = true

	for cell_pos in footprint_cells:
		if not ignore_set.is_empty() and ignore_set.has(cell_pos):
			continue

		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)
		assert(cell.has("structure") and (cell["structure"] is Dictionary), "PlacementValidator: cell.structure 缺失或类型错误（期望 Dictionary）: %s" % str(cell_pos))
		var structure: Dictionary = cell["structure"]

		if not structure.is_empty():
			assert(structure.has("piece_id") and (structure["piece_id"] is String), "PlacementValidator: structure.piece_id 缺失或类型错误（期望 String）: %s" % str(cell_pos))
			var existing_piece: String = str(structure["piece_id"])
			return Result.failure("位置 %s 已有建筑: %s" % [str(cell_pos), existing_piece])

	return Result.success()

# 验证不能与营销板件占地重叠
static func validate_no_marketing_overlap(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	var placements_val = map_ctx.get("marketing_placements", null)
	if placements_val == null:
		return Result.success()

	assert(placements_val is Dictionary, "PlacementValidator: map_ctx.marketing_placements 类型错误（期望 Dictionary）")
	var placements: Dictionary = placements_val
	if placements.is_empty():
		return Result.success()

	for k in placements.keys():
		var p_val = placements[k]
		assert(p_val is Dictionary, "PlacementValidator: marketing_placements[%s] 类型错误（期望 Dictionary）" % str(k))
		var p: Dictionary = p_val

		assert(p.has("world_pos") and (p["world_pos"] is Vector2i), "PlacementValidator: marketing_placements[%s].world_pos 缺失或类型错误（期望 Vector2i）" % str(k))
		var anchor: Vector2i = p["world_pos"]

		# footprint_size/rotation 为新增字段；缺失则按 1x1/rotation=0 兜底（兼容旧存档/测试）。
		var base_size := Vector2i.ONE
		if p.has("footprint_size"):
			var fs_val = p.get("footprint_size", null)
			if fs_val is Vector2i:
				base_size = Vector2i(fs_val)
			elif fs_val is Array:
				var arr: Array = fs_val
				assert(arr.size() == 2, "PlacementValidator: marketing_placements[%s].footprint_size 长度错误（期望 2）" % str(k))
				var w_val = arr[0]
				var h_val = arr[1]
				assert(w_val is int or w_val is float, "PlacementValidator: marketing_placements[%s].footprint_size[0] 类型错误" % str(k))
				assert(h_val is int or h_val is float, "PlacementValidator: marketing_placements[%s].footprint_size[1] 类型错误" % str(k))
				base_size = Vector2i(int(w_val), int(h_val))
			else:
				assert(false, "PlacementValidator: marketing_placements[%s].footprint_size 类型错误（期望 Vector2i 或 [w,h] Array）" % str(k))

		var rotation := 0
		if p.has("rotation"):
			var rot_val = p.get("rotation", null)
			if rot_val is int:
				rotation = int(rot_val)
			elif rot_val is float:
				var f: float = float(rot_val)
				assert(f == floor(f), "PlacementValidator: marketing_placements[%s].rotation 必须为整数" % str(k))
				rotation = int(f)
			else:
				assert(false, "PlacementValidator: marketing_placements[%s].rotation 类型错误（期望 int）" % str(k))
		assert(rotation in [0, 90, 180, 270], "PlacementValidator: marketing_placements[%s].rotation 非法: %s" % [str(k), str(rotation)])

		if base_size.x <= 0 or base_size.y <= 0:
			return Result.failure("营销板件占地非法: %s" % str(base_size))

		var size := base_size
		if rotation == 90 or rotation == 270:
			size = Vector2i(base_size.y, base_size.x)

		var left := anchor.x
		var right := anchor.x + size.x - 1
		var top := anchor.y
		var bottom := anchor.y + size.y - 1

		for cell_pos in footprint_cells:
			if cell_pos.x < left or cell_pos.x > right or cell_pos.y < top or cell_pos.y > bottom:
				continue

			var bn_val = p.get("board_number", null)
			var board_number := str(bn_val) if bn_val != null else str(k)
			return Result.failure("位置 %s 与营销板件重叠: #%s" % [str(cell_pos), board_number])

	return Result.success()

# 验证邻接道路
static func validate_road_adjacency(
	map_ctx: Dictionary,
	piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	if not piece_def.must_touch_road:
		return Result.success()

	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	# 创建占地集合
	var footprint_set := {}
	for cell in footprint_cells:
		footprint_set[cell] = true

	# 检查是否有任何占地格子邻接道路
	for cell_pos in footprint_cells:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(cell_pos, dir)

			# 跳过占地内部
			if footprint_set.has(neighbor):
				continue

			# 跳过边界外
			if not MapAccess.has_world_cell(map_ctx, neighbor):
				continue

			var neighbor_cell: Dictionary = MapAccess.get_world_cell(map_ctx, neighbor)
			assert(neighbor_cell.has("road_segments") and (neighbor_cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = neighbor_cell["road_segments"]
			if not road_segments.is_empty():
				return Result.success()

	return Result.failure("放置位置必须邻接道路")
