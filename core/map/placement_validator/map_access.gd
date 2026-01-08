extends RefCounted

static func get_map_origin(map_ctx: Dictionary) -> Vector2i:
	if map_ctx.has("map_origin"):
		var v = map_ctx.get("map_origin", null)
		assert(v is Vector2i, "PlacementValidator: map_ctx.map_origin 类型错误（期望 Vector2i）")
		return v
	return Vector2i.ZERO

static func world_to_index(map_ctx: Dictionary, world_pos: Vector2i) -> Vector2i:
	return world_pos + get_map_origin(map_ctx)

static func has_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> bool:
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]
	var idx := world_to_index(map_ctx, world_pos)
	return idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y

static func get_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> Dictionary:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var cells: Array = map_ctx["cells"]
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	var idx := world_to_index(map_ctx, world_pos)
	assert(idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y, "PlacementValidator: world_pos 越界: %s (grid=%s origin=%s)" % [str(world_pos), str(grid_size), str(get_map_origin(map_ctx))])

	var row_val = cells[idx.y]
	assert(row_val is Array, "PlacementValidator: cells[%d] 类型错误（期望 Array）" % idx.y)
	var row: Array = row_val
	var cell_val = row[idx.x]
	assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [idx.y, idx.x])
	return cell_val

