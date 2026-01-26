extends RefCounted

const Coords = preload("res://core/map/map_runtime/coords.gd")

const _EXTERNAL_CELLS_KEY := "external_cells"

static func get_cell(state, pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return {}
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return {}
	var idx := Coords.world_to_index(state, pos)
	if idx.x < 0 or idx.x >= grid_size.x or idx.y < 0 or idx.y >= grid_size.y:
		return {}

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return {}
	var cells: Array = state.map["cells"]
	if cells.size() != grid_size.y:
		return {}
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return {}
	var row: Array = row_val
	if row.size() != grid_size.x:
		return {}
	var cell_val = row[idx.x]
	if cell_val is Dictionary:
		return cell_val
	return {}

static func has_cell_any(state, pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if Coords.is_world_pos_in_grid(state, pos):
		return true
	var external_cells_val = state.map.get(_EXTERNAL_CELLS_KEY, null)
	if external_cells_val is Dictionary:
		var external_cells: Dictionary = external_cells_val
		return external_cells.has(pos_key(pos))
	return false

static func get_cell_any(state, pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	if Coords.is_world_pos_in_grid(state, pos):
		return get_cell(state, pos)
	var key := pos_key(pos)
	var external_cells_val = state.map.get(_EXTERNAL_CELLS_KEY, null)
	if not (external_cells_val is Dictionary):
		return {}
	var external_cells: Dictionary = external_cells_val
	var cell_val = external_cells.get(key, null)
	if cell_val is Dictionary:
		return cell_val
	return {}

static func pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func try_parse_pos_key(key: String):
	var parts := key.split(",")
	if parts.size() != 2:
		return null
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))

static func sorted_positions_from_external_cells(external_cells: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in external_cells.keys():
		if not (k is String):
			continue
		var pos_val = try_parse_pos_key(str(k))
		if pos_val is Vector2i:
			out.append(pos_val)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return out

static func has_road_at(state, pos: Vector2i) -> bool:
	var cell := get_cell(state, pos)
	if cell.is_empty():
		return false
	var rs_val = cell.get("road_segments", null)
	if not (rs_val is Array):
		return false
	var segments: Array = rs_val
	return not segments.is_empty()

static func has_road_at_any(state, pos: Vector2i) -> bool:
	if not has_cell_any(state, pos):
		return false
	var cell := get_cell_any(state, pos)
	if cell.is_empty():
		return false
	var rs_val = cell.get("road_segments", null)
	if not (rs_val is Array):
		return false
	var segments: Array = rs_val
	return not segments.is_empty()

static func has_structure_at(state, pos: Vector2i) -> bool:
	var cell := get_cell(state, pos)
	if cell.is_empty():
		return false
	var structure_val = cell.get("structure", null)
	if not (structure_val is Dictionary):
		return false
	var structure: Dictionary = structure_val
	return not structure.is_empty()
