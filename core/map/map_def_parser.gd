extends RefCounted

const MapParseHelpersClass = preload("res://core/map/parse_helpers.gd")

static func parse_fields_from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("MapDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"grid_size",
		"tiles",
		"min_players",
		"max_players",
		"random_tile_pool",
		"random_rotation",
		"random_seed",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("MapDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).strip_edges().is_empty():
		return Result.failure("MapDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).strip_edges().is_empty():
		return Result.failure("MapDef.display_name 类型错误或为空（期望非空 String）")

	var grid_size_read := MapParseHelpersClass.parse_vec2i(data.get("grid_size", null), "MapDef.grid_size")
	if not grid_size_read.ok:
		return grid_size_read
	var gs: Vector2i = grid_size_read.value
	if gs.x <= 0 or gs.y <= 0:
		return Result.failure("MapDef.grid_size 无效: %s" % str(gs))

	var min_players_read := MapParseHelpersClass.parse_non_negative_int(data.get("min_players", null), "MapDef.min_players")
	if not min_players_read.ok:
		return min_players_read
	var max_players_read := MapParseHelpersClass.parse_non_negative_int(data.get("max_players", null), "MapDef.max_players")
	if not max_players_read.ok:
		return max_players_read

	var random_tile_pool_read := MapParseHelpersClass.parse_string_array(data.get("random_tile_pool", null), "MapDef.random_tile_pool", false)
	if not random_tile_pool_read.ok:
		return random_tile_pool_read

	var random_rotation_val = data.get("random_rotation", null)
	if not (random_rotation_val is bool):
		return Result.failure("MapDef.random_rotation 类型错误（期望 bool）")

	var random_seed_read := MapParseHelpersClass.parse_non_negative_int(data.get("random_seed", null), "MapDef.random_seed")
	if not random_seed_read.ok:
		return random_seed_read

	var tiles_val = data.get("tiles", null)
	var tiles_read := MapParseHelpersClass.parse_tile_placements(tiles_val, "MapDef.tiles")
	if not tiles_read.ok:
		return tiles_read

	return Result.success({
		"id": str(id_val).strip_edges(),
		"display_name": str(display_name_val).strip_edges(),
		"grid_size": gs,
		"min_players": int(min_players_read.value),
		"max_players": int(max_players_read.value),
		"random_tile_pool": random_tile_pool_read.value,
		"random_rotation": bool(random_rotation_val),
		"random_seed": int(random_seed_read.value),
		"tiles": tiles_read.value,
	})

