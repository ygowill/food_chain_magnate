extends RefCounted

static func make_node_key(pos: Vector2i, segment_index: int) -> String:
	return "%d,%d:%d" % [pos.x, pos.y, segment_index]

static func parse_node_key(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	var pos_parts := parts[0].split(",")
	if pos_parts.size() != 2:
		return {}
	return {
		"pos": Vector2i(int(pos_parts[0]), int(pos_parts[1])),
		"segment_index": int(parts[1])
	}

