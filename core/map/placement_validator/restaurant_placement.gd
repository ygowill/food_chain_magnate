extends RefCounted

const Placement = preload("res://core/map/placement_validator/placement.gd")
const MapAccess = preload("res://core/map/placement_validator/map_access.gd")

# 验证餐厅放置
static func validate_restaurant_placement(
	map_ctx: Dictionary,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	_player_id: int,
	is_initial_placement: bool,
	context: Dictionary = {}
) -> Result:
	# 基础验证
	var base_result := Placement.validate_placement(map_ctx, "restaurant", world_anchor, rotation, piece_registry, context)
	if not base_result.ok:
		return base_result

	var footprint_cells: Array = base_result.value.footprint_cells

	# 获取餐厅入口
	var piece_def: PieceDef = piece_registry.get("restaurant")
	assert(piece_def != null, "PlacementValidator: piece_registry 缺少 restaurant PieceDef")
	var entrance_points := piece_def.get_world_entrance_points(world_anchor, rotation)
	assert(not entrance_points.is_empty(), "PlacementValidator: restaurant entrance_points 不能为空")

	# 验证入口邻接道路
	var has_road_access := false
	for entrance in entrance_points:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(entrance, dir)
			if not MapAccess.has_world_cell(map_ctx, neighbor):
				continue
			var neighbor_cell: Dictionary = MapAccess.get_world_cell(map_ctx, neighbor)
			assert(neighbor_cell.has("road_segments") and (neighbor_cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = neighbor_cell["road_segments"]
			if not road_segments.is_empty():
				has_road_access = true
				break
		if has_road_access:
			break

	if not has_road_access:
		return Result.failure("餐厅入口必须邻接道路")

	# 初始放置限制: 每个板块只能有一个餐厅入口
	if is_initial_placement:
		var entrance_tile: Vector2i = MapUtils.world_to_tile(entrance_points[0]).board_pos

		assert(map_ctx.has("restaurants") and (map_ctx["restaurants"] is Dictionary), "PlacementValidator: map_ctx.restaurants 缺失或类型错误（期望 Dictionary）")
		var restaurants: Dictionary = map_ctx["restaurants"]
		for rest_id in restaurants:
			var rest_val = restaurants[rest_id]
			assert(rest_val is Dictionary, "PlacementValidator: restaurants[%s] 类型错误（期望 Dictionary）" % str(rest_id))
			var rest: Dictionary = rest_val
			assert(rest.has("entrance_pos") and (rest["entrance_pos"] is Vector2i), "PlacementValidator: restaurants[%s].entrance_pos 缺失或类型错误（期望 Vector2i）" % str(rest_id))
			var rest_entrance: Vector2i = rest["entrance_pos"]
			var rest_tile: Vector2i = MapUtils.world_to_tile(rest_entrance).board_pos
			if rest_tile == entrance_tile:
				return Result.failure("初始放置: 每个板块只能有一个餐厅入口")

	# 添加入口信息到结果
	var result_value: Dictionary = base_result.value
	result_value["entrance_pos"] = entrance_points[0]
	result_value["entrance_points"] = entrance_points

	return Result.success(result_value)

