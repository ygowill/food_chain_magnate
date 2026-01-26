extends RefCounted

static func set_blocked(tile: TileDef, local_pos: Vector2i, blocked: bool) -> void:
	if tile == null:
		return
	var idx := tile.blocked_cells.find(local_pos)
	if blocked and idx == -1:
		tile.blocked_cells.append(local_pos)
	elif not blocked and idx != -1:
		tile.blocked_cells.remove_at(idx)

static func add_road_segment(tile: TileDef, local_pos: Vector2i, dirs: Array[String], is_bridge: bool = false) -> void:
	if tile == null:
		return
	tile.ensure_road_grid()
	if local_pos.x < 0 or local_pos.x >= TileDef.TILE_SIZE:
		return
	if local_pos.y < 0 or local_pos.y >= TileDef.TILE_SIZE:
		return
	tile.road_segments[local_pos.y][local_pos.x].append({
		"dirs": dirs,
		"bridge": is_bridge
	})

static func clear_road_segments(tile: TileDef, local_pos: Vector2i) -> void:
	if tile == null:
		return
	tile.ensure_road_grid()
	if local_pos.x < 0 or local_pos.x >= TileDef.TILE_SIZE:
		return
	if local_pos.y < 0 or local_pos.y >= TileDef.TILE_SIZE:
		return
	tile.road_segments[local_pos.y][local_pos.x] = []

static func add_printed_structure(
	tile: TileDef,
	piece_id: String,
	anchor: Vector2i,
	rotation: int = 0,
	house_id: String = "",
	house_number = null
) -> void:
	if tile == null:
		return
	var struct := {
		"piece_id": piece_id,
		"anchor": anchor,
		"rotation": rotation
	}
	if not house_id.is_empty():
		struct["house_id"] = house_id
		struct["house_number"] = house_number if house_number != null else 0
	tile.printed_structures.append(struct)

static func add_drink_source(tile: TileDef, local_pos: Vector2i, drink_type: String) -> void:
	if tile == null:
		return
	tile.drink_sources.append({
		"pos": local_pos,
		"type": drink_type
	})

