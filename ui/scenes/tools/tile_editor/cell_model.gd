extends RefCounted

static func get_drink_source_at(tile: TileDef, local_pos: Vector2i):
	if tile == null:
		return null
	for src in tile.drink_sources:
		if src.get("pos", Vector2i(-1, -1)) == local_pos:
			return src
	return null

static func remove_drink_source_at(tile: TileDef, local_pos: Vector2i) -> void:
	if tile == null:
		return
	for i in range(tile.drink_sources.size() - 1, -1, -1):
		var src: Dictionary = tile.drink_sources[i]
		if src.get("pos", Vector2i(-1, -1)) == local_pos:
			tile.drink_sources.remove_at(i)

static func has_printed_anchor_at(tile: TileDef, local_pos: Vector2i) -> bool:
	if tile == null:
		return false
	for s in tile.printed_structures:
		if s.get("anchor", Vector2i(-1, -1)) == local_pos:
			return true
	return false

