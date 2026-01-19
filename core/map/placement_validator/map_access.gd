extends RefCounted

static func get_map_origin(map_ctx: Dictionary) -> Vector2i:
	if map_ctx.has("map_origin"):
		var v = map_ctx.get("map_origin", null)
		if v is Vector2i:
			return v
	return Vector2i.ZERO

static func world_to_index(map_ctx: Dictionary, world_pos: Vector2i) -> Vector2i:
	return world_pos + get_map_origin(map_ctx)

static func has_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> bool:
	if not map_ctx.has("grid_size") or not (map_ctx["grid_size"] is Vector2i):
		return false
	var grid_size: Vector2i = map_ctx["grid_size"]
	var idx := world_to_index(map_ctx, world_pos)
	return idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y

static func get_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> Dictionary:
	if not map_ctx.has("cells") or not (map_ctx["cells"] is Array):
		return {}
	var cells: Array = map_ctx["cells"]
	if not map_ctx.has("grid_size") or not (map_ctx["grid_size"] is Vector2i):
		return {}
	var grid_size: Vector2i = map_ctx["grid_size"]

	var idx := world_to_index(map_ctx, world_pos)
	if idx.x < 0 or idx.y < 0 or idx.x >= grid_size.x or idx.y >= grid_size.y:
		return {}

	var row_val = cells[idx.y]
	if not (row_val is Array):
		return {}
	var row: Array = row_val
	var cell_val = row[idx.x]
	if cell_val is Dictionary:
		return cell_val
	return {}
