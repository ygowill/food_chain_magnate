# PieceDef Dictionary 解析（从 piece_def.gd 抽离）
# 目的：缩短 PieceDef 单文件体积，将“严格解析/校验”职责集中到解析器中。
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const MapParseHelpersClass = preload("res://core/map/parse_helpers.gd")
const _VALID_ROTATIONS = MapUtilsClass.VALID_ROTATIONS

static func parse_piece_def_dict(data) -> Result:
	if not (data is Dictionary):
		return Result.failure("PieceDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"category",
		"footprint_mask",
		"anchor",
		"allowed_rotations",
		"mirror_allowed",
		"must_be_on_empty",
		"must_touch_road",
		"allowed_on",
		"forbidden_layers",
		"entrance_type",
		"entrance_points",
		"is_house",
		"can_have_garden",
		"garden_extension_size",
	]
	for key in required_keys:
		if not (data as Dictionary).has(key):
			return Result.failure("PieceDef 缺少字段: %s" % key)

	var id_val = (data as Dictionary).get("id", null)
	if not (id_val is String) or str(id_val).strip_edges().is_empty():
		return Result.failure("PieceDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = (data as Dictionary).get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).strip_edges().is_empty():
		return Result.failure("PieceDef.display_name 类型错误或为空（期望非空 String）")
	var category_val = (data as Dictionary).get("category", null)
	if not (category_val is String) or str(category_val).strip_edges().is_empty():
		return Result.failure("PieceDef.category 类型错误或为空（期望非空 String）")

	var footprint_val = (data as Dictionary).get("footprint_mask", null)
	var footprint_read := MapParseHelpersClass.parse_footprint_mask(footprint_val, "PieceDef.footprint_mask")
	if not footprint_read.ok:
		return footprint_read

	var anchor_read := MapParseHelpersClass.parse_vec2i((data as Dictionary).get("anchor", null), "PieceDef.anchor")
	if not anchor_read.ok:
		return anchor_read

	var rotations_read := MapParseHelpersClass.parse_rotation_array(
		(data as Dictionary).get("allowed_rotations", null),
		"PieceDef.allowed_rotations",
		_VALID_ROTATIONS
	)
	if not rotations_read.ok:
		return rotations_read

	var mirror_val = (data as Dictionary).get("mirror_allowed", null)
	if not (mirror_val is bool):
		return Result.failure("PieceDef.mirror_allowed 类型错误（期望 bool）")
	var must_be_on_empty_val = (data as Dictionary).get("must_be_on_empty", null)
	if not (must_be_on_empty_val is bool):
		return Result.failure("PieceDef.must_be_on_empty 类型错误（期望 bool）")
	var must_touch_road_val = (data as Dictionary).get("must_touch_road", null)
	if not (must_touch_road_val is bool):
		return Result.failure("PieceDef.must_touch_road 类型错误（期望 bool）")

	var allowed_on_read := MapParseHelpersClass.parse_string_array((data as Dictionary).get("allowed_on", null), "PieceDef.allowed_on", true)
	if not allowed_on_read.ok:
		return allowed_on_read
	var forbidden_layers_read := MapParseHelpersClass.parse_string_array(
		(data as Dictionary).get("forbidden_layers", null),
		"PieceDef.forbidden_layers",
		false
	)
	if not forbidden_layers_read.ok:
		return forbidden_layers_read

	var entrance_type_val = (data as Dictionary).get("entrance_type", null)
	if not (entrance_type_val is String) or str(entrance_type_val).strip_edges().is_empty():
		return Result.failure("PieceDef.entrance_type 类型错误或为空（期望非空 String）")

	var entrance_points_read := MapParseHelpersClass.parse_vec2i_array(
		(data as Dictionary).get("entrance_points", null),
		"PieceDef.entrance_points"
	)
	if not entrance_points_read.ok:
		return entrance_points_read

	var is_house_val = (data as Dictionary).get("is_house", null)
	if not (is_house_val is bool):
		return Result.failure("PieceDef.is_house 类型错误（期望 bool）")
	var can_have_garden_val = (data as Dictionary).get("can_have_garden", null)
	if not (can_have_garden_val is bool):
		return Result.failure("PieceDef.can_have_garden 类型错误（期望 bool）")

	var garden_size_read := MapParseHelpersClass.parse_vec2i(
		(data as Dictionary).get("garden_extension_size", null),
		"PieceDef.garden_extension_size"
	)
	if not garden_size_read.ok:
		return garden_size_read

	return Result.success({
		"id": str(id_val).strip_edges(),
		"display_name": str(display_name_val).strip_edges(),
		"category": str(category_val).strip_edges(),
		"footprint_mask": footprint_read.value,
		"anchor": anchor_read.value,
		"allowed_rotations": rotations_read.value,
		"mirror_allowed": bool(mirror_val),
		"must_be_on_empty": bool(must_be_on_empty_val),
		"must_touch_road": bool(must_touch_road_val),
		"allowed_on": allowed_on_read.value,
		"forbidden_layers": forbidden_layers_read.value,
		"entrance_type": str(entrance_type_val).strip_edges(),
		"entrance_points": entrance_points_read.value,
		"is_house": bool(is_house_val),
		"can_have_garden": bool(can_have_garden_val),
		"garden_extension_size": garden_size_read.value,
	})
