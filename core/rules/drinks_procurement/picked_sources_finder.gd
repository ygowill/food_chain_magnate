# 饮料采购：沿路线拾取来源（Fail Fast）
extends RefCounted

const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

static func find_picked_sources_along_route(
	state: GameState,
	drink_sources: Array,
	route: Array[Vector2i],
	range_type: String
) -> Result:
	var route_set := {}
	for pos in route:
		route_set[pos] = true

	var picked: Array[Dictionary] = []
	for source in drink_sources:
		var src: Vector2i = source["world_pos"]
		var ok := false
		if range_type == "air":
			ok = route_set.has(src)
		else:
			var cells_result := RangeUtilsClass.get_adjacent_road_cells(state, src)
			if not cells_result.ok:
				return cells_result
			var cells: Array[Vector2i] = cells_result.value
			for c in cells:
				if route_set.has(c):
					ok = true
					break

		if ok:
			picked.append({
				"world_pos": src,
				"type": source["type"],
				"tile_id": source["tile_id"]
			})

	return Result.success(picked)

