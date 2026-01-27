extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const MapParseHelpersClass = preload("res://core/map/parse_helpers.gd")

static func parse_fields_from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("TileDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"road_segments",
		"printed_structures",
		"drink_sources",
		"blocked_cells",
		"allowed_rotations",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("TileDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).strip_edges().is_empty():
		return Result.failure("TileDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).strip_edges().is_empty():
		return Result.failure("TileDef.display_name 类型错误或为空（期望非空 String）")

	var rotations_val = data.get("allowed_rotations", null)
	var rotations_read := MapParseHelpersClass.parse_rotation_array(
		rotations_val,
		"TileDef.allowed_rotations",
		MapUtilsClass.VALID_ROTATIONS
	)
	if not rotations_read.ok:
		return rotations_read

	var road_segments_val = data.get("road_segments", null)
	var road_segments_read := MapParseHelpersClass.parse_road_grid(
		road_segments_val,
		"TileDef.road_segments",
		int(MapUtilsClass.TILE_SIZE),
		MapUtilsClass.DIRECTIONS
	)
	if not road_segments_read.ok:
		return road_segments_read

	var blocked_cells_val = data.get("blocked_cells", null)
	var blocked_read := MapParseHelpersClass.parse_vec2i_array(blocked_cells_val, "TileDef.blocked_cells")
	if not blocked_read.ok:
		return blocked_read

	var drink_sources_val = data.get("drink_sources", null)
	var drink_sources_read := MapParseHelpersClass.parse_drink_sources(drink_sources_val, "TileDef.drink_sources")
	if not drink_sources_read.ok:
		return drink_sources_read

	var printed_val = data.get("printed_structures", null)
	var printed_read := MapParseHelpersClass.parse_printed_structures(
		printed_val,
		"TileDef.printed_structures",
		MapUtilsClass.VALID_ROTATIONS
	)
	if not printed_read.ok:
		return printed_read

	return Result.success({
		"id": str(id_val).strip_edges(),
		"display_name": str(display_name_val).strip_edges(),
		"allowed_rotations": rotations_read.value,
		"road_segments": road_segments_read.value,
		"blocked_cells": blocked_read.value,
		"drink_sources": drink_sources_read.value,
		"printed_structures": printed_read.value,
	})

