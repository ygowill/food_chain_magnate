# MapCanvas：外部格子解析 / bounds 计算 / overlay 索引下沉
class_name MapCanvasIndexer
extends RefCounted

static func parse_external_cells(map_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw = map_data.get("external_cells", null)
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	for k in d.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2:
			continue
		if not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var cell_val = d[k]
		if cell_val is Dictionary:
			out[pos] = cell_val
	return out

static func compute_bounds(base_grid_size: Vector2i, map_origin: Vector2i, external_cells: Dictionary) -> Dictionary:
	var min_pos := Vector2i.ZERO
	var max_pos := Vector2i(max(0, base_grid_size.x - 1), max(0, base_grid_size.y - 1))
	if base_grid_size != Vector2i.ZERO:
		min_pos = -map_origin
		max_pos = Vector2i(
			base_grid_size.x - map_origin.x - 1,
			base_grid_size.y - map_origin.y - 1
		)
	for pos in external_cells.keys():
		if not (pos is Vector2i):
			continue
		var p: Vector2i = pos
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	var size := max_pos - min_pos + Vector2i.ONE
	return {"min": min_pos, "max": max_pos, "size": size}

static func rebuild_overlay_indexes(canvas) -> void:
	canvas._marketing_by_pos.clear()
	canvas._structures_by_anchor.clear()

	# marketing placements
	if canvas._map_data.has("marketing_placements") and (canvas._map_data["marketing_placements"] is Dictionary):
		var placements: Dictionary = canvas._map_data["marketing_placements"]
		for k in placements.keys():
			var p_val = placements[k]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pos_val = p.get("world_pos", null)
			if pos_val is Vector2i:
				canvas._marketing_by_pos[pos_val] = p

	# structures by anchor (scan all cells once)
	for y in range(canvas._base_grid_size.y):
		if y < 0 or y >= canvas._cells.size():
			continue
		var row_val = canvas._cells[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(canvas._base_grid_size.x):
			if x < 0 or x >= row.size():
				continue
			_index_structure_cell(canvas, Vector2i(x, y), row[x])

	var external_positions: Array[Vector2i] = []
	for k in canvas._external_cells_by_pos.keys():
		if k is Vector2i:
			external_positions.append(k)
	external_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for p in external_positions:
		_index_structure_cell(canvas, p, canvas._external_cells_by_pos[p])

static func _index_structure_cell(canvas, world_pos: Vector2i, cell_val) -> void:
	if not (cell_val is Dictionary):
		return
	var cell: Dictionary = cell_val
	var structure_val = cell.get("structure", null)
	if not (structure_val is Dictionary):
		return
	var structure: Dictionary = structure_val
	if structure.is_empty():
		return

	var anchor_val = structure.get("parent_anchor", null)
	if not (anchor_val is Vector2i):
		return
	var anchor: Vector2i = anchor_val

	var piece_id: String = str(structure.get("piece_id", ""))
	var owner: int = int(structure.get("owner", -1))
	var rotation: int = int(structure.get("rotation", 0))
	var house_id: String = str(structure.get("house_id", ""))

	var pos = canvas._world_to_view(world_pos)
	if not canvas._structures_by_anchor.has(anchor):
		canvas._structures_by_anchor[anchor] = {
			"piece_id": piece_id,
			"owner": owner,
			"rotation": rotation,
			"house_id": house_id,
			"min": pos,
			"max": pos,
		}
	else:
		var info: Dictionary = canvas._structures_by_anchor[anchor]
		if not house_id.is_empty():
			info["house_id"] = house_id
		var min_pos: Vector2i = info.get("min", pos)
		var max_pos: Vector2i = info.get("max", pos)
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)
		info["min"] = min_pos
		info["max"] = max_pos
		canvas._structures_by_anchor[anchor] = info
